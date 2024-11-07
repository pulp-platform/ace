`ifndef _SNOOP_TEST_PKG
*** INCLUDED IN snoop_test_pkg ***
`endif
class snoop_agent #(
    /// Snoop address width
    parameter      AW = 32,
    /// Snoop data width
    parameter      DW = 32,
    /// Bytes in a cacheline
    parameter      CACHELINE_BYTES = 0,
    /// Stimuli application time
    parameter time TA = 0ns,
    /// Stimuli test time
    parameter time TT = 0ns,
    /// Snoop bus interface type
    parameter type snoop_bus_t = logic,
    /// Clock interface type
    parameter type clk_if_t = logic
);
    typedef ace_ac_beat #(
        .AW(AW)
    ) ac_beat_t;

    typedef ace_cr_beat cr_beat_t;

    typedef ace_cd_beat #(
        .DW(DW)
    ) cd_beat_t;

    snoop_bus_t snoop;
    clk_if_t    clk_if;

    mailbox #(ac_beat_t) ac_mbx = new;
    mailbox #(cd_beat_t) cd_mbx = new;
    mailbox #(cr_beat_t) cr_mbx = new;

    snoop_driver #(
        .TA(TA), .TT(TT),
        .snoop_bus_t(snoop_bus_t),
        .ac_beat_t(ac_beat_t),
        .cd_beat_t(cd_beat_t),
        .cr_beat_t(cr_beat_t)
    ) snoop_drv;

    snoop_monitor #(
        .TA(TA), .TT(TT),
        .snoop_bus_t(snoop_bus_t),
        .ac_beat_t(ac_beat_t),
        .cd_beat_t(cd_beat_t),
        .cr_beat_t(cr_beat_t)
    ) snoop_mon;

    snoop_sequencer #(
        .TA(TA), .TT(TT), .CD_DW(DW),
        .CACHELINE_BYTES(CACHELINE_BYTES),
        .ac_beat_t(ac_beat_t),
        .cd_beat_t(cd_beat_t),
        .cr_beat_t(cr_beat_t)
    ) snoop_seq;

    function new(
        snoop_bus_t snoop,
        clk_if_t clk_if,
        mailbox #(cache_snoop_req)  snoop_req_mbx,
        mailbox #(cache_snoop_resp) snoop_resp_mbx
    );
        this.snoop  = snoop;
        this.clk_if = clk_if;

        this.snoop_drv = new(
            this.snoop, this.cr_mbx,
            this.cd_mbx
        );
        this.snoop_mon = new(
            this.snoop, this.ac_mbx
        );
        this.snoop_seq = new(
            this.ac_mbx, this.cr_mbx,
            this.cd_mbx,
            snoop_req_mbx,
            snoop_resp_mbx
        );

    endfunction

    task reset;
        this.snoop_drv.reset();
    endtask

    task run;
        fork
            this.snoop_drv.run();
            this.snoop_mon.run();
            this.snoop_seq.run();
        join
    endtask

endclass
