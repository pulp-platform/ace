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

    `include "snoop/snoop_beat_types.svh"
    `include "snoop/snoop_driver.svh"
    `include "snoop/snoop_monitor.svh"
    `include "snoop/snoop_sequencer.svh"
    `include "snoop/snoop_agent.svh"


endpackage