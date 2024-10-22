`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif

/// Datatype to orchestrate cache read and write requests
class cache_req;
    int unsigned addr;
    int unsigned data_q[$];
    int unsigned len;
    int unsigned size;
    bit          read;
    bit          write;
endclass

/// Datatype to orchestrate cache lookups between
/// cache sequencer and cache scoreboard
class cache_resp;
    int unsigned data_q[$];
    bit          hit;
endclass
