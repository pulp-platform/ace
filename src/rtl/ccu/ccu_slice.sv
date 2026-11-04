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

//! Home slice
//
//  Home of every line: transaction table, engines, snoop filter, exclusive monitor and write lane.
module ccu_slice
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg          = '{default: '0},
    parameter  type         domain_map_t    = logic,
    parameter  type         ar_hdr_t        = logic,
    parameter  type         aw_hdr_t        = logic,
    parameter  type         w_beat_t        = logic,
    parameter  type         ac_req_t        = logic,
    parameter  type         cr_ret_t        = logic,
    parameter  type         cd_w_t          = logic,
    parameter  type         route_t         = logic,
    parameter  type         r_info_t        = logic,
    parameter  type         rb_mem_t        = logic,
    parameter  type         b_ret_t         = logic,
    parameter  type         se_tok_t        = logic,
    parameter  type         se_resolve_t    = logic,
    parameter  type         me_tok_t        = logic,
    parameter  type         writeback_req_t = logic,
    parameter  type         excl_req_t      = logic,
    parameter  type         mgr_ar_t        = logic,
    parameter  type         mgr_aw_t        = logic,
    parameter  type         mgr_w_t         = logic,
    parameter  type         mgr_r_t         = logic,
    parameter  type         mgr_b_t         = logic,
    parameter  type         mgr_req_t       = logic,
    parameter  type         mgr_resp_t      = logic,
    localparam int unsigned numSub          = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW         = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids         = ccuCfg.numTids,
    localparam int unsigned tidW            = ccuCfg.tidWidth,
    localparam int unsigned wSlotW          = ccuCfg.wSlotWidth,
    localparam int unsigned lineW           = ccuCfg.numLineWidth
) (
    input  logic                               clk_i,
    input  logic                               rst_ni,

    input  domain_map_t [numSub-1:0]           domain_map_i,

    //  Request headers
    input  ar_hdr_t     [numSub-1:0]           ar_i,
    input  logic        [numSub-1:0]           ar_valid_i,
    output logic        [numSub-1:0]           ar_ready_o,
    output logic        [numSub-1:0]           bind_valid_o,
    output logic        [ccuCfg.rSlotWidth-1:0] bind_rslot_o,
    output logic        [tidW-1:0]             bind_tid_o,
    input  aw_hdr_t     [numSub-1:0]           aw_i,
    input  logic        [numSub-1:0]           aw_valid_i,
    output logic        [numSub-1:0]           aw_ready_o,
    input  logic        [numSub-1:0]           remove_valid_i,
    input  logic        [numSub-1:0][lineW-1:0] remove_line_i,
    output logic        [numSub-1:0]           remove_ready_o,

    //  Snoop channels, tagged by tid
    output ac_req_t     [numSub-1:0]           ac_o,
    output logic        [numSub-1:0]           ac_valid_o,
    input  logic        [numSub-1:0]           ac_ready_i,
    input  cr_ret_t     [numSub-1:0]           cr_i,
    input  logic        [numSub-1:0]           cr_valid_i,
    output logic                               route_valid_o,
    output route_t                             route_o,
    input  logic        [numSub-1:0]           cd_done_i,
    input  logic        [numSub-1:0][tidW-1:0] cd_done_tid_i,
    input  logic        [numSub-1:0]           cd_head_valid_i,
    input  logic        [numSub-1:0][tidW-1:0] cd_head_tid_i,

    //  Tagged data in: W and snoop writebacks
    input  w_beat_t     [numSub-1:0]           w_i,
    input  logic        [numSub-1:0]           w_valid_i,
    output logic        [numSub-1:0]           w_ready_o,
    input  cd_w_t       [numSub-1:0]           cd_w_i,
    input  logic        [numSub-1:0]           cd_w_valid_i,
    output logic        [numSub-1:0]           cd_w_ready_o,

    //  Tagged data out: memory R and B, and each read's response
    output rb_mem_t     [numSub-1:0]           rb_mem_o,
    output logic        [numSub-1:0]           rb_mem_valid_o,
    output logic        [numSub-1:0]           r_info_valid_o,
    output r_info_t                            r_info_o,
    output logic        [numSub-1:0][ccuCfg.u.numRSlots-1:0] r_go_o,
    output b_ret_t      [numSub-1:0]           b_o,
    output logic        [numSub-1:0]           b_valid_o,

    //  Retire
    input  logic        [numSub-1:0]           rack_i,
    input  logic        [numSub-1:0][tidW-1:0] rack_tid_i,

    output mgr_req_t                           manager_req_o,
    input  mgr_resp_t                          manager_resp_i,

    output ccu_phase_e  [numTids-1:0]          phase_o,

    output ccu_tt_events_t                     tt_events_o,
    output ccu_snoop_events_t                  snoop_events_o,
    output ccu_mem_events_t                    mem_events_o,
    output ccu_lane_events_t                   lane_events_o,
    output ccu_filter_events_t                 filter_events_o
);

    if (ccuCfg.u.numSlices != 1) begin : gen_slices_check
        $error("numSlices (%0d) must be 1", ccuCfg.u.numSlices);
    end

    //  Back-invalidations need tids no read can hold
    if (ccuCfg.u.numBackInvalSlots < 1) begin : gen_back_inval_check
        $error("numBackInvalSlots (%0d) must be at least 1", ccuCfg.u.numBackInvalSlots);
    end

    se_tok_t                       se_tok;
    logic                          se_tok_valid, se_tok_ready;
    se_resolve_t                   se_resolve;
    logic                          se_resolve_valid, se_resolve_ready;
    logic        [numSub-1:0]      ac_room;
    me_tok_t                       me_tok;
    logic                          me_tok_valid, me_tok_ready;
    logic        [tidW-1:0]        mem_ar_tid;
    mgr_ar_t                       mem_ar;
    logic        [numTids-1:0]     mem_done;
    writeback_req_t                writeback;
    logic                          writeback_valid, writeback_ready, writeback_scarce;
    logic        [wSlotW-1:0]      writeback_slot;
    excl_req_t                     excl_req;
    logic                          excl_req_valid;
    ccu_excl_t                     excl;
    logic        [numTids-1:0]     acked, freeing;

    logic                          lookup_valid;
    logic        [lineW-1:0]       lookup_line;
    logic        [numSub-1:0]      lookup_present;
    logic        [numSub-1:0]      bi_valid, bi_ready;
    logic        [numSub-1:0][lineW-1:0] bi_line;
    logic                          insert_valid;
    logic        [subIdxW-1:0]     insert_port;
    logic        [lineW-1:0]       insert_line;
    logic        [tidW-1:0]        insert_tid;
    logic        [numSub-1:0]      insert_free, insert_done;
    logic        [numSub-1:0][tidW-1:0] insert_done_tid;
    logic                          cr_remove_valid, cr_remove_ready;
    logic        [numSub-1:0]      cr_remove_sel;
    logic        [lineW-1:0]       cr_remove_line;
    logic        [tidW-1:0]        cr_remove_tid;

    logic        [ccuCfg.numWSlots-1:0]                    hazard_valid;
    logic        [ccuCfg.numWSlots-1:0][lineW-1:0]         hazard_line;
    logic        [1:0]                                     hazard_alloc;
    logic        [1:0][lineW-1:0]                          hazard_alloc_line;

