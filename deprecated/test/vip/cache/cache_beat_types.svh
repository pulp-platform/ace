`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif


// Cache Requester operations
localparam int REQ_LOAD           = 5'b00000;
localparam int REQ_STORE          = 5'b00001;

// Cache Memory operations
localparam int MEM_READ        = 3'b000;
localparam int MEM_WRITE       = 3'b001;
//localparam int MEM_ATOMIC      = 3'b010;

/// Datatype to orchestrate cache read and write requests
class cache_req;
    int unsigned addr         = 0;
    logic [7:0]  data_q[$];
    int unsigned op           = REQ_LOAD;
    bit          cached       = 0;
    int unsigned shareability = 0;
    int unsigned size         = 0;
    int unsigned timestamp    = 0;
endclass

/// Datatype to orchestrate cache lookups between
/// cache sequencer and cache scoreboard
class cache_resp;
    logic [7:0]       data_q[$];
endclass

class mem_req;
    int unsigned       addr           = 0;
    int unsigned       len            = 0;
    int unsigned       size           = 0;
    int unsigned       op             = MEM_READ;
    logic [7:0]        data_q[$];
    int unsigned       cacheable      = 0;
    ace_pkg::arsnoop_t read_snoop_op  = ace_pkg::ReadShared;
    ace_pkg::awsnoop_t write_snoop_op = ace_pkg::WriteBack;
endclass

class mem_resp;
    logic [7:0] data_q[$];
    bit         is_shared  = 0;
    bit         pass_dirty = 0;
endclass
