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

//! Port adapter, write side
//
//  Non-blocking writes to the write lane; Evicts answered here; B in order per id.
module ccu_port_write
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg    = '{default: '0},
    parameter  type         sub_req_t = logic,
    parameter  type         sub_b_t   = logic,
    parameter  type         aw_hdr_t  = logic,
    parameter  type         w_beat_t  = logic,
    parameter  type         b_ret_t   = logic,
    localparam int unsigned numBSlots = ccuCfg.numBSlots,
    localparam int unsigned bSlotW    = ccuCfg.bSlotWidth,
    localparam int unsigned lineW     = ccuCfg.numLineWidth,
    localparam int unsigned offW      = ccuCfg.cachelineByteIndexWidth,
    localparam int unsigned subIdW    = ccuCfg.u.axiSubordinateIdWidth
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    //  The manager's AW, W and B
    input  sub_req_t         req_i,
    output logic             sub_aw_ready_o,
    output logic             sub_w_ready_o,
    output sub_b_t           sub_b_o,
    output logic             sub_b_valid_o,
    input  logic             wack_i,

    //  Non-blocking writes, named by their port-local B slot; W follows tagged with it
    output aw_hdr_t          aw_hdr_o,
    output logic             aw_valid_o,
    input  logic             aw_ready_i,
    //  The line leaves this manager's cache
    output logic             remove_valid_o,
    output logic [lineW-1:0] remove_line_o,
    input  logic             remove_ready_i,
    output w_beat_t          w_o,
    output logic             w_valid_o,
    input  logic             w_ready_i,
    input  b_ret_t           b_i,
    input  logic             b_valid_i,

    output ccu_port_events_t events_o
);

    localparam int unsigned numBeats = ccuCfg.cachelineAxiTransfers;
    localparam int unsigned numWacks = 4;

    typedef struct packed {
        logic              drop;
        logic [bSlotW-1:0] bslot;
    } steer_t;

//  AW: non-blocking writes to the write lane, Evict answered here, WriteUnique stubbed
//  {{{
    logic              aw_is_evict, aw_is_unique, aw_nonblocking, aw_removes_line, aw_drains;
    logic              aw_pre, aw_accept;
    logic              steer_full, steer_empty;
    steer_t            steer_head;
    logic              b_full;
    logic [bSlotW-1:0] b_alloc_slot;

    assign aw_is_evict  = ace_is_evict(req_i.aw.bar[0], req_i.aw.domain, req_i.aw.snoop);
    assign aw_is_unique = ace_aw_is_shareable(req_i.aw.bar[0], req_i.aw.domain, req_i.aw.snoop);
    assign aw_nonblocking   = !aw_is_evict && !aw_is_unique;
    assign aw_drains    = !aw_is_evict;
    //  Non-shareable lines are never tracked
    assign aw_removes_line   = req_i.aw.domain inside {InnerShareable, OuterShareable} &&
                          (aw_is_evict ||
                           ace_is_write_back (req_i.aw.bar[0], req_i.aw.domain, req_i.aw.snoop) ||
                           ace_is_write_evict(req_i.aw.bar[0], req_i.aw.domain, req_i.aw.snoop));

    //  Every leg is taken in the same cycle; none of them waits on the table
    assign aw_pre    = req_i.aw_valid && !b_full && !steer_full &&
                       (!aw_removes_line || remove_ready_i);
    assign aw_accept = aw_pre && (!aw_nonblocking || aw_ready_i);

    assign aw_valid_o      = aw_pre && aw_nonblocking;
    assign remove_valid_o      = req_i.aw_valid && aw_removes_line && !b_full && !steer_full &&
                             (!aw_nonblocking || aw_ready_i);
    assign sub_aw_ready_o = aw_accept;

    assign aw_hdr_o  = '{aw: req_i.aw, bslot: b_alloc_slot};
    assign remove_line_o = req_i.aw.addr[offW +: lineW];
//  }}}

//  W steering, in AW order; W is never buffered here
//  {{{
    logic w_handshake;

    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (numBSlots),
        .dtype        (steer_t)
    ) u_steer_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (steer_full),
        .empty_o    (steer_empty),
        .usage_o    (),
        .data_i     (steer_t'{drop: aw_is_unique, bslot: b_alloc_slot}),
        .push_i     (aw_accept && aw_drains),
        .data_o     (steer_head),
        .pop_i      (w_handshake && req_i.w.last)
    );

    assign w_valid_o      = req_i.w_valid && !steer_empty && !steer_head.drop;
    assign sub_w_ready_o = !steer_empty && (steer_head.drop || w_ready_i);
    assign w_handshake           = req_i.w_valid && sub_w_ready_o;
    assign w_o            = '{bslot: steer_head.bslot, w: req_i.w};
//  }}}