//  Transaction table
//  {{{
    ccu_tt #(
        .ccuCfg          (ccuCfg),
        .domain_map_t    (domain_map_t),
        .ar_hdr_t        (ar_hdr_t),
        .se_tok_t        (se_tok_t),
        .se_resolve_t    (se_resolve_t),
        .me_tok_t        (me_tok_t),
        .mgr_ar_t        (mgr_ar_t),
        .writeback_req_t (writeback_req_t),
        .route_t         (route_t),
        .r_info_t        (r_info_t),
        .excl_req_t      (excl_req_t)
    ) u_tt (
        .clk_i,
        .rst_ni,
        .domain_map_i,
        .ar_i,
        .ar_valid_i,
        .ar_ready_o,
        .bind_valid_o,
        .bind_rslot_o,
        .bind_tid_o,
        .bi_valid_i         (bi_valid),
        .bi_line_i          (bi_line),
        .bi_ready_o         (bi_ready),
        .lookup_valid_o     (lookup_valid),
        .lookup_line_o      (lookup_line),
        .lookup_present_i   (lookup_present),
        .excl_req_o         (excl_req),
        .excl_req_valid_o   (excl_req_valid),
        .excl_i             (excl),
        .se_tok_o           (se_tok),
        .se_tok_valid_o     (se_tok_valid),
        .se_tok_ready_i     (se_tok_ready),
        .ac_room_i          (ac_room),
        .se_resolve_i       (se_resolve),
        .se_resolve_valid_i (se_resolve_valid),
        .se_resolve_ready_o (se_resolve_ready),
        .writeback_o        (writeback),
        .writeback_valid_o  (writeback_valid),
        .writeback_ready_i  (writeback_ready),
        .writeback_slot_i   (writeback_slot),
        .me_tok_o           (me_tok),
        .me_tok_valid_o     (me_tok_valid),
        .me_tok_ready_i     (me_tok_ready),
        .mem_ar_tid_i       (mem_ar_tid),
        .mem_ar_o           (mem_ar),
        .mem_done_i         (mem_done),
        .cd_done_i,
        .cd_done_tid_i,
        .rack_i,
        .rack_tid_i,
        .route_valid_o,
        .route_o,
        .r_info_valid_o,
        .r_info_o,
        .r_go_o,
        .insert_valid_o     (insert_valid),
        .insert_port_o      (insert_port),
        .insert_line_o      (insert_line),
        .insert_tid_o       (insert_tid),
        .insert_free_i      (insert_free),
        .insert_done_i      (insert_done),
        .insert_done_tid_i  (insert_done_tid),
        .cr_remove_valid_o  (cr_remove_valid),
        .cr_remove_sel_o    (cr_remove_sel),
        .cr_remove_line_o   (cr_remove_line),
        .cr_remove_tid_o    (cr_remove_tid),
        .cr_remove_ready_i  (cr_remove_ready),
        .acked_o            (acked),
        .free_o             (freeing),
        .phase_o,
        .events_o           (tt_events_o)
    );
