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

`include "ace/typedef.svh"
`include "ace/assign.svh"
`include "ace/convert.svh"

module ace_ccu_master_path import ace_pkg::*; import ccu_pkg::*;
#(
  parameter ccu_cfg_t CcuCfg                   = '{default: '0},
  parameter type slv_ar_chan_t                 = logic,
  parameter type slv_aw_chan_t                 = logic,
  parameter type slv_b_chan_t                  = logic,
  parameter type w_chan_t                      = logic,
  parameter type slv_r_chan_t                  = logic,
  parameter type mst_ar_chan_t                 = logic,
  parameter type mst_aw_chan_t                 = logic,
  parameter type mst_b_chan_t                  = logic,
  parameter type mst_r_chan_t                  = logic,
  parameter type slv_req_t                     = logic,
  parameter type slv_resp_t                    = logic,
  parameter type mst_req_t                     = logic,
  parameter type mst_resp_t                    = logic,
  parameter type snoop_ac_t                    = logic,
  parameter type snoop_cr_t                    = logic,
  parameter type snoop_cd_t                    = logic,
  parameter type snoop_req_t                   = logic,
  parameter type snoop_resp_t                  = logic,
  parameter type domain_mask_t                 = logic,
  parameter type domain_set_t                  = logic,
  // Local parameters
  localparam type cm_addr_t                    = logic [CcuCfg.CmAddrWidth-1:0]
) (
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  domain_set_t [CcuCfg.NoSlvPorts-1:0]   domain_set_i,
  input  slv_req_t    [CcuCfg.NoSlvPorts-1:0]   slv_req_i,
  output slv_resp_t   [CcuCfg.NoSlvPorts-1:0]   slv_resp_o,
  output snoop_req_t  [CcuCfg.NoSnoopPorts-1:0] snoop_req_o,
  output domain_mask_t[CcuCfg.NoSnoopPorts-1:0] snoop_masks_o,
  input  snoop_resp_t [CcuCfg.NoSnoopPorts-1:0] snoop_resp_i,
  output mst_req_t                              mst_req_o,
  input  mst_resp_t                             mst_resp_i,

  output logic      [2*CcuCfg.NoGroups-1:0]     cm_req_o,
  output cm_addr_t  [2*CcuCfg.NoGroups-1:0]     cm_addr_o
);

  /////////////////
  // Localparams //
  /////////////////

  // ID width after ACE mux
  localparam PostMuxIdWidth = CcuCfg.AxiSlvIdWidth + $clog2(CcuCfg.NoSlvPerGroup);
  // ID width after snoop_path (adds 2 bits)
  localparam PostSnpIdWidth = PostMuxIdWidth + 2;

  //////////////
  // Typedefs //
  //////////////

  typedef logic [CcuCfg.AxiAddrWidth -1:0]  addr_t;
  typedef logic [CcuCfg.AxiDataWidth-1:0]   data_t;
  typedef logic [CcuCfg.AxiUserWidth-1:0]   user_t;
  typedef logic [PostMuxIdWidth-1:0]        pm_id_t;
  typedef logic [PostSnpIdWidth-1:0]        ps_id_t;

  `ACE_TYPEDEF_AW_CHAN_T(int_ace_aw_chan_t, addr_t, pm_id_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T (int_ace_b_chan_t, pm_id_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(int_ace_ar_chan_t, addr_t, pm_id_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T (int_ace_r_chan_t, data_t, pm_id_t, user_t)
  `ACE_TYPEDEF_REQ_T    (int_ace_req_t, int_ace_aw_chan_t, w_chan_t, int_ace_ar_chan_t)
  `ACE_TYPEDEF_RESP_T   (int_ace_resp_t, int_ace_b_chan_t, int_ace_r_chan_t)

  `AXI_TYPEDEF_AW_CHAN_T(int_axi_aw_chan_t, addr_t, ps_id_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T (int_axi_b_chan_t, ps_id_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(int_axi_ar_chan_t, addr_t, ps_id_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T (int_axi_r_chan_t, data_t, ps_id_t, user_t)
  `AXI_TYPEDEF_REQ_T    (int_axi_req_t, int_axi_aw_chan_t, w_chan_t, int_axi_ar_chan_t)
  `AXI_TYPEDEF_RESP_T   (int_axi_resp_t, int_axi_b_chan_t, int_axi_r_chan_t)

  slv_req_t  [CcuCfg.NoSlvPorts-1:0] ace_snooping_req,  ace_nonsnooping_req;
  slv_resp_t [CcuCfg.NoSlvPorts-1:0] ace_snooping_resp, ace_nonsnooping_resp;

  int_axi_req_t  [CcuCfg.NoMemPorts-1:0] axi_memory_reqs;
  int_axi_resp_t [CcuCfg.NoMemPorts-1:0] axi_memory_resps;

  ///////////
  // DEMUX //
  ///////////

  for (genvar i = 0; i < CcuCfg.NoSlvPorts; i++) begin : gen_demux

    logic slv_aw_snooping, slv_ar_snooping;

    ace_aw_transaction_decoder #(
        .aw_chan_t (slv_aw_chan_t)
    ) i_write_decoder (
        .aw_i          (slv_req_i[i].aw),
        .snooping_o    (slv_aw_snooping),
        .acsnoop_o     (),
        .illegal_trs_o ()
    );

    ace_ar_transaction_decoder #(
        .LEGACY    (CcuCfg.AmoHotfix),
        .ar_chan_t (slv_ar_chan_t)
    ) i_read_decoder (
        .ar_i          (slv_req_i[i].ar),
        .snooping_o    (slv_ar_snooping),
        .snoop_info_o  (),
        .illegal_trs_o ()
    );

    ace_demux #(
      .AxiIdWidth  (CcuCfg.AxiSlvIdWidth),
      .AtopSupport (1'b1),
      .aw_chan_t   (slv_aw_chan_t),
      .w_chan_t    (w_chan_t),
      .b_chan_t    (slv_b_chan_t),
      .ar_chan_t   (slv_ar_chan_t),
      .r_chan_t    (slv_r_chan_t),
      .axi_req_t   (slv_req_t),
      .axi_resp_t  (slv_resp_t),
      .NoMstPorts  (32'd2),
      .MaxTrans    (32'd8),
      .AxiLookBits (32'd3),
      .UniqueIds   (1'b0),
      .SpillAw     (CcuCfg.CutSlvReq || CcuCfg.CutSlvAx),
      .SpillW      (CcuCfg.CutSlvReq),
      .SpillB      (CcuCfg.CutSlvResp),
      .SpillAr     (CcuCfg.CutSlvReq || CcuCfg.CutSlvAx),
      .SpillR      (CcuCfg.CutSlvResp)
    ) i_slv_demux (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .test_i          (1'b0),
      .slv_req_i       (slv_req_i[i]),
      .slv_resp_o      (slv_resp_o[i]),
      .slv_aw_select_i (slv_aw_snooping),
      .slv_ar_select_i (slv_ar_snooping),
      .mst_reqs_o      ({ace_snooping_req[i],  ace_nonsnooping_req[i]}),
      .mst_resps_i     ({ace_snooping_resp[i], ace_nonsnooping_resp[i]})
    );

  end

  for (genvar i = 0; i < CcuCfg.NoGroups; i++) begin : gen_snoop

    slv_req_t  [CcuCfg.NoSlvPerGroup-1:0] ace_snooping_group_req;
    slv_resp_t [CcuCfg.NoSlvPerGroup-1:0] ace_snooping_group_resp;

    int_ace_req_t  ace_snooping_muxed_req;
    int_ace_resp_t ace_snooping_muxed_resp;

    int_ace_req_t  ace_snooping_forked_req;
    int_ace_resp_t ace_snooping_forked_resp;

    int_ace_req_t  [1:0] ace_memory_reqs;
    int_ace_resp_t [1:0] ace_memory_resps;

    for (genvar j = 0; j < CcuCfg.NoSlvPerGroup; j++) begin
    `ACE_ASSIGN_REQ_STRUCT(ace_snooping_group_req[j], ace_snooping_req [CcuCfg.NoSlvPerGroup * i + j])
    `ACE_ASSIGN_RESP_STRUCT(ace_snooping_resp[CcuCfg.NoSlvPerGroup * i + j], ace_snooping_group_resp[j])
    end

    /////////
    // MUX //
    /////////

    ace_mux #(
        .SlvAxiIDWidth (CcuCfg.AxiSlvIdWidth),
        .slv_aw_chan_t (slv_aw_chan_t),
        .mst_aw_chan_t (int_ace_aw_chan_t),
        .w_chan_t      (w_chan_t),
        .slv_b_chan_t  (slv_b_chan_t),
        .mst_b_chan_t  (int_ace_b_chan_t),
        .slv_ar_chan_t (slv_ar_chan_t),
        .mst_ar_chan_t (int_ace_ar_chan_t),
        .slv_r_chan_t  (slv_r_chan_t),
        .mst_r_chan_t  (int_ace_r_chan_t),
        .slv_req_t     (slv_req_t),
        .slv_resp_t    (slv_resp_t),
        .mst_req_t     (int_ace_req_t),
        .mst_resp_t    (int_ace_resp_t),
        .NoSlvPorts    (CcuCfg.NoSlvPerGroup),
        .MaxWTrans     (32'd8),
        .MaxRTrans     (32'd8),
        .MaxBTrans     (32'd8),
        .FallThrough   (1'b0),
        .SpillAw       (1'b0),
        .SpillW        (1'b0),
        .SpillB        (1'b0),
        .SpillAr       (1'b0),
        .SpillR        (1'b0)
    ) i_snoop_mux (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .test_i      (1'b0),
        .slv_reqs_i  (ace_snooping_group_req),
        .slv_resps_o (ace_snooping_group_resp),
        .mst_req_o   (ace_snooping_muxed_req),
        .mst_resp_i  (ace_snooping_muxed_resp)
    );

    //////////////////////
    // ADDRESS TRACKING //
    //////////////////////

    logic aw_queue_valid, aw_queue_ready;
    logic ar_queue_valid, ar_queue_ready;

    stream_fork #(
      .N_OUP (2)
    ) i_aw_fork (
      .clk_i,
      .rst_ni,
      .valid_i (ace_snooping_muxed_req.aw_valid),
      .ready_o (ace_snooping_muxed_resp.aw_ready),
      .valid_o ({ace_snooping_forked_req.aw_valid , aw_queue_valid}),
      .ready_i ({ace_snooping_forked_resp.aw_ready, aw_queue_ready})
    );

    stream_fork #(
      .N_OUP (2)
    ) i_ar_fork (
      .clk_i,
      .rst_ni,
      .valid_i (ace_snooping_muxed_req.ar_valid),
      .ready_o (ace_snooping_muxed_resp.ar_ready),
      .valid_o ({ace_snooping_forked_req.ar_valid , ar_queue_valid}),
      .ready_i ({ace_snooping_forked_resp.ar_ready, ar_queue_ready})
    );

    logic w_fifo_full;
    logic w_fifo_push, w_fifo_pop;

    logic [PostMuxIdWidth-1:0] w_fifo_id_in, w_fifo_id_out;

    id_queue #(
      .ID_WIDTH            (PostMuxIdWidth),
      .CAPACITY            (8),
      .FULL_BW             (1'b1),
      .CUT_OUP_POP_INP_GNT (1'b1),
      .data_t              (cm_addr_t)
    ) i_w_queue (
      .clk_i,
      .rst_ni,
      .inp_id_i         (ace_snooping_muxed_req.aw.id),
      .inp_data_i       (ace_snooping_muxed_req.aw.addr[CcuCfg.CmAddrBase+:CcuCfg.CmAddrWidth]),
      .inp_req_i        (aw_queue_valid),
      .inp_gnt_o        (aw_queue_ready),
      .exists_data_i    ('0),
      .exists_mask_i    ('0),
      .exists_req_i     ('0),
      .exists_o         (),
      .exists_gnt_o     (),
      .oup_id_i         (w_fifo_id_out),
      .oup_pop_i        (1'b1),
      .oup_req_i        (ace_snooping_muxed_req.wack),
      .oup_data_o       (cm_addr_o[2*i]),
      .oup_data_valid_o (),
      .oup_gnt_o        ()
    );

    assign w_fifo_push  = ace_snooping_forked_resp.b_valid &&
                          ace_snooping_muxed_req.b_ready   &&
                          !w_fifo_full;
    assign w_fifo_pop   = ace_snooping_muxed_req.wack;
    assign w_fifo_id_in = ace_snooping_forked_resp.b.id;

    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (4),
        .DATA_WIDTH   (PostMuxIdWidth)
    ) i_w_addr_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (w_fifo_full),
        .empty_o    (),
        .usage_o    (),
        .data_i     (w_fifo_id_in),
        .push_i     (w_fifo_push),
        .data_o     (w_fifo_id_out),
        .pop_i      (w_fifo_pop)
    );

    logic r_fifo_full;
    logic r_fifo_push, r_fifo_pop;

    logic [PostMuxIdWidth-1:0] r_fifo_id_in, r_fifo_id_out;

    id_queue #(
      .ID_WIDTH            (PostMuxIdWidth),
      .CAPACITY            (8),
      .FULL_BW             (1'b1),
      .CUT_OUP_POP_INP_GNT (1'b1),
      .data_t              (cm_addr_t)
    ) i_r_queue (
      .clk_i,
      .rst_ni,
      .inp_id_i         (ace_snooping_muxed_req.ar.id),
      .inp_data_i       (ace_snooping_muxed_req.ar.addr[CcuCfg.CmAddrBase+:CcuCfg.CmAddrWidth]),
      .inp_req_i        (ar_queue_valid),
      .inp_gnt_o        (ar_queue_ready),
      .exists_data_i    ('0),
      .exists_mask_i    ('0),
      .exists_req_i     ('0),
      .exists_o         (),
      .exists_gnt_o     (),
      .oup_id_i         (r_fifo_id_out),
      .oup_pop_i        (1'b1),
      .oup_req_i        (ace_snooping_muxed_req.rack),
      .oup_data_o       (cm_addr_o[2*i+1]),
      .oup_data_valid_o (),
      .oup_gnt_o        ()
    );

    assign r_fifo_push  = ace_snooping_forked_resp.r_valid &&
                          ace_snooping_muxed_req.r_ready   &&
                          ace_snooping_forked_resp.r.last  &&
                          !r_fifo_full;
    assign r_fifo_pop   = ace_snooping_muxed_req.rack;
    assign r_fifo_id_in = ace_snooping_forked_resp.r.id;

    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (4),
        .DATA_WIDTH   (PostMuxIdWidth)
    ) i_r_addr_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (r_fifo_full),
        .empty_o    (),
        .usage_o    (),
        .data_i     (r_fifo_id_in),
        .push_i     (r_fifo_push),
        .data_o     (r_fifo_id_out),
        .pop_i      (r_fifo_pop)
    );

    `ACE_ASSIGN_AW_STRUCT(ace_snooping_forked_req.aw, ace_snooping_muxed_req.aw)
    `ACE_ASSIGN_AR_STRUCT(ace_snooping_forked_req.ar, ace_snooping_muxed_req.ar)
    `AXI_ASSIGN_W_STRUCT (ace_snooping_forked_req.w, ace_snooping_muxed_req.w)
    `ACE_ASSIGN_R_STRUCT(ace_snooping_muxed_resp.r, ace_snooping_forked_resp.r)
    `AXI_ASSIGN_B_STRUCT(ace_snooping_muxed_resp.b, ace_snooping_forked_resp.b)
    assign ace_snooping_forked_req.w_valid = ace_snooping_muxed_req.w_valid;
    assign ace_snooping_muxed_resp.w_ready = ace_snooping_forked_resp.w_ready;

    assign ace_snooping_muxed_resp.b_valid = !w_fifo_full && ace_snooping_forked_resp.b_valid;
    assign ace_snooping_muxed_resp.r_valid = !r_fifo_full && ace_snooping_forked_resp.r_valid;
    assign ace_snooping_forked_req.b_ready = !w_fifo_full && ace_snooping_muxed_req.b_ready;
    assign ace_snooping_forked_req.r_ready = !r_fifo_full && ace_snooping_muxed_req.r_ready;

    assign cm_req_o   [2*i  ] = ace_snooping_muxed_req.wack;
    assign cm_req_o   [2*i+1] = ace_snooping_muxed_req.rack;

    assign ace_snooping_forked_req.wack = ace_snooping_muxed_req.wack;
    assign ace_snooping_forked_req.rack = ace_snooping_muxed_req.rack;


    ////////////////
    // SNOOP PATH //
    ////////////////

    int_axi_req_t  axi_memory_group_reqs;
    int_axi_resp_t axi_memory_group_resps;

    ace_ccu_snoop_path #(
      .LEGACY          (CcuCfg.AmoHotfix),
      .NoRules         (CcuCfg.NoSlvPerGroup),
      .DcacheLineWidth (CcuCfg.DcacheLineWidth),
      .AxiDataWidth    (CcuCfg.AxiDataWidth),
      .AxiSlvIdWidth   (CcuCfg.AxiSlvIdWidth),
      .AxiAddrWidth    (CcuCfg.AxiAddrWidth),
      .AxiUserWidth    (CcuCfg.AxiUserWidth),
      .ace_aw_chan_t   (int_ace_aw_chan_t),
      .ace_ar_chan_t   (int_ace_ar_chan_t),
      .ace_r_chan_t    (int_ace_r_chan_t),
      .ace_req_t       (int_ace_req_t),
      .ace_resp_t      (int_ace_resp_t),
      .w_chan_t        (w_chan_t),
      .axi_req_t       (int_axi_req_t),
      .axi_resp_t      (int_axi_resp_t),
      .snoop_ac_t      (snoop_ac_t),
      .snoop_cr_t      (snoop_cr_t),
      .snoop_cd_t      (snoop_cd_t),
      .snoop_req_t     (snoop_req_t),
      .snoop_resp_t    (snoop_resp_t),
      .domain_mask_t   (domain_mask_t),
      .domain_set_t    (domain_set_t)
    ) i_snoop_path (
      .clk_i          (clk_i),
      .rst_ni         (rst_ni),
      .slv_req_i      (ace_snooping_forked_req),
      .slv_resp_o     (ace_snooping_forked_resp),
      .mst_req_o      (axi_memory_group_reqs),
      .mst_resp_i     (axi_memory_group_resps),
      .domain_set_i   (domain_set_i    [(CcuCfg.NoSlvPerGroup*i)+:CcuCfg.NoSlvPerGroup]),
      .snoop_reqs_o   (snoop_req_o     [(2*i)+:2]),
      .snoop_resps_i  (snoop_resp_i    [(2*i)+:2]),
      .snoop_masks_o  (snoop_masks_o   [(2*i)+:2])
    );

    `AXI_ASSIGN_REQ_STRUCT(axi_memory_reqs [i * CcuCfg.NoMemPortsPerGroup + 1], axi_memory_group_reqs)
    `AXI_ASSIGN_RESP_STRUCT(axi_memory_group_resps, axi_memory_resps[i * CcuCfg.NoMemPortsPerGroup + 1])
  end

  //////////////////
  // NOSNOOP PATH //
  //////////////////

  for (genvar i = 0; i < CcuCfg.NoGroups; i++) begin : gen_nosnoop

    slv_req_t  [CcuCfg.NoSlvPerGroup-1:0] ace_nonsnooping_group_req;
    slv_resp_t [CcuCfg.NoSlvPerGroup-1:0] ace_nonsnooping_group_resp;

    int_ace_req_t  ace_nonsnooping_muxed_req;
    int_ace_resp_t ace_nonsnooping_muxed_resp;

    for (genvar j = 0; j < CcuCfg.NoSlvPerGroup; j++) begin
    `ACE_ASSIGN_REQ_STRUCT(ace_nonsnooping_group_req[j], ace_nonsnooping_req [CcuCfg.NoSlvPerGroup * i + j])
    `ACE_ASSIGN_RESP_STRUCT(ace_nonsnooping_resp[CcuCfg.NoSlvPerGroup * i + j], ace_nonsnooping_group_resp[j])
    end

    ace_mux #(
      .SlvAxiIDWidth (CcuCfg.AxiSlvIdWidth),
      .slv_aw_chan_t (slv_aw_chan_t),
      .mst_aw_chan_t (int_ace_aw_chan_t),
      .w_chan_t      (w_chan_t),
      .slv_b_chan_t  (slv_b_chan_t),
      .mst_b_chan_t  (int_ace_b_chan_t),
      .slv_ar_chan_t (slv_ar_chan_t),
      .mst_ar_chan_t (int_ace_ar_chan_t),
      .slv_r_chan_t  (slv_r_chan_t),
      .mst_r_chan_t  (int_ace_r_chan_t),
      .slv_req_t     (slv_req_t),
      .slv_resp_t    (slv_resp_t),
      .mst_req_t     (int_ace_req_t),
      .mst_resp_t    (int_ace_resp_t),
      .NoSlvPorts    (CcuCfg.NoSlvPerGroup),
      .MaxWTrans     (32'd8),
      .MaxRTrans     (32'd8),
      .MaxBTrans     (32'd8),
      .FallThrough   (1'b0),
      .SpillAw       (1'b0),
      .SpillW        (1'b0),
      .SpillB        (1'b0),
      .SpillAr       (1'b0),
      .SpillR        (1'b0)
    ) i_nosnoop_mux (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),
      .test_i      (1'b0),
      .slv_reqs_i  (ace_nonsnooping_group_req),
      .slv_resps_o (ace_nonsnooping_group_resp),
      .mst_req_o   (ace_nonsnooping_muxed_req),
      .mst_resp_i  (ace_nonsnooping_muxed_resp)
    );

    `ACE_TO_AXI_ASSIGN_REQ (axi_memory_reqs[CcuCfg.NoMemPortsPerGroup*i], ace_nonsnooping_muxed_req)
    `AXI_TO_ACE_ASSIGN_RESP(ace_nonsnooping_muxed_resp, axi_memory_resps[CcuCfg.NoMemPortsPerGroup*i])
  end

  ///////////////
  // FINAL MUX //
  ///////////////

  axi_mux #(
    .SlvAxiIDWidth (PostSnpIdWidth),
    .slv_aw_chan_t (int_axi_aw_chan_t),
    .slv_b_chan_t  (int_axi_b_chan_t),
    .slv_ar_chan_t (int_axi_ar_chan_t),
    .slv_req_t     (int_axi_req_t),
    .slv_resp_t    (int_axi_resp_t),
    .slv_r_chan_t  (int_axi_r_chan_t),
    .mst_aw_chan_t (mst_aw_chan_t),
    .w_chan_t      (w_chan_t),
    .mst_b_chan_t  (mst_b_chan_t),
    .mst_ar_chan_t (mst_ar_chan_t),
    .mst_r_chan_t  (mst_r_chan_t),
    .mst_req_t     (mst_req_t),
    .mst_resp_t    (mst_resp_t),
    .NoSlvPorts    (CcuCfg.NoMemPorts),
    .MaxWTrans     (32'd8),
    .FallThrough   (1'b0),
    .SpillAw       (CcuCfg.CutMstReq || CcuCfg.CutMstAx),
    .SpillW        (CcuCfg.CutMstReq),
    .SpillB        (CcuCfg.CutMstResp),
    .SpillAr       (CcuCfg.CutMstReq || CcuCfg.CutMstAx),
    .SpillR        (CcuCfg.CutMstResp)
  ) i_mux (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .test_i      (1'b0),
    .slv_reqs_i  (axi_memory_reqs),
    .slv_resps_o (axi_memory_resps),
    .mst_req_o   (mst_req_o),
    .mst_resp_i  (mst_resp_i)
  );

endmodule
