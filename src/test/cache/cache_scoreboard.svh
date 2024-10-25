`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_scoreboard #(
    parameter int AW = 32,
    parameter int DW = 32,
    parameter int WORD_WIDTH,
    parameter int CACHELINE_WORDS,
    parameter int WAYS,
    parameter int SETS
);

    localparam int BYTES_PER_WORD = DW / 8;
    localparam int CACHELINE_BYTES = CACHELINE_WORDS * WORD_WIDTH / 8;
    localparam int BLOCK_OFFSET_BITS = $clog2(CACHELINE_BYTES);
    localparam int INDEX_BITS = $clog2(SETS);
    localparam int TAG_BITS = AW - BLOCK_OFFSET_BITS - INDEX_BITS;

    localparam int VALID_IDX = 0;
    localparam int SHARD_IDX = 1;
    localparam int DIRTY_IDX = 2;

    typedef logic [TAG_BITS-1:0]        tag_t;
    typedef logic [AW-1:0]              addr_t;
    typedef logic [7:0]                 byte_t;
    typedef logic [CACHELINE_BYTES-1:0] cacheline_t;
    typedef logic [2:0]                 status_t;

    typedef struct {
        logic hit;
        status_t status;
        int way;
        int idx;
        int unsigned addr;
    } tag_resp_t;
    
    byte_t   data_q[SETS][CACHELINE_BYTES][WAYS];   // Cache data
    status_t status_q[SETS][CACHELINE_BYTES][WAYS]; // Cache state
    tag_t    tag_q[SETS][WAYS];                     // Cache tag
    // Semaphore to ensure only one process accesses the cache at a time
    semaphore cache_lookup_sem; 

    mailbox #(cache_req)  cache_req_mbx;
    mailbox #(cache_resp) cache_resp_mbx;
    mailbox #(mem_req)    mem_req_mbx;
    mailbox #(mem_resp)   mem_resp_mbx;

    function new(
        mailbox #(cache_req)  cache_req_mbx,
        mailbox #(cache_resp) cache_resp_mbx,
        mailbox #(mem_req)    mem_req_mbx,
        mailbox #(mem_resp)   mem_resp_mbx,
    );
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
        this.mem_req_mbx    = mem_req_mbx;
        this.mem_resp_mbx   = mem_resp_mbx;

        this.cache_lookup_sem = new(1);
    endfunction

    function void init_mem_from_file(string fname);
        int fd, scanret;
        addr_t addr;
        byte_t rvalue;
        status_t rstatus;
        fd = $fopen(fname, "r");
        addr = '0;
        if (fd) begin
            while (!$feof(fd)) begin
                scanret = $fscanf(fd, "%x,%x", rvalue, rstatus);
                memory_q[addr] = rvalue;
                status_q[addr] = rstatus;
                addr++;
            end
        end else begin
            $fatal("Could not open file %s", fname);
        end
        $fclose(fd);
    endfunction


    function tag_resp_t read_and_compare_tag(addr_t addr);
        tag_resp_t resp;
        tag_t lu_tag;
        status_t status;
        logic hit = '0;
        int way;
        int not_valid_way = '0;
        int i;
        int unsigned addr;
        int unsigned idx = addr[BLOCK_OFFSET_BITS+INDEX_BITS-1:BLOCK_OFFSET_BITS];
        tag_t tag        = addr[AW-1:AW-TAG_BITS];
        for (way = 0; way < WAYS; way++) begin
            lu_tag = tag_q[idx][way];
            status = status_q[idx][way];
            if (!status[VALID_IDX]) begin
                // Current way is invalid
                // -> suitable for replacement
                not_valid_way = way;
            end
            if (tag == lu_tag && status[VALID_IDX]) begin
                hit = 'b1;
                break;
            end
        end
        resp.hit  = hit;
        resp.idx  = idx;
        if (hit) begin
            resp.way  = way;
        end else begin
            resp.way = not_valid_way;
        end
        resp.addr = {lu_tag, idx, BLOCK_OFFSET_BITS{1'b0}};
        return resp;
    endfunction

    function automatic cache_resp cache_read(tag_resp_t info);
        int unsigned n_bytes = (req.len + 1) * (2**req.size);
        int line_crossings = 0;
        cache_resp resp = new;
        for (int i = 0; i < n_bytes; i++) begin
            // Wrap around cacheline if it goes cross line boundary
            int real_i = i - CACHELINE_BYTES*line_crossings;
            if (real_i >= (CACHELINE_BYTES - 1)) line_crossings++;
            req.data.push_back(data_q[info.idx][real_i][info.way]);
        end
        return resp;
    endfunction

    function automatic void cache_write(tag_resp_t info, cache_req req);
        int unsigned n_bytes = axi_pkg::num_bytes(req.size);
        cache_resp resp = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = req.addr[BLOCK_OFFSET_BITS-1:0];
        for (int i = 0; i < n_bytes; i++) begin
            byte_idx = byte_idx + i;
            data_q[info.idx][byte_idx][info.way] = (req.data & ('hFF << 8*i)) >> 8*i;
        end
        status_q[info.idx][info.way][DIRTY_IDX] = 'b1;
        return;
    endfunction

    function automatic mem_req gen_write_back(tag_resp_t info);
        mem_req mem_req;
        mem_req.size = clog2(BYTES_PER_WORD);
        mem_req.len  = CACHELINE_WORDS - 1;
        mem_req.addr = info.addr;
        mem_req.op   = MEM_WRITE_BACK;
        for (int i = 0; i < CACHELINE_WORDS; i++) begin
            int unsigned word = 0;
            for (int j = 0; j < BYTES_PER_WORD; j++) begin
                word = (word << 8) & data_q[info.idx][i*BYTES_PER_WORD+j][info.way];
            end
            mem_req.data_q.push_back(word);
        end
        return mem_req;
    endfunction

    function automatic mem_req gen_read_allocate(cache_req req);
        mem_req mem_req;
        mem_req.size = $clog2(BYTES_PER_WORD);
        mem_req.len  = CACHELINE_WORDS - 1;
        mem_req.addr = req.addr;
        mem_req.op   = REQ_LOAD;
        return mem_req;
    endfunction

    function automatic void allocate(mem_req req, mem_resp resp, tag_resp_t info);
        int unsigned n_bytes = axi_pkg::num_bytes(req.size);
        cache_resp resp = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = req.addr[BLOCK_OFFSET_BITS-1:0];
        for (int i = 0; i < req.len; i++) begin
            for (int j = 0; j < n_bytes; j++) begin
                byte_idx = byte_idx + n_bytes*i + j;
                data_q[info.idx][byte_idx][info.way] = (resp.data & ('hFF << 8*real_i)) >> 8*real_i;
            end
        end
        status_q[info.idx][info.way][DIRTY_IDX] = resp.pass_dirty;
        status_q[info.idx][info.way][SHARD_IDX] = resp.is_shared;
        status_q[info.idx][info.way][VALID_IDX] = 'b1;
    endfunction;

    task automatic cache_fsm(input cache_req req, output cache_resp resp);
        tag_resp_t tag_lu;
        mem_req mem_req;
        cache_lookup_sem.get(1);
        tag_lu = read_and_compare_tag(req.addr);
        if (tag_lu.hit) begin
            if (req.read) begin
                resp = cache_read(tag_lu);
            end else if (req.write) begin
                resp = cache_write(tag_lu, req);
            end
        end else begin
            if (tag_lu.status.dirty && tag_lu.status.valid) begin
                // Generate write-back request
                mem_req = gen_write_back(tag_lu);
                // Send request and wait for response
                mem_req_mbx.put(mem_req);
                mem_resp_mbx.get(mem_resp);
            end
            // Generate read request for new cache line
            mem_req = gen_read_allocate(req);
            // Send request and wait for response
            mem_req_mbx.put(mem_req);
            mem_resp_mbx.get(mem_resp);
            // Allocate cache line for the new entry
            allocate(mem_req, mem_resp, tag_lu);
            // Handle the initial cache request
            if (req.read) begin
                resp = cache_read(tag_lu);
            end else begin
                resp = cache_write(tag_lu, req);
            end
        end
        cache_resp_mbx.put(resp);
        cache_lookup_sem.put(1);
    endtask

    task cache_req;
        cache_req req;
        cache_resp resp;
        cache_req_mbx.get(req);
        resp = cache_fsm(req.addr);
        cache_resp_mbx.put(resp);
    endtask

endclass