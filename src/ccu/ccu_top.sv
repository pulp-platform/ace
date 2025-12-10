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
    parameter type         ccu_snoop_resp_t           = logic
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
    input  ccu_axi_manager_resp_t                                    manager_resp_i
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

localparam int unsigned scoreboardEntryIndexWidth = ccuCfg.transactionIndexWidth;

logic                                                           scoreboard_full;
logic                                                           scoreboard_alloc_check;
logic                                                           scoreboard_alloc;
logic                                                           scoreboard_alloc_hit;
logic                                                           scoreboard_dealloc_check;
logic [ccuCfg.axiCcuIdWidth-1:0]                                scoreboard_dealloc_id;
logic                                                           scoreboard_dealloc_hit;
logic [scoreboardEntryIndexWidth-1:0]                           scoreboard_dealloc_hit_entry;
logic [ccuCfg.u.numSubordinates]                                scoreboard_dealloc;
logic [ccuCfg.u.numSubordinates][scoreboardEntryIndexWidth-1:0] scoreboard_dealloc_entry;

logic                                replay_alloc;
logic                                replay_full;

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
logic                                snoop_read_engine_ar_valid;
logic                                snoop_read_engine_ar_ready;
ccu_axi_manager_ar_t                 snoop_read_engine_ar;
logic                                snoop_read_engine_r_valid;
logic                                snoop_read_engine_r_ready;
ccu_ace_r_t                          snoop_read_engine_r;


logic                                read_engine_addr_check;
logic                                read_engine_addr_hit;
logic [ccuCfg.addressCheckWidth-1:0] read_engine_addr_slice;

ccu_axi_manager_req_t   manager_cut_req;
ccu_axi_manager_resp_t  manager_cut_resp;

//  Frontend
//  {{{
    //  The frontend acts as the Point of Serialization (PoS)
    ccu_ace_req_t  frontend_req;
    ccu_ace_resp_t frontend_resp;
    logic          shareable_stall;

    assign shareable_stall = 1'b0;

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
        .shareable_stall_i          (shareable_stall),
        .subordinate_req_i          (subordinate_req_i),
        .subordinate_resp_o         (subordinate_resp_o),
        .subordinate_rack_i         (subordinate_rack_i),
        .subordinate_wack_i         (subordinate_wack_i),
        .manager_req_o              (frontend_req),
        .manager_resp_i             (frontend_resp),
        .scoreboard_dealloc_check_o (scoreboard_dealloc_check),
        .scoreboard_dealloc_id_o    (scoreboard_dealloc_id),
        .scoreboard_dealloc_hit_i   (scoreboard_dealloc_hit),
        .scoreboard_dealloc_entry_i (scoreboard_dealloc_hit_entry),
        .scoreboard_dealloc_o       (scoreboard_dealloc),
        .scoreboard_dealloc_entry_o (scoreboard_dealloc_entry)
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
        .ar_i                     (frontend_req.ar),
        .ar_valid_i               (frontend_req.ar_valid),
        .ar_ready_o               (frontend_resp.ar_ready),
        .scoreboard_alloc_check_o (scoreboard_alloc_check),
        .scoreboard_alloc_o       (scoreboard_alloc),
        .scoreboard_alloc_hit_i   (scoreboard_alloc_hit),
        .scoreboard_full_i        (scoreboard_full),
        .replay_alloc_o           (replay_alloc),
        .replay_full_i            (replay_full),
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
        .read_engine_ar_valid_o   (snoop_read_engine_ar_valid),
        .read_engine_ar_ready_i   (snoop_read_engine_ar_ready),
        .read_engine_ar_o         (snoop_read_engine_ar),
        .read_engine_r_valid_o    (snoop_read_engine_r_valid),
        .read_engine_r_ready_i    (snoop_read_engine_r_ready),
        .read_engine_r_o          (snoop_read_engine_r)
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

//  Scoreboard
//  {{{
    ccu_scoreboard #(
        .ccuCfg (ccuCfg)
    ) u_ccu_scoreboard (
        .clk_i,
        .rst_ni,
        .full_o              (scoreboard_full),
        .alloc_check_i       (scoreboard_alloc_check),
        .alloc_i             (scoreboard_alloc),
        .alloc_addr_i        (frontend_req.ar.addr),
        .alloc_id_i          (frontend_req.ar.id),
        .alloc_hit_o         (scoreboard_alloc_hit),
        .dealloc_check_i     (scoreboard_dealloc_check),
        .dealloc_id_i        (scoreboard_dealloc_id),
        .dealloc_hit_o       (scoreboard_dealloc_hit),
        .dealloc_hit_entry_o (scoreboard_dealloc_hit_entry),
        .dealloc_i           (scoreboard_dealloc),
        .dealloc_entry_i     (scoreboard_dealloc_entry)
    );
//  }}}

//  Replay list
//  TODO: currently a stub, to be implemented
//  {{{
    ccu_replay #(
        .ccuCfg (ccuCfg)
    ) u_ccu_replay (
        .clk_i,
        .rst_ni,
        .replay_alloc_i (replay_alloc),
        .replay_full_o  (replay_full)
    );
//  }}}

//  Write engine
//  {{{
    /*
        NOTE: AW/W/B pipelining happens in the frontend
              by adding spill registers on these channels
    */

    // Intermediate signals to zero-pad the ID
    // and drop the coherence fields
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
        .aw_valid_o               (manager_cut_req.aw_valid),
        .aw_ready_i               (manager_cut_resp.aw_ready),
        .aw_o                     (manager_cut_req.aw),
        .w_valid_o                (manager_cut_req.w_valid),
        .w_ready_i                (manager_cut_resp.w_ready),
        .w_o                      (manager_cut_req.w),
        .b_valid_i                (manager_cut_resp.b_valid),
        .b_ready_o                (manager_cut_req.b_ready),
        .b_i                      (manager_cut_resp.b),
        .read_engine_addr_check_i (read_engine_addr_check),
        .read_engine_addr_hit_o   (read_engine_addr_hit),
        .read_engine_addr_slice_i (read_engine_addr_slice)
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
        .ar_addr_check_o          (read_engine_addr_check),
        .ar_addr_hit_i            (read_engine_addr_hit),
        .ar_addr_slice_o          (read_engine_addr_slice),
        .snoop_pipeline_r_valid_i (snoop_read_engine_r_valid),
        .snoop_pipeline_r_ready_o (snoop_read_engine_r_ready),
        .snoop_pipeline_r_i       (snoop_read_engine_r),
        .r_valid_o                (frontend_resp.r_valid),
        .r_ready_i                (frontend_req.r_ready),
        .r_o                      (frontend_resp.r),
        .ar_valid_o               (manager_cut_req.ar_valid),
        .ar_ready_i               (manager_cut_resp.ar_ready),
        .ar_o                     (manager_cut_req.ar),
        .r_valid_i                (manager_cut_resp.r_valid),
        .r_ready_o                (manager_cut_req.r_ready),
        .r_i                      (manager_cut_resp.r)
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
endmodule
