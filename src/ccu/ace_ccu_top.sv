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

`include "ace/assign.svh"
`include "ace/typedef.svh"
`include "ace/domain.svh"

module ace_ccu_top import ace_pkg::*; import ccu_pkg::*;
#(
  parameter ccu_cfg_t CcuCfg         = '{default: '0},
  parameter type      slv_ar_chan_t  = logic,
  parameter type      slv_aw_chan_t  = logic,
  parameter type      slv_b_chan_t   = logic,
  parameter type      w_chan_t       = logic,
  parameter type      slv_r_chan_t   = logic,
  parameter type      mst_ar_chan_t  = logic,
  parameter type      mst_aw_chan_t  = logic,
  parameter type      mst_b_chan_t   = logic,
  parameter type      mst_r_chan_t   = logic,
  parameter type      slv_req_t      = logic,
  parameter type      slv_resp_t     = logic,
  parameter type      mst_req_t      = logic,
  parameter type      mst_resp_t     = logic,
  parameter type      snoop_ac_t     = logic,
  parameter type      snoop_cr_t     = logic,
  parameter type      snoop_cd_t     = logic,
  parameter type      snoop_req_t    = logic,
  parameter type      snoop_resp_t   = logic,
  localparam type     domain_mask_t  = `DOMAIN_MASK_T(CcuCfg.NoSlvPorts),
  localparam type     domain_set_t   = `DOMAIN_SET_T
) (
  input  logic                                clk_i,
  input  logic                                rst_ni,
  input  domain_set_t [CcuCfg.NoSlvPorts-1:0] domain_set_i,
  input  slv_req_t    [CcuCfg.NoSlvPorts-1:0] slv_req_i,
  output slv_resp_t   [CcuCfg.NoSlvPorts-1:0] slv_resp_o,
  output snoop_req_t  [CcuCfg.NoSlvPorts-1:0] snoop_req_o,
  input  snoop_resp_t [CcuCfg.NoSlvPorts-1:0] snoop_resp_i,
  output mst_req_t                            mst_req_o,
  input  mst_resp_t                           mst_resp_i
);

  typedef logic [CcuCfg.CmAddrWidth-1:0] cm_idx_t;

  // To snoop interconnect
  domain_mask_t [CcuCfg.NoSnoopPorts-1:0] snoop_sel;
  snoop_req_t   [CcuCfg.NoSnoopPorts-1:0] snoop_reqs;
  snoop_resp_t  [CcuCfg.NoSnoopPorts-1:0] snoop_resps;

  // Conflict management signals
  logic      [2*CcuCfg.NoGroups-1:0] cm_x_req;
  cm_idx_t   [2*CcuCfg.NoGroups-1:0] cm_x_addr;
  logic                       cm_snoop_valid;
  logic                       cm_snoop_ready;
  logic                       cm_snoop_stall;
  cm_idx_t                    cm_snoop_addr;

  ace_ccu_master_path #(
    .CcuCfg               (CcuCfg),
    .slv_ar_chan_t        (slv_ar_chan_t),
    .slv_aw_chan_t        (slv_aw_chan_t),
    .slv_b_chan_t         (slv_b_chan_t),
    .slv_r_chan_t         (slv_r_chan_t),
    .mst_ar_chan_t        (mst_ar_chan_t),
    .mst_aw_chan_t        (mst_aw_chan_t),
    .mst_b_chan_t         (mst_b_chan_t),
    .w_chan_t             (w_chan_t    ),
    .mst_r_chan_t         (mst_r_chan_t),
    .slv_req_t            (slv_req_t   ),
    .slv_resp_t           (slv_resp_t  ),
    .mst_req_t            (mst_req_t   ),
    .mst_resp_t           (mst_resp_t  ),
    .snoop_ac_t           (snoop_ac_t  ),
    .snoop_cr_t           (snoop_cr_t  ),
    .snoop_cd_t           (snoop_cd_t  ),
    .snoop_req_t          (snoop_req_t ),
    .snoop_resp_t         (snoop_resp_t),
    .domain_set_t         (domain_set_t),
    .domain_mask_t        (domain_mask_t)
  ) i_master_path (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .slv_req_i            (slv_req_i),
    .slv_resp_o           (slv_resp_o),
    .snoop_req_o          (snoop_reqs),
    .snoop_resp_i         (snoop_resps),
    .mst_req_o            (mst_req_o),
    .mst_resp_i           (mst_resp_i),
    .domain_set_i         (domain_set_i),
    .snoop_masks_o        (snoop_sel),
    .cm_req_o             (cm_x_req),
    .cm_addr_o            (cm_x_addr)
  );

  ace_ccu_snoop_interconnect #(
    .NumInp       (CcuCfg.NoSnoopPorts),
    .NumOup       (CcuCfg.NoSlvPorts),
    .BufferInpReq (0),
    .BufferInpResp(0),
    .BufferOupReq (CcuCfg.CutSnoopReq),
    .BufferOupResp(CcuCfg.CutSnoopResp),
    .CmAddrBase   (CcuCfg.CmAddrBase),
    .CmAddrWidth  (CcuCfg.CmAddrWidth),
    .ac_chan_t    (snoop_ac_t),
    .cr_chan_t    (snoop_cr_t),
    .cd_chan_t    (snoop_cd_t),
    .snoop_req_t  (snoop_req_t),
    .snoop_resp_t (snoop_resp_t)
  ) i_snoop_interconnect (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .inp_sel_i         (snoop_sel),
    .inp_req_i         (snoop_reqs),
    .inp_resp_o        (snoop_resps),
    .oup_req_o         (snoop_req_o),
    .oup_resp_i        (snoop_resp_i),
    .cm_valid_o        (cm_snoop_valid),
    .cm_ready_o        (cm_snoop_ready),
    .cm_addr_o         (cm_snoop_addr),
    .cm_stall_i        (cm_snoop_stall)
  );

  ace_ccu_conflict_manager #(
    .AxiAddrWidth  (CcuCfg.AxiAddrWidth),
    .NoRespPorts   (2*CcuCfg.NoGroups),
    .MaxRespTrans  (8),
    .MaxSnoopTrans (8),
    .CmAddrWidth   (CcuCfg.CmAddrWidth)
  ) i_conflict_manager (
    .clk_i,
    .rst_ni,
    .cm_snoop_valid_i (cm_snoop_valid),
    .cm_snoop_ready_i (cm_snoop_ready),
    .cm_snoop_addr_i  (cm_snoop_addr),
    .cm_snoop_stall_o (cm_snoop_stall),
    .cm_x_req_i       (cm_x_req),
    .cm_x_addr_i      (cm_x_addr)
  );

endmodule

module ace_ccu_top_intf import ccu_pkg::*; #(
  parameter ccu_cfg_t CCU_CFG       = '{default: '0},
  localparam type     domain_mask_t = `DOMAIN_MASK_T(CCU_CFG.NoSlvPorts),
  localparam type     domain_set_t  = `DOMAIN_SET_T
) (
  input logic                                 clk_i,
  input logic                                 rst_ni,
  input domain_set_t [CCU_CFG.NoSlvPorts-1:0] domain_set_i,
  ACE_BUS.Slave                               slv_ports   [CCU_CFG.NoSlvPorts-1:0],
  SNOOP_BUS.Slave                             snoop_ports [CCU_CFG.NoSlvPorts-1:0],
  AXI_BUS.Master                              mst_port
);

  typedef logic [CCU_CFG.AxiSlvIdWidth-1:0]  id_slv_t;
  typedef logic [CCU_CFG.AxiMstIdWidth-1:0]  id_mst_t;
  typedef logic [CCU_CFG.AxiAddrWidth-1:0]   addr_t;
  typedef logic [CCU_CFG.AxiDataWidth-1:0]   data_t;
  typedef logic [CCU_CFG.AxiDataWidth/8-1:0] strb_t;
  typedef logic [CCU_CFG.AxiUserWidth-1:0]   user_t;

  `AXI_TYPEDEF_W_CHAN_T (w_chan_t, data_t, strb_t, user_t)

  `ACE_TYPEDEF_AW_CHAN_T(slv_aw_chan_t, addr_t, id_slv_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T (slv_b_chan_t, id_slv_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(slv_ar_chan_t, addr_t, id_slv_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T (slv_r_chan_t, data_t, id_slv_t, user_t)
  `ACE_TYPEDEF_REQ_T    (slv_req_t, slv_aw_chan_t, w_chan_t, slv_ar_chan_t)
  `ACE_TYPEDEF_RESP_T   (slv_resp_t, slv_b_chan_t, slv_r_chan_t)

  `AXI_TYPEDEF_AW_CHAN_T(mst_aw_chan_t, addr_t, id_mst_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T (mst_b_chan_t, id_mst_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(mst_ar_chan_t, addr_t, id_mst_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T (mst_r_chan_t, data_t, id_mst_t, user_t)
  `AXI_TYPEDEF_REQ_T    (mst_req_t, mst_aw_chan_t, w_chan_t, mst_ar_chan_t)
  `AXI_TYPEDEF_RESP_T   (mst_resp_t, mst_b_chan_t, mst_r_chan_t)

  `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
  `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
  `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
  `SNOOP_TYPEDEF_REQ_T    (snoop_req_t, snoop_ac_t)
  `SNOOP_TYPEDEF_RESP_T   (snoop_resp_t, snoop_cd_t, snoop_cr_t)

  slv_req_t  [CCU_CFG.NoSlvPorts-1:0] slv_reqs;
  slv_resp_t [CCU_CFG.NoSlvPorts-1:0] slv_resps;

  mst_req_t  mst_req;
  mst_resp_t mst_resp;

  snoop_req_t  [CCU_CFG.NoSlvPorts-1:0] snoop_reqs;
  snoop_resp_t [CCU_CFG.NoSlvPorts-1:0] snoop_resps;

  for (genvar i = 0; i < CCU_CFG.NoSlvPorts; i++) begin
    `ACE_ASSIGN_TO_REQ(slv_reqs[i], slv_ports[i])
    `ACE_ASSIGN_FROM_RESP(slv_ports[i], slv_resps[i])
    `SNOOP_ASSIGN_FROM_REQ(snoop_ports[i], snoop_reqs[i])
    `SNOOP_ASSIGN_TO_RESP(snoop_resps[i], snoop_ports[i])
  end

  `AXI_ASSIGN_FROM_REQ(mst_port, mst_req)
  `AXI_ASSIGN_TO_RESP(mst_resp, mst_port)

  ace_ccu_top #(
    .CcuCfg          (CCU_CFG      ),
    .slv_ar_chan_t   (slv_ar_chan_t),
    .slv_aw_chan_t   (slv_aw_chan_t),
    .slv_b_chan_t    (slv_b_chan_t ),
    .w_chan_t        (w_chan_t     ),
    .slv_r_chan_t    (slv_r_chan_t ),
    .mst_ar_chan_t   (mst_ar_chan_t),
    .mst_aw_chan_t   (mst_aw_chan_t),
    .mst_b_chan_t    (mst_b_chan_t ),
    .mst_r_chan_t    (mst_r_chan_t ),
    .slv_req_t       (slv_req_t    ),
    .slv_resp_t      (slv_resp_t   ),
    .mst_req_t       (mst_req_t    ),
    .mst_resp_t      (mst_resp_t   ),
    .snoop_ac_t      (snoop_ac_t   ),
    .snoop_cr_t      (snoop_cr_t   ),
    .snoop_cd_t      (snoop_cd_t   ),
    .snoop_req_t     (snoop_req_t  ),
    .snoop_resp_t    (snoop_resp_t )
  ) i_ace_ccu_top (
    .clk_i,
    .rst_ni,
    .domain_set_i,
    .slv_req_i    (slv_reqs),
    .slv_resp_o   (slv_resps),
    .snoop_req_o  (snoop_reqs),
    .snoop_resp_i (snoop_resps),
    .mst_req_o    (mst_req),
    .mst_resp_i   (mst_resp)
);

endmodule
