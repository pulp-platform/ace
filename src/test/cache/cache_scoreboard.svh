`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_scoreboard #(
    parameter int AW = 32,
    parameter int DW = 32,
    // Width of one cache word
    parameter int WORD_WIDTH,
    // How many words per cache line
    parameter int CACHELINE_WORDS,
    // How many ways per set
    parameter int WAYS,
    // How many sets
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
    typedef logic [2:0]                 status_t;

    typedef struct {
        logic hit;
        status_t status;
        int way;
        int idx;
        int unsigned addr;
    } tag_resp_t;
    
    byte_t   data_q[SETS][WAYS][CACHELINE_BYTES];   // Cache data
    status_t status_q[SETS][WAYS];                  // Cache state
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
        mailbox #(mem_resp)   mem_resp_mbx
    );
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
        this.mem_req_mbx    = mem_req_mbx;
        this.mem_resp_mbx   = mem_resp_mbx;

        this.cache_lookup_sem = new(1);
    endfunction

    function void init_data_mem_from_file(
        string fname
    );
        $readmemh(fname, data_q);
    endfunction

    function void init_tag_mem_from_file(
        string fname
    );
        $readmemh(fname, tag_q);
    endfunction

    function void init_status_from_file(
        string fname
    );
        // Initialize all to zeros
        for (int set = 0; set < SETS; set++) begin
            for (int way = 0; way < WAYS; way++) begin
                status_q[set][way] = '0;
            end
        end
        // Read initial values from file
        $readmemb(fname, status_q);
    endfunction

    function void init_mem_from_file(
        string data_fname,
        string tag_fname,
        string status_fname
    );
        init_data_mem_from_file(data_fname);
        init_tag_mem_from_file(tag_fname);
        init_status_from_file(status_fname);
    endfunction

    function tag_resp_t read_and_compare_tag(addr_t addr);
        tag_resp_t resp;
        tag_t lu_tag;
        status_t status;
        logic hit = '0;
        int way;
        int not_valid_way = '0;
        int i;
        int unsigned idx = addr[BLOCK_OFFSET_BITS+INDEX_BITS-1:BLOCK_OFFSET_BITS];
        tag_t tag        = addr[AW-1:AW-TAG_BITS];
        // Replacement policy = highest index with invalid status
        // otherwise, the highest way
        // TODO: implement LRU
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
        resp.addr = {lu_tag, idx, {BLOCK_OFFSET_BITS{1'b0}}};
        return resp;
    endfunction

    function automatic cache_resp cache_read(tag_resp_t info, cache_req req);
        int unsigned n_bytes = axi_pkg::num_bytes(req.size);
        int line_crossings = 0;
        cache_resp resp = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = req.addr[BLOCK_OFFSET_BITS-1:0];
        resp.data = 0;
        for (int i = 0; i < n_bytes; i++) begin
            resp.data = (resp.data << 8) | data_q[info.idx][info.way][byte_idx];
            byte_idx++;
        end
        return resp;
    endfunction

    function automatic cache_resp cache_write(tag_resp_t info, cache_req req);
        int unsigned n_bytes = axi_pkg::num_bytes(req.size);
        cache_resp resp = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = req.addr[BLOCK_OFFSET_BITS-1:0];
        for (int i = 0; i < n_bytes; i++) begin
            data_q[info.idx][info.way][byte_idx] = (req.data & ('hFF << 8*i)) >> 8*i;
            byte_idx++;
        end
        status_q[info.idx][info.way][DIRTY_IDX] = 'b1;
        return resp;
    endfunction

    function automatic mem_req gen_write_back(tag_resp_t info);
        mem_req mem_req;
        mem_req.size           = $clog2(BYTES_PER_WORD);
        mem_req.len            = CACHELINE_WORDS - 1;
        mem_req.addr           = info.addr;
        mem_req.op             = MEM_WRITE;
        mem_req.write_snoop_op = ace_pkg::WriteBack;
        for (int i = 0; i < CACHELINE_WORDS; i++) begin
            int unsigned word = 0;
            for (int j = 0; j < BYTES_PER_WORD; j++) begin
                word = (word << 8) & data_q[info.idx][info.way][i*BYTES_PER_WORD+j];
            end
            mem_req.data_q.push_back(word);
        end
        return mem_req;
    endfunction

    function automatic mem_req gen_read_allocate(cache_req req);
        mem_req mem_req = new;
        mem_req.size          = $clog2(BYTES_PER_WORD);
        mem_req.len           = CACHELINE_WORDS - 1;
        mem_req.addr          = req.addr;
        mem_req.op            = REQ_LOAD;
        mem_req.read_snoop_op = ace_pkg::ReadShared;
        return mem_req;
    endfunction

    function automatic void allocate(mem_req req, mem_resp resp, tag_resp_t info);
        int unsigned n_bytes = axi_pkg::num_bytes(req.size);
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = req.addr[BLOCK_OFFSET_BITS-1:0];
        for (int i = 0; i < req.len; i++) begin
            // data_word is of size indicated by req.size
            int unsigned data_word = resp.data_q.pop_front();
            for (int j = 0; j < n_bytes; j++) begin
                data_q[info.idx][info.way][byte_idx] =
                    (data_word & (8'hFF << 8*j)) >> 8*j;
                byte_idx++;
            end
        end
        status_q[info.idx][info.way][DIRTY_IDX] = resp.pass_dirty;
        status_q[info.idx][info.way][SHARD_IDX] = resp.is_shared;
        status_q[info.idx][info.way][VALID_IDX] = 'b1;
    endfunction;

    task automatic cache_fsm(input cache_req req, output cache_resp resp);
        tag_resp_t tag_lu;
        mem_req mem_req = new;
        mem_resp mem_resp;
        mem_req.cacheable = !req.uncacheable;
        cache_lookup_sem.get(1);
        tag_lu = read_and_compare_tag(req.addr);
        // TODO: uncached transactions don't check for tag
        if (tag_lu.hit) begin
            if (req.op == REQ_LOAD) begin
                resp = cache_read(tag_lu, req);
            end else if (req.op == REQ_STORE) begin
                resp = cache_write(tag_lu, req);
            end else begin
                $fatal("Unsupported op");
            end
        end else begin
            if (tag_lu.status[DIRTY_IDX] &&
                tag_lu.status[VALID_IDX]) begin
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
            $display("sent mem req");
            mem_resp_mbx.get(mem_resp);
            // Allocate cache line for the new entry
            allocate(mem_req, mem_resp, tag_lu);
            // Handle the initial cache request
            if (req.op == REQ_LOAD) begin
                resp = cache_read(tag_lu, req);
            end else if (req.op == REQ_STORE) begin
                resp = cache_write(tag_lu, req);
            end else begin
                $fatal("Unsupported op");
            end
        end
        cache_resp_mbx.put(resp);
        cache_lookup_sem.put(1);
    endtask

    task gen_cache_req;
        cache_req req;
        cache_resp resp = new;
        cache_req_mbx.get(req);
        $info("cache req received");
        cache_fsm(req, resp);
        cache_resp_mbx.put(resp);
    endtask

    task run;
        forever gen_cache_req();
    endtask

endclass