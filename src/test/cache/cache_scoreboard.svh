`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_scoreboard #(
    parameter int AW = 32
);

    typedef logic [AW-1:0] addr_t;
    typedef logic [7:0]    byte_t;
    typedef logic [2:0]    status_t;

    byte_t   memory_q[addr_t]; // Cache data
    status_t status_q[addr_t]; // Cache state

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

endclass