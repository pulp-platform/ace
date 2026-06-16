`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class mem_logger #(
    parameter int  AW        = 0,
    parameter int  DW        = 0,
    parameter int  IW        = 0,
    parameter int  UW        = 0,
    parameter time TA        = 0ns, // stimuli application time
    parameter time TT        = 0ns, // stimuli test time
    parameter type mon_bus_t = logic
);

    typedef logic [AW-1:0] addr_t;
    typedef logic [DW-1:0] data_t;
    typedef logic [7:0]    byte_t;

    mon_bus_t mem_mon_bus;

    string log_file;
    bit first_write = 1;

    function new(
        mon_bus_t mon,
        string log_file
    );
        this.mem_mon_bus = mon;
        this.log_file    = log_file;
    endfunction

    function void log_word(
        addr_t addr,
        data_t data
    );
        int fd;
        if (first_write) fd = $fopen(log_file, "w");
        else             fd = $fopen(log_file, "a");
        first_write = 0;
        for (int i = 0; i < DW / 8; i++) begin
            addr_t byte_addr = addr + i;
            byte_t byte_data = data[i*8 +: 8];
            $fwrite(fd, "ADDR:%x DATA:%x\n", byte_addr, byte_data);
        end
        $fclose(fd);
    endfunction

    function void log_time();
        int fd;
        if (first_write) fd = $fopen(log_file, "w");
        else             fd = $fopen(log_file, "a");
        first_write = 0;
        $fwrite(fd, "TIME:%0t\n", $time);
        $fclose(fd);
    endfunction

    task recv_writes;
        addr_t w_addr;
        byte_t data[$];
        int unsigned beat_count = 0;
        forever begin
            @(posedge mem_mon_bus.clk_i);
            if (mem_mon_bus.w_valid) begin
                beat_count = mem_mon_bus.w_beat_count;
                if (beat_count == 0) log_time();
                log_word(mem_mon_bus.w_addr, mem_mon_bus.w_data);
            end
        end
    endtask

    task run;
        recv_writes();
    endtask

endclass