//  }}}

//  Snoop engine
//  {{{
    ccu_snoop_engine #(
        .ccuCfg       (ccuCfg),
        .se_tok_t     (se_tok_t),
        .ac_req_t     (ac_req_t),
        .cr_ret_t     (cr_ret_t),
        .se_resolve_t (se_resolve_t)
    ) u_snoop_engine (
        .clk_i,
        .rst_ni,
        .tok_i              (se_tok),
        .tok_valid_i        (se_tok_valid),
        .tok_ready_o        (se_tok_ready),
        .ac_o,
        .ac_valid_o,
        .ac_ready_i,
        .cr_i,
        .cr_valid_i,
        .resolve_o          (se_resolve),
        .resolve_valid_o    (se_resolve_valid),
        .resolve_ready_i    (se_resolve_ready),
        .free_i             (freeing),
        .writeback_scarce_i (writeback_scarce),
        .cd_head_valid_i,
        .cd_head_tid_i,
        .ac_room_o          (ac_room),
        .events_o           (snoop_events_o)
    );
//  }}}

//  Memory engine
//  {{{
    ccu_mem_engine #(
        .ccuCfg   (ccuCfg),
        .me_tok_t (me_tok_t),
        .mgr_ar_t (mgr_ar_t),
        .mgr_r_t  (mgr_r_t),
        .rb_mem_t (rb_mem_t)
    ) u_mem_engine (
        .clk_i,
        .rst_ni,
        .tok_i               (me_tok),
        .tok_valid_i         (me_tok_valid),
        .tok_ready_o         (me_tok_ready),
        .request_tid_o       (mem_ar_tid),
        .request_i           (mem_ar),
        .hazard_valid_i      (hazard_valid),
        .hazard_line_i       (hazard_line),
        .hazard_alloc_i      (hazard_alloc),
        .hazard_alloc_line_i (hazard_alloc_line),
        .ar_o                (manager_req_o.ar),
        .ar_valid_o          (manager_req_o.ar_valid),
        .ar_ready_i          (manager_resp_i.ar_ready),
        .r_i                 (manager_resp_i.r),
        .r_valid_i           (manager_resp_i.r_valid),
        .r_ready_o           (manager_req_o.r_ready),
        .rb_o                (rb_mem_o),
        .rb_valid_o          (rb_mem_valid_o),
        .done_o              (mem_done),
        .events_o            (mem_events_o)
    );
