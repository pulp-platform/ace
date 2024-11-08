`ifndef _ACE_TEST_PKG
*** INCLUDED IN ace_test_pkg ***
`endif
class ace_agent #(
    /// Address width
    parameter AW      = 32,
    /// Data width
    parameter DW      = 32,
    /// ID width
    parameter IW      = 8 ,
    /// User width
    parameter UW      = 1,
    /// Stimuli application time
    parameter time TA = 0ns,
    /// Stimuli test time
    parameter time TT = 0ns,
    /// ACE bus interface type
    parameter type ace_bus_t = logic,
    /// Clock interface type
    parameter type clk_if_t  = logic,
    parameter type aw_beat_t = logic,
    parameter type w_beat_t  = logic,
    parameter type ar_beat_t = logic,
    parameter type r_beat_t  = logic,
    parameter type b_beat_t  = logic
);

    mailbox #(aw_beat_t) i_aw_mbx = new;
    mailbox #(w_beat_t) i_w_mbx  = new;
    mailbox #(ar_beat_t) i_ar_mbx = new;

    mailbox #(aw_beat_t) aw_mbx;
    mailbox #(w_beat_t)  w_mbx;
    mailbox #(ar_beat_t) ar_mbx;
    mailbox #(r_beat_t)  r_mbx;
    mailbox #(b_beat_t)  b_mbx;

    ace_bus_t  ace;
    clk_if_t clk_if;

    ace_driver #(
        .AW(AW), .DW(DW), .IW(IW),
        .UW(UW), .TA(TA), .TT(TT),
        .ace_bus_t(ace_bus_t),
        .aw_beat_t(aw_beat_t),
        .ar_beat_t(ar_beat_t),
        .w_beat_t(w_beat_t)
    ) ace_drv;

    ace_mbox_sequencer #(
        .AW(AW), .IW(IW), .UW(UW), .DW(DW),
        .aw_beat_t(aw_beat_t),
        .ar_beat_t(ar_beat_t),
        .w_beat_t(w_beat_t),
        .RAND_WAIT(0)
    ) ace_seq;

    ace_monitor #(
        .TA(TA), .TT(TT),
        .ace_bus_t(ace_bus_t),
        .ar_beat_t(ar_beat_t),
        .r_beat_t(r_beat_t),
        .b_beat_t(b_beat_t)
    ) ace_mon;

    function new(
        ace_bus_t   ace,
        clk_if_t    clk_if,
        mailbox #(aw_beat_t) aw_mbx,
        mailbox #(w_beat_t)  w_mbx,
        mailbox #(ar_beat_t) ar_mbx,
        mailbox #(r_beat_t)  r_mbx,
        mailbox #(b_beat_t)  b_mbx
    );
        this.ace    = ace;
        this.clk_if = clk_if;

        this.aw_mbx = aw_mbx;
        this.w_mbx  = w_mbx;
        this.ar_mbx = ar_mbx;
        this.r_mbx  = r_mbx;
        this.b_mbx  = b_mbx;

        this.ace_drv = new(
            this.ace, this.i_aw_mbx,
            this.i_w_mbx, this.i_ar_mbx
        );
        this.ace_seq = new(
            this.clk_if, this.i_aw_mbx,
            this.i_w_mbx, this.i_ar_mbx,
            this.aw_mbx, this.w_mbx,
            this.ar_mbx
        );
        this.ace_mon = new(
            this.ace, this.ar_mbx,
            this.r_mbx, this.b_mbx
        );
    endfunction

    task reset;
        this.ace_drv.reset();
    endtask

    task run;
        fork
            this.ace_drv.run();
            this.ace_seq.run();
            this.ace_mon.run();
        join
    endtask

endclass
