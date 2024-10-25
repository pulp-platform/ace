`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif


// Cache Requester operations
localparam int REQ_LOAD        = 5'b00000;
localparam int REQ_STORE       = 5'b00001;
localparam int CMO_FLUSH_NLINE = 5'b10100;

// Cache Memory operations
localparam int MEM_READ       = 3'b000;
localparam int MEM_WRITE      = 3'b001;
localparam int MEM_ATOMIC     = 3'b010;
localparam int MEM_WRITE_BACK = 3'b011;

localparam int WR_POLICY_WB   = 3'b010;
localparam int WR_POLICY_WT   = 3'b100;

/// Datatype to orchestrate cache read and write requests
class cache_req;
    int unsigned addr;
    int unsigned data;
    int unsigned size;
    int unsigned op;
    bit          uncacheable;
    bit          wr_policy_hint;
endclass

/// Datatype to orchestrate cache lookups between
/// cache sequencer and cache scoreboard
class cache_resp;
    int unsigned data;
endclass

class mem_req;
    int unsigned addr;
    int unsigned len;
    int unsigned size;
    int unsigned op;
    int unsigned data_q[$];
endclass

class mem_resp;
    int unsigned data_q[$];
    bit is_shared;
    bit pass_dirty;
endclass