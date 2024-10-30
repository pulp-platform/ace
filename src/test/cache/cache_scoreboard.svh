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
    mailbox #(cache_snoop_req)  snoop_req_mbx;
    mailbox #(cache_snoop_resp) snoop_resp_mbx;
    mailbox #(mem_req)    mem_req_mbx;
    mailbox #(mem_resp)   mem_resp_mbx;

    function new(
        mailbox #(cache_req)  cache_req_mbx,
        mailbox #(cache_resp) cache_resp_mbx,
        mailbox #(cache_snoop_req)  snoop_req_mbx,
        mailbox #(cache_snoop_resp) snoop_resp_mbx,
        mailbox #(mem_req)    mem_req_mbx,
        mailbox #(mem_resp)   mem_resp_mbx
    );
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
        this.snoop_req_mbx  = snoop_req_mbx;
        this.snoop_resp_mbx = snoop_resp_mbx;
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
        int unsigned n_bytes = CACHELINE_BYTES;
        cache_resp resp = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = req.addr[BLOCK_OFFSET_BITS-1:0];
        for (int i = 0; i < n_bytes; i++) begin
            resp.data_q.push_back(data_q[info.idx][info.way][byte_idx]);
            byte_idx++;
        end
        return resp;
    endfunction

    function automatic cache_resp cache_write(tag_resp_t info, cache_req req);
        int unsigned n_bytes = CACHELINE_BYTES;
        cache_resp resp = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = req.addr[BLOCK_OFFSET_BITS-1:0];
        for (int i = 0; i < n_bytes; i++) begin
            data_q[info.idx][info.way][byte_idx] = req.data_q.pop_front();
            byte_idx++;
        end
        status_q[info.idx][info.way][DIRTY_IDX] = 'b1;
        return resp;
    endfunction

    function automatic cache_resp cache_set_state(tag_resp_t info, status_t state);
        cache_resp resp = new;
        status_q[info.idx][info.way] = state;
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
            for (int j = 0; j < BYTES_PER_WORD; j++) begin
                mem_req.data_q.push_back(
                    data_q[info.idx][info.way][i*BYTES_PER_WORD+j]);
            end
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
            for (int j = 0; j < n_bytes; j++) begin
                data_q[info.idx][info.way][byte_idx] =
                    resp.data_q.pop_front();
                byte_idx++;
            end
        end
        status_q[info.idx][info.way][DIRTY_IDX] = resp.pass_dirty;
        status_q[info.idx][info.way][SHARD_IDX] = resp.is_shared;
        status_q[info.idx][info.way][VALID_IDX] = 'b1;
    endfunction;

    task automatic snoop(input cache_snoop_req req, output cache_snoop_resp resp);
        tag_resp_t tag_lu;
        cache_req cache_req = new;
        cache_resp cache_resp;
        resp = new;
        cache_req.addr = req.addr;
        tag_lu = read_and_compare_tag(cache_req.addr);
        resp.snoop_resp.Error = 1'b0;
        if (tag_lu.hit) begin
            cache_resp = cache_read(tag_lu, cache_req);
            resp.snoop_resp.WasUnique = !tag_lu.status[SHARD_IDX];
            while (cache_resp.data_q.size() > 0) begin
                logic [7:0] data = cache_resp.data_q.pop_front();
                resp.data_q.push_back(data);
            end
            case (req.snoop_op)
                ace_pkg::ReadOnce: begin
                    resp.snoop_resp.DataTransfer = 1'b1;
                    resp.snoop_resp.IsShared     = 1'b1;
                    resp.snoop_resp.PassDirty    = 1'b0;
                end
                ace_pkg::ReadClean, ace_pkg::ReadNotSharedDirty: begin
                    // recommended to pass clean
                    status_t new_status = tag_lu.status;
                    resp.snoop_resp.DataTransfer = 1'b1;
                    resp.snoop_resp.IsShared     = 1'b1;
                    resp.snoop_resp.PassDirty    = 1'b0;
                    new_status[SHARD_IDX]        = 1'b1;
                    cache_set_state(tag_lu, new_status);
                end
                ace_pkg::ReadShared: begin
                    // recommended to pass dirty
                    status_t new_status = tag_lu.status;
                    resp.snoop_resp.DataTransfer = 1'b1;
                    resp.snoop_resp.IsShared     = 1'b1;
                    new_status[SHARD_IDX]        = 1'b1;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    new_status[DIRTY_IDX]        = 1'b0;
                    cache_set_state(tag_lu, new_status);
                end
                ace_pkg::ReadUnique: begin
                    // data transfer and invalidate
                    status_t new_status = tag_lu.status;
                    resp.snoop_resp.DataTransfer = 1'b1;
                    resp.snoop_resp.IsShared     = 1'b0;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    new_status[VALID_IDX]        = 1'b0;
                    cache_set_state(tag_lu, new_status);
                end
                ace_pkg::CleanInvalid: begin
                    // data transfer dirty and invalidate
                    status_t new_status = tag_lu.status;
                    resp.snoop_resp.DataTransfer = tag_lu.status[DIRTY_IDX];
                    resp.snoop_resp.IsShared     = 1'b0;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    new_status[VALID_IDX]        = 1'b0;
                    cache_set_state(tag_lu, new_status);
                end
                ace_pkg::MakeInvalid: begin
                    // invalidate
                    status_t new_status = tag_lu.status;
                    resp.snoop_resp.DataTransfer = 1'b0;
                    resp.snoop_resp.IsShared     = 1'b0;
                    resp.snoop_resp.PassDirty    = 1'b0;
                    new_status[VALID_IDX]        = 1'b0;
                    cache_set_state(tag_lu, new_status);
                end
                ace_pkg::CleanShared: begin
                    // pass dirty
                    status_t new_status = tag_lu.status;
                    resp.snoop_resp.DataTransfer = tag_lu.status[DIRTY_IDX];
                    resp.snoop_resp.IsShared     = 1'b1;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    new_status[DIRTY_IDX]        = 1'b0;
                    new_status[SHARD_IDX]        = 1'b1;
                    cache_set_state(tag_lu, new_status);
                end
                default: $fatal(1, "Unsupported snoop op!");
            endcase
        end
    endtask

    task automatic cache_fsm(input cache_req req, output cache_resp resp);
        tag_resp_t tag_lu;
        mem_req mem_req = new;
        mem_resp mem_resp;
        mem_req.cacheable = !req.uncacheable;
        //cache_lookup_sem.get(1);
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
        //cache_lookup_sem.put(1);
    endtask

    task gen_cache_req;
        cache_req req;
        cache_resp resp = new;
        cache_req_mbx.get(req);
        $info("cache req received");
        cache_fsm(req, resp);
        cache_resp_mbx.put(resp);
    endtask

    task recv_snoop_reqs;
        cache_snoop_req req;
        cache_snoop_resp resp = new;
        snoop_req_mbx.get(req);
        snoop(req, resp);
        snoop_resp_mbx.put(resp);
    endtask

    task run;
        fork
            forever gen_cache_req();
            forever recv_snoop_reqs();
        join
    endtask

endclass