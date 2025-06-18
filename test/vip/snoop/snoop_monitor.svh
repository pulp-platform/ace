`ifndef _SNOOP_TEST_PKG
*** INCLUDED IN snoop_test_pkg ***
`endif
class snoop_monitor #(
    parameter time TA            = 0ns,  // stimuli application time
    parameter time TT            = 0ns,  // stimuli test time
    parameter type snoop_bus_t   = logic,
    parameter type ac_beat_t     = logic,
    parameter type cd_beat_t     = logic,
    parameter type cr_beat_t     = logic
);

    snoop_bus_t snoop;

    // Mailbox for AC transactions
    // Should be created and connected outside
    mailbox #(ac_beat_t) ac_mbx;

    task cycle_start;
        #TT;
    endtask

    task cycle_end;
        @(posedge snoop.clk_i);
    endtask

    function new (
        snoop_bus_t snoop,
        mailbox #(ac_beat_t) ac_mbx
    );
        this.snoop = snoop;
        this.ac_mbx = ac_mbx;
    endfunction

    task mon_ac;
        ac_beat_t ac_txn = new;
        cycle_start();
        while (!(snoop.ac_valid && snoop.ac_ready)) begin cycle_end(); cycle_start(); end
        ac_txn.ac_addr  = snoop.ac_addr;
        ac_txn.ac_snoop = snoop.ac_snoop;
        ac_txn.ac_prot  = snoop.ac_prot;
        ac_mbx.put(ac_txn);
        cycle_end();
    endtask

    task run;
        forever mon_ac();
    endtask

endclass
