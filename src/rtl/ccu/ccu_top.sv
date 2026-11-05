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

`include "axi/typedef.svh"
`include "ace/typedef.svh"

//! Cache coherence unit
//
//  A port adapter per manager, the networks to one home slice, and optional register cuts per channel.
module ccu_top
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg                     = '{default: '0},
    parameter type         domain_map_t               = logic,
    parameter type         ccu_ace_subordinate_ar_t   = logic,
    parameter type         ccu_ace_subordinate_aw_t   = logic,
    parameter type         ccu_w_t                    = logic,
    parameter type         ccu_ace_subordinate_r_t    = logic,
    parameter type         ccu_ace_subordinate_b_t    = logic,
    parameter type         ccu_ace_subordinate_req_t  = logic,
    parameter type         ccu_ace_subordinate_resp_t = logic,
    parameter type         ccu_axi_manager_ar_t       = logic,
    parameter type         ccu_axi_manager_aw_t       = logic,
    parameter type         ccu_axi_manager_r_t        = logic,
    parameter type         ccu_axi_manager_b_t        = logic,
    parameter type         ccu_axi_manager_req_t      = logic,
    parameter type         ccu_axi_manager_resp_t     = logic,
    parameter type         ccu_snoop_ac_t             = logic,
    parameter type         ccu_snoop_cr_t             = logic,
    parameter type         ccu_snoop_cd_t             = logic,
    parameter type         ccu_snoop_req_t            = logic,
    parameter type         ccu_snoop_resp_t           = logic,
    parameter type         apb_req_t                  = logic,
    parameter type         apb_resp_t                 = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  domain_map_t               [ccuCfg.u.numSubordinates-1:0] domain_map_i,
    input  ccu_ace_subordinate_req_t  [ccuCfg.u.numSubordinates-1:0] subordinate_req_i,
    output ccu_ace_subordinate_resp_t [ccuCfg.u.numSubordinates-1:0] subordinate_resp_o,
    input  logic                      [ccuCfg.u.numSubordinates-1:0] subordinate_rack_i,
    input  logic                      [ccuCfg.u.numSubordinates-1:0] subordinate_wack_i,
    output ccu_snoop_req_t            [ccuCfg.u.numSubordinates-1:0] snoop_req_o,
    input  ccu_snoop_resp_t           [ccuCfg.u.numSubordinates-1:0] snoop_resp_i,
    output ccu_axi_manager_req_t                                     manager_req_o,
    input  ccu_axi_manager_resp_t                                    manager_resp_i,

    input  apb_req_t  apb_subordinate_req_i,
    output apb_resp_t apb_subordinate_resp_o
);

    localparam int unsigned numSub  = ccuCfg.u.numSubordinates;
    localparam int unsigned subIdxW = ccuCfg.subordinateIndexWidth;
    localparam int unsigned numTids = ccuCfg.numTids;
    localparam int unsigned tidW    = ccuCfg.tidWidth;
    localparam int unsigned rSlotW  = ccuCfg.rSlotWidth;
    localparam int unsigned wSlotW  = ccuCfg.wSlotWidth;
    localparam int unsigned bSlotW  = ccuCfg.bSlotWidth;
    localparam int unsigned lineW   = ccuCfg.numLineWidth;
    localparam int unsigned dataW   = ccuCfg.u.axiDataWidth;
    localparam int unsigned userW   = ccuCfg.u.axiUserWidth;

    //  A memory ARID is a tid and an AWID a chain ID
    if ($bits(manager_req_o.ar.id) < ccuCfg.managerIdWidth) begin : gen_id_width_check
        $error("manager ID width %0d is below the %0d a tid or a chain ID needs",
               $bits(manager_req_o.ar.id), ccuCfg.managerIdWidth);
    end

