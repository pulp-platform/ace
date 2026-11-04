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

//! Port adapter, read side
//
//  Every read holds an R slot from admission; R is reassembled there.
module ccu_port_read
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg    = '{default: '0},
    parameter  type         sub_req_t = logic,
    parameter  type         sub_r_t   = logic,
    parameter  type         ar_hdr_t  = logic,
    parameter  type         rb_mem_t  = logic,
    parameter  type         rb_cd_t   = logic,
    parameter  type         r_info_t  = logic,
    localparam int unsigned tidW      = ccuCfg.tidWidth,
    localparam int unsigned rSlotW    = ccuCfg.rSlotWidth,
    localparam int unsigned subIdW    = ccuCfg.u.axiSubordinateIdWidth
) (
    input  logic                          clk_i,
    input  logic                          rst_ni,

    //  The manager's AR and R
    input  sub_req_t                      req_i,
    output logic                          sub_ar_ready_o,
    output sub_r_t                        sub_r_o,
    output logic                          sub_r_valid_o,
    input  logic                          rack_i,

    //  Snoop-dependent reads; the table binds a tid to the R slot later
    output ar_hdr_t                       ar_hdr_o,
    output logic                          ar_valid_o,
    input  logic                          ar_ready_i,
    input  logic                          bind_valid_i,
    input  logic [rSlotW-1:0]             bind_rslot_i,
    input  logic [tidW-1:0]               bind_tid_i,

    //  Responses: data, the response fixed at resolve, and the R slots that may go
    input  rb_mem_t                       rb_mem_i,
    input  logic                          rb_mem_valid_i,
    input  rb_cd_t                        rb_cd_i,
    input  logic                          rb_cd_valid_i,
    output logic                          rb_cd_ready_o,
    input  logic                          r_info_valid_i,
    input  r_info_t                       r_info_i,
    input  logic [ccuCfg.u.numRSlots-1:0] r_go_i,

    //  ACKED: the RACK of a read, by tid
    output logic                          rack_o,
    output logic [tidW-1:0]               rack_tid_o,

    output ccu_port_events_t              events_o
);

    localparam int unsigned numBeats = ccuCfg.cachelineAxiTransfers;

    typedef struct packed {
        logic [tidW-1:0]   tid;
        logic [rSlotW-1:0] slot;
    } rack_t;

//  AR: every read is snoop-dependent, and holds an R slot from admission
//  {{{
    logic              rb_full, ar_handshake;
    logic [rSlotW-1:0] rb_alloc_slot;

    assign ar_valid_o      = req_i.ar_valid && !rb_full;
    assign sub_ar_ready_o = ar_ready_i && !rb_full;
    assign ar_handshake           = ar_valid_o && ar_ready_i;
    assign ar_hdr_o        = '{ar: req_i.ar, rslot: rb_alloc_slot};
//  }}}

//  R reassembly, and the RACK FIFO behind it
//  {{{
    sub_r_t            rb_r;
    logic              rb_r_valid, rb_r_ready;
    logic [tidW-1:0]   rb_r_tid;
    logic [rSlotW-1:0] rb_r_slot;
    logic              rack_full, rack_empty;
    rack_t             rack_head;

    ccu_r_buffer #(
        .ccuCfg   (ccuCfg),
        .r_t      (sub_r_t),
        .rb_mem_t (rb_mem_t),
        .rb_cd_t  (rb_cd_t),
        .r_info_t (r_info_t)
    ) u_r_buffer (
        .clk_i,
        .rst_ni,
        .alloc_i      (ar_handshake),
        .alloc_id_i   (req_i.ar.id),
        .alloc_user_i (req_i.ar.user),
        .alloc_len_i  (req_i.ar.len),
        .alloc_slot_o (rb_alloc_slot),
        .full_o       (rb_full),
        .mem_valid_i  (rb_mem_valid_i),
        .mem_i        (rb_mem_i),
        .cd_valid_i   (rb_cd_valid_i),
        .cd_ready_o   (rb_cd_ready_o),
        .cd_i         (rb_cd_i),
        .bind_valid_i (bind_valid_i),
        .bind_slot_i  (bind_rslot_i),
        .bind_tid_i   (bind_tid_i),
        .info_valid_i (r_info_valid_i),
        .info_i       (r_info_i),
        .go_i         (r_go_i),
        .r_valid_o    (rb_r_valid),
        .r_ready_i    (rb_r_ready),
        .r_o          (rb_r),
        .r_tid_o      (rb_r_tid),
        .r_slot_o     (rb_r_slot),
        .free_i       (rack_i),
        .free_slot_i  (rack_head.slot)
    );

    assign sub_r_o       = rb_r;
    assign sub_r_valid_o = rb_r_valid;
    assign rb_r_ready     = req_i.r_ready;

    //  One entry per R slot, so a RACK never waits
    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (ccuCfg.u.numRSlots),
        .dtype        (rack_t)
    ) u_rack_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (rack_full),
        .empty_o    (rack_empty),
        .usage_o    (),
        .data_i     (rack_t'{tid: rb_r_tid, slot: rb_r_slot}),
        .push_i     (rb_r_valid && rb_r_ready && rb_r.last),
        .data_o     (rack_head),
        .pop_i      (rack_i)
    );

    assign rack_o     = rack_i;
    assign rack_tid_o = rack_head.tid;
//  }}}

//  Performance events, registered by the port adapter
//  {{{
    always_comb begin : events_comb
        events_o = '0;
        events_o.ar_accept       = ar_handshake;
        events_o.ar_stall_r_slot = req_i.ar_valid && rb_full;
        events_o.r_beat          = rb_r_valid && rb_r_ready;
        events_o.r_stall         = rb_r_valid && !rb_r_ready;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        req_i.ar_valid |-> !req_i.ar.bar[0] && !(req_i.ar.snoop inside {DVMComplete, DVMMessage}))
        else $error("barrier or DVM read: unsupported");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        req_i.ar_valid |-> req_i.ar.len < numBeats)
        else $error("read burst longer than a cacheline");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        rack_i |-> !rack_empty)
        else $error("RACK without an outstanding R");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        rb_r_valid && rb_r_ready && rb_r.last |-> !rack_full)
        else $error("RACK FIFO overflow");

    logic r_open_q;
    logic [subIdW-1:0] r_open_id_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_open_q    <= 1'b0;
            r_open_id_q <= '0;
        end else if (rb_r_valid && rb_r_ready) begin
            r_open_q    <= !rb_r.last;
            r_open_id_q <= rb_r.id;
        end
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        rb_r_valid && r_open_q |-> rb_r.id == r_open_id_q)
        else $error("R bursts interleaved at a port");
    `endif
    // pragma translate_on
//  }}}
endmodule