//  B order: released in order per id
//  {{{
    logic   [numBSlots-1:0]                live_q,    live_d;
    logic   [numBSlots-1:0]                done_q,    done_d;
    logic   [numBSlots-1:0][subIdW-1:0]    b_id_q,    b_id_d;
    sub_b_t [numBSlots-1:0]                b_q,       b_d;
    logic   [numBSlots-1:0][numBSlots-1:0] b_older_q, b_older_d;
    logic   [numBSlots-1:0]                b_ready, b_gnt;
    logic   [bSlotW-1:0]                   b_idx;
    logic                                  b_out_valid, b_handshake;
    logic                                  wack_full, wack_empty;
    logic                                  stub_done;

    lzc #(
        .WIDTH (numBSlots),
        .MODE  (1'b0)
    ) u_b_lzc (
        .in_i    (~live_q),
        .cnt_o   (b_alloc_slot),
        .empty_o (b_full)
    );

    for (genvar b = 0; b < numBSlots; b++) begin : gen_b_ready
        assign b_ready[b] = live_q[b] && done_q[b] && (b_older_q[b] & live_q) == '0;
    end

    rr_arb_tree #(
        .NumIn     (numBSlots),
        .DataType  (sub_b_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1)
    ) u_b_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (b_ready),
        .gnt_o   (b_gnt),
        .data_i  (b_q),
        .req_o   (b_out_valid),
        .gnt_i   (req_i.b_ready && !wack_full),
        .data_o  (sub_b_o),
        .idx_o   (b_idx)
    );

    assign sub_b_valid_o = b_out_valid && !wack_full;
    assign b_handshake           = sub_b_valid_o && req_i.b_ready;
    assign stub_done      = w_handshake && req_i.w.last && steer_head.drop;

    always_comb begin : b_comb
        live_d    = live_q;
        done_d    = done_q;
        b_id_d    = b_id_q;
        b_d       = b_q;
        b_older_d = b_older_q;

        if (b_valid_i) begin
            done_d[b_i.bslot]      = 1'b1;
            b_d[b_i.bslot].resp    = b_i.resp;
            b_d[b_i.bslot].user    = b_i.user;
        end
        //  The WriteUnique stub answers once its data is drained
        if (stub_done) begin
            done_d[steer_head.bslot]   = 1'b1;
            b_d[steer_head.bslot].resp = axi_pkg::RESP_SLVERR;
        end

        if (b_handshake) begin
            live_d[b_idx] = 1'b0;
            done_d[b_idx] = 1'b0;
            for (int unsigned b = 0; b < numBSlots; b++) b_older_d[b][b_idx] = 1'b0;
        end

        if (aw_accept) begin
            live_d[b_alloc_slot]    = 1'b1;
            //  An Evict never leaves the CCU
            done_d[b_alloc_slot]    = aw_is_evict;
            b_id_d[b_alloc_slot]    = req_i.aw.id;
            b_d[b_alloc_slot]       = '{id: req_i.aw.id, resp: axi_pkg::RESP_OKAY,
                                        user: req_i.aw.user};
            for (int unsigned b = 0; b < numBSlots; b++)
                b_older_d[b_alloc_slot][b] = live_q[b] && b_id_q[b] == req_i.aw.id &&
                                             !(b_handshake && b_idx == bSlotW'(b));
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            live_q    <= '0;
            done_q    <= '0;
            b_id_q    <= '0;
            b_q       <= '0;
            b_older_q <= '0;
        end else begin
            live_q    <= live_d;
            done_q    <= done_d;
            b_id_q    <= b_id_d;
            b_q       <= b_d;
            b_older_q <= b_older_d;
        end
    end

    //  A B is released only with room for its WACK, which is never stalled
    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (numWacks),
        .DATA_WIDTH   (1)
    ) u_wack_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (wack_full),
        .empty_o    (wack_empty),
        .usage_o    (),
        .data_i     (1'b0),
        .push_i     (b_handshake),
        .data_o     (),
        .pop_i      (wack_i)
    );
//  }}}

//  Performance events, registered by the port adapter
//  {{{
    always_comb begin : events_comb
        events_o = '0;
        events_o.aw_accept  = aw_accept;
        events_o.aw_stall   = req_i.aw_valid && !aw_accept;
        events_o.w_wait_map = w_valid_o && !w_ready_i;
        events_o.b_beat     = b_handshake;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        req_i.aw_valid |-> !req_i.aw.bar[0] && req_i.aw.atop == '0)
        else $error("barrier or atomic write: unsupported");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        req_i.aw_valid && aw_nonblocking |-> req_i.aw.len < numBeats)
        else $error("write burst longer than a cacheline");

    always @(posedge clk_i) begin
        if (rst_ni && aw_accept && aw_is_unique)
            $error("WriteUnique/WriteLineUnique not implemented: answered SLVERR");
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wack_i |-> !wack_empty)
        else $error("WACK without an outstanding B");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        b_handshake |-> !wack_full)
        else $error("WACK FIFO overflow");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        sub_b_valid_o && !req_i.b_ready |=> sub_b_valid_o && $stable(sub_b_o))
        else $error("B channel unstable while stalled");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        b_valid_i |-> live_q[b_i.bslot] && !done_q[b_i.bslot])
        else $error("write response for a write not outstanding");
    `endif
    // pragma translate_on
//  }}}
endmodule
