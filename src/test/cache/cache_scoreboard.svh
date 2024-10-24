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
    } tag_resp_t;
    
    byte_t   data_q[SETS][CACHELINE_BYTES][WAYS];   // Cache data
    status_t status_q[SETS][CACHELINE_BYTES][WAYS]; // Cache state
    tag_t    tag_q[SETS][WAYS];                     // Cache tag
    // Semaphore to ensure only one process accesses the cache at a time
    semaphore cache_lookup_sem; 

    mailbox #(cache_req)  cache_req_mbx;
    mailbox #(cache_resp) cache_resp_mbx;

    function new(
        mailbox #(cache_req)  cache_req_mbx,
        mailbox #(cache_resp) cache_resp_mbx
    );
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;

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
        int way = 0;
        int unsigned idx = addr[BLOCK_OFFSET_BITS+INDEX_BITS-1:BLOCK_OFFSET_BITS];
        tag_t tag        = addr[AW-1:AW-TAG_BITS];
        for (int i = 0; i < WAYS; i++) begin
            lu_tag = tag_q[idx][i];
            status  = status_q[idx][i];
            if (tag == lu_tag) begin
                hit = 'b1;
                way = i;
                break;
            end
        end
        resp.hit = hit;
        resp.way = way;
        resp.idx = idx;
        return resp;
    endfunction

    function automatic cache_resp cache_read(tag_resp_t info);
        int unsigned n_bytes = (req.len + 1) * (2**req.size);
        int line_crossings = 0;
        cache_resp resp;
        for (int i = 0; i < n_bytes; i++) begin
            // Wrap around cacheline if it goes cross line boundary
            int real_i = i - CACHELINE_BYTES*line_crossings;
            if (real_i >= (CACHELINE_BYTES - 1)) line_crossings++;
            req.data.push_back(data_q[info.idx][real_i][info.way]);
        end
        return resp;
    endfunction

    function automatic void set_dirty(tag_resp_t info):
        status_q[info.idx][info.way][DIRTY_IDX] = 'b1;
        return;
    endfunction

    task automatic cache_fsm(input cache_req req, output cache_resp resp);
        tag_resp_t tag_lu;
        cache_lookup_sem.get(1);
        tag_lu = read_and_compare_tag(req.addr);
        if (tag_lu.hit && tag_lu.status.valid) begin
            resp = cache_read(tag_lu);    
            if (req.write) begin
                set_dirty(tag_lu);
            end
        end else if (!tag_lu.hit && tag_lu.status.dirty) begin
            // Generate write-back request
        end
        cache_lookup_sem.put(1);
    endtask

    task cache_req;
        cache_req req;
        cache_resp resp;
        cache_req_mbx.get(req);
        resp = cache_read(req.addr);
        cache_resp_mbx.put(resp);
    endtask

endclass