//  Network types
//  {{{
    typedef logic [tidW-1:0]    tid_t;
    typedef logic [subIdxW-1:0] port_t;
    typedef logic [rSlotW-1:0]  r_slot_t;
    typedef logic [wSlotW-1:0]  w_slot_t;
    typedef logic [bSlotW-1:0]  b_slot_t;
    typedef logic [lineW-1:0]   line_t;
    typedef logic [dataW-1:0]   data_t;
    typedef logic [numSub-1:0]  port_mask_t;
    typedef logic [ccuCfg.u.numRSlots-1:0] r_go_t;

    typedef struct packed {
        ccu_ace_subordinate_ar_t ar;
        r_slot_t                 rslot;
    } ar_hdr_t;

    typedef struct packed {
        ccu_ace_subordinate_aw_t aw;
        b_slot_t                 bslot;
    } aw_hdr_t;

    typedef struct packed {
        b_slot_t bslot;
        ccu_w_t  w;
    } w_beat_t;

    typedef struct packed {
        r_slot_t rslot;
        tid_t    tid;
    } bind_t;

    typedef struct packed {
        ccu_snoop_ac_t ac;
        tid_t          tid;
    } ac_req_t;

    typedef struct packed {
        tid_t    tid;
        crresp_t resp;
    } cr_ret_t;

    //  Where a tid's snoop data goes, fixed at resolve
    typedef struct packed {
        tid_t    tid;
        port_t   src;
        logic    to_r;
        port_t   r_port;
        r_slot_t r_slot;
        logic    to_w;
        w_slot_t w_slot;
    } route_t;

    //  What a read's R carries, fixed at resolve, and whether it may go yet
    typedef struct packed {
        r_slot_t rslot;
        logic go;
        logic ack;
        logic is_shared;
        logic pass_dirty;
        logic exokay;
    } r_info_t;

    typedef struct packed {
        r_slot_t        slot;
        data_t          data;
        axi_pkg::resp_t resp;
        logic           last;
    } rb_mem_t;

    typedef struct packed {
        r_slot_t slot;
        data_t   data;
        logic    last;
    } rb_cd_t;

    typedef struct packed {
        port_t  port;
        rb_cd_t rb;
    } cd_r_t;

    typedef struct packed {
        w_slot_t slot;
        data_t   data;
        logic    last;
    } cd_w_t;

    typedef struct packed {
        b_slot_t              bslot;
        axi_pkg::resp_t       resp;
        logic [userW-1:0]     user;
    } b_ret_t;

    typedef struct packed {
        tid_t          tid;
        ccu_op_e       op;
        ccu_excl_t     excl;
        ccu_snoop_ac_t ac;
        port_mask_t    sel;
    } se_tok_t;

    typedef struct packed {
        tid_t         tid;
        ccu_outcome_t outcome;
        port_t        src;
        port_mask_t   dt;
        port_mask_t   remove;
    } se_resolve_t;

    typedef struct packed {
        tid_t                tid;
        port_t               port;
        r_slot_t             rslot;
    } me_tok_t;

    typedef struct packed {
        line_t             line;
        axi_pkg::cache_t   cache;
        axi_pkg::prot_t    prot;
        axi_pkg::qos_t     qos;
        axi_pkg::region_t  region;
        logic [userW-1:0]  user;
    } writeback_req_t;

    typedef struct packed {
        port_t port;
        line_t line;
        tid_t  tid;
        logic  load;
        logic  store;
    } excl_req_t;
//  }}}

//  Subordinate cuts
//  {{{
    ccu_ace_subordinate_req_t  [numSub-1:0] sub_req;
    ccu_ace_subordinate_resp_t [numSub-1:0] sub_resp;
    ccu_snoop_req_t            [numSub-1:0] snp_req;
    ccu_snoop_resp_t           [numSub-1:0] snp_resp;
    logic                      [numSub-1:0] rack, wack;

    for (genvar p = 0; p < numSub; p++) begin : gen_sub_cut
        ace_cut #(
            .BypassAr  (!ccuCfg.u.cutSubordinate[CutAr]),
            .BypassAw  (!ccuCfg.u.cutSubordinate[CutAw]),
            .BypassW   (!ccuCfg.u.cutSubordinate[CutW]),
            .BypassR   (!ccuCfg.u.cutSubordinate[CutR]),
            .BypassB   (!ccuCfg.u.cutSubordinate[CutB]),
            .aw_chan_t (ccu_ace_subordinate_aw_t),
            .w_chan_t  (ccu_w_t),
            .b_chan_t  (ccu_ace_subordinate_b_t),
            .ar_chan_t (ccu_ace_subordinate_ar_t),
            .r_chan_t  (ccu_ace_subordinate_r_t),
            .req_t     (ccu_ace_subordinate_req_t),
            .resp_t    (ccu_ace_subordinate_resp_t)
        ) u_ace_cut (
            .clk_i,
            .rst_ni,
            .req_i  (subordinate_req_i[p]),
            .resp_o (subordinate_resp_o[p]),
            .req_o  (sub_req[p]),
            .resp_i (sub_resp[p])
        );

        snoop_cut #(
            .BypassAc  (!ccuCfg.u.cutSubordinate[CutAc]),
            .BypassCr  (!ccuCfg.u.cutSubordinate[CutCr]),
            .BypassCd  (!ccuCfg.u.cutSubordinate[CutCd]),
            .ac_chan_t (ccu_snoop_ac_t),
            .cr_chan_t (ccu_snoop_cr_t),
            .cd_chan_t (ccu_snoop_cd_t),
            .req_t     (ccu_snoop_req_t),
            .resp_t    (ccu_snoop_resp_t)
        ) u_snoop_cut (
            .clk_i,
            .rst_ni,
            .req_i  (snp_req[p]),
            .resp_o (snp_resp[p]),
            .req_o  (snoop_req_o[p]),
            .resp_i (snoop_resp_i[p])
        );

        //  An acknowledge cannot be stalled, so a flop rather than a spill register
        if (ccuCfg.u.cutSubordinate[CutRack]) begin : gen_rack_cut
            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) rack[p] <= 1'b0;
                else         rack[p] <= subordinate_rack_i[p];
            end
        end else begin : gen_rack_wire
            assign rack[p] = subordinate_rack_i[p];
        end

        if (ccuCfg.u.cutSubordinate[CutWack]) begin : gen_wack_cut
            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) wack[p] <= 1'b0;
                else         wack[p] <= subordinate_wack_i[p];
            end
        end else begin : gen_wack_wire
            assign wack[p] = subordinate_wack_i[p];
        end
    end
//  }}}

//  Port adapters
//  {{{
    ar_hdr_t                  [numSub-1:0] ar_hdr;
    logic                     [numSub-1:0] ar_valid, ar_ready;
    bind_t                    [numSub-1:0] rslot_bind;
    logic                     [numSub-1:0] bind_valid;
    aw_hdr_t                  [numSub-1:0] aw_hdr;
    logic                     [numSub-1:0] aw_valid, aw_ready;
    logic                     [numSub-1:0] remove_valid, remove_ready;
    line_t                    [numSub-1:0] remove_line;
    w_beat_t                  [numSub-1:0] w_beat;
    logic                     [numSub-1:0] w_valid, w_ready;
    ac_req_t                  [numSub-1:0] ac;
    logic                     [numSub-1:0] ac_valid, ac_ready;
    cr_ret_t                  [numSub-1:0] cr;
    logic                     [numSub-1:0] cr_valid;
    logic                                  route_valid;
    route_t                                route;
    cd_r_t                    [numSub-1:0] cd_r;
    logic                     [numSub-1:0] cd_r_valid, cd_r_ready;
    cd_w_t                    [numSub-1:0] cd_w;
    logic                     [numSub-1:0] cd_w_valid, cd_w_ready;
    logic                     [numSub-1:0] cd_done;
    tid_t                     [numSub-1:0] cd_done_tid;
    logic                     [numSub-1:0] cd_head_valid;
    tid_t                     [numSub-1:0] cd_head_tid;
    rb_mem_t                  [numSub-1:0] rb_mem;
    logic                     [numSub-1:0] rb_mem_valid;
    rb_cd_t                   [numSub-1:0] rb_cd;
    logic                     [numSub-1:0] rb_cd_valid, rb_cd_ready;
    logic                     [numSub-1:0] r_info_valid;
    r_info_t                  [numSub-1:0] r_info;
    r_go_t                    [numSub-1:0] r_go;
    b_ret_t                   [numSub-1:0] b_ret;
    logic                     [numSub-1:0] b_ret_valid;
    logic                     [numSub-1:0] rack_valid;
    tid_t                     [numSub-1:0] rack_tid;
    ccu_port_events_t         [numSub-1:0] port_events;

    for (genvar p = 0; p < numSub; p++) begin : gen_port
        ccu_port_adapter #(
            .ccuCfg       (ccuCfg),
            .sub_req_t    (ccu_ace_subordinate_req_t),
            .sub_resp_t   (ccu_ace_subordinate_resp_t),
            .sub_r_t      (ccu_ace_subordinate_r_t),
            .sub_b_t      (ccu_ace_subordinate_b_t),
            .snoop_req_t  (ccu_snoop_req_t),
            .snoop_resp_t (ccu_snoop_resp_t),
            .snoop_cd_t   (ccu_snoop_cd_t),
            .ar_hdr_t     (ar_hdr_t),
            .aw_hdr_t     (aw_hdr_t),
            .w_beat_t     (w_beat_t),
            .ac_req_t     (ac_req_t),
            .cr_ret_t     (cr_ret_t),
            .route_t      (route_t),
            .r_info_t     (r_info_t),
            .rb_mem_t     (rb_mem_t),
            .rb_cd_t      (rb_cd_t),
            .cd_r_t       (cd_r_t),
            .cd_w_t       (cd_w_t),
            .b_ret_t      (b_ret_t)
        ) u_port_adapter (
            .clk_i,
            .rst_ni,
            .port_i          (port_t'(p)),
            .req_i           (sub_req[p]),
            .resp_o          (sub_resp[p]),
            .rack_i          (rack[p]),
            .wack_i          (wack[p]),
            .snoop_req_o     (snp_req[p]),
            .snoop_resp_i    (snp_resp[p]),
            .ar_hdr_o        (ar_hdr[p]),
            .ar_valid_o      (ar_valid[p]),
            .ar_ready_i      (ar_ready[p]),
            .bind_valid_i    (bind_valid[p]),
            .bind_rslot_i    (rslot_bind[p].rslot),
            .bind_tid_i      (rslot_bind[p].tid),
            .aw_hdr_o        (aw_hdr[p]),
            .aw_valid_o      (aw_valid[p]),
            .aw_ready_i      (aw_ready[p]),
            .remove_valid_o  (remove_valid[p]),
            .remove_line_o   (remove_line[p]),
            .remove_ready_i  (remove_ready[p]),
            .w_o             (w_beat[p]),
            .w_valid_o       (w_valid[p]),
            .w_ready_i       (w_ready[p]),
            .ac_i            (ac[p]),
            .ac_valid_i      (ac_valid[p]),
            .ac_ready_o      (ac_ready[p]),
            .cr_o            (cr[p]),
            .cr_valid_o      (cr_valid[p]),
            .route_valid_i   (route_valid),
            .route_i         (route),
            .cd_r_o          (cd_r[p]),
            .cd_r_valid_o    (cd_r_valid[p]),
            .cd_r_ready_i    (cd_r_ready[p]),
            .cd_w_o          (cd_w[p]),
            .cd_w_valid_o    (cd_w_valid[p]),
            .cd_w_ready_i    (cd_w_ready[p]),
            .cd_done_o       (cd_done[p]),
            .cd_done_tid_o   (cd_done_tid[p]),
            .cd_head_valid_o (cd_head_valid[p]),
            .cd_head_tid_o   (cd_head_tid[p]),
            .rb_mem_i        (rb_mem[p]),
            .rb_mem_valid_i  (rb_mem_valid[p]),
            .rb_cd_i         (rb_cd[p]),
            .rb_cd_valid_i   (rb_cd_valid[p]),
            .rb_cd_ready_o   (rb_cd_ready[p]),
            .r_info_valid_i  (r_info_valid[p]),
            .r_info_i        (r_info[p]),
            .r_go_i          (r_go[p]),
            .b_i             (b_ret[p]),
            .b_valid_i       (b_ret_valid[p]),
            .rack_o          (rack_valid[p]),
            .rack_tid_o      (rack_tid[p]),
            .events_o        (port_events[p])
        );
    end
//  }}}

//  Snoop data network: a snooped port's CD into the initiator's R slot
//  {{{
    logic   [numSub-1:0][numSub-1:0] cd_r_req, cd_r_gnt;
    rb_cd_t [numSub-1:0]             cd_r_beat;

    for (genvar s = 0; s < numSub; s++) begin : gen_cd_r_beat
        assign cd_r_beat[s] = cd_r[s].rb;
    end

    for (genvar d = 0; d < numSub; d++) begin : gen_cd_r_net
        for (genvar s = 0; s < numSub; s++) begin : gen_req
            assign cd_r_req[d][s] = cd_r_valid[s] && cd_r[s].port == port_t'(d);
        end

        //  One beat at a time: a source's next beat may wait on its manager
        rr_arb_tree #(
            .NumIn     (numSub),
            .DataType  (rb_cd_t),
            .ExtPrio   (1'b0),
            .AxiVldRdy (1'b1),
            .LockIn    (1'b0)
        ) u_cd_r_arbiter (
            .clk_i,
            .rst_ni,
            .flush_i (1'b0),
            .rr_i    ('0),
            .req_i   (cd_r_req[d]),
            .gnt_o   (cd_r_gnt[d]),
            .data_i  (cd_r_beat),
            .req_o   (rb_cd_valid[d]),
            .gnt_i   (rb_cd_ready[d]),
            .data_o  (rb_cd[d]),
            .idx_o   ()
        );
    end

    always_comb begin : cd_r_ready_comb
        cd_r_ready = '0;
        for (int unsigned s = 0; s < numSub; s++)
            cd_r_ready[s] = cd_r_gnt[cd_r[s].port][s];
    end
//  }}}

//  Networks between the ports and the slice, each hop optionally cut
//  {{{
    localparam bit cutToSlice = ccuCfg.u.cutInternal[CutToSlice];
    localparam bit cutToPort  = ccuCfg.u.cutInternal[CutToPort];

    ar_hdr_t      [numSub-1:0]  slc_ar;
    logic         [numSub-1:0]  slc_ar_valid, slc_ar_ready;
    aw_hdr_t      [numSub-1:0]  slc_aw;
    logic         [numSub-1:0]  slc_aw_valid, slc_aw_ready;
    line_t        [numSub-1:0]  slc_remove_line;
    logic         [numSub-1:0]  slc_remove_valid, slc_remove_ready;
    w_beat_t      [numSub-1:0]  slc_w;
    logic         [numSub-1:0]  slc_w_valid, slc_w_ready;
    cd_w_t        [numSub-1:0]  slc_cd_w;
    logic         [numSub-1:0]  slc_cd_w_valid, slc_cd_w_ready;
    cr_ret_t      [numSub-1:0]  slc_cr;
    logic         [numSub-1:0]  slc_cr_valid;
    tid_t         [numSub-1:0]  slc_cd_done_tid, slc_rack_tid, slc_cd_head_tid;
    logic         [numSub-1:0]  slc_cd_head_valid;
    logic         [numSub-1:0]  slc_cd_done, slc_rack;
    ac_req_t      [numSub-1:0]  slc_ac;
    logic         [numSub-1:0]  slc_ac_valid, slc_ac_ready;
    rb_mem_t      [numSub-1:0]  slc_rb_mem;
    logic         [numSub-1:0]  slc_rb_mem_valid;
    b_ret_t       [numSub-1:0]  slc_b_ret;
    logic         [numSub-1:0]  slc_b_ret_valid;
    logic         [numSub-1:0]  slc_bind_valid;
    r_slot_t                    slc_bind_rslot;
    tid_t                       slc_bind_tid;
    bind_t        [numSub-1:0]  slc_bind;

    for (genvar p = 0; p < numSub; p++) begin : gen_slc_bind
        assign slc_bind[p] = '{rslot: slc_bind_rslot, tid: slc_bind_tid};
    end
    logic                       slc_route_valid;
    route_t                     slc_route;
    logic         [numSub-1:0]  slc_r_info_valid;
    r_info_t                    slc_r_info;
    r_go_t        [numSub-1:0]  slc_r_go;

    for (genvar p = 0; p < numSub; p++) begin : gen_net
        //  Toward the slice
        spill_register #(
            .T      (ar_hdr_t),
            .Bypass (!cutToSlice)
        ) u_ar (
            .clk_i,
            .rst_ni,
            .valid_i (ar_valid[p]),
            .ready_o (ar_ready[p]),
            .data_i  (ar_hdr[p]),
            .valid_o (slc_ar_valid[p]),
            .ready_i (slc_ar_ready[p]),
            .data_o  (slc_ar[p])
        );

        spill_register #(
            .T      (aw_hdr_t),
            .Bypass (!cutToSlice)
        ) u_aw (
            .clk_i,
            .rst_ni,
            .valid_i (aw_valid[p]),
            .ready_o (aw_ready[p]),
            .data_i  (aw_hdr[p]),
            .valid_o (slc_aw_valid[p]),
            .ready_i (slc_aw_ready[p]),
            .data_o  (slc_aw[p])
        );

        spill_register #(
            .T      (line_t),
            .Bypass (!cutToSlice)
        ) u_remove (
            .clk_i,
            .rst_ni,
            .valid_i (remove_valid[p]),
            .ready_o (remove_ready[p]),
            .data_i  (remove_line[p]),
            .valid_o (slc_remove_valid[p]),
            .ready_i (slc_remove_ready[p]),
            .data_o  (slc_remove_line[p])
        );

        spill_register #(
            .T      (w_beat_t),
            .Bypass (!cutToSlice)
        ) u_w (
            .clk_i,
            .rst_ni,
            .valid_i (w_valid[p]),
            .ready_o (w_ready[p]),
            .data_i  (w_beat[p]),
            .valid_o (slc_w_valid[p]),
            .ready_i (slc_w_ready[p]),
            .data_o  (slc_w[p])
        );

        spill_register #(
            .T      (cd_w_t),
            .Bypass (!cutToSlice)
        ) u_cd_w (
            .clk_i,
            .rst_ni,
            .valid_i (cd_w_valid[p]),
            .ready_o (cd_w_ready[p]),
            .data_i  (cd_w[p]),
            .valid_o (slc_cd_w_valid[p]),
            .ready_i (slc_cd_w_ready[p]),
            .data_o  (slc_cd_w[p])
        );

        ccu_pulse_cut #(
            .T      (cr_ret_t),
            .Bypass (!cutToSlice)
        ) u_cr (
            .clk_i,
            .rst_ni,
            .valid_i (cr_valid[p]),
            .data_i  (cr[p]),
            .valid_o (slc_cr_valid[p]),
            .data_o  (slc_cr[p])
        );

        ccu_pulse_cut #(
            .T      (tid_t),
            .Bypass (!cutToSlice)
        ) u_cd_done (
            .clk_i,
            .rst_ni,
            .valid_i (cd_done[p]),
            .data_i  (cd_done_tid[p]),
            .valid_o (slc_cd_done[p]),
            .data_o  (slc_cd_done_tid[p])
        );

        //  A stale head only delays
        ccu_pulse_cut #(
            .T      (tid_t),
            .Bypass (!cutToSlice)
        ) u_cd_head (
            .clk_i,
            .rst_ni,
            .valid_i (cd_head_valid[p]),
            .data_i  (cd_head_tid[p]),
            .valid_o (slc_cd_head_valid[p]),
            .data_o  (slc_cd_head_tid[p])
        );

        ccu_pulse_cut #(
            .T      (tid_t),
            .Bypass (!cutToSlice)
        ) u_rack (
            .clk_i,
            .rst_ni,
            .valid_i (rack_valid[p]),
            .data_i  (rack_tid[p]),
            .valid_o (slc_rack[p]),
            .data_o  (slc_rack_tid[p])
        );

        //  Toward the port; the snoop engine's AC FIFO is the cut
        assign ac[p]           = slc_ac[p];
        assign ac_valid[p]     = slc_ac_valid[p];
        assign slc_ac_ready[p] = ac_ready[p];

        ccu_pulse_cut #(
            .T      (rb_mem_t),
            .Bypass (!cutToPort)
        ) u_rb_mem (
            .clk_i,
            .rst_ni,
            .valid_i (slc_rb_mem_valid[p]),
            .data_i  (slc_rb_mem[p]),
            .valid_o (rb_mem_valid[p]),
            .data_o  (rb_mem[p])
        );

        ccu_pulse_cut #(
            .T      (b_ret_t),
            .Bypass (!cutToPort)
        ) u_b (
            .clk_i,
            .rst_ni,
            .valid_i (slc_b_ret_valid[p]),
            .data_i  (slc_b_ret[p]),
            .valid_o (b_ret_valid[p]),
            .data_o  (b_ret[p])
        );

        ccu_pulse_cut #(
            .T      (bind_t),
            .Bypass (!cutToPort)
        ) u_bind (
            .clk_i,
            .rst_ni,
            .valid_i (slc_bind_valid[p]),
            .data_i  (slc_bind[p]),
            .valid_o (bind_valid[p]),
            .data_o  (rslot_bind[p])
        );
    end

    ccu_pulse_cut #(
        .T      (route_t),
        .Bypass (!cutToPort)
    ) u_route (
        .clk_i,
        .rst_ni,
        .valid_i (slc_route_valid),
        .data_i  (slc_route),
        .valid_o (route_valid),
        .data_o  (route)
    );

    for (genvar p = 0; p < numSub; p++) begin : gen_net_r_info
        ccu_pulse_cut #(
            .T      (r_info_t),
            .Bypass (!cutToPort)
        ) u_r_info (
            .clk_i,
            .rst_ni,
            .valid_i (slc_r_info_valid[p]),
            .data_i  (slc_r_info),
            .valid_o (r_info_valid[p]),
            .data_o  (r_info[p])
        );

        ccu_pulse_cut #(
            .T      (r_go_t),
            .Bypass (!cutToPort)
        ) u_r_go (
            .clk_i,
            .rst_ni,
            .valid_i (1'b1),
            .data_i  (slc_r_go[p]),
            .valid_o (),
            .data_o  (r_go[p])
        );
    end
//  }}}

//  Home slice
//  {{{
    ccu_axi_manager_req_t  slice_req;
    ccu_axi_manager_resp_t slice_resp;
    ccu_events_t      perf_events;

    ccu_slice #(
        .ccuCfg          (ccuCfg),
        .domain_map_t    (domain_map_t),
        .ar_hdr_t        (ar_hdr_t),
        .aw_hdr_t        (aw_hdr_t),
        .w_beat_t        (w_beat_t),
        .ac_req_t        (ac_req_t),
        .cr_ret_t        (cr_ret_t),
        .cd_w_t          (cd_w_t),
        .route_t         (route_t),
        .r_info_t        (r_info_t),
        .rb_mem_t        (rb_mem_t),
        .b_ret_t         (b_ret_t),
        .se_tok_t        (se_tok_t),
        .se_resolve_t    (se_resolve_t),
        .me_tok_t        (me_tok_t),
        .writeback_req_t (writeback_req_t),
        .excl_req_t      (excl_req_t),
        .mgr_ar_t        (ccu_axi_manager_ar_t),
        .mgr_aw_t        (ccu_axi_manager_aw_t),
        .mgr_w_t         (ccu_w_t),
        .mgr_r_t         (ccu_axi_manager_r_t),
        .mgr_b_t         (ccu_axi_manager_b_t),
        .mgr_req_t       (ccu_axi_manager_req_t),
        .mgr_resp_t      (ccu_axi_manager_resp_t)
    ) u_slice (
        .clk_i,
        .rst_ni,
        .domain_map_i,
        .ar_i            (slc_ar),
        .ar_valid_i      (slc_ar_valid),
        .ar_ready_o      (slc_ar_ready),
        .bind_valid_o    (slc_bind_valid),
        .bind_rslot_o    (slc_bind_rslot),
        .bind_tid_o      (slc_bind_tid),
        .aw_i            (slc_aw),
        .aw_valid_i      (slc_aw_valid),
        .aw_ready_o      (slc_aw_ready),
        .remove_valid_i  (slc_remove_valid),
        .remove_line_i   (slc_remove_line),
        .remove_ready_o  (slc_remove_ready),
        .ac_o            (slc_ac),
        .ac_valid_o      (slc_ac_valid),
        .ac_ready_i      (slc_ac_ready),
        .cr_i            (slc_cr),
        .cr_valid_i      (slc_cr_valid),
        .route_valid_o   (slc_route_valid),
        .route_o         (slc_route),
        .cd_done_i       (slc_cd_done),
        .cd_done_tid_i   (slc_cd_done_tid),
        .cd_head_valid_i (slc_cd_head_valid),
        .cd_head_tid_i   (slc_cd_head_tid),
        .w_i             (slc_w),
        .w_valid_i       (slc_w_valid),
        .w_ready_o       (slc_w_ready),
        .cd_w_i          (slc_cd_w),
        .cd_w_valid_i    (slc_cd_w_valid),
        .cd_w_ready_o    (slc_cd_w_ready),
        .rb_mem_o        (slc_rb_mem),
        .rb_mem_valid_o  (slc_rb_mem_valid),
        .r_info_valid_o  (slc_r_info_valid),
        .r_info_o        (slc_r_info),
        .r_go_o          (slc_r_go),
        .b_o             (slc_b_ret),
        .b_valid_o       (slc_b_ret_valid),
        .rack_i          (slc_rack),
        .rack_tid_i      (slc_rack_tid),
        .manager_req_o   (slice_req),
        .manager_resp_i  (slice_resp),
        .tt_events_o     (perf_events.tt),
        .snoop_events_o  (perf_events.snoop),
        .mem_events_o    (perf_events.mem),
        .lane_events_o   (perf_events.lane),
        .filter_events_o (perf_events.filter)
    );
//  }}}

//  Manager cut
//  {{{
    axi_cut #(
        .BypassAr   (!ccuCfg.u.cutManager[CutAr]),
        .BypassAw   (!ccuCfg.u.cutManager[CutAw]),
        .BypassW    (!ccuCfg.u.cutManager[CutW]),
        .BypassR    (!ccuCfg.u.cutManager[CutR]),
        .BypassB    (!ccuCfg.u.cutManager[CutB]),
        .aw_chan_t  (ccu_axi_manager_aw_t),
        .w_chan_t   (ccu_w_t),
        .b_chan_t   (ccu_axi_manager_b_t),
        .ar_chan_t  (ccu_axi_manager_ar_t),
        .r_chan_t   (ccu_axi_manager_r_t),
        .axi_req_t  (ccu_axi_manager_req_t),
        .axi_resp_t (ccu_axi_manager_resp_t)
    ) u_manager_cut (
        .clk_i,
        .rst_ni,
        .slv_req_i  (slice_req),
        .slv_resp_o (slice_resp),
        .mst_req_o  (manager_req_o),
        .mst_resp_i (manager_resp_i)
    );
//  }}}

//  Performance events
//  {{{
    ccu_port_mem_events_t top_events_d;

    always_comb begin : top_events_comb
        top_events_d            = '0;
        top_events_d.cycles     = 1'b1;
        top_events_d.mem_ar     = manager_req_o.ar_valid && manager_resp_i.ar_ready;
        top_events_d.mem_r_beat = manager_resp_i.r_valid && manager_req_o.r_ready;
        top_events_d.mem_aw     = manager_req_o.aw_valid && manager_resp_i.aw_ready;
        top_events_d.mem_w_beat = manager_req_o.w_valid  && manager_resp_i.w_ready;
        top_events_d.mem_b      = manager_resp_i.b_valid && manager_req_o.b_ready;
    end

    ccu_port_mem_events_t top_events_q;
    ccu_port_events_t     port_events_any;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) top_events_q <= '0;
        else         top_events_q <= top_events_d;
    end

    //  Registered by each port already
    always_comb begin : port_events_comb
        port_events_any = '0;
        for (int unsigned p = 0; p < numSub; p++) port_events_any |= port_events[p];
    end

    assign perf_events.top  = top_events_q;
    assign perf_events.port = port_events_any;
//  }}}

//  Control and status registers
//  {{{
    if (ccuCfg.u.enableCSRs) begin : gen_csr
        ccu_csr_wrap #(
            .ccuCfg     (ccuCfg),
            .apb_req_t  (apb_req_t),
            .apb_resp_t (apb_resp_t),
            .numEvents  ($bits(ccu_events_t))
        ) u_ccu_csrs (
            .clk_i,
            .rst_ni,
            .apb_req_i  (apb_subordinate_req_i),
            .apb_resp_o (apb_subordinate_resp_o),
            .events_i   (perf_events)
        );
    end else begin : gen_no_csr
        always_comb begin : apb_sink_tieoff
            apb_subordinate_resp_o        = '0;
            apb_subordinate_resp_o.pready = 1'b1;
        end
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    //  Memory R and B are never back-pressured
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        slice_req.r_ready && slice_req.b_ready)
        else $error("memory R or B back-pressured inside the cut");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        manager_req_o.r_ready && manager_req_o.b_ready)
        else $error("memory R or B back-pressured at the manager port");
    `endif
    // pragma translate_on
//  }}}
endmodule
