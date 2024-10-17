`ifndef _SNOOP_TEST_PKG
*** INCLUDED IN snoop_test_pkg ***
`endif
class snoop_sequencer #(
    parameter time TA            = 0ns,  // stimuli application time
    parameter time TT            = 0ns,  // stimuli test time
    parameter int  SNOOP_LEN     = 4,
    parameter type ac_beat_t     = logic,
    parameter type cd_beat_t     = logic,
    parameter type cr_beat_t     = logic
);
    cd_beat_t cd_txn;

    // Mailboxes for snoop transactions
    // Should be created and connected outside
    mailbox ac_mbx, cr_mbx, cd_mbx;

    function new(
        mailbox ac_mbx,
        mailbox cr_mbx,
        mailbox cd_mbx
    );
        this.ac_mbx = ac_mbx;
        this.cr_mbx = cr_mbx;
        this.cd_mbx = cd_mbx;
    endfunction

    function cd_beat_t gen_rand_cd;
        cd_beat_t beat = new;
        beat.cd_data = $urandom();
        beat.cd_last = '0;
        return beat;
    endfunction

    function cr_beat_t gen_rand_cr;
        cr_beat_t beat = new;
        beat.cr_resp[4:2] = $urandom_range(0, 3'b111);
        beat.cr_resp[1]   = 1'b0;
        beat.cr_resp[0]   = $urandom_range(0, 1);
        return beat;
    endfunction

    task gen_snoop_resp;
        ac_beat_t ac_txn = new;
        cd_beat_t cd_txn = new;
        cr_beat_t cr_txn = new;
        ac_mbx.get(ac_txn);
        for (int i = 0; i < SNOOP_LEN; i++) begin
            cd_txn = gen_rand_cd();
            if (i == (SNOOP_LEN - 1)) begin
                cd_txn.cd_last = '1;
            end
            cd_mbx.put(cd_txn);
        end
        cr_txn = gen_rand_cr();
        cr_mbx.put(cr_txn);
    endtask

    task run;
        forever gen_snoop_resp;
    endtask

endclass