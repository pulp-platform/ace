`ifndef _ACE_TEST_PKG
*** INCLUDED IN ace_test_pkg ***
`endif
class ace_driver #(
    parameter AW              = 32,
    parameter DW              = 32,
    parameter IW              = 8 ,
    parameter UW              = 1,
    parameter time TA         = 0ns, // stimuli application time
    parameter time TT         = 0ns,  // stimuli test time
    parameter type ace_bus_t  = logic,
    parameter type aw_beat_t  = logic,
    parameter type ar_beat_t  = logic,
    parameter type w_beat_t   = logic
);
    aw_beat_t aw_txn;
    ar_beat_t ar_txn;
    w_beat_t  w_txn;

    ace_bus_t ace;

    mailbox #(aw_beat_t) aw_mbx;
    mailbox #(w_beat_t)  w_mbx;
    mailbox #(ar_beat_t) ar_mbx;

    function new(
        ace_bus_t ace,
        mailbox #(aw_beat_t) aw_mbx,
        mailbox #(w_beat_t)  w_mbx,
        mailbox #(ar_beat_t) ar_mbx
    );
        this.ace = ace;

        this.aw_mbx = aw_mbx;
        this.ar_mbx = ar_mbx;
        this.w_mbx  = w_mbx;
    endfunction

    task cycle_start;
        #TT;
    endtask

    task cycle_end;
        @(posedge ace.clk_i);
    endtask

    task run();
        cycle_end();
        fork
            forever begin
                if (aw_mbx.try_get(aw_txn)) send_aw(aw_txn);
                else cycle_end();
            end
            forever begin
                if (w_mbx.try_get(w_txn)) send_w(w_txn);
                else cycle_end();
            end
            forever begin
                if (ar_mbx.try_get(ar_txn)) send_ar(ar_txn);
                else cycle_end();
            end
            forever recv_r();
            forever recv_b();
        join
    endtask

    task reset();
        ace.aw_id       <= '0;
        ace.aw_addr     <= '0;
        ace.aw_len      <= '0;
        ace.aw_size     <= '0;
        ace.aw_burst    <= '0;
        ace.aw_lock     <= '0;
        ace.aw_cache    <= '0;
        ace.aw_prot     <= '0;
        ace.aw_qos      <= '0;
        ace.aw_region   <= '0;
        ace.aw_atop     <= '0;
        ace.aw_user     <= '0;
        ace.aw_valid    <= '0;
        ace.aw_snoop    <= '0;
        ace.aw_bar      <= '0;
        ace.aw_domain   <= '0;
        ace.aw_awunique <= '0;
        ace.w_data      <= '0;
        ace.w_strb      <= '0;
        ace.w_last      <= '0;
        ace.w_user      <= '0;
        ace.w_valid     <= '0;
        ace.b_ready     <= '0;
        ace.ar_id       <= '0;
        ace.ar_addr     <= '0;
        ace.ar_len      <= '0;
        ace.ar_size     <= '0;
        ace.ar_burst    <= '0;
        ace.ar_lock     <= '0;
        ace.ar_cache    <= '0;
        ace.ar_prot     <= '0;
        ace.ar_qos      <= '0;
        ace.ar_region   <= '0;
        ace.ar_user     <= '0;
        ace.ar_snoop    <= '0;
        ace.ar_bar      <= '0;
        ace.ar_domain   <= '0;
        ace.ar_valid    <= '0;
        ace.r_ready     <= '0;
        ace.wack        <= '0;
        ace.rack        <= '0;
    endtask

    task send_aw (
        input aw_beat_t beat
    );
        ace.aw_id       <= #TA beat.id;
        ace.aw_addr     <= #TA beat.addr;
        ace.aw_len      <= #TA beat.len;
        ace.aw_size     <= #TA beat.size;
        ace.aw_burst    <= #TA beat.burst;
        ace.aw_lock     <= #TA beat.lock;
        ace.aw_cache    <= #TA beat.cache;
        ace.aw_prot     <= #TA beat.prot;
        ace.aw_qos      <= #TA beat.qos;
        ace.aw_region   <= #TA beat.region;
        ace.aw_atop     <= #TA beat.atop;
        ace.aw_user     <= #TA beat.user;
        ace.aw_valid    <= #TA 1;
        ace.aw_snoop    <= #TA beat.snoop;
        ace.aw_bar      <= #TA beat.bar;
        ace.aw_domain   <= #TA beat.domain;
        ace.aw_awunique <= #TA beat.awunique;
        cycle_start();
        while (ace.aw_ready != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        ace.aw_id       <= #TA '0;
        ace.aw_addr     <= #TA '0;
        ace.aw_len      <= #TA '0;
        ace.aw_size     <= #TA '0;
        ace.aw_burst    <= #TA '0;
        ace.aw_lock     <= #TA '0;
        ace.aw_cache    <= #TA '0;
        ace.aw_prot     <= #TA '0;
        ace.aw_qos      <= #TA '0;
        ace.aw_region   <= #TA '0;
        ace.aw_atop     <= #TA '0;
        ace.aw_user     <= #TA '0;
        ace.aw_valid    <= #TA  0;
        ace.aw_snoop    <= #TA '0;
        ace.aw_bar      <= #TA '0;
        ace.aw_domain   <= #TA '0;
        ace.aw_awunique <= #TA  0;
    endtask

    /// Issue a beat on the AR channel.
    task send_ar (
        input ar_beat_t beat
    );
        ace.ar_id       <= #TA beat.id;
        ace.ar_addr     <= #TA beat.addr;
        ace.ar_len      <= #TA beat.len;
        ace.ar_size     <= #TA beat.size;
        ace.ar_burst    <= #TA beat.burst;
        ace.ar_lock     <= #TA beat.lock;
        ace.ar_cache    <= #TA beat.cache;
        ace.ar_prot     <= #TA beat.prot;
        ace.ar_qos      <= #TA beat.qos;
        ace.ar_region   <= #TA beat.region;
        ace.ar_user     <= #TA beat.user;
        ace.ar_valid    <= #TA 1;
        ace.ar_snoop    <= #TA beat.snoop;
        ace.ar_bar      <= #TA beat.bar;
        ace.ar_domain   <= #TA beat.domain;
        cycle_start();
        while (ace.ar_ready != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        ace.ar_id       <= #TA '0;
        ace.ar_addr     <= #TA '0;
        ace.ar_len      <= #TA '0;
        ace.ar_size     <= #TA '0;
        ace.ar_burst    <= #TA '0;
        ace.ar_lock     <= #TA '0;
        ace.ar_cache    <= #TA '0;
        ace.ar_prot     <= #TA '0;
        ace.ar_qos      <= #TA '0;
        ace.ar_region   <= #TA '0;
        ace.ar_user     <= #TA '0;
        ace.ar_valid    <= #TA '0;
        ace.ar_snoop    <= #TA '0;
        ace.ar_bar      <= #TA '0;
        ace.ar_domain   <= #TA '0;
    endtask

    /// Issue a beat on the W channel.
    task send_w (
        input w_beat_t beat
    );
        ace.w_data  <= #TA beat.data;
        ace.w_strb  <= #TA beat.strb;
        ace.w_last  <= #TA beat.last;
        ace.w_user  <= #TA beat.user;
        ace.w_valid <= #TA 1;
        cycle_start();
        while (ace.w_ready != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        ace.w_data  <= #TA '0;
        ace.w_strb  <= #TA '0;
        ace.w_last  <= #TA '0;
        ace.w_user  <= #TA '0;
        ace.w_valid <= #TA 0;
    endtask

    task recv_r;
        ace.r_ready <= #TA 1;
        cycle_start();
        while (!(ace.r_valid && ace.r_last)) begin
            cycle_end(); cycle_start();
        end
        cycle_end();
        ace.r_ready <= #TA 0;
        ace.rack    <= #TA 1;
        cycle_start(); cycle_end();
        ace.rack    <= #TA 0;
    endtask

    /// Wait for a beat on the B channel.
    task recv_b ();
        ace.b_ready <= #TA 1;
        cycle_start();
        while (ace.b_valid != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        ace.b_ready <= #TA 0;
        ace.wack    <= #TA 1;
        cycle_start(); cycle_end();
        ace.wack <= #TA 0;
    endtask

endclass
