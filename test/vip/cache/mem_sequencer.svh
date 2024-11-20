`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class mem_sequencer #(
    parameter type aw_beat_t = logic,
    parameter type ar_beat_t = logic,
    parameter type r_beat_t  = logic,
    parameter type w_beat_t  = logic,
    parameter type b_beat_t  = logic
);
    mailbox #(mem_req)    mem_req_mbx;
    mailbox #(mem_resp)   mem_resp_mbx;
    mailbox #(aw_beat_t)  aw_mbx_o;
    mailbox #(ar_beat_t)  ar_mbx_o;
    mailbox #(r_beat_t)   r_mbx_o;
    mailbox #(w_beat_t)   w_mbx_o;
    mailbox #(b_beat_t)   b_mbx_o;

    function new(
        mailbox #(mem_req)    mem_req_mbx,
        mailbox #(mem_resp)   mem_resp_mbx,
        mailbox #(aw_beat_t)  aw_mbx_o,
        mailbox #(ar_beat_t)  ar_mbx_o,
        mailbox #(r_beat_t)   r_mbx_o,
        mailbox #(w_beat_t)   w_mbx_o,
        mailbox #(b_beat_t)   b_mbx_o
    );
        this.mem_req_mbx  = mem_req_mbx;
        this.mem_resp_mbx = mem_resp_mbx;
        this.aw_mbx_o     = aw_mbx_o;
        this.ar_mbx_o     = ar_mbx_o;
        this.r_mbx_o      = r_mbx_o;
        this.w_mbx_o      = w_mbx_o;
        this.b_mbx_o      = b_mbx_o;
    endfunction

    function automatic axi_pkg::cache_t calc_cache(mem_req req);
        if (!req.cacheable) begin
            return '0;
        end else begin
            return axi_pkg::CACHE_BUFFERABLE |
                   axi_pkg::CACHE_MODIFIABLE;
        end
    endfunction

    function automatic ace_pkg::axdomain_t calc_domain(mem_req req);
        if (!req.cacheable) begin
            return ace_pkg::System;
        end else begin
            return ace_pkg::InnerShareable;
        end
    endfunction

    task recv_mem_req;
        mem_req req;
        mem_req_mbx.get(req);
        if (req.op == MEM_WRITE) begin
            send_aw_beat(req);
            send_w_beats(req);
        end else if (req.op == MEM_READ) begin
            send_ar_beat(req);
        end else begin
            $fatal("Unsupported op!");
        end
    endtask

    task send_aw_beat(input mem_req req);
        aw_beat_t aw_beat = new;
        aw_beat.addr   = req.addr;
        aw_beat.len    = req.len;
        aw_beat.size   = req.size;
        aw_beat.snoop  = req.write_snoop_op;
        aw_beat.burst  = (req.len > 0) ? axi_pkg::BURST_WRAP : axi_pkg::BURST_INCR;
        aw_beat.domain = calc_domain(req);
        aw_beat.cache  = calc_cache(req);
        aw_mbx_o.put(aw_beat);
    endtask

    task send_w_beats(input mem_req req);
        while (req.data_q.size() > 0) begin
            w_beat_t w_beat = new;
            for (int i = 0; i < (w_beat.DW / 8); i++) begin
                w_beat.data[i*8 +: 8] = req.data_q.pop_front();
            end
            w_beat.strb = '1;
            w_beat.user = '0;
            w_beat.last = (req.data_q.size() == 0);
            w_mbx_o.put(w_beat);
        end
    endtask

    task send_ar_beat(input mem_req req);
        ar_beat_t ar_beat = new;
        ar_beat.addr = req.addr;
        ar_beat.len = req.len;
        ar_beat.size = req.size;
        ar_beat.snoop = req.read_snoop_op;
        ar_beat.burst = axi_pkg::BURST_WRAP;
        ar_beat.domain = calc_domain(req);
        ar_beat.cache = calc_cache(req);
        ar_mbx_o.put(ar_beat);
    endtask

    task recv_r_beats;
        r_beat_t r_beat;
        mem_resp resp = new;
        do begin
            r_mbx_o.get(r_beat);
            for (int i = 0; i < (r_beat.DW / 8); i++) begin
                resp.data_q.push_back(r_beat.data[i*8 +: 8]);
            end
            resp.is_shared  = r_beat.resp[3];
            resp.pass_dirty = r_beat.resp[2];
        end while (!r_beat.last);
        mem_resp_mbx.put(resp);
    endtask

    task recv_b_beats;
        b_beat_t b_beat;
        mem_resp resp = new;
        b_mbx_o.get(b_beat);
        // Nothing to transfer in the response
        mem_resp_mbx.put(resp);
    endtask

    task recv_mem_reqs;
        forever recv_mem_req();
    endtask

    task send_mem_resps;
        fork
            forever recv_r_beats();
            forever recv_b_beats();;
        join
    endtask

    task run;
        fork
            recv_mem_reqs();
            send_mem_resps();
        join
    endtask

endclass
