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

//! Transaction table
//
//  A dispatch pool for operations waiting to issue, a completion buffer for those issued.
module ccu_tt
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg          = '{default: '0},
    parameter  type         domain_map_t    = logic,
    parameter  type         ar_hdr_t        = logic,
    parameter  type         se_tok_t        = logic,
    parameter  type         se_resolve_t    = logic,
    parameter  type         me_tok_t        = logic,
    parameter  type         mgr_ar_t        = logic,
    parameter  type         writeback_req_t = logic,
    parameter  type         route_t         = logic,
    parameter  type         r_info_t        = logic,
    parameter  type         excl_req_t      = logic,
    localparam int unsigned numSub          = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW         = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids         = ccuCfg.numTids,
    localparam int unsigned numReads        = ccuCfg.u.numShareableTransactions,
    localparam int unsigned tidW            = ccuCfg.tidWidth,
    localparam int unsigned rSlotW          = ccuCfg.rSlotWidth,
    localparam int unsigned wSlotW          = ccuCfg.wSlotWidth,
    localparam int unsigned lineW           = ccuCfg.numLineWidth,
    localparam int unsigned offW            = ccuCfg.cachelineByteIndexWidth
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    input  domain_map_t [numSub-1:0]            domain_map_i,

    //  Admission: reads from the ports, back-invalidations on reserved slots
    input  ar_hdr_t     [numSub-1:0]            ar_i,
    input  logic        [numSub-1:0]            ar_valid_i,
    output logic        [numSub-1:0]            ar_ready_o,
    //  The tid each read got at issue, for its port's R slot
    output logic        [numSub-1:0]            bind_valid_o,
    output logic        [rSlotW-1:0]            bind_rslot_o,
    output logic        [tidW-1:0]              bind_tid_o,
    input  logic        [numSub-1:0]            bi_valid_i,
    input  logic        [numSub-1:0][lineW-1:0] bi_line_i,
    output logic        [numSub-1:0]            bi_ready_o,

    //  Snoop filter lookup at admission, answered two cycles later
    output logic                                lookup_valid_o,
    output logic        [lineW-1:0]             lookup_line_o,
    input  logic        [numSub-1:0]            lookup_present_i,
    input  logic                                lookup_ready_i,

    //  Exclusive monitor, answer registered
    output excl_req_t                           excl_req_o,
    output logic                                excl_req_valid_o,
    input  ccu_excl_t                           excl_i,

    //  Snoop engine
    output se_tok_t                             se_tok_o,
    output logic                                se_tok_valid_o,
    input  logic                                se_tok_ready_i,
    input  logic        [numSub-1:0]            ac_room_i,
    input  se_resolve_t                             se_resolve_i,
    input  logic                                se_resolve_valid_i,
    output logic                                se_resolve_ready_o,

    //  Write lane: a writeback slot for each snoop writeback
    output writeback_req_t                      writeback_o,
    output logic                                writeback_valid_o,
    input  logic                                writeback_ready_i,
    input  logic        [wSlotW-1:0]            writeback_slot_i,

    //  Memory engine
    output me_tok_t                             me_tok_o,
    output logic                                me_tok_valid_o,
    input  logic                                me_tok_ready_i,
    //  The memory AR of a tid, read by the memory engine when it issues
    input  logic        [tidW-1:0]              mem_ar_tid_i,
    output mgr_ar_t                             mem_ar_o,
    input  logic        [numTids-1:0]           mem_done_i,

    //  From the ports: a tid's CD consumed, a tid's RACK
    input  logic        [numSub-1:0]            cd_done_i,
    input  logic        [numSub-1:0][tidW-1:0]  cd_done_tid_i,
    input  logic        [numSub-1:0]            rack_i,
    input  logic        [numSub-1:0][tidW-1:0]  rack_tid_i,

    //  To the ports at resolve: CD routing to all, the R response to the initiator
    output logic                                route_valid_o,
    output route_t                              route_o,
    output logic        [numSub-1:0]            r_info_valid_o,
    output r_info_t                             r_info_o,
    output logic        [numSub-1:0][ccuCfg.u.numRSlots-1:0] r_go_o,

    //  Snoop filter updates; the filter applies removals first
    output logic                                insert_valid_o,
    output logic        [subIdxW-1:0]           insert_port_o,
    output logic        [lineW-1:0]             insert_line_o,
    output logic        [tidW-1:0]              insert_tid_o,
    input  logic        [numSub-1:0]            insert_free_i,
    input  logic        [numSub-1:0]            insert_done_i,
    input  logic        [numSub-1:0][tidW-1:0]  insert_done_tid_i,
    output logic                                cr_remove_valid_o,
    output logic        [numSub-1:0]            cr_remove_sel_o,
    output logic        [lineW-1:0]             cr_remove_line_o,
    output logic        [tidW-1:0]              cr_remove_tid_o,
    input  logic                                cr_remove_ready_i,

    output ccu_tt_events_t                      events_o,
    output logic        [numTids-1:0]           acked_o,
    output logic        [numTids-1:0]           free_o
);

