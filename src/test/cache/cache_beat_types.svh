`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif

/// Datatype to orchestrate cache read and write requests
class cache_req;
    unsigned int addr;
    unsigned int data_q[$];
    unsigned int len;
    unsigned int size;
    boolean read;
    boolean write;
endclass

/// Datatype to orchestrate cache lookups between
/// cache sequencer and cache scoreboard
class cache_lookup_resp;
    unsigned int data_q[$];
    boolean      hit;
endclass
