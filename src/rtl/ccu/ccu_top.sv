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
//  }}}

logic [ccuCfg.u.numShareableTransactions-1:0]                   rack_free;
logic [ccuCfg.u.numShareableTransactions-1:0]                   rack_error;
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
ccu_ace_ar_t                         ar;

logic                                dispatch_ar_valid;
logic                                dispatch_ar_ready;
ccu_ace_ar_t                         dispatch_ar;
ccu_ar_flags_t                       dispatch_ar_flags;
ccu_ar_flags_t                       ar_flags;

logic [ccuCfg.transactionIndexWidth-1:0] dispatch_ar_tid;
logic [ccuCfg.transactionIndexWidth-1:0] ar_tid;
logic [ccuCfg.transactionIndexWidth-1:0] snoop_read_engine_ar_tid;
logic                                snoop_read_engine_ar_is_shared;
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

ccu_snoop_pipeline_events_t perf_events;

logic                                sf_lookup_valid;
ccu_address_t                        sf_lookup_addr;
logic [ccuCfg.u.numSubordinates-1:0] sf_present;
logic [ccuCfg.u.numSubordinates-1:0] dispatch_ar_present;
logic [ccuCfg.u.numSubordinates-1:0] ar_present;
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

//  Back-invalidation requests, arbitrated into the snoop pipeline
typedef struct packed {
    logic [ccuCfg.u.axiAddressWidth-1:0]  addr;
    logic [ccuCfg.u.numSubordinates-1:0]  sel;
} backinval_req_t;

logic           [ccuCfg.u.numSubordinates-1:0] sf_backinval_valid;
logic           [ccuCfg.u.numSubordinates-1:0][ccuCfg.u.axiAddressWidth-1:0] sf_backinval_addr;
logic           [ccuCfg.u.numSubordinates-1:0] sf_backinval_ready;
backinval_req_t [ccuCfg.u.numSubordinates-1:0] backinval_req;
backinval_req_t                                maint_req;
logic                                          maint_valid, maint_ready;
logic           [ccuCfg.u.numSubordinates-1:0] sf_backinval_busy;
logic           [ccuCfg.u.numSubordinates-1:0] sf_backinval_hazard;
logic           [ccuCfg.u.numSubordinates-1:0] bi_arb_ready;

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
        .subordinate_wack_i         (subordinate_wack_i),
        .manager_req_o              (frontend_req),
        .manager_resp_i             (frontend_resp),
        .manager_r_sc_fail_i        (exclusive_sc_fail),
        .manager_r_tid_i            (manager_r_tid),
        .exclusive_lock_i           (exclusive_lock),
        .exclusive_entry_id_i       (exclusive_entry_id),
        .exclusive_dealloc_o        (exclusive_dealloc),
        .rack_free_o                (rack_free),
        .rack_error_o               (rack_error),
        .pos_aw_valid_o             (pos_aw_valid),
        .pos_aw_slice_o             (pos_aw_slice),
        .pos_aw_full_i              (pos_aw_full),
        .sf_aw_remove_valid_o       (sf_aw_remove_valid),
        .sf_aw_remove_addr_o        (sf_aw_remove_addr),
        .sf_aw_remove_ready_i       (sf_aw_remove_ready)
    );
//  }}}

//  AR dispatch
//  {{{
    ccu_ar_dispatch #(
        .ccuCfg       (ccuCfg),
        .ccu_ace_ar_t (ccu_ace_ar_t)
    ) u_ccu_ar_dispatch (
        .clk_i,
        .rst_ni,
        .ar_i              (frontend_req.ar),
        .ar_valid_i        (frontend_req.ar_valid),
        .ar_ready_o        (frontend_resp.ar_ready),
        .ar_o              (dispatch_ar),
        .ar_flags_o        (dispatch_ar_flags),
        .ar_tid_o          (dispatch_ar_tid),
        .ar_present_o      (dispatch_ar_present),
        .sf_lookup_valid_o (sf_lookup_valid),
        .sf_lookup_addr_o  (sf_lookup_addr),
        .sf_present_i      (sf_present),
        .ar_valid_o        (dispatch_ar_valid),
        .ar_ready_i        (dispatch_ar_ready),
        .rack_mask_i       (rack_free),
        .rack_error_i      (rack_error),
        .drop_valid_i      (sc_fail_r_valid),
        .drop_tid_i        (sc_fail_r_tid),
        .sf_insert_valid_o (sf_insert_valid),
        .sf_insert_addr_o  (sf_insert_addr),
        .sf_insert_ready_i (sf_insert_ready),
        .bi_addr_i         (sf_backinval_addr),
        .bi_busy_i         (sf_backinval_busy),
        .bi_hazard_o       (sf_backinval_hazard),
        .sb_id_o           (sb_id)
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
        .backinval_valid_o  (sf_backinval_valid),
        .backinval_addr_o   (sf_backinval_addr),
        .backinval_ready_i  (sf_backinval_ready),
        .backinval_hazard_i (sf_backinval_hazard),
        .backinval_busy_o   (sf_backinval_busy),
        .remove_miss_o      (sf_remove_miss)
    );

    //  Round-robin so a busy set cannot keep another table's insert waiting
    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_backinval_req
        assign backinval_req[s] = '{
            addr: sf_backinval_addr[s],
            sel : ccuCfg.u.numSubordinates'(1) << s
        };
    end

    stream_arbiter #(
        .DATA_T  (backinval_req_t),
        .N_INP   (ccuCfg.u.numSubordinates),
        .ARBITER ("rr")
    ) u_backinval_arb (
        .clk_i,
        .rst_ni,
        .inp_data_i  (backinval_req),
        .inp_valid_i (sf_backinval_valid),
        .inp_ready_o (bi_arb_ready),
        .oup_data_o  (maint_req),
        .oup_valid_o (maint_valid),
        .oup_ready_i (maint_ready)
    );

    assign sf_backinval_ready = bi_arb_ready & sf_backinval_valid;

    end else begin : gen_no_snoop_filter

        assign sf_present          = '1;
        assign sf_insert_ready     = '1;
        assign sf_aw_remove_ready  = '1;
        assign sf_cr_remove_ready  = 1'b1;
        assign sf_remove_miss      = '0;
        assign sf_backinval_valid  = '0;
        assign sf_backinval_addr   = '0;
        assign sf_backinval_ready  = '0;
        assign sf_backinval_busy   = '0;
        assign maint_valid         = 1'b0;
        assign maint_req           = '0;

    end
//  }}}

//  Exclusive monitor
//  {{{
    ccu_exclusive_monitor #(
        .ccuCfg       (ccuCfg),
        .ccu_ace_ar_t (ccu_ace_ar_t),
        .ccu_ace_r_t  (ccu_ace_r_t)
    ) u_ccu_exclusive_monitor (
        .clk_i,
        .rst_ni,
        .dealloc_i    (exclusive_dealloc),
        .lock_o       (exclusive_lock),
        .entry_id_o   (exclusive_entry_id),
        .ar_i         (dispatch_ar),
        .ar_flags_i   (dispatch_ar_flags),
        .ar_tid_i     (dispatch_ar_tid),
        .ar_present_i (dispatch_ar_present),
        .ar_valid_i   (dispatch_ar_valid),
        .ar_ready_o   (dispatch_ar_ready),
        .ar_o         (ar),
        .ar_flags_o   (ar_flags),
        .ar_tid_o     (ar_tid),
        .ar_present_o (ar_present),
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
        .ar_i                     (ar),
        .ar_flags_i               (ar_flags),
        .ar_tid_i                 (ar_tid),
        .ar_valid_i               (ar_valid),
        .ar_ready_o               (ar_ready),
        .maint_valid_i            (maint_valid),
        .maint_addr_i             (maint_req.addr),
        .maint_sel_i              (maint_req.sel),
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
        .read_engine_r_valid_o    (snoop_read_engine_r_valid),
        .read_engine_r_ready_i    (snoop_read_engine_r_ready),
        .read_engine_r_o          (snoop_read_engine_r),
        .read_engine_r_tid_o      (snoop_read_engine_r_tid),
        .ar_present_i             (ar_present),
        .sf_cr_remove_valid_o     (sf_cr_remove_valid),
        .sf_cr_remove_sel_o       (sf_cr_remove_sel),
        .sf_cr_remove_addr_o      (sf_cr_remove_addr),
        .sf_cr_remove_maint_o     (sf_cr_remove_maint),
        .sf_cr_remove_ready_i     (sf_cr_remove_ready),
        .events_o                 (perf_events)
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
        .wack_i                   (subordinate_wack_i),
        .pos_aw_valid_i           (pos_aw_valid),
        .pos_aw_slice_i           (pos_aw_slice),
        .pos_aw_full_o            (pos_aw_full),
        .mem_ar_addr_check_i      (mem_ar_addr_check),
        .mem_ar_addr_slice_i      (mem_ar_addr_slice),
        .mem_ar_stall_o           (mem_ar_stall)
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
        .mem_ar_stall_i           (mem_ar_stall)
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

//  Control and status registers
//  {{{
    if (ccuCfg.u.enableCSRs) begin : gen_csr
        ccu_csr_wrap #(
            .ccuCfg     (ccuCfg),
            .apb_req_t  (apb_req_t),
            .apb_resp_t (apb_resp_t),
            .numEvents  ($bits(ccu_snoop_pipeline_events_t))
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