//  }}}

//  Write lane
//  {{{
    ccu_write_lane #(
        .ccuCfg          (ccuCfg),
        .aw_hdr_t        (aw_hdr_t),
        .w_beat_t        (w_beat_t),
        .cd_w_t          (cd_w_t),
        .writeback_req_t (writeback_req_t),
        .b_ret_t         (b_ret_t),
        .mgr_aw_t        (mgr_aw_t),
        .mgr_w_t         (mgr_w_t),
        .mgr_b_t         (mgr_b_t)
    ) u_write_lane (
        .clk_i,
        .rst_ni,
        .aw_i,
        .aw_valid_i,
        .aw_ready_o,
        .w_i,
        .w_valid_i,
        .w_ready_o,
        .writeback_i         (writeback),
        .writeback_valid_i   (writeback_valid),
        .writeback_ready_o   (writeback_ready),
        .writeback_slot_o    (writeback_slot),
        .writeback_scarce_o  (writeback_scarce),
        .cd_i                (cd_w_i),
        .cd_valid_i          (cd_w_valid_i),
        .cd_ready_o          (cd_w_ready_o),
        .b_o,
        .b_valid_o,
        .hazard_valid_o      (hazard_valid),
        .hazard_line_o       (hazard_line),
        .hazard_alloc_o      (hazard_alloc),
        .hazard_alloc_line_o (hazard_alloc_line),
        .aw_o                (manager_req_o.aw),
        .aw_valid_o          (manager_req_o.aw_valid),
        .aw_ready_i          (manager_resp_i.aw_ready),
        .w_o                 (manager_req_o.w),
        .w_valid_o           (manager_req_o.w_valid),
        .w_ready_i           (manager_resp_i.w_ready),
        .b_i                 (manager_resp_i.b),
        .b_valid_i           (manager_resp_i.b_valid),
        .b_ready_o           (manager_req_o.b_ready),
        .events_o            (lane_events_o)
    );
//  }}}

//  Exclusive monitor
//  {{{
    ccu_excl_monitor #(
        .ccuCfg     (ccuCfg),
        .excl_req_t (excl_req_t)
    ) u_excl_monitor (
        .clk_i,
        .rst_ni,
        .req_i       (excl_req),
        .req_valid_i (excl_req_valid),
        .excl_o      (excl),
        .acked_i     (acked)
    );
//  }}}

//  Snoop filter
//  {{{
    if (ccuCfg.u.enableSnoopFilter) begin : gen_snoop_filter
        ccu_snoop_filter #(
            .ccuCfg (ccuCfg)
        ) u_snoop_filter (
            .clk_i,
            .rst_ni,
            .lookup_valid_i    (lookup_valid),
            .lookup_line_i     (lookup_line),
            .lookup_present_o  (lookup_present),
            .insert_valid_i    (insert_valid),
            .insert_port_i     (insert_port),
            .insert_line_i     (insert_line),
            .insert_tid_i      (insert_tid),
            .insert_free_o     (insert_free),
            .insert_done_o     (insert_done),
            .insert_done_tid_o (insert_done_tid),
            .aw_remove_valid_i (remove_valid_i),
            .aw_remove_line_i  (remove_line_i),
            .aw_remove_ready_o (remove_ready_o),
            .cr_remove_valid_i (cr_remove_valid),
            .cr_remove_sel_i   (cr_remove_sel),
            .cr_remove_line_i  (cr_remove_line),
            .cr_remove_tid_i   (cr_remove_tid),
            .cr_remove_ready_o (cr_remove_ready),
            .bi_valid_o        (bi_valid),
            .bi_line_o         (bi_line),
            .bi_ready_i        (bi_ready),
            .events_o          (filter_events_o)
        );
    end else begin : gen_no_snoop_filter
        //  Every snoop is broadcast
        assign lookup_present  = '1;
        assign bi_valid        = '0;
        assign bi_line         = '0;
        assign insert_free     = '1;
        assign insert_done     = '0;
        assign insert_done_tid = '0;
        assign cr_remove_ready = 1'b1;
        assign remove_ready_o  = '1;
        assign filter_events_o = '0;
    end
//  }}}

endmodule
