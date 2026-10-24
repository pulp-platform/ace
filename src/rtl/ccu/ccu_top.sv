// Copyright (c) 2025 ETH Zurich, University of Bologna
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
`include "axi/assign.svh"
`include "ace/assign.svh"

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

//  AXI/ACE typedefs
//  {{{
    typedef logic [ccuCfg.axiCcuIdWidth-1:0]     ccu_id_t;
    typedef logic [ccuCfg.u.axiAddressWidth-1:0] ccu_address_t;
    typedef logic [ccuCfg.u.axiDataWidth-1:0]    ccu_data_t;
    typedef logic [ccuCfg.u.axiDataWidth/8-1:0]  ccu_strb_t;
    typedef logic [ccuCfg.u.axiUserWidth-1:0]    ccu_user_t;

    `ACE_TYPEDEF_AW_CHAN_T(ccu_ace_aw_t, ccu_address_t, ccu_id_t, ccu_user_t)
    `AXI_TYPEDEF_B_CHAN_T(ccu_ace_b_t, ccu_id_t, ccu_user_t)
    `ACE_TYPEDEF_AR_CHAN_T(ccu_ace_ar_t, ccu_address_t, ccu_id_t, ccu_user_t)
    `ACE_TYPEDEF_R_CHAN_T(ccu_ace_r_t, ccu_data_t, ccu_id_t, ccu_user_t)
    `ACE_TYPEDEF_REQ_T(ccu_ace_req_t, ccu_ace_aw_t, ccu_w_t, ccu_ace_ar_t)
    `ACE_TYPEDEF_RESP_T(ccu_ace_resp_t, ccu_ace_b_t, ccu_ace_r_t)

    //  A dispatched AR on its way to the snoop pipeline
    typedef struct packed {
        ccu_ace_ar_t                             ar;
        ccu_ar_flags_t                           flags;
        logic [ccuCfg.transactionIndexWidth-1:0] tid;
        logic [ccuCfg.u.numSubordinates-1:0]     present;
    } ccu_ar_req_t;
//  }}}

//  A hazard slice with offset bits would miss same-line accesses at different offsets
if (ccuCfg.u.addressCheckLsb < ccuCfg.cachelineByteIndexWidth) begin : gen_slice_check
    $error("addressCheckLsb (%0d) is below the cacheline offset width (%0d)",
           ccuCfg.u.addressCheckLsb, ccuCfg.cachelineByteIndexWidth);
end

logic [ccuCfg.u.numShareableTransactions-1:0]                   rack_free;
logic [ccuCfg.u.numShareableTransactions-1:0]
      [ccuCfg.axiCcuIdWidth-1:0]                                sb_id;

logic                                                           pos_aw_valid;
logic [ccuCfg.addressCheckWidth-1:0]                            pos_aw_slice;
logic                                                           pos_aw_full;
logic                                                           mem_ar_addr_check;
logic [ccuCfg.addressCheckWidth-1:0]                            mem_ar_addr_slice;
logic                                                           mem_ar_stall;

logic          [ccuCfg.u.numSubordinates-1:0] snoop_ac_valid;
logic          [ccuCfg.u.numSubordinates-1:0] snoop_ac_ready;
ccu_snoop_ac_t [ccuCfg.u.numSubordinates-1:0] snoop_ac;
logic          [ccuCfg.u.numSubordinates-1:0] snoop_cr_valid;
logic          [ccuCfg.u.numSubordinates-1:0] snoop_cr_ready;
ccu_snoop_cr_t [ccuCfg.u.numSubordinates-1:0] snoop_cr;
logic          [ccuCfg.u.numSubordinates-1:0] snoop_cd_valid;
logic          [ccuCfg.u.numSubordinates-1:0] snoop_cd_ready;
ccu_snoop_cd_t [ccuCfg.u.numSubordinates-1:0] snoop_cd;

logic                                snoop_write_engine_aw_valid;
logic                                snoop_write_engine_aw_ready;
ccu_axi_manager_aw_t                 snoop_write_engine_aw;
logic                                snoop_write_engine_w_valid;
logic                                snoop_write_engine_w_ready;
ccu_w_t                              snoop_write_engine_w;
logic                                snoop_write_engine_wb_alloc_valid;
logic                                snoop_write_engine_wb_alloc_ready;
logic [ccuCfg.addressCheckWidth-1:0] snoop_write_engine_wb_alloc_slice;
logic                                snoop_read_engine_ar_valid;
logic                                snoop_read_engine_ar_ready;
ccu_axi_manager_ar_t                 snoop_read_engine_ar;
logic                                snoop_read_engine_r_valid;
logic                                snoop_read_engine_r_ready;
ccu_ace_r_t                          snoop_read_engine_r;


logic                                ar_valid;
logic                                ar_ready;
ccu_ar_req_t                         ar_req;

logic                                dispatch_ar_valid;
logic                                dispatch_ar_ready;
ccu_ar_req_t                         dispatch_ar_req;

logic [ccuCfg.transactionIndexWidth-1:0] snoop_read_engine_ar_tid;
logic                                snoop_read_engine_ar_is_shared;
logic                                snoop_read_engine_ar_exclusive;
logic [ccuCfg.transactionIndexWidth-1:0] snoop_read_engine_r_tid;
logic [ccuCfg.transactionIndexWidth-1:0] sc_fail_r_tid;
logic [ccuCfg.transactionIndexWidth-1:0] manager_r_tid;

logic [ccuCfg.u.numSubordinates-1:0] exclusive_lock;
logic [ccuCfg.u.numSubordinates-1:0]
      [ccuCfg.u.axiSubordinateIdWidth-1:0] exclusive_entry_id;
logic [ccuCfg.u.numSubordinates-1:0] exclusive_dealloc;
logic                                exclusive_sc_fail;

logic                                sc_fail_r_valid;
logic                                sc_fail_r_ready;
ccu_ace_r_t                          sc_fail_r;

ccu_axi_manager_req_t   manager_cut_req;
ccu_axi_manager_resp_t  manager_cut_resp;

ccu_snoop_pipeline_events_t snoop_pipeline_events;
ccu_frontend_events_t       frontend_events;
ccu_ar_dispatch_events_t    ar_dispatch_events;
ccu_snoop_filter_events_t   snoop_filter_events;
ccu_write_engine_events_t   write_engine_events;
ccu_read_engine_events_t    read_engine_events;
ccu_top_events_t            top_events_d, top_events;
ccu_events_t                perf_events;

logic                                sf_lookup_valid;
ccu_address_t                        sf_lookup_addr;
logic [ccuCfg.u.numSubordinates-1:0] sf_present;
logic                                sf_lookup_ready;
logic [ccuCfg.u.numSubordinates-1:0] sf_insert_valid;
logic [ccuCfg.u.numSubordinates-1:0][ccuCfg.u.axiAddressWidth-1:0] sf_insert_addr;
logic [ccuCfg.u.numSubordinates-1:0] sf_insert_ready;
logic [ccuCfg.u.numSubordinates-1:0] sf_aw_remove_valid;
logic [ccuCfg.u.numSubordinates-1:0][ccuCfg.u.axiAddressWidth-1:0] sf_aw_remove_addr;
logic [ccuCfg.u.numSubordinates-1:0] sf_aw_remove_ready;
logic                                sf_cr_remove_valid;
logic [ccuCfg.u.numSubordinates-1:0] sf_cr_remove_sel;
ccu_address_t                        sf_cr_remove_addr;
logic                                sf_cr_remove_maint;
logic                                sf_cr_remove_ready;
logic [ccuCfg.u.numSubordinates-1:0] sf_remove_miss;

//  Back-invalidations into the snoop pipeline
logic                                                              maint_valid, maint_ready;
logic [ccuCfg.u.axiAddressWidth-1:0]                               maint_addr;
logic [ccuCfg.u.numSubordinates-1:0]                               maint_sel;
logic [ccuCfg.u.numSubordinates-1:0][ccuCfg.u.axiAddressWidth-1:0] sf_backinval_addr;
logic [ccuCfg.u.numSubordinates-1:0]                               sf_backinval_busy;
logic [ccuCfg.u.numSubordinates-1:0]                               sf_backinval_hazard;

//  Frontend
//  {{{
    //  The frontend acts as the Point of Serialization (PoS)
    ccu_ace_req_t  frontend_req;
    ccu_ace_resp_t frontend_resp;

    ccu_frontend #(
        .ccuCfg                     (ccuCfg),
        .ccu_ace_manager_ar_t       (ccu_ace_ar_t),
        .ccu_ace_manager_aw_t       (ccu_ace_aw_t),
        .ccu_w_t                    (ccu_w_t),
        .ccu_ace_manager_r_t        (ccu_ace_r_t),
        .ccu_ace_manager_b_t        (ccu_ace_b_t),
        .ccu_ace_manager_req_t      (ccu_ace_req_t),
        .ccu_ace_manager_resp_t     (ccu_ace_resp_t),
        .ccu_ace_subordinate_ar_t   (ccu_ace_subordinate_ar_t),
        .ccu_ace_subordinate_aw_t   (ccu_ace_subordinate_aw_t),
        .ccu_ace_subordinate_r_t    (ccu_ace_subordinate_r_t),
        .ccu_ace_subordinate_b_t    (ccu_ace_subordinate_b_t),
        .ccu_ace_subordinate_req_t  (ccu_ace_subordinate_req_t),
        .ccu_ace_subordinate_resp_t (ccu_ace_subordinate_resp_t)
    ) u_ccu_frontend (
        .clk_i,
        .rst_ni,
        .subordinate_req_i          (subordinate_req_i),
        .subordinate_resp_o         (subordinate_resp_o),
        .subordinate_rack_i         (subordinate_rack_i),
        .manager_req_o              (frontend_req),
        .manager_resp_i             (frontend_resp),
        .manager_r_sc_fail_i        (exclusive_sc_fail),
        .manager_r_tid_i            (manager_r_tid),
        .exclusive_lock_i           (exclusive_lock),
        .exclusive_entry_id_i       (exclusive_entry_id),
        .exclusive_dealloc_o        (exclusive_dealloc),
        .rack_free_o                (rack_free),
        .pos_aw_valid_o             (pos_aw_valid),
        .pos_aw_slice_o             (pos_aw_slice),
        .pos_aw_full_i              (pos_aw_full),
        .sf_aw_remove_valid_o       (sf_aw_remove_valid),
        .sf_aw_remove_addr_o        (sf_aw_remove_addr),
        .sf_aw_remove_ready_i       (sf_aw_remove_ready),
        .events_o                   (frontend_events)
    );
//  }}}

//  AR dispatch
//  {{{
    ccu_ar_dispatch #(
        .ccuCfg       (ccuCfg),
        .ccu_ace_ar_t (ccu_ace_ar_t),
        .ccu_ar_req_t (ccu_ar_req_t)
    ) u_ccu_ar_dispatch (
        .clk_i,
        .rst_ni,
        .ar_i              (frontend_req.ar),
        .ar_valid_i        (frontend_req.ar_valid),
        .ar_ready_o        (frontend_resp.ar_ready),
        .ar_req_o          (dispatch_ar_req),
        .sf_lookup_valid_o (sf_lookup_valid),
        .sf_lookup_addr_o  (sf_lookup_addr),
        .sf_present_i      (sf_present),
        .sf_lookup_ready_i (sf_lookup_ready),
        .ar_valid_o        (dispatch_ar_valid),
        .ar_ready_i        (dispatch_ar_ready),
        .rack_mask_i       (rack_free),
        .drop_i            (sc_fail_r_valid && sc_fail_r_ready),
        .drop_tid_i        (sc_fail_r_tid),
        .sf_insert_valid_o (sf_insert_valid),
        .sf_insert_addr_o  (sf_insert_addr),
        .sf_insert_ready_i (sf_insert_ready),
        .sf_aw_remove_valid_i (sf_aw_remove_valid),
        .sf_aw_remove_addr_i  (sf_aw_remove_addr),
        .bi_addr_i         (sf_backinval_addr),
        .bi_busy_i         (sf_backinval_busy),
        .bi_hazard_o       (sf_backinval_hazard),
        .sb_id_o           (sb_id),
        .events_o          (ar_dispatch_events)
    );
//  }}}

//  Snoop filter
//  {{{
    //  When off, every snoop is broadcast
    if (ccuCfg.u.enableSnoopFilter) begin : gen_snoop_filter

    ccu_snoop_filter #(
        .ccuCfg (ccuCfg)
    ) u_ccu_snoop_filter (
        .clk_i,
        .rst_ni,
        .lookup_valid_i     (sf_lookup_valid),
        .lookup_addr_i      (sf_lookup_addr),
        .lookup_present_o   (sf_present),
        .lookup_ready_o     (sf_lookup_ready),
        .insert_valid_i     (sf_insert_valid),
        .insert_addr_i      (sf_insert_addr),
        .insert_ready_o     (sf_insert_ready),
        .aw_remove_valid_i  (sf_aw_remove_valid),
        .aw_remove_addr_i   (sf_aw_remove_addr),
        .aw_remove_ready_o  (sf_aw_remove_ready),
        .cr_remove_valid_i  (sf_cr_remove_valid),
        .cr_remove_sel_i    (sf_cr_remove_sel),
        .cr_remove_addr_i   (sf_cr_remove_addr),
        .cr_remove_maint_i  (sf_cr_remove_maint),
        .cr_remove_ready_o  (sf_cr_remove_ready),
        .maint_valid_o      (maint_valid),
        .maint_addr_o       (maint_addr),
        .maint_sel_o        (maint_sel),
        .maint_ready_i      (maint_ready),
        .backinval_addr_o   (sf_backinval_addr),
        .backinval_hazard_i (sf_backinval_hazard),
        .backinval_busy_o   (sf_backinval_busy),
        .remove_miss_o      (sf_remove_miss),
        .events_o           (snoop_filter_events)
    );

    end else begin : gen_no_snoop_filter

        assign sf_present          = '1;
        assign sf_lookup_ready     = 1'b1;
        assign sf_insert_ready     = '1;
        assign sf_aw_remove_ready  = '1;
        assign sf_cr_remove_ready  = 1'b1;
        assign sf_remove_miss      = '0;
        assign sf_backinval_addr   = '0;
        assign sf_backinval_busy   = '0;
        assign maint_valid         = 1'b0;
        assign maint_addr          = '0;
        assign maint_sel           = '0;
        assign snoop_filter_events = '0;

    end
//  }}}

//  Exclusive monitor
//  {{{
    ccu_exclusive_monitor #(
        .ccuCfg       (ccuCfg),
        .ccu_ar_req_t (ccu_ar_req_t),
        .ccu_ace_r_t  (ccu_ace_r_t)
    ) u_ccu_exclusive_monitor (
        .clk_i,
        .rst_ni,
        .dealloc_i    (exclusive_dealloc),
        .lock_o       (exclusive_lock),
        .entry_id_o   (exclusive_entry_id),
        .ar_req_i     (dispatch_ar_req),
        .ar_valid_i   (dispatch_ar_valid),
        .ar_ready_o   (dispatch_ar_ready),
        .ar_req_o     (ar_req),
        .ar_valid_o   (ar_valid),
        .ar_ready_i   (ar_ready),
        .r_o          (sc_fail_r),
        .r_tid_o      (sc_fail_r_tid),
        .r_valid_o    (sc_fail_r_valid),
        .r_ready_i    (sc_fail_r_ready)
    );
//  }}}

