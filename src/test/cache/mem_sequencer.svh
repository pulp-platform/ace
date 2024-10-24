`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class mem_sequencer #(
    parameter type aw_beat_t = logic,
    parameter type ar_beat_t = logic,
    parameter type w_beat_t = logic
);
    mailbox #(mem_req)    mem_req_mbx;
    mailbox #(mem_resp)   mem_resp_mbx;
    mailbox #(aw_beat_t)  aw_mbx_o;
    mailbox #(ar_beat_t)  ar_mbx_o;
    mailbox #(w_beat_t)   w_mbx_o;

    function new(
        mailbox #(mem_req)    mem_req_mbx,
        mailbox #(mem_resp)   mem_resp_mbx,
        mailbox #(aw_beat_t)  aw_mbx_o,
        mailbox #(ar_beat_t)  ar_mbx_o,
        mailbox #(w_beat_t)   w_mbx_o
    );
        this.mem_req_mbx  = mem_req_mbx;
        this.mem_resp_mbx = mem_resp_mbx;
        this.aw_mbx_o     = aw_mbx_o;
        this.ar_mbx_o     = ar_mbx_o;
        this.w_mbx_o      = w_mbx_o;
    endfunction

    function automatic ace_pkg::awsnoop_t calc_write_snoop_op(mem_req req);
        if (req.uncacheable) begin
            return ace_pkg::WriteNoSnoop;
        end else begin
            return ace_pkg::WriteBack;
        end
    endfunction

    function automatic ace_pkg::arsnoop_t calc_read_snoop_op(mem_req req);
        if (req.uncacheable) begin
            return ace_pkg::ReadNoSnoop;
        end else begin
            return ace_pkg::ReadShared;
        end
    endfunction

    function automatic axi_pkg::cache_t calc_cache(mem_req req);
        if (req.uncacheable) begin
            return '0;
        end else begin
            return axi_pkg::CACHE_BUFFERABLE | 
                   axi_pkg::CACHE_MODIFIABLE;
        end
    endfunction

    function automatic ace_pkg::domain_t calc_domain(mem_req req);
        if (req.uncacheable) begin
            return ace_pkg::System;
        end else begin
            return ace_pkg::InnerShareable;
        end
    endfunction

    task recv_mem_req;
        mem_req req;
        mem_req_mbx.get(req);
        if (req.op == REQ_STORE) begin
            send_aw_beat(req);
            send_w_beats(req);
        end else if (req.op == REQ_LOAD) begin
            send_ar_beat(req);
        end
    endtask

    task send_aw_beat(input mem_req req);
        aw_beat_t aw_beat;
        aw_beat.addr   = req.addr;
        aw_beat.len    = req.len;
        aw_beat.size   = req.size;
        aw_beat.snoop  = calc_write_snoop_op(req);
        aw_beat.burst  = axi_pkg::BURST_WRAP;
        aw_beat.domain = calc_domain(req);
        aw_beat.cache  = calc_cache(req);
        aw_mbx_o.put(aw_beat);
    endtask

    task send_w_beats(input mem_req req);
        while (req.data_q.size() > 0) begin
            w_beat_t w_beat;
            w_beat.data = req.data_q.pop_front();
            w_beat.strb = '1;
            w_beat.user = '0;
            w_beat.last = (req.data_q.size() == 1);
            w_mbx_o.put(w_beat);
        end
    endtask

    task send_ar_beat(input mem_req req);
        ar_beat_t ar_beat;
        ar_beat.addr = req.addr;
        ar_beat.len = req.len;
        ar_beat.size = req.size;
        ar_beat.snoop = calc_read_snoop_op(req);
        ar_beat.burst = axi_pkg::BURST_WRAP;
        ar_beat.domain = calc_domain(req);
        ar_beat.cache = calc_cache(req);
        ar_mbx_o.put(ar_beat);
    endtask

    task recv_mem_reqs;
        forever recv_mem_req();
    endtask

    task run;
        recv_mem_reqs();
    endtask

endclass