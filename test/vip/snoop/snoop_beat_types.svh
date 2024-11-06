`ifndef _SNOOP_TEST_PKG
*** INCLUDED IN snoop_test_pkg ***
`endif
/// The data transferred on a beat on the AC channel.
class ace_ac_beat #(
    parameter AW = 32
);
    rand logic [AW-1:0] ac_addr  = '0;
    logic      [3:0]    ac_snoop = '0;
    logic      [2:0]    ac_prot  = '0;
endclass

/// The data transferred on a beat on the CR channel.
class ace_cr_beat;
    ace_pkg::crresp_t cr_resp = '0;
endclass

/// The data transferred on a beat on the CD channel.
class ace_cd_beat #(
    parameter DW = 32
);
    rand logic [DW-1:0] cd_data = '0;
    logic               cd_last = '0;
endclass

// Snoop request to a cache
class cache_snoop_req;
    int unsigned       addr     = 0;
    ace_pkg::acsnoop_t snoop_op = '0;
endclass

// Snoop response from a cache
class cache_snoop_resp;
    logic [7:0]       data_q[$];
    ace_pkg::crresp_t snoop_resp = '0;
endclass