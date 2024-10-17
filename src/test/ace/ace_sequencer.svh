`ifndef _ACE_TEST_PKG
*** INCLUDED IN ace_test_pkg ***
`endif
class ace_sequencer #(
    parameter AW              = 32,
    parameter DW              = 32,
    parameter IW              = 8,
    parameter UW              = 1,
    parameter type aw_beat_t  = logic,
    parameter type ar_beat_t  = logic,
    parameter type w_beat_t   = logic
);

    mailbox aw_mbx, ar_mbx, w_mbx;

    virtual CLK_IF clk_if;

    function new(
        virtual CLK_IF clk_if,
        mailbox aw_mbx,
        mailbox w_mbx,
        mailbox ar_mbx
    );
        this.clk_if = clk_if;

        this.aw_mbx = aw_mbx;
        this.ar_mbx = ar_mbx;
        this.w_mbx  = w_mbx;
    endfunction

    task automatic rand_wait(input int unsigned min, max);
        int unsigned rand_success, cycles;
        cycles = $urandom_range(min, max);
        repeat (cycles) begin
            @(posedge this.clk_if.clk_i);
        end
    endtask

    function aw_beat_t create_aw();
        aw_beat_t beat = new;
        beat.addr = $urandom();
        beat.burst = axi_pkg::BURST_WRAP;
        beat.size = $clog2(DW);
        beat.len = 3;
        beat.id = '0;
        beat.qos = '0;
        beat.snoop = ace_pkg::WriteUnique;
        beat.bar = '0;
        beat.domain = 'b1;
        beat.awunique = '0;
        return beat;
    endfunction

    function ar_beat_t create_ar();
        ar_beat_t beat = new;
        beat.addr = $urandom();
        beat.burst = axi_pkg::BURST_WRAP;
        beat.size = $clog2(DW);
        beat.len = 3;
        beat.id = '0;
        beat.qos = '0;
        beat.snoop = ace_pkg::ReadShared;
        beat.bar = '0;
        beat.domain = 'b1;
        return beat;
    endfunction

    function w_beat_t create_w();
        w_beat_t beat = new;
        beat.data   = $urandom();
        beat.strb   = '1;
        beat.last   = '0;
        return beat;
    endfunction

    task send_aws();
        aw_beat_t aw_txn = new;
        repeat (10) begin
            rand_wait(2, 20);
            aw_txn = create_aw();
            aw_mbx.put(aw_txn);
        end
    endtask

    task send_ws();
        w_beat_t w_txn = new;
        repeat (10) begin
            for (int i = 0; i < 4; i++) begin
                rand_wait(2, 20);
                w_txn = create_w();
                if (i == 3) w_txn.last = '1;
                w_mbx.put(w_txn);
            end
        end
    endtask

    task send_ars();
        ar_beat_t ar_txn = new;
        repeat (10) begin
            rand_wait(2, 20);
            ar_txn = create_ar();
            ar_mbx.put(ar_txn);
        end
    endtask

    task run();
        send_aws();
        send_ws();
        send_ars();
    endtask
    
endclass