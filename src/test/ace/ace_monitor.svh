`ifndef _ACE_TEST_PKG
*** INCLUDED IN ace_test_pkg ***
`endif
class ace_monitor #(
    parameter time TA        = 0ns, // stimuli application time
    parameter time TT        = 0ns,  // stimuli test time
    parameter type ace_bus_t = logic,
    parameter type ar_beat_t = logic,
    parameter type r_beat_t  = logic
);

    ace_bus_t ace;

    mailbox #(ar_beat_t) ar_mbx;
    mailbox #(r_beat_t) r_mbx;

    task cycle_start;
        #TT;
    endtask

    task cycle_end;
        @(posedge ace.clk_i);
    endtask

    function new(
        ace_bus_t ace,
        mailbox #(ar_beat_t) ar_mbx,
        mailbox #(r_beat_t) r_mbx
    );
        this.ace = ace;

        this.ar_mbx = ar_mbx;
        this.r_mbx  = r_mbx;

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

    task recv_rs;
        forever begin
            r_beat_t beat;
            mon_r(beat);
            r_mbx.put(beat);
        end
    endtask

    task run;
        forever recv_rs();
    endtask
endclass