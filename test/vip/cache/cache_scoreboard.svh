`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_scoreboard #(
    /// Address space
    parameter int AW = 32,
    /// Width of the memory bus
    parameter int DW = 32,
    /// Width of one cache word
    parameter int WORD_WIDTH = 0,
    /// How many words per cache line
    parameter int CACHELINE_WORDS = 0,
    /// How many ways per set
    parameter int WAYS = 0,
    /// How many sets
    parameter int SETS = 0,
    /// Clock interface type
    parameter type clk_if_t = logic
);

    localparam int BYTES_PER_WORD    = DW / 8;
    localparam int CACHELINE_BYTES   = CACHELINE_WORDS * WORD_WIDTH / 8;
    localparam int BLOCK_OFFSET_BITS = $clog2(CACHELINE_BYTES);
    localparam int INDEX_BITS        = $clog2(SETS);
    localparam int TAG_BITS          = AW - BLOCK_OFFSET_BITS - INDEX_BITS;

    localparam int VALID_IDX = 0;
    localparam int SHARD_IDX = 1;
    localparam int DIRTY_IDX = 2;

    int INDEX = -1;

    typedef logic [TAG_BITS-1:0]        tag_t;
    typedef logic [AW-1:0]              addr_t;
    typedef logic [7:0]                 byte_t;
    typedef logic [2:0]                 status_t;
    typedef logic [$clog2(WAYS)-1:0]    lru_rank_t;
    typedef logic [INDEX_BITS-1:0]      idx_t;

    // Data structure for carrying cache request information
    // It also monitors all cache modifications so that they can
    // be executed at once and logged easily.
    typedef struct {
        // Cache hit
        logic hit;
        // Status of the old cache line
        status_t status;
        // Way index for hit or replacement
        int way;
        // Set index of the old cache line
        idx_t idx;
        // Tag of the old cache line
        tag_t tag;
        // Cacheline-aligned address of the old cache line
        addr_t addr;
        // Cacheline-aligned address of the new cache line
        addr_t new_addr;
        // Byte index within the cache line
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx;
        // New cache line to be stored
        byte_t new_cline [CACHELINE_BYTES];
        // New status for the cache line
        status_t new_status;
        // New tag for the cache line
        tag_t new_tag;
    } tag_resp_t;

    byte_t     data_q[SETS][WAYS][CACHELINE_BYTES];   // Cache data
    status_t   status_q[SETS][WAYS];                  // Cache state
    tag_t      tag_q[SETS][WAYS];                     // Cache tag
    lru_rank_t lru_rank_q[SETS][WAYS];                // LRU ranks

    // Semaphore to ensure only one process accesses the cache at a time
    // The two processes are cache requests and snoop requests
    // TODO: figure the critical point where using this is necessary
    // ATM it is not used
    semaphore cache_lookup_sem;

    // Interface to provide simulation clock
    clk_if_t clk_if;

    string state_file;
    logic first_write = '1;

    // Mailboxes for cache requests
    mailbox #(cache_req)        cache_req_mbx;
    mailbox #(cache_resp)       cache_resp_mbx;
    // Mailboxes for snoop requests
    mailbox #(cache_snoop_req)  snoop_req_mbx;
    mailbox #(cache_snoop_resp) snoop_resp_mbx;
    // Mailboxes for memory requests
    mailbox #(mem_req)          mem_req_mbx;
    mailbox #(mem_resp)         mem_resp_mbx;

    function new(
        clk_if_t                    clk_if,
        mailbox #(cache_req)        cache_req_mbx,
        mailbox #(cache_resp)       cache_resp_mbx,
        mailbox #(cache_snoop_req)  snoop_req_mbx,
        mailbox #(cache_snoop_resp) snoop_resp_mbx,
        mailbox #(mem_req)          mem_req_mbx,
        mailbox #(mem_resp)         mem_resp_mbx,
        string                      state_file,
        int index
    );
        this.clk_if         = clk_if;
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
        this.snoop_req_mbx  = snoop_req_mbx;
        this.snoop_resp_mbx = snoop_resp_mbx;
        this.mem_req_mbx    = mem_req_mbx;
        this.mem_resp_mbx   = mem_resp_mbx;
        this.state_file     = state_file;
        this.INDEX = index;

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
                status_q[set][way]   = '0;
                lru_rank_q[set][way] = '0;
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

    function automatic void log_state_change(
        bit initiator,
        int unsigned addr,
        int unsigned set,
        int unsigned way,
        tag_t new_tag,
        status_t new_status,
        byte_t new_data[CACHELINE_BYTES],
        bit modify
    );
        int fd;
        if (first_write) fd = $fopen(this.state_file, "w");
        else             fd = $fopen(this.state_file, "a");
        first_write = 0;
        $fwrite(fd, "TIME:%0t ADDR:%x INITIATOR:%0d", $time, addr, initiator);
        if (modify) begin
            $fwrite(fd, " SET:%0d WAY:%0d TAG:%x STATUS:%b DATA:[",
                    set, way, new_tag, new_status);
            for (int i = 0; i < CACHELINE_BYTES; i++) begin
                if (i == 0)
                    $fwrite(fd, "%x", new_data[i]);
                else
                    $fwrite(fd, ",%x", new_data[i]);
            end
            $fwrite(fd, "]");
        end
        $fwrite(fd, "\n");
        $fclose(fd);
    endfunction

    // Atomic function for all cache writes
    // Cache state is saved optionally
    // NO OTHER FUNCTION SHOULD MODIFY THE CACHE
    // initiator = 1 when "core" modifies the cache
    // initiator = 0 when cache is modified by snooping
    function automatic void modify_cache(
        tag_resp_t info, bit initiator, bit modify
    );
        if (modify) begin
            data_q[info.idx][info.way]   = info.new_cline;
            status_q[info.idx][info.way] = info.new_status;
            tag_q[info.idx][info.way]    = info.new_tag;
            update_lru(info);
        end
        log_state_change(
            initiator,
            info.new_addr,
            info.idx,
            info.way,
            tag_q[info.idx][info.way],
            status_q[info.idx][info.way],
            data_q[info.idx][info.way],
            modify
        );
    endfunction

    function automatic void update_lru(tag_resp_t info);
        for (int way = 0; way < WAYS; way++) begin
            if (way == info.way) begin
                lru_rank_q[info.idx][way] = WAYS-1;
            end else begin
                if (lru_rank_q[info.idx][way] != '0) begin
                    lru_rank_q[info.idx][way]--;
                end
            end
        end
    endfunction

    function automatic tag_resp_t read_and_compare_tag(addr_t addr);
        tag_resp_t resp;
        tag_t lu_tag;
        status_t status;
        logic hit = '0;
        logic invalid_found = '0;
        int way;
        int i;
        idx_t idx = addr[BLOCK_OFFSET_BITS+INDEX_BITS-1:BLOCK_OFFSET_BITS];
        tag_t tag = addr[AW-1:AW-TAG_BITS];
        for (int i = 0; i < WAYS; i++) begin
            lu_tag = tag_q[idx][i];
            if (!status_q[idx][i][VALID_IDX]) begin
                way           = i;
                invalid_found = '1;
            end else if (!invalid_found && lru_rank_q[idx][i] == 0) begin
                // Least recently used
                way = i;
            end
            if (tag == lu_tag && status_q[idx][i][VALID_IDX]) begin
                way = i;
                hit = 'b1;
                break;
            end
        end
        resp.hit        = hit;
        resp.idx        = idx;
        resp.way        = way;
        resp.status     = status_q[idx][way];
        resp.tag        = tag_q[idx][way];
        resp.addr       = {tag_q[idx][way], idx, {BLOCK_OFFSET_BITS{1'b0}}};
        resp.byte_idx   = addr[BLOCK_OFFSET_BITS-1:0];
        resp.new_addr   = {addr[AW-1:BLOCK_OFFSET_BITS], {BLOCK_OFFSET_BITS{1'b0}}};
        resp.new_tag    = tag;
        resp.new_status = status_q[idx][way];
        resp.new_cline  = data_q[idx][way];
        return resp;
    endfunction

    function automatic cache_resp cache_read(tag_resp_t info, cache_req req);
        int unsigned n_bytes = 1 << req.size;
        cache_resp resp = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = info.byte_idx;
        for (int i = 0; i < n_bytes; i++) begin
            resp.data_q.push_back(data_q[info.idx][info.way][byte_idx]);
            byte_idx++;
        end
        return resp;
    endfunction

    function automatic void cache_write(
        ref tag_resp_t info, ref byte_t data_q[$]
    );
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = info.byte_idx;
        while (data_q.size() > 0) begin
            info.new_cline[byte_idx] = data_q.pop_front();
            byte_idx++;
        end
    endfunction

    function automatic void cache_evict(ref tag_resp_t info);
        info.new_status[VALID_IDX] = 1'b0;
    endfunction


    function automatic mem_req gen_write_back(tag_resp_t info);
        mem_req mem_req = new;
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

    function automatic mem_req gen_read_allocate(tag_resp_t info, cache_req req);
        mem_req mem_req = new;
        mem_req.size          = $clog2(BYTES_PER_WORD);
        mem_req.len           = CACHELINE_WORDS - 1;
        mem_req.addr          = info.new_addr;
        mem_req.op            = MEM_READ;
        mem_req.cacheable     = '1;
        if (req.op == REQ_STORE) begin
            mem_req.read_snoop_op = ace_pkg::ReadUnique;
        end else begin
            mem_req.read_snoop_op = ace_pkg::ReadShared;
        end
        return mem_req;
    endfunction

    function automatic mem_req gen_clean_unique(tag_resp_t info);
        mem_req mem_req = new;
        mem_req.size          = $clog2(BYTES_PER_WORD);
        mem_req.len           = CACHELINE_WORDS - 1;
        mem_req.addr          = info.new_addr;
        mem_req.op            = MEM_READ;
        mem_req.cacheable     = '1;
        mem_req.read_snoop_op = ace_pkg::CleanUnique;
        return mem_req;
    endfunction

    function automatic mem_req gen_write_line_unique(tag_resp_t info, cache_req req);
        // Merge with write word
        mem_req mem_req = new;
        logic [BLOCK_OFFSET_BITS-1:0] byte_idx = info.byte_idx;
        mem_req.size          = $clog2(BYTES_PER_WORD);
        mem_req.len           = CACHELINE_WORDS - 1;
        mem_req.addr          = info.new_addr;
        mem_req.op            = MEM_WRITE;
        mem_req.cacheable     = '1;
        mem_req.write_snoop_op = ace_pkg::WriteLineUnique;
        for (int i = 0; i < CACHELINE_WORDS; i++) begin
            for (int j = 0; j < BYTES_PER_WORD; j++) begin
                mem_req.data_q.push_back(
                    data_q[info.idx][info.way][i*BYTES_PER_WORD+j]);
            end
        end
        return mem_req;
    endfunction

    function automatic mem_req gen_write_unique(cache_req req);
        mem_req mem_req = new;
        mem_req.size          = $clog2(BYTES_PER_WORD);
        mem_req.len           = 0;
        mem_req.addr          = req.addr;
        mem_req.op            = MEM_WRITE;
        mem_req.cacheable     = '1;
        mem_req.write_snoop_op = ace_pkg::WriteUnique;
        for (int i = 0; i < BYTES_PER_WORD; i++) begin
            mem_req.data_q.push_back(req.data_q.pop_front());
        end
        return mem_req;
    endfunction

    function automatic void allocate(mem_req req, mem_resp resp, ref tag_resp_t info);
        info.new_status[DIRTY_IDX] = resp.pass_dirty;
        info.new_status[SHARD_IDX] = resp.is_shared;
        info.new_status[VALID_IDX] = 1'b1;
        info.byte_idx = 0; // Cache line allocations are always cacheline-aligned
        cache_write(info, resp.data_q);
    endfunction;

    task automatic snoop(input cache_snoop_req req, output cache_snoop_resp resp);
        tag_resp_t tag_lu;
        cache_resp cache_resp;
        resp = new;
        tag_lu = read_and_compare_tag(req.addr);
        resp.snoop_resp.Error = 1'b0;
        if (tag_lu.hit) begin
            cache_req cache_req = new;
            cache_req.addr = req.addr;
            cache_req.size = $clog2(CACHELINE_BYTES);
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
                    resp.snoop_resp.DataTransfer = 1'b1;
                    resp.snoop_resp.IsShared     = 1'b1;
                    resp.snoop_resp.PassDirty    = 1'b0;
                    tag_lu.new_status[SHARD_IDX] = 1'b1;
                    modify_cache(tag_lu, 0, 1);
                end
                ace_pkg::ReadShared: begin
                    // recommended to pass dirty
                    resp.snoop_resp.DataTransfer = 1'b1;
                    resp.snoop_resp.IsShared     = 1'b1;
                    tag_lu.new_status[SHARD_IDX] = 1'b1;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    tag_lu.new_status[DIRTY_IDX] = 1'b0;
                    modify_cache(tag_lu, 0, 1);
                end
                ace_pkg::ReadUnique: begin
                    // data transfer and invalidate
                    resp.snoop_resp.DataTransfer = 1'b1;
                    resp.snoop_resp.IsShared     = 1'b0;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    tag_lu.new_status[VALID_IDX] = 1'b0;
                    modify_cache(tag_lu, 0, 1);
                end
                ace_pkg::CleanInvalid: begin
                    // data transfer dirty and invalidate
                    resp.snoop_resp.DataTransfer = tag_lu.status[DIRTY_IDX];
                    resp.snoop_resp.IsShared     = 1'b0;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    tag_lu.new_status[VALID_IDX] = 1'b0;
                    modify_cache(tag_lu, 0, 1);
                end
                ace_pkg::MakeInvalid: begin
                    // invalidate
                    resp.snoop_resp.DataTransfer = 1'b0;
                    resp.snoop_resp.IsShared     = 1'b0;
                    resp.snoop_resp.PassDirty    = 1'b0;
                    tag_lu.new_status[VALID_IDX] = 1'b0;
                    modify_cache(tag_lu, 0, 1);
                end
                ace_pkg::CleanShared: begin
                    // pass dirty
                    resp.snoop_resp.DataTransfer = tag_lu.status[DIRTY_IDX];
                    resp.snoop_resp.IsShared     = 1'b1;
                    resp.snoop_resp.PassDirty    = tag_lu.status[DIRTY_IDX];
                    tag_lu.new_status[DIRTY_IDX] = 1'b0;
                    tag_lu.new_status[SHARD_IDX] = 1'b1;
                    modify_cache(tag_lu, 0, 1);
                end
                default: $fatal(1, "Unsupported snoop op!");
            endcase
        end else begin
            resp.snoop_resp.WasUnique    = 1'b0;
            resp.snoop_resp.DataTransfer = 1'b0;
            resp.snoop_resp.IsShared     = 1'b0;
            resp.snoop_resp.PassDirty    = 1'b0;
        end
    endtask

    task automatic cache_fsm(input cache_req req, output cache_resp resp);
        bit cache_modified = 1;
        tag_resp_t tag_lu;
        mem_req mem_req = new;
        mem_resp mem_resp;
        resp = new;
        mem_req.cacheable = '1;
        //cache_lookup_sem.get(1);
        tag_lu = read_and_compare_tag(req.addr);
        if (tag_lu.hit) begin
            if (req.op == REQ_LOAD) begin
                resp = cache_read(tag_lu, req);
            end else if (req.op == REQ_STORE) begin
                if (req.cached && tag_lu.status[SHARD_IDX]) begin
                    // Make unique
                    mem_req = gen_clean_unique(tag_lu);
                    mem_req_mbx.put(mem_req);
                    mem_resp_mbx.get(mem_resp);
                    allocate(mem_req, mem_resp, tag_lu);
                end
                cache_write(tag_lu, req.data_q);
                if (req.cached) begin
                    tag_lu.new_status[DIRTY_IDX] = 1'b1;
                end else begin
                    mem_req = gen_write_line_unique(tag_lu, req);
                    mem_req_mbx.put(mem_req);
                    mem_resp_mbx.get(mem_resp);
                    cache_evict(tag_lu);
                end
            end else begin
                $fatal("Unsupported op");
            end
        end else begin
            if (req.cached) begin
                if (tag_lu.status[DIRTY_IDX] &&
                    tag_lu.status[VALID_IDX]) begin
                    // Generate write-back request
                    mem_req = gen_write_back(tag_lu);
                    // Send request and wait for response
                    mem_req_mbx.put(mem_req);
                    mem_resp_mbx.get(mem_resp);
                end
                // Generate read request for new cache line
                mem_req = gen_read_allocate(tag_lu, req);
                // Send request and wait for response
                mem_req_mbx.put(mem_req);
                mem_resp_mbx.get(mem_resp);
                // Allocate cache line for the new entry
                allocate(mem_req, mem_resp, tag_lu);
                // Handle the initial cache request
                if (req.op == REQ_LOAD) begin
                    resp = cache_read(tag_lu, req);
                end else if (req.op == REQ_STORE) begin
                    cache_write(tag_lu, req.data_q);
                    tag_lu.new_status[DIRTY_IDX] = 1'b1;
                end else begin
                    $fatal("Unsupported op");
                end
            end else begin
                cache_modified = 0;
                mem_req = gen_write_unique(req);
                mem_req_mbx.put(mem_req);
                mem_resp_mbx.get(mem_resp);
            end
        end
        modify_cache(tag_lu, 1, cache_modified);
        //cache_resp_mbx.put(resp);
        //cache_lookup_sem.put(1);
    endtask

    task recv_cache_req;
        cache_req req;
        cache_resp resp = new;
        cache_req_mbx.get(req);
        @(posedge clk_if.clk_i);
        cache_fsm(req, resp);
        cache_resp_mbx.put(resp);
    endtask

    task recv_snoop_req;
        cache_snoop_req req;
        cache_snoop_resp resp = new;
        snoop_req_mbx.get(req);
        snoop(req, resp);
        snoop_resp_mbx.put(resp);
    endtask

    // Handle one request per clock cycle
    // Snooping gets priority
    /*
    task handle_reqs;
        int snp_exists;
        int c_req_exists;
        cache_snoop_req snp_req;
        cache_req c_req;
        @(posedge clk_if.clk_i);
        snp_exists = snoop_req_mbx.try_get(snp_req);
        if (snp_exists != 0) begin
            recv_snoop_req(snp_req);
        end
        c_req_exists = cache_req_mbx.try_get(c_req);
        if (c_req_exists) begin
            recv_cache_req(c_req);
        end
    endtask
    */

    task recv_cache_reqs;
        forever recv_cache_req();
    endtask

    task recv_snoop_reqs;
        forever recv_snoop_req();
    endtask

    task run;
        fork
            forever recv_cache_reqs();
            forever recv_snoop_reqs();
        join
    endtask

endclass