//  AR-related snoop pipeline
//  {{{
    ccu_snoop_pipeline #(
        .ccuCfg         (ccuCfg),
        .ccu_ace_ar_t   (ccu_ace_ar_t),
        .ccu_ar_req_t   (ccu_ar_req_t),
        .ccu_ace_r_t    (ccu_ace_r_t),
        .ccu_snoop_ac_t (ccu_snoop_ac_t),
        .ccu_snoop_cr_t (ccu_snoop_cr_t),
        .ccu_snoop_cd_t (ccu_snoop_cd_t),
        .ccu_w_t        (ccu_w_t),
        .ccu_axi_ar_t   (ccu_axi_manager_ar_t),
        .ccu_axi_aw_t   (ccu_axi_manager_aw_t),
        .domain_map_t   (domain_map_t)
    ) u_ccu_snoop_pipeline (
        .clk_i,
        .rst_ni,
        .domain_map_i             (domain_map_i),
        .ar_req_i                 (ar_req),
        .ar_valid_i               (ar_valid),
        .ar_ready_o               (ar_ready),
        .maint_valid_i            (maint_valid),
        .maint_addr_i             (maint_addr),
        .maint_sel_i              (maint_sel),
        .maint_ready_o            (maint_ready),
        .ac_valid_o               (snoop_ac_valid),
        .ac_ready_i               (snoop_ac_ready),
        .ac_o                     (snoop_ac),
        .cr_valid_i               (snoop_cr_valid),
        .cr_ready_o               (snoop_cr_ready),
        .cr_i                     (snoop_cr),
        .cd_valid_i               (snoop_cd_valid),
        .cd_ready_o               (snoop_cd_ready),
        .cd_i                     (snoop_cd),
        .write_engine_aw_valid_o  (snoop_write_engine_aw_valid),
        .write_engine_aw_ready_i  (snoop_write_engine_aw_ready),
        .write_engine_aw_o        (snoop_write_engine_aw),
        .write_engine_w_valid_o   (snoop_write_engine_w_valid),
        .write_engine_w_ready_i   (snoop_write_engine_w_ready),
        .write_engine_w_o         (snoop_write_engine_w),
        .write_engine_wb_alloc_valid_o (snoop_write_engine_wb_alloc_valid),
        .write_engine_wb_alloc_ready_i (snoop_write_engine_wb_alloc_ready),
        .write_engine_wb_alloc_slice_o (snoop_write_engine_wb_alloc_slice),
        .read_engine_ar_valid_o   (snoop_read_engine_ar_valid),
        .read_engine_ar_ready_i   (snoop_read_engine_ar_ready),
        .read_engine_ar_o         (snoop_read_engine_ar),
        .read_engine_ar_tid_o     (snoop_read_engine_ar_tid),
        .read_engine_ar_is_shared_o (snoop_read_engine_ar_is_shared),
        .read_engine_ar_exclusive_o (snoop_read_engine_ar_exclusive),
        .read_engine_r_valid_o    (snoop_read_engine_r_valid),
        .read_engine_r_ready_i    (snoop_read_engine_r_ready),
        .read_engine_r_o          (snoop_read_engine_r),
        .read_engine_r_tid_o      (snoop_read_engine_r_tid),
        .sf_cr_remove_valid_o     (sf_cr_remove_valid),
        .sf_cr_remove_sel_o       (sf_cr_remove_sel),
        .sf_cr_remove_addr_o      (sf_cr_remove_addr),
        .sf_cr_remove_maint_o     (sf_cr_remove_maint),
        .sf_cr_remove_ready_i     (sf_cr_remove_ready),
        .events_o                 (snoop_pipeline_events)
    );

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_snoop_assignments
        `SNOOP_ASSIGN_AC_STRUCT(snoop_req_o[s].ac, snoop_ac[s])
        assign snoop_req_o[s].ac_valid = snoop_ac_valid[s];
        assign snoop_ac_ready[s] = snoop_resp_i[s].ac_ready;
        `SNOOP_ASSIGN_CR_STRUCT(snoop_cr[s], snoop_resp_i[s].cr)
        assign snoop_cr_valid[s] = snoop_resp_i[s].cr_valid;
        assign snoop_req_o[s].cr_ready = snoop_cr_ready[s];
        `SNOOP_ASSIGN_CD_STRUCT(snoop_cd[s], snoop_resp_i[s].cd)
        assign snoop_cd_valid[s] = snoop_resp_i[s].cd_valid;
        assign snoop_req_o[s].cd_ready = snoop_cd_ready[s];
    end
//  }}}

//  Write engine
//  {{{
    //  Zero-pad the ID and drop the coherence fields
    ccu_axi_manager_aw_t frontend_req_aw;
    ccu_axi_manager_b_t  frontend_resp_b;

    `AXI_ASSIGN_AW_STRUCT(frontend_req_aw, frontend_req.aw)
    `AXI_ASSIGN_B_STRUCT(frontend_resp.b, frontend_resp_b)

    ccu_write_engine #(
        .ccuCfg       (ccuCfg),
        .ccu_axi_aw_t (ccu_axi_manager_aw_t),
        .ccu_w_t      (ccu_w_t),
        .ccu_axi_b_t  (ccu_axi_manager_b_t)
    ) u_ccu_write_engine (
        .clk_i,
        .rst_ni,
        .aw_valid_i               (frontend_req.aw_valid),
        .aw_ready_o               (frontend_resp.aw_ready),
        .aw_i                     (frontend_req_aw),
        .w_valid_i                (frontend_req.w_valid),
        .w_ready_o                (frontend_resp.w_ready),
        .w_i                      (frontend_req.w),
        .b_valid_o                (frontend_resp.b_valid),
        .b_ready_i                (frontend_req.b_ready),
        .b_o                      (frontend_resp_b),
        .writeback_aw_valid_i     (snoop_write_engine_aw_valid),
        .writeback_aw_ready_o     (snoop_write_engine_aw_ready),
        .writeback_aw_i           (snoop_write_engine_aw),
        .writeback_w_valid_i      (snoop_write_engine_w_valid),
        .writeback_w_ready_o      (snoop_write_engine_w_ready),
        .writeback_w_i            (snoop_write_engine_w),
        .wb_alloc_valid_i         (snoop_write_engine_wb_alloc_valid),
        .wb_alloc_ready_o         (snoop_write_engine_wb_alloc_ready),
        .wb_alloc_slice_i         (snoop_write_engine_wb_alloc_slice),
        .aw_valid_o               (manager_cut_req.aw_valid),
        .aw_ready_i               (manager_cut_resp.aw_ready),
        .aw_o                     (manager_cut_req.aw),
        .w_valid_o                (manager_cut_req.w_valid),
        .w_ready_i                (manager_cut_resp.w_ready),
        .w_o                      (manager_cut_req.w),
        .b_valid_i                (manager_cut_resp.b_valid),
        .b_ready_o                (manager_cut_req.b_ready),
        .b_i                      (manager_cut_resp.b),
        .pos_aw_valid_i           (pos_aw_valid),
        .pos_aw_slice_i           (pos_aw_slice),
        .pos_aw_full_o            (pos_aw_full),
        .mem_ar_addr_check_i      (mem_ar_addr_check),
        .mem_ar_addr_slice_i      (mem_ar_addr_slice),
        .mem_ar_stall_o           (mem_ar_stall),
        .events_o                 (write_engine_events)
    );
//  }}}

//  Read engine
//  {{{
    ccu_read_engine #(
        .ccuCfg       (ccuCfg),
        .ccu_axi_ar_t (ccu_axi_manager_ar_t),
        .ccu_ace_r_t  (ccu_ace_r_t),
        .ccu_axi_r_t  (ccu_axi_manager_r_t)
    ) u_ccu_read_engine (
        .clk_i,
        .rst_ni,
        .ar_valid_i               (snoop_read_engine_ar_valid),
        .ar_ready_o               (snoop_read_engine_ar_ready),
        .ar_i                     (snoop_read_engine_ar),
        .ar_tid_i                 (snoop_read_engine_ar_tid),
        .ar_is_shared_i           (snoop_read_engine_ar_is_shared),
        .ar_exclusive_i           (snoop_read_engine_ar_exclusive),
        .snoop_pipeline_r_valid_i (snoop_read_engine_r_valid),
        .snoop_pipeline_r_ready_o (snoop_read_engine_r_ready),
        .snoop_pipeline_r_i       (snoop_read_engine_r),
        .snoop_pipeline_r_tid_i   (snoop_read_engine_r_tid),
        .sc_fail_r_valid_i        (sc_fail_r_valid),
        .sc_fail_r_ready_o        (sc_fail_r_ready),
        .sc_fail_r_i              (sc_fail_r),
        .sc_fail_r_tid_i          (sc_fail_r_tid),
        .sb_id_i                  (sb_id),
        .r_valid_o                (frontend_resp.r_valid),
        .r_ready_i                (frontend_req.r_ready),
        .r_o                      (frontend_resp.r),
        .r_tid_o                  (manager_r_tid),
        .r_sc_fail_o              (exclusive_sc_fail),
        .ar_valid_o               (manager_cut_req.ar_valid),
        .ar_ready_i               (manager_cut_resp.ar_ready),
        .ar_o                     (manager_cut_req.ar),
        .r_valid_i                (manager_cut_resp.r_valid),
        .r_ready_o                (manager_cut_req.r_ready),
        .r_i                      (manager_cut_resp.r),
        .mem_ar_addr_check_o      (mem_ar_addr_check),
        .mem_ar_addr_slice_o      (mem_ar_addr_slice),
        .mem_ar_stall_i           (mem_ar_stall),
        .events_o                 (read_engine_events)
    );
//  }}}

//  AXI cut
//  {{{
    axi_cut #(
        .Bypass     (1'b0),
        .aw_chan_t  (ccu_axi_manager_aw_t),
        .w_chan_t   (ccu_w_t),
        .b_chan_t   (ccu_axi_manager_b_t),
        .ar_chan_t  (ccu_axi_manager_ar_t),
        .r_chan_t   (ccu_axi_manager_r_t),
        .axi_req_t  (ccu_axi_manager_req_t),
        .axi_resp_t (ccu_axi_manager_resp_t)
    ) u_ccu_axi_manager_cut (
        .clk_i,
        .rst_ni,
        .slv_req_i  (manager_cut_req),
        .slv_resp_o (manager_cut_resp),
        .mst_req_o  (manager_req_o),
        .mst_resp_i (manager_resp_i)
    );
//  }}}

//  Performance events
//  {{{
    always_comb begin : top_events_comb
        top_events_d            = '0;
        top_events_d.cycles     = 1'b1;
        top_events_d.mem_ar     = manager_req_o.ar_valid && manager_resp_i.ar_ready;
        top_events_d.mem_r_beat = manager_resp_i.r_valid && manager_req_o.r_ready;
        top_events_d.mem_w_beat = manager_req_o.w_valid  && manager_resp_i.w_ready;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) top_events <= '0;
        else         top_events <= top_events_d;
    end

    assign perf_events = '{
        cycles                            : top_events.cycles,
        ad_ar_admitted                    : ar_dispatch_events.ar_admitted,
        ad_ar_dispatched                  : ar_dispatch_events.ar_dispatched,
        fe_aw_accepted                    : frontend_events.aw_accepted,
        fe_rack_outstanding               : frontend_events.rack_outstanding,
        re_r_beat_mem                     : read_engine_events.r_beat_mem,
        re_r_beat_snoop                   : read_engine_events.r_beat_snoop,
        re_r_beat_sc_fail                 : read_engine_events.r_beat_sc_fail,
        sp_snoop_hit                      : snoop_pipeline_events.snoop_hit,
        sp_snoop_miss                     : snoop_pipeline_events.snoop_miss,
        sp_snoop_writeback                : snoop_pipeline_events.snoop_writeback,
        sp_backinval_dirty                : snoop_pipeline_events.backinval_dirty,
        we_mem_ar_stall                   : write_engine_events.mem_ar_stall,
        mem_ar                            : top_events.mem_ar,
        sp_read_no_snoop                  : snoop_pipeline_events.read_no_snoop,
        sp_read_shared                    : snoop_pipeline_events.read_shared,
        sp_read_clean                     : snoop_pipeline_events.read_clean,
        sp_read_unique                    : snoop_pipeline_events.read_unique,
        sp_clean_unique                   : snoop_pipeline_events.clean_unique,
        sp_make_unique                    : snoop_pipeline_events.make_unique,
        sp_ac_sent                        : snoop_pipeline_events.ac_sent,
        sp_ac_stall                       : snoop_pipeline_events.ac_stall,
        sp_ac_pruned                      : snoop_pipeline_events.ac_pruned,
        sp_stage0_stall_ac_fifo_full      : snoop_pipeline_events.stage0_stall_ac_fifo_full,
        sp_stage0_stall_stage1_fifo_full  : snoop_pipeline_events.stage0_stall_stage1_fifo_full,
        sp_stage0_stall_maintenance       : snoop_pipeline_events.stage0_stall_maintenance,
        sp_stage0_stall_other             : snoop_pipeline_events.stage0_stall_other,
        sp_stage1_stall_cr_not_valid      : snoop_pipeline_events.stage1_stall_cr_not_valid,
        sp_stage1_stall_write_engine_busy : snoop_pipeline_events.stage1_stall_write_engine_busy,
        sp_stage1_stall_cd_engine_busy    : snoop_pipeline_events.stage1_stall_cd_engine_busy,
        sp_stage1_stall_other             : snoop_pipeline_events.stage1_stall_other,
        ad_chained                        : ar_dispatch_events.chained,
        ad_queue_blocked                  : ar_dispatch_events.queue_blocked,
        ad_queue_pred_wait                : ar_dispatch_events.queue_pred_wait,
        ad_stall_sb_full                  : ar_dispatch_events.stall_sb_full,
        ad_stall_queue_full               : ar_dispatch_events.stall_queue_full,
        ad_dispatch_stall                 : ar_dispatch_events.dispatch_stall,
        ad_sf_insert_stall                : ar_dispatch_events.sf_insert_stall,
        ad_sf_insert_outstanding          : ar_dispatch_events.sf_insert_outstanding,
        ad_bi_blocked                     : ar_dispatch_events.bi_blocked,
        sf_lookup                         : snoop_filter_events.lookup,
        sf_lookup_present_none            : snoop_filter_events.lookup_present_none,
        sf_lookup_present_all             : snoop_filter_events.lookup_present_all,
        sf_port_busy                      : snoop_filter_events.port_busy,
        sf_update_blocked_by_lookup       : snoop_filter_events.update_blocked_by_lookup,
        sf_insert_stuck                   : snoop_filter_events.insert_stuck,
        sf_backinval_issued               : snoop_filter_events.backinval_issued,
        sf_remove_miss                    : snoop_filter_events.remove_miss,
        we_aw_issued                      : write_engine_events.aw_issued,
        we_aw_writeback                   : write_engine_events.aw_writeback,
        fe_aw_stall_pos_full              : frontend_events.aw_stall_pos_full,
        we_wb_alloc_stall_full            : write_engine_events.wb_alloc_stall_full,
        we_aw_stall_hash_full             : write_engine_events.aw_stall_hash_full,
        we_aw_stall_mem                   : write_engine_events.aw_stall_mem,
        we_w_stall_mem                    : write_engine_events.w_stall_mem,
        we_w_starve                       : write_engine_events.w_starve,
        re_ar_stall_hazard                : read_engine_events.ar_stall_hazard,
        re_ar_stall_mem                   : read_engine_events.ar_stall_mem,
        re_r_stall                        : read_engine_events.r_stall,
        fe_ar_stall                       : frontend_events.ar_stall,
        fe_aw_stall_sf_remove_full        : frontend_events.aw_stall_sf_remove_full,
        fe_r_stall_rack_fifo_full         : frontend_events.r_stall_rack_fifo_full,
        mem_r_beat                        : top_events.mem_r_beat,
        mem_w_beat                        : top_events.mem_w_beat
    };
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
    end else begin
        always_comb begin : apb_sink_tieoff
            apb_subordinate_resp_o        = '0;
            apb_subordinate_resp_o.pready = 1'b1;
        end
    end
//  }}}
endmodule
