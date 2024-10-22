`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_scoreboard #(
    parameter int AW = 32,
    parameter int DW = 32,
    parameter int TW = 8,
    parameter int WORD_WIDTH,
    parameter int CACHELINE_WORDS,
    parameter int WAYS,
);

    localparam int CACHELINE_BITS = WORD_WIDTH * CACHELINE_WORDS;

    typedef logic [TW-1:0]             tag_t;
    typedef logic [AW-1:0]             addr_t;
    typedef logic [7:0]                byte_t;
    typedef logic [CACHELINE_BITS-1:0] cacheline_t;
    typedef logic [2:0]                status_t;
    
    cacheline_t  data_q[addr_t];   // Cache data
    status_t     status_q[addr_t]; // Cache state

    mailbox #(cache_req)  cache_req_mbx;
    mailbox #(cache_resp) cache_resp_mbx;

    function new(
        mailbox #(cache_req)  cache_req_mbx,
        mailbox #(cache_resp) cache_resp_mbx
    );
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
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

    task cache_req;
        cache_req req;
        cache_resp resp;
        cache_req_mbx.get(req);
    endtask

endclass