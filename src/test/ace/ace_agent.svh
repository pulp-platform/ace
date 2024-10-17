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
    parameter type clk_if_t  = logic
);
    typedef ace_aw_beat #(
        .AW(AW), .IW(IW), .UW(UW)
    ) aw_beat_t;

    typedef ace_ar_beat #(
        .AW(AW), .IW(IW), .UW(UW)
    ) ar_beat_t;

    typedef ace_r_beat #(
        .DW(DW), .IW(IW), .UW(UW)
    ) r_beat_t;

    typedef ace_w_beat #(
        .DW(DW), .UW(UW)
    ) w_beat_t;

    typedef ace_b_beat #(
        .IW(IW), .UW(UW)
    ) b_beat_t;

    mailbox aw_mbx = new;
    mailbox w_mbx  = new;
    mailbox ar_mbx = new;

    ace_bus_t  ace;
    clk_if_t clk_if;

    ace_driver #(
        .AW(AW), .DW(DW), .IW(IW),
        .UW(UW), .TA(TA), .TT(TT),
        .ace_bus_t(ace_bus_t),
        .aw_beat_t(aw_beat_t),
        .ar_beat_t(ar_beat_t),
        .w_beat_t(w_beat_t),
        .b_beat_t(b_beat_t)
    ) ace_drv;

    ace_sequencer #(
        .AW(AW), .IW(IW), .UW(UW), .DW(DW),
        .aw_beat_t(aw_beat_t),
        .ar_beat_t(ar_beat_t),
        .w_beat_t(w_beat_t)
    ) ace_seq;

    function new(
        ace_bus_t   ace,
        clk_if_t    clk_if
    );
        this.ace    = ace;
        this.clk_if = clk_if;

        this.ace_drv = new(
            this.ace, this.aw_mbx,
            this.w_mbx, this.ar_mbx
        );
        this.ace_seq = new(
            this.clk_if, this.aw_mbx,
            this.w_mbx, this.ar_mbx
        );
    endfunction

    task reset;
        this.ace_drv.reset();
    endtask

    task run;
        fork
            this.ace_drv.run();
            this.ace_seq.run();
        join
    endtask

endclass