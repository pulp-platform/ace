`ifndef _ACE_TEST_PKG
*** INCLUDED IN ace_test_pkg ***
`endif
class ace_monitor #(
    parameter time TA        = 0ns, // stimuli application time
    parameter time TT        = 0ns,  // stimuli test time
    parameter type ace_bus_t = logic,
    parameter type ar_beat_t = logic,
    parameter type r_beat_t  = logic,
    parameter type b_beat_t
);

    ace_bus_t ace;

    mailbox #(ar_beat_t) ar_mbx;
    mailbox #(r_beat_t) r_mbx;
    mailbox #(b_beat_t) b_mbx;

    task cycle_start;
        #TT;
    endtask

    task cycle_end;
        @(posedge ace.clk_i);
    endtask

    function new(
        ace_bus_t ace,
        mailbox #(ar_beat_t) ar_mbx,
        mailbox #(r_beat_t) r_mbx,
        mailbox #(b_beat_t) b_mbx
    );
        this.ace = ace;

        this.ar_mbx = ar_mbx;
        this.r_mbx  = r_mbx;
        this.b_mbx  = b_mbx;

    endfunction

    task mon_r (output r_beat_t beat);
        cycle_start();
        while (!(ace.r_valid && ace.r_ready)) begin cycle_end(); cycle_start(); end
        beat = new;
        beat.id   = ace.r_id;
        beat.data = ace.r_data;
        beat.resp = ace.r_resp;
        beat.last = ace.r_last;
        beat.user = ace.r_user;
        cycle_end();
    endtask

    task mon_b (output b_beat_t beat);
        cycle_start();
        while (!(ace.b_valid && ace.b_ready)) begin cycle_end(); cycle_start(); end
        beat = new;
        beat.id   = ace.b_id;
        beat.resp = ace.b_resp;
        beat.user = ace.b_user;
        cycle_end();
    endtask

    task recv_rs;
        forever begin
            r_beat_t beat;
            mon_r(beat);
            r_mbx.put(beat);
        end
    endtask

    task recv_bs;
        forever begin
            b_beat_t beat;
            mon_b(beat);
            b_mbx.put(beat);
        end
    endtask

    task run;
        fork
            forever recv_rs();
            forever recv_bs();
        join
    endtask
endclass