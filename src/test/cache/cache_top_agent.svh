`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_top_agent #(
    /// Address width
    parameter AW      = 32,
    /// Data width
    parameter DW      = 32,
    /// Snoop address width
    parameter AC_AW   = 32,
    /// Snoop data width
    parameter CD_DW   = 32,
    /// ID width
    parameter IW      = 8 ,
    /// User width
    parameter UW      = 1,
    /// Stimuli application time
    parameter time TA = 0ns,
    /// Stimuli test time
    parameter time TT = 0ns,
    /// ACE bus interface type
    parameter type ace_bus_t   = logic,
    /// Clock interface type
    parameter type clk_if_t    = logic,
    /// Snoop bus interface type
    parameter type snoop_bus_t = logic
);
    ace_bus_t ace;
    snoop_bus_t snoop;
    clk_if_t clk_if;

    ace_test_pkg::ace_agent #(
        .AW(AW), .DW(DW), .IW(IW), .UW(UW),
        .TA(TA), .TT(TT),
        .ace_bus_t(ace_bus_t),
        .clk_if_t(clk_if_t)
    ) ace_agent;

    snoop_test_pkg::snoop_agent #(
        .AW(AC_AW), .DW(CD_DW),
        .TA(TA), .TT(TT),
        .snoop_bus_t(snoop_bus_t),
        .clk_if_t(clk_if_t)
    ) snoop_agent;

    function new(
        ace_bus_t ace,
        snoop_bus_t snoop,
        clk_if_t clk_if
    );
        this.ace    = ace;
        this.snoop  = snoop;
        this.clk_if = clk_if;

        this.ace_agent   = new(this.ace, this.clk_if);
        this.snoop_agent = new(this.snoop, this.clk_if);
    endfunction

    task reset;
        fork
            this.ace_agent.reset();
            this.snoop_agent.reset();
        join
    endtask

    task run;
        fork
            this.ace_agent.run();
            this.snoop_agent.run();
        join
    endtask

endclass