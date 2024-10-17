package snoop_test_pkg;
    `define _SNOOP_TEST_PKG
    typedef enum logic [3:0] {
        AC_READ_ONCE             = 0,
        AC_READ_SHARED           = 1,
        AC_READ_CLEAN            = 2,
        AC_READ_NOT_SHARED_DIRTY = 3,
        AC_READ_UNIQUE           = 4,
        AC_CLEAN_SHARED          = 5,
        AC_CLEAN_INVALID         = 6,
        AC_MAKE_INVALID          = 7,
        AC_DVM_COMPLETE          = 8,
        AC_DVM_MESSAGE           = 9
    } ac_snoop_e;

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
        logic               cd_last;
    endclass
    `include "snoop/snoop_driver.svh"
    `include "snoop/snoop_monitor.svh"
    `include "snoop/snoop_sequencer.svh"
    `include "snoop/snoop_agent.svh"


endpackage