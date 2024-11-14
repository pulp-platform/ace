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
    /// How many words in a cache line
    parameter CACHELINE_WORDS  = 4,
    /// Width of a cacheline word
    parameter WORD_WIDTH       = 32,
    /// How many ways in the cache
    parameter WAYS             = 4,
    /// How many sets in the cache
    parameter SETS             = 1024,
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

    mailbox #(cache_req)  cache_req_mbx        = new();
    mailbox #(cache_resp) cache_resp_mbx       = new();
    mailbox #(mem_req)    mem_req_mbx          = new();
    mailbox #(mem_resp)   mem_resp_mbx         = new();
    mailbox #(aw_beat_t)  aw_mbx               = new();
    mailbox #(w_beat_t)   w_mbx                = new();
    mailbox #(ar_beat_t)  ar_mbx               = new();
    mailbox #(r_beat_t)   r_mbx                = new();
    mailbox #(b_beat_t)   b_mbx                = new();
    mailbox #(cache_snoop_req)  snoop_req_mbx  = new();
    mailbox #(cache_snoop_resp) snoop_resp_mbx = new();

    logic cache_seq_done = 1'b0;

    int unsigned os_cache_reqs = 0;
    localparam int CachelineBytes = (CACHELINE_WORDS * WORD_WIDTH) / 8;

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
        .CACHELINE_BYTES(CachelineBytes),
        .snoop_bus_t(snoop_bus_t),
        .clk_if_t(clk_if_t)
    ) snoop_agent;

    cache_scoreboard #(
        .AW(AW),
        .DW(DW),
        .WORD_WIDTH(WORD_WIDTH),
        .CACHELINE_WORDS(CACHELINE_WORDS),
        .WAYS(WAYS),
        .SETS(SETS),
        .clk_if_t(clk_if_t)
    ) cache_sb;

    cache_sequencer #(
        .AW(AW),
        .DW(DW),
        .clk_if_t(clk_if_t)
    ) cache_seq;

    mem_sequencer #(
        .aw_beat_t(aw_beat_t),
        .ar_beat_t(ar_beat_t),
        .r_beat_t(r_beat_t),
        .w_beat_t(w_beat_t),
        .b_beat_t(b_beat_t)
    ) mem_seq;

    function new(
        ace_bus_t ace,
        snoop_bus_t snoop,
        clk_if_t clk_if,
        string data_mem_file,
        string tag_mem_file,
        string status_file,
        string txn_file,
        string state_file,
        int index
    );
        this.ace    = ace;
        this.snoop  = snoop;
        this.clk_if = clk_if;

        this.ace_agent   = new(this.ace, this.clk_if, this.aw_mbx,
                               this.w_mbx, this.ar_mbx, this.r_mbx,
                               this.b_mbx);
        this.snoop_agent = new(this.snoop, this.clk_if,
                               this.snoop_req_mbx,
                               this.snoop_resp_mbx);
        this.cache_sb    = new(this.clk_if,
                               this.cache_req_mbx, this.cache_resp_mbx,
                               this.snoop_req_mbx, this.snoop_resp_mbx,
                               this.mem_req_mbx, this.mem_resp_mbx,
                               state_file, index);
        this.cache_seq   = new(this.clk_if,
                               this.cache_req_mbx, this.cache_resp_mbx, txn_file);
        this.mem_seq     = new(this.mem_req_mbx, this.mem_resp_mbx,
                               this.aw_mbx, this.ar_mbx, this.r_mbx,
                               this.w_mbx, this.b_mbx);

        this.cache_sb.init_mem_from_file(
            data_mem_file,
            tag_mem_file,
            status_file
        );
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
            this.cache_sb.run();
            this.mem_seq.run();
        join_any
    endtask

endclass
