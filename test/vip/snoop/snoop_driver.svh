`ifndef _SNOOP_TEST_PKG
*** INCLUDED IN snoop_test_pkg ***
`endif
class snoop_driver #(
    parameter time TA            = 0ns,  // stimuli application time
    parameter time TT            = 0ns,  // stimuli test time
    parameter type snoop_bus_t   = logic,
    parameter type ac_beat_t     = logic,
    parameter type cd_beat_t     = logic,
    parameter type cr_beat_t     = logic
);

    snoop_bus_t snoop;

    cd_beat_t cd_txn;
    cr_beat_t cr_txn;

    // Mailboxes for CD and CR transcations
    // Should be created and connected outside
    mailbox #(cd_beat_t) cd_mbx;
    mailbox #(cr_beat_t) cr_mbx;

    function new (
        snoop_bus_t snoop,
        mailbox #(cr_beat_t) cr_mbx,
        mailbox #(cd_beat_t) cd_mbx
    );
        this.snoop = snoop;

        this.cr_mbx = cr_mbx;
        this.cd_mbx = cd_mbx;
    endfunction

    task cycle_start;
        #TT;
    endtask

    task cycle_end;
        @(posedge snoop.clk_i);
    endtask

    task reset;
        snoop.ac_ready <= '0;
        snoop.cr_valid <= '0;
        snoop.cr_resp  <= '0;
        snoop.cd_valid <= '0;
        snoop.cd_data  <= '0;
        snoop.cd_last  <= '0;
    endtask

    task rec_cd_txns;
        // Ensure that mailbox is read only
        // at cycle_end
        forever begin
            cd_beat_t beat;
            if (cd_mbx.try_get(beat)) begin
                send_cd(beat);
            end else begin
                cycle_end();
            end
        end
    endtask

    task rec_cr_txns;
        // Ensure that mailbox is read only
        // at cycle_end
        forever begin
            cr_beat_t beat;
            if (cr_mbx.try_get(beat)) begin
                send_cr(beat);
            end else begin
                cycle_end();
            end
        end
    endtask

    /// Issue a beat on the CR channel.
    task send_cr(cr_beat_t beat);
        snoop.cr_valid  <= #TA 1;
        snoop.cr_resp   <= #TA beat.cr_resp;
        cycle_start();
        while (snoop.cr_ready != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        snoop.cr_valid <= #TA '0;
        snoop.cr_resp  <= #TA '0;
    endtask

    /// Issue a beat on the CD channel.
    task send_cd(cd_beat_t beat);
        snoop.cd_valid  <= #TA 1;
        snoop.cd_data   <= #TA beat.cd_data;
        snoop.cd_last   <= #TA beat.cd_last;
        cycle_start();
        while (snoop.cd_ready != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        snoop.cd_valid <= #TA '0;
        snoop.cd_data  <= #TA '0;
        snoop.cd_last  <= #TA '0;
    endtask

    /// Randomly toggle ACREADY.
    /// Address is read in snoop_monitor.
    task recv_ac ();
        snoop.ac_ready <= #TA $urandom_range(0,1);
        cycle_start();
        cycle_end();
    endtask

    task run();
        fork
            rec_cd_txns();
            rec_cr_txns();
            forever recv_ac();
        join
    endtask
endclass