//  Issue: what the completion entry starts from
//  {{{
    typedef struct packed {
        logic                bi;
        logic [lineW-1:0]    line;
        logic [subIdxW-1:0]  port;
        logic [rSlotW-1:0]   rslot;
        logic                tail;
        logic                owes_insert;
        logic                exokay;
    } issue_t;

    logic                           issue_valid;
    logic        [tidW-1:0]         issue_tid;
    issue_t                         issue;
    mgr_ar_t                        issue_request;
    logic        [tidW-1:0]         cb_read_tid;
    logic                           cb_read_full;
    logic        [tidW-1:0]         cb_bi_tid;
    logic                           cb_bi_full;
    logic        [numTids-1:0]      cb_live, cb_tail, cb_insert_pending, cb_tail_clear, cb_released;
    logic        [numTids-1:0][lineW-1:0]   cb_line;
    logic        [numTids-1:0][subIdxW-1:0] cb_port;
    ccu_tt_events_t                 pool_events, buffer_events;
//  }}}

//  Dispatch pool
//  {{{
    ccu_dispatch_pool #(
        .ccuCfg       (ccuCfg),
        .domain_map_t (domain_map_t),
        .ar_hdr_t     (ar_hdr_t),
        .se_tok_t     (se_tok_t),
        .mgr_ar_t     (mgr_ar_t),
        .excl_req_t   (excl_req_t),
        .issue_t      (issue_t)
    ) u_dispatch_pool (
        .clk_i,
        .rst_ni,
        .domain_map_i,
        .ar_i,
        .ar_valid_i,
        .ar_ready_o,
        .bi_valid_i,
        .bi_line_i,
        .bi_ready_o,
        .lookup_valid_o,
        .lookup_line_o,
        .lookup_present_i,
        .lookup_ready_i,
        .cb_read_tid_i       (cb_read_tid),
        .cb_read_full_i      (cb_read_full),
        .cb_bi_tid_i         (cb_bi_tid),
        .cb_bi_full_i        (cb_bi_full),
        .cb_live_i           (cb_live),
        .cb_tail_i           (cb_tail),
        .cb_line_i           (cb_line),
        .cb_port_i           (cb_port),
        .cb_insert_pending_i (cb_insert_pending),
        .cb_tail_clear_o     (cb_tail_clear),
        .cb_released_i       (cb_released),
        .excl_req_o,
        .excl_req_valid_o,
        .excl_i,
        .se_tok_o,
        .se_tok_valid_o,
        .se_tok_ready_i,
        .ac_room_i,
        .bind_valid_o,
        .bind_rslot_o,
        .bind_tid_o,
        .issue_valid_o       (issue_valid),
        .issue_tid_o         (issue_tid),
        .issue_o             (issue),
        .issue_request_o     (issue_request),
        .events_o            (pool_events)
    );
//  }}}

//  Completion buffer
//  {{{
    ccu_completion_buffer #(
        .ccuCfg          (ccuCfg),
        .issue_t         (issue_t),
        .se_resolve_t    (se_resolve_t),
        .me_tok_t        (me_tok_t),
        .mgr_ar_t        (mgr_ar_t),
        .writeback_req_t (writeback_req_t),
        .route_t         (route_t),
        .r_info_t        (r_info_t)
    ) u_completion_buffer (
        .clk_i,
        .rst_ni,
        .read_tid_o         (cb_read_tid),
        .read_full_o        (cb_read_full),
        .bi_tid_o           (cb_bi_tid),
        .bi_full_o          (cb_bi_full),
        .issue_valid_i      (issue_valid),
        .issue_tid_i        (issue_tid),
        .issue_i            (issue),
        .issue_request_i    (issue_request),
        .live_o             (cb_live),
        .tail_o             (cb_tail),
        .line_o             (cb_line),
        .port_o             (cb_port),
        .insert_pending_o   (cb_insert_pending),
        .tail_clear_i       (cb_tail_clear),
        .released_o         (cb_released),
        .se_resolve_i,
        .se_resolve_valid_i,
        .se_resolve_ready_o,
        .writeback_o,
        .writeback_valid_o,
        .writeback_ready_i,
        .writeback_slot_i,
        .me_tok_o,
        .me_tok_valid_o,
        .me_tok_ready_i,
        .mem_ar_tid_i,
        .mem_ar_o,
        .mem_done_i,
        .cd_done_i,
        .cd_done_tid_i,
        .rack_i,
        .rack_tid_i,
        .route_valid_o,
        .route_o,
        .r_info_valid_o,
        .r_info_o,
        .r_go_o,
        .insert_valid_o,
        .insert_port_o,
        .insert_line_o,
        .insert_tid_o,
        .insert_free_i,
        .insert_done_i,
        .insert_done_tid_i,
        .cr_remove_valid_o,
        .cr_remove_sel_o,
        .cr_remove_line_o,
        .cr_remove_tid_o,
        .cr_remove_ready_i,
        .events_o           (buffer_events),
        .acked_o,
        .free_o
    );
//  }}}

//  Performance events
//  {{{
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) events_o <= '0;
        else         events_o <= pool_events | buffer_events;
    end
//  }}}
endmodule
