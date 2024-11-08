`ifndef _SNOOP_TEST_PKG
*** INCLUDED IN snoop_test_pkg ***
`endif
class snoop_sequencer #(
    parameter time TA              = 0ns,  // stimuli application time
    parameter time TT              = 0ns,  // stimuli test time
    parameter int  CD_DW           = 0,
    parameter int  CACHELINE_BYTES = 0,
    parameter type ac_beat_t       = logic,
    parameter type cd_beat_t       = logic,
    parameter type cr_beat_t       = logic
);

    cd_beat_t cd_txn;

    localparam int BYTES_PER_CD_DW = CD_DW / 8;

    // Mailboxes for snoop transactions
    // Should be created and connected outside
    mailbox #(ac_beat_t) ac_mbx;
    mailbox #(cr_beat_t) cr_mbx;
    mailbox #(cd_beat_t) cd_mbx;

    mailbox #(cache_snoop_req)  snoop_req_mbx;
    mailbox #(cache_snoop_resp) snoop_resp_mbx;

    function new(
        mailbox #(ac_beat_t)  ac_mbx,
        mailbox #(cr_beat_t)  cr_mbx,
        mailbox #(cd_beat_t)  cd_mbx,
        mailbox #(cache_snoop_req)  snoop_req_mbx,
        mailbox #(cache_snoop_resp) snoop_resp_mbx
    );
        this.ac_mbx = ac_mbx;
        this.cr_mbx = cr_mbx;
        this.cd_mbx = cd_mbx;

        this.snoop_req_mbx  = snoop_req_mbx;
        this.snoop_resp_mbx = snoop_resp_mbx;
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
        ac_beat_t ac_beat;
        cd_beat_t cd_beat = new;
        cr_beat_t cr_beat = new;
        cache_snoop_req cache_req = new;
        cache_snoop_resp cache_resp;
        int byte_count = 0;
        ac_mbx.get(ac_beat);
        cache_req.addr     = ac_beat.ac_addr;
        cache_req.snoop_op = ac_beat.ac_snoop;
        snoop_req_mbx.put(cache_req);
        snoop_resp_mbx.get(cache_resp);
        cr_beat.cr_resp = cache_resp.snoop_resp;
        cr_mbx.put(cr_beat);
        if (cache_resp.snoop_resp.DataTransfer) begin
            for (int i = 0; i < CACHELINE_BYTES; i++) begin
                cd_beat.cd_data[byte_count*8 +: 8] = cache_resp.data_q.pop_front();
                cd_beat.cd_last = 1'b0;
                byte_count++;
                if (byte_count == BYTES_PER_CD_DW) begin
                    if (i == (CACHELINE_BYTES - 1)) cd_beat.cd_last = 1'b1;
                    cd_mbx.put(cd_beat);
                    cd_beat = new;
                    byte_count = 0;
                end
            end
        end
    endtask

    task run;
        forever gen_snoop_resp();
    endtask

endclass
