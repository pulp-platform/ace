`ifndef _ACE_TEST_PKG
*** INCLUDED IN ace_test_pkg ***
`endif

virtual class ace_sequencer #(
    parameter AW              = 32,
    parameter DW              = 32,
    parameter IW              = 8,
    parameter UW              = 1,
    parameter type aw_beat_t  = logic,
    parameter type ar_beat_t  = logic,
    parameter type w_beat_t   = logic
);

    // Input mailboxes
    mailbox #(aw_beat_t) aw_mbx_i;
    mailbox #(ar_beat_t) ar_mbx_i;
    mailbox #(w_beat_t)  w_mbx_i;

    // Output mailboxes
    mailbox #(aw_beat_t) aw_mbx_o;
    mailbox #(ar_beat_t) ar_mbx_o;
    mailbox #(w_beat_t)  w_mbx_o;

    // Clock interface needed for generating delays
    // between sending transactions
    virtual CLK_IF clk_if;

    function new(
        virtual CLK_IF clk_if,
        mailbox #(aw_beat_t) aw_mbx_o,
        mailbox #(w_beat_t)  w_mbx_o,
        mailbox #(ar_beat_t) ar_mbx_o
    );
        this.clk_if = clk_if;

        this.aw_mbx_o = aw_mbx_o;
        this.ar_mbx_o = ar_mbx_o;
        this.w_mbx_o  = w_mbx_o;

    endfunction

    task automatic rand_wait(input int unsigned min, max);
        int unsigned rand_success, cycles;
        cycles = $urandom_range(min, max);
        repeat (cycles) begin
            @(posedge this.clk_if.clk_i);
        end
    endtask

endclass

// Class which generates random sequences
class ace_rand_sequencer #(
    parameter AW              = 32,
    parameter DW              = 32,
    parameter IW              = 8,
    parameter UW              = 1,
    parameter type aw_beat_t  = logic,
    parameter type ar_beat_t  = logic,
    parameter type w_beat_t   = logic
) extends ace_sequencer #(
    .AW(AW), .DW(DW), .IW(IW), .UW(UW),
    .aw_beat_t(aw_beat_t),
    .ar_beat_t(ar_beat_t),
    .w_beat_t(w_beat_t)
);

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
            aw_mbx_o.put(aw_txn);
        end
    endtask

    task send_ws();
        w_beat_t w_txn = new;
        repeat (10) begin
            for (int i = 0; i < 4; i++) begin
                rand_wait(2, 20);
                w_txn = create_w();
                if (i == 3) w_txn.last = '1;
                w_mbx_o.put(w_txn);
            end
        end
    endtask

    task send_ars();
        ar_beat_t ar_txn = new;
        repeat (10) begin
            rand_wait(2, 20);
            ar_txn = create_ar();
            ar_mbx_o.put(ar_txn);
        end
    endtask

    task run();
        send_aws();
        send_ws();
        send_ars();
    endtask
    
endclass

// Class which generates sequences when detected in
// input mailboxes
class ace_mbox_sequencer #(
    parameter AW              = 32,
    parameter DW              = 32,
    parameter IW              = 8,
    parameter UW              = 1,
    parameter type aw_beat_t  = logic,
    parameter type ar_beat_t  = logic,
    parameter type w_beat_t   = logic,
    parameter RAND_WAIT       = 1
) extends ace_sequencer #(
    .AW(AW), .DW(DW), .IW(IW), .UW(UW),
    .aw_beat_t(aw_beat_t),
    .ar_beat_t(ar_beat_t),
    .w_beat_t(w_beat_t)
);

    function new(
        virtual CLK_IF clk_if,
        mailbox #(aw_beat_t) aw_mbx_o,
        mailbox #(w_beat_t)  w_mbx_o,
        mailbox #(ar_beat_t) ar_mbx_o,
        mailbox #(aw_beat_t) aw_mbx_i,
        mailbox #(w_beat_t)  w_mbx_i,
        mailbox #(ar_beat_t) ar_mbx_i
    );
        super.new(clk_if, aw_mbx_o, w_mbx_o, ar_mbx_o);
        this.aw_mbx_i = aw_mbx_i;
        this.ar_mbx_i = ar_mbx_i;
        this.w_mbx_i = w_mbx_i;
    endfunction

    task wait_for_aws;
        aw_beat_t aw_beat;
        forever begin
            aw_mbx_i.get(aw_beat);
            if (RAND_WAIT) rand_wait(2, 20);
            aw_mbx_o.put(aw_beat);
        end
    endtask

    task wait_for_ars;
        ar_beat_t ar_beat;
        forever begin
            ar_mbx_i.get(ar_beat);
            if (RAND_WAIT) rand_wait(2, 20);
            ar_mbx_o.put(ar_beat);
        end
    endtask

    task wait_for_ws;
        w_beat_t w_beat;
        forever begin
            w_mbx_i.get(w_beat);
            if (RAND_WAIT) rand_wait(2, 20);
            w_mbx_o.put(w_beat);
        end
    endtask

    task gen_txns_from_mbox;
        fork
            wait_for_aws();
            wait_for_ws();
            wait_for_ars();
        join
    endtask

    task run();
        gen_txns_from_mbox();
    endtask
    
endclass