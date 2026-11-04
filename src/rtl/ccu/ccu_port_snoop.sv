// Copyright (c) 2026 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Authors:
// - Riccardo Tedeschi <riccardo.tedeschi6@unibo.it>

//! Port adapter, snoop side
//
//  A snoop slot per AC until its CR or last CD; CD is buffered and routed.
module ccu_port_snoop
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg       = '{default: '0},
    parameter  type         snoop_req_t  = logic,
    parameter  type         snoop_resp_t = logic,
    parameter  type         snoop_cd_t   = logic,
    parameter  type         ac_req_t     = logic,
    parameter  type         cr_ret_t     = logic,
    parameter  type         route_t      = logic,
    parameter  type         cd_r_t       = logic,
    parameter  type         cd_w_t       = logic,
    localparam int unsigned tidW         = ccuCfg.tidWidth,
    localparam int unsigned subIdxW      = ccuCfg.subordinateIndexWidth
) (
    input  logic               clk_i,
    input  logic               rst_ni,
    //  Which port this is
    input  logic [subIdxW-1:0] port_i,

    //  The manager's snoop channels
    output snoop_req_t         snoop_req_o,
    input  snoop_resp_t        snoop_resp_i,

    //  Snoops, tagged with the tid they answer
    input  ac_req_t            ac_i,
    input  logic               ac_valid_i,
    output logic               ac_ready_o,
    output cr_ret_t            cr_o,
    output logic               cr_valid_o,
    //  Routing of a resolved tid's CD, to every port
    input  logic               route_valid_i,
    input  route_t             route_i,
    output cd_r_t              cd_r_o,
    output logic               cd_r_valid_o,
    input  logic               cd_r_ready_i,
    output cd_w_t              cd_w_o,
    output logic               cd_w_valid_o,
    input  logic               cd_w_ready_i,
    output logic               cd_done_o,
    output logic [tidW-1:0]    cd_done_tid_o,
    //  Next CD's tid
    output logic               cd_head_valid_o,
    output logic [tidW-1:0]    cd_head_tid_o,

    output ccu_port_events_t   events_o
);

    localparam int unsigned numBeats = ccuCfg.cachelineAxiTransfers;

//  Snoops: a slot each from AC to its CR, or to its last CD if it carries data
//  {{{
    localparam int unsigned numSnoops = ccuCfg.u.numSnoopTransactions;
    localparam int unsigned snoopW    = numSnoops > 1 ? $clog2(numSnoops) : 1;

    typedef struct packed {
        logic            valid;
        logic [tidW-1:0] tid;
        logic            routed;
        route_t          route;
    } snoop_slot_t;

    snoop_slot_t [numSnoops-1:0] snoop_q, snoop_d;
    logic        [numSnoops-1:0] snoop_free;
    logic [snoopW-1:0] snoop_alloc, ac_head, cd_head;
    logic              snoops_full, ac_handshake, ac_full, ac_empty, cd_full, cd_empty;
    logic              cr_handshake, cr_data, cd_handshake;
    logic              cd_in_valid, cd_take;
    route_t            route;
    logic              cd_ok, cd_src, cd_to_r, cd_to_w, cd_fork_valid, cd_fork_ready;

    for (genvar s = 0; s < numSnoops; s++) begin : gen_snoop_free
        assign snoop_free[s] = !snoop_q[s].valid;
    end

    lzc #(
        .WIDTH (numSnoops),
        .MODE  (1'b0)
    ) u_snoop_lzc (
        .in_i    (snoop_free),
        .cnt_o   (snoop_alloc),
        .empty_o (snoops_full)
    );

    //  Taken only while a slot is free; a full table cannot drop a presented AC
    assign snoop_req_o.ac       = ac_i.ac;
    assign snoop_req_o.ac_valid = ac_valid_i && !snoops_full;
    assign ac_ready_o           = snoop_resp_i.ac_ready && !snoops_full;
    assign ac_handshake         = snoop_req_o.ac_valid && snoop_resp_i.ac_ready;

    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (numSnoops),
        .DATA_WIDTH   (snoopW)
    ) u_ac_order_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (ac_full),
        .empty_o    (ac_empty),
        .usage_o    (),
        .data_i     (snoop_alloc),
        .push_i     (ac_handshake),
        .data_o     (ac_head),
        .pop_i      (cr_handshake)
    );

    //  Every snoop answer is taken at once: its slot is at the head
    assign snoop_req_o.cr_ready = !ac_empty;
    assign cr_handshake         = snoop_resp_i.cr_valid && !ac_empty;
    assign cr_data              = snoop_resp_i.cr.resp.DataTransfer;
    assign cr_valid_o           = cr_handshake;
    assign cr_o                 = '{tid: snoop_q[ac_head].tid, resp: snoop_resp_i.cr.resp};

    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (numSnoops),
        .DATA_WIDTH   (snoopW)
    ) u_cd_order_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (cd_full),
        .empty_o    (cd_empty),
        .usage_o    (),
        .data_i     (ac_head),
        .push_i     (cr_handshake && cr_data),
        .data_o     (cd_head),
        .pop_i      (cd_handshake && cd_in.last)
    );

    always_comb begin : snoop_slot_comb
        snoop_d = snoop_q;
        for (int unsigned s = 0; s < numSnoops; s++)
            if (route_valid_i && snoop_q[s].valid && snoop_q[s].tid == route_i.tid) begin
                snoop_d[s].routed = 1'b1;
                snoop_d[s].route  = route_i;
            end
        if (cr_handshake && !cr_data)                    snoop_d[ac_head] = '0;
        if (cd_handshake && cd_in.last)                  snoop_d[cd_head] = '0;
        if (ac_handshake)
            snoop_d[snoop_alloc] = '{valid: 1'b1, tid: ac_i.tid, routed: 1'b0, route: '0};
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) snoop_q <= '0;
        else         snoop_q <= snoop_d;
    end

    //  CD buffer: the manager's CD drains here, routed or not
    localparam int unsigned cdDepth = ccuCfg.u.numCdBufferLines * numBeats;

    snoop_cd_t cd_in;

    if (cdDepth == 0) begin : gen_no_cd_buffer
        assign cd_in_valid          = snoop_resp_i.cd_valid;
        assign cd_in                = snoop_resp_i.cd;
        assign snoop_req_o.cd_ready = cd_take;
    end else begin : gen_cd_buffer
        //  Falls through, so a routed head costs no cycle
        stream_fifo #(
            .FALL_THROUGH (1'b1),
            .DEPTH        (cdDepth),
            .T            (snoop_cd_t)
        ) u_cd_buffer (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .usage_o    (),
            .data_i     (snoop_resp_i.cd),
            .valid_i    (snoop_resp_i.cd_valid),
            .ready_o    (snoop_req_o.cd_ready),
            .data_o     (cd_in),
            .valid_o    (cd_in_valid),
            .ready_i    (cd_take)
        );
    end

    //  CD waits here until its slot is routed: resolving needs CRs only
    assign route   = snoop_q[cd_head].route;
    assign cd_ok   = !cd_empty && snoop_q[cd_head].routed;
    assign cd_src  = route.src == port_i;
    assign cd_to_r = cd_src && route.to_r;
    assign cd_to_w = cd_src && route.to_w;

    stream_fork_dynamic #(
        .N_OUP (2)
    ) u_cd_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (cd_fork_valid),
        .ready_o     (cd_fork_ready),
        .sel_i       ({cd_to_w, cd_to_r}),
        .sel_valid_i (cd_fork_valid),
        .sel_ready_o (),
        .valid_o     ({cd_w_valid_o, cd_r_valid_o}),
        .ready_i     ({cd_w_ready_i, cd_r_ready_i})
    );

    assign cd_fork_valid = cd_in_valid && cd_ok && (cd_to_r || cd_to_w);
    assign cd_take       = cd_ok && ((cd_to_r || cd_to_w) ? cd_fork_ready : 1'b1);
    assign cd_handshake  = cd_in_valid && cd_take;

    assign cd_r_o = '{port: route.r_port,
                      rb:   '{slot: route.r_slot, data: cd_in.data, last: cd_in.last}};
    assign cd_w_o = '{slot: route.w_slot, data: cd_in.data, last: cd_in.last};

    assign cd_done_o     = cd_handshake && cd_in.last;
    assign cd_done_tid_o = snoop_q[cd_head].tid;

    assign cd_head_valid_o = !cd_empty;
    assign cd_head_tid_o   = snoop_q[cd_head].tid;
//  }}}

//  Performance events, registered by the port adapter
//  {{{
    always_comb begin : events_comb
        events_o = '0;
        events_o.cd_wait_resolve = cd_in_valid && !cd_empty && !snoop_q[cd_head].routed;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ac_handshake |-> !ac_full)
        else $error("AC order FIFO overflow");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cr_handshake && snoop_resp_i.cr.resp.DataTransfer |-> !cd_full)
        else $error("CD order FIFO overflow");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        snoop_resp_i.cr_valid |-> !ac_empty)
        else $error("CR without an outstanding AC");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        snoop_resp_i.cr_valid |->
            !(snoop_resp_i.cr.resp.PassDirty && !snoop_resp_i.cr.resp.DataTransfer))
        else $error("PassDirty without DataTransfer");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cd_handshake |-> !cd_empty)
        else $error("CD without a DataTransfer CR");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        snoop_req_o.ac_valid && !snoop_resp_i.ac_ready |=>
            snoop_req_o.ac_valid && $stable(snoop_req_o.ac))
        else $error("AC channel unstable while stalled");

    logic [$clog2(numBeats+1)-1:0] cd_beats_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)    cd_beats_q <= '0;
        else if (cd_handshake) cd_beats_q <= cd_in.last ? '0 : cd_beats_q + 1'b1;
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cd_handshake |-> cd_in.last == (cd_beats_q == numBeats - 1))
        else $error("CD burst is not one cacheline");
    `endif
    // pragma translate_on
//  }}}
endmodule
