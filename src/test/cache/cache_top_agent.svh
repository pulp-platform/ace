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
    parameter type snoop_bus_t = logic,
    /// File path for initial data memory state
    parameter string data_mem_file  = "",
    /// File path for initial tag memory state
    parameter string tag_mem_file  = "",
    /// File path for cacheline status bit
    parameter string status_mem_file  = "",
    /// File path for transactions file
    parameter string txn_file  = "",
    /// File path for recording memory states
    parameter string mem_state_file = ""
);
    ace_bus_t ace;
    snoop_bus_t snoop;
    clk_if_t clk_if;

    typedef ace_test_pkg::ace_aw_beat #(
        .AW(AW), .IW(IW), .UW(UW)
    ) aw_beat_t;

    typedef ace_test_pkg::ace_ar_beat #(
        .AW(AW), .IW(IW), .UW(UW)
    ) ar_beat_t;

    typedef ace_test_pkg::ace_r_beat #(
        .DW(DW), .IW(IW), .UW(UW)
    ) r_beat_t;

    typedef ace_test_pkg::ace_w_beat #(
        .DW(DW), .UW(UW)
    ) w_beat_t;

    typedef ace_test_pkg::ace_b_beat #(
        .IW(IW), .UW(UW)
    ) b_beat_t;

    mailbox #(cache_req)  cache_req_mbx = new;
    mailbox #(cache_resp) cache_resp_mbx = new;
    mailbox #(mem_req)    mem_req_mbx = new;
    mailbox #(mem_resp)   mem_resp_mbx = new;
    mailbox #(aw_beat_t)  aw_mbx = new;
    mailbox #(w_beat_t)   w_mbx = new;
    mailbox #(ar_beat_t)  ar_mbx = new;


    ace_test_pkg::ace_agent #(
        .AW(AW), .DW(DW), .IW(IW), .UW(UW),
        .TA(TA), .TT(TT),
        .ace_bus_t(ace_bus_t),
        .clk_if_t(clk_if_t),
        .aw_beat_t(aw_beat_t),
        .w_beat_t(w_beat_t),
        .ar_beat_t(ar_beat_t),
        .r_beat_t(r_beat_t),
        .b_beat_t(b_beat_t)
    ) ace_agent;

    snoop_test_pkg::snoop_agent #(
        .AW(AC_AW), .DW(CD_DW),
        .TA(TA), .TT(TT),
        .snoop_bus_t(snoop_bus_t),
        .clk_if_t(clk_if_t)
    ) snoop_agent;

    cache_scoreboard #(
        .AW(AW),
        .DW(DW),
        .WORD_WIDTH(DW),
        .CACHELINE_WORDS(4),
        .WAYS(2),
        .SETS(1024)
    ) cache_sb;

    cache_sequencer #(
        .AW(AW),
        .txn_file("/scratch2/akorsman/ace/scripts/python/txns.csv")
    ) cache_seq;

    mem_sequencer #(
        .aw_beat_t(aw_beat_t),
        .ar_beat_t(ar_beat_t),
        .w_beat_t(w_beat_t)
    ) mem_seq;

    function new(
        ace_bus_t ace,
        snoop_bus_t snoop,
        clk_if_t clk_if
    );
        this.ace    = ace;
        this.snoop  = snoop;
        this.clk_if = clk_if;

        this.ace_agent   = new(this.ace, this.clk_if, this.aw_mbx, this.w_mbx, this.ar_mbx);
        this.snoop_agent = new(this.snoop, this.clk_if);
        this.cache_sb    = new(this.cache_req_mbx, this.cache_resp_mbx,
                               this.mem_req_mbx, this.mem_resp_mbx);
        this.cache_seq   = new(this.cache_req_mbx);
        this.mem_seq     = new(this.mem_req_mbx, this.mem_resp_mbx,
                               this.aw_mbx, this.ar_mbx, this.w_mbx);

        this.cache_sb.init_mem_from_file(
            data_mem_file, tag_mem_file, status_mem_file);

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
            this.cache_seq.run();
        join
    endtask

endclass