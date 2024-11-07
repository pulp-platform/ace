`include "ace/assign.svh"
`include "ace/typedef.svh"
`include "ace/domain.svh"

module ace_ccu_top import ace_pkg::*;
#(
  parameter int unsigned AxiAddrWidth    = 0,
  parameter int unsigned AxiDataWidth    = 0,
  parameter int unsigned AxiUserWidth    = 0,
  parameter int unsigned AxiSlvIdWidth   = 0,
  parameter int unsigned NoSlvPorts      = 0,
  parameter int unsigned NoSlvPerGroup   = 0,
  parameter int unsigned DcacheLineWidth = 0,
  parameter int unsigned LupAddrBase     = 0,
  parameter int unsigned LupAddrWidth    = AxiAddrWidth,
  parameter type slv_ar_chan_t           = logic,
  parameter type slv_aw_chan_t           = logic,
  parameter type slv_b_chan_t            = logic,
  parameter type w_chan_t                = logic,
  parameter type slv_r_chan_t            = logic,
  parameter type mst_ar_chan_t           = logic,
  parameter type mst_aw_chan_t           = logic,
  parameter type mst_b_chan_t            = logic,
  parameter type mst_r_chan_t            = logic,
  parameter type slv_req_t               = logic,
  parameter type slv_resp_t              = logic,
  parameter type mst_req_t               = logic,
  parameter type mst_resp_t              = logic,
  parameter type snoop_ac_t              = logic,
  parameter type snoop_cr_t              = logic,
  parameter type snoop_cd_t              = logic,
  parameter type snoop_req_t             = logic,
  parameter type snoop_resp_t            = logic,
  parameter type domain_mask_t           = `DOMAIN_MASK_T(NoSlvPorts),
  parameter type domain_set_t            = `DOMAIN_SET_T
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  domain_set_t [NoSlvPorts-1:0] domain_set_i,
  input  slv_req_t    [NoSlvPorts-1:0] slv_req_i,
  output slv_resp_t   [NoSlvPorts-1:0] slv_resp_o,
  output snoop_req_t  [NoSlvPorts-1:0] snoop_req_o,
  input  snoop_resp_t [NoSlvPorts-1:0] snoop_resp_i,
  output mst_req_t                     mst_req_o,
  input  mst_resp_t                    mst_resp_i
);

  typedef logic [LupAddrWidth-1:0] lup_addr_t;

  // Parameters to be used for testing/debugging
  // Otherwise assume they are hardcoded
  localparam ConfCheck = 1;

  // Local parameters
  localparam NoGroups             = NoSlvPorts / NoSlvPerGroup;
  localparam NoSnoopPortsPerGroup = 2;
  localparam NoSnoopPorts         = NoSnoopPortsPerGroup * NoGroups;

  // To snoop interconnect
  domain_mask_t [NoSnoopPorts-1:0] snoop_sel;
  snoop_req_t   [NoSnoopPorts-1:0] snoop_reqs;
  snoop_resp_t  [NoSnoopPorts-1:0] snoop_resps;

  // Conflict management signals
  logic      [2*NoGroups-1:0] x_valids_in;
  logic      [2*NoGroups-1:0] x_readies_out;
  logic      [2*NoGroups-1:0] x_valids_out;
  logic      [2*NoGroups-1:0] x_readies_in;
  logic      [2*NoGroups-1:0] x_acks_out;
  lup_addr_t [2*NoGroups-1:0] x_addr_out;
  logic      [2*NoGroups-1:0] x_lasts_out;
  logic                       snoop_valid_out;
  logic                       snoop_ready_in;
  logic                       snoop_clr_out;
  logic                       snoop_valid_in;
  logic                       snoop_ready_out;
  lup_addr_t                  snoop_addr_out;

  ace_ccu_master_path #(
    .AxiAddrWidth      (AxiAddrWidth),
    .AxiDataWidth      (AxiDataWidth),
    .AxiUserWidth      (AxiUserWidth),
    .AxiSlvIdWidth     (AxiSlvIdWidth),
    .NoSlvPorts        (NoSlvPorts),
    .NoSlvPerGroup     (NoSlvPerGroup),
    .DcacheLineWidth   (DcacheLineWidth),
    .LupAddrBase       (LupAddrBase),
    .LupAddrWidth      (LupAddrWidth),
    .ConfCheck         (ConfCheck),
    .slv_ar_chan_t     (slv_ar_chan_t),
    .slv_aw_chan_t     (slv_aw_chan_t),
    .slv_b_chan_t      (slv_b_chan_t),
    .slv_r_chan_t      (slv_r_chan_t),
    .mst_ar_chan_t     (mst_ar_chan_t),
    .mst_aw_chan_t     (mst_aw_chan_t),
    .mst_b_chan_t      (mst_b_chan_t),
    .w_chan_t          (w_chan_t    ),
    .mst_r_chan_t      (mst_r_chan_t),
    .slv_req_t         (slv_req_t   ),
    .slv_resp_t        (slv_resp_t  ),
    .mst_req_t         (mst_req_t   ),
    .mst_resp_t        (mst_resp_t  ),
    .snoop_ac_t        (snoop_ac_t  ),
    .snoop_cr_t        (snoop_cr_t  ),
    .snoop_cd_t        (snoop_cd_t  ),
    .snoop_req_t       (snoop_req_t ),
    .snoop_resp_t      (snoop_resp_t),
    .domain_set_t      (domain_set_t),
    .domain_mask_t     (domain_mask_t)
  ) i_master_path (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .slv_req_i         (slv_req_i),
    .slv_resp_o        (slv_resp_o),
    .snoop_req_o       (snoop_reqs),
    .snoop_resp_i      (snoop_resps),
    .mst_req_o         (mst_req_o),
    .mst_resp_i        (mst_resp_i),
    .domain_set_i      (domain_set_i),
    .snoop_masks_o     (snoop_sel),
    .x_valids_i        (x_valids_in),
    .x_readies_o       (x_readies_out),
    .x_valids_o        (x_valids_out),
    .x_readies_i       (x_readies_in),
    .x_acks_o          (x_acks_out),
    .x_addr_o          (x_addr_out),
    .x_lasts_o         (x_lasts_out)
  );

  ace_ccu_snoop_interconnect #(
    .NumInp       (NoSnoopPorts),
    .NumOup       (NoSlvPorts),
    .BufferInpReq (1),
    .BufferInpResp(1),
    .BufferOupReq (1),
    .BufferOupResp(1),
    .ConfCheck    (ConfCheck),
    .LupAddrBase  (LupAddrBase),
    .LupAddrWidth (LupAddrWidth),
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
    .lup_valid_o       (snoop_valid_out),
    .lup_ready_i       (snoop_ready_in),
    .lup_addr_o        (snoop_addr_out),
    .lup_valid_i       (snoop_valid_in),
    .lup_ready_o       (snoop_ready_out),
    .lup_clr_o         (snoop_clr_out)
  );

  if (ConfCheck) begin : gen_conf_mng

    ace_ccu_conflict_manager #(
      .AxiAddrWidth  (AxiAddrWidth),
      .NoRespPorts   (2*NoGroups),
      .MaxRespTrans  (8),
      .MaxSnoopTrans (8),
      .LupAddrBase   (LupAddrBase),
      .LupAddrWidth  (LupAddrWidth)
    ) i_conflict_manager (
      .clk_i,
      .rst_ni,
      .x_valid_i     (x_valids_out),
      .x_ready_o     (x_readies_in),
      .x_addr_i      (x_addr_out),
      .x_valid_o     (x_valids_in),
      .x_ready_i     (x_readies_out),
      .x_ack_i       (x_acks_out),
      .x_lasts_i     (x_lasts_out),
      .snoop_valid_i (snoop_valid_out),
      .snoop_ready_o (snoop_ready_in),
      .snoop_clr_i   (snoop_clr_out),
      .snoop_addr_i  (snoop_addr_out),
      .snoop_valid_o (snoop_valid_in),
      .snoop_ready_i (snoop_ready_out)
    );

  end

endmodule

module ace_ccu_top_intf #(
  parameter int unsigned AXI_ADDR_WIDTH    = 0,
  parameter int unsigned AXI_DATA_WIDTH    = 0,
  parameter int unsigned AXI_USER_WIDTH    = 0,
  parameter int unsigned AXI_SLV_ID_WIDTH  = 0,
  parameter int unsigned NO_SLV_PORTS      = 0,
  parameter int unsigned NO_SLV_PER_GROUPS = 0,
  parameter int unsigned DCACHE_LINE_WIDTH = 0,
  parameter type         domain_mask_t     = `DOMAIN_MASK_T(NO_SLV_PORTS),
  parameter type         domain_set_t      = `DOMAIN_SET_T
) (
  input logic                           clk_i,
  input logic                           rst_ni,
  input domain_set_t [NO_SLV_PORTS-1:0] domain_set_i,
  ACE_BUS.Slave                         slv_ports   [NO_SLV_PORTS-1:0],
  SNOOP_BUS.Master                      snoop_ports [NO_SLV_PORTS-1:0],
  AXI_BUS.Master                        mst_port
);

  localparam NO_GROUPS = NO_SLV_PORTS/NO_SLV_PER_GROUPS;
  localparam AXI_ID_MST_WIDTH = AXI_SLV_ID_WIDTH          + // Initial ID width
                                $clog2(NO_SLV_PER_GROUPS) + // Internal MUX additional bits
                                $clog2(3*NO_GROUPS);        // Final MUX additional bits

  typedef logic [AXI_SLV_ID_WIDTH-1:0] id_slv_t;
  typedef logic [AXI_ID_MST_WIDTH-1:0] id_mst_t;
  typedef logic [AXI_ADDR_WIDTH-1:0]   addr_t;
  typedef logic [AXI_DATA_WIDTH-1:0]   data_t;
  typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
  typedef logic [AXI_USER_WIDTH-1:0]   user_t;

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

  slv_req_t  [NO_SLV_PORTS-1:0] slv_reqs;
  slv_resp_t [NO_SLV_PORTS-1:0] slv_resps;

  mst_req_t  mst_req;
  mst_resp_t mst_resp;

  snoop_req_t  [NO_SLV_PORTS-1:0] snoop_reqs;
  snoop_resp_t [NO_SLV_PORTS-1:0] snoop_resps;

  for (genvar i = 0; i < NO_SLV_PORTS; i++) begin
    `ACE_ASSIGN_TO_REQ(slv_reqs[i], slv_ports[i])
    `ACE_ASSIGN_FROM_RESP(slv_ports[i], slv_resps[i])
    `SNOOP_ASSIGN_FROM_REQ(snoop_ports[i], snoop_reqs[i])
    `SNOOP_ASSIGN_TO_RESP(snoop_resps[i], snoop_ports[i])
  end

  `AXI_ASSIGN_FROM_REQ(mst_port, mst_req)
  `AXI_ASSIGN_TO_RESP(mst_resp, mst_port)

  ace_ccu_top #(
    .AxiAddrWidth    (AXI_ADDR_WIDTH   ),
    .AxiDataWidth    (AXI_DATA_WIDTH   ),
    .AxiUserWidth    (AXI_USER_WIDTH   ),
    .AxiSlvIdWidth   (AXI_SLV_ID_WIDTH ),
    .NoSlvPorts      (NO_SLV_PORTS     ),
    .NoSlvPerGroup   (NO_SLV_PER_GROUPS),
    .DcacheLineWidth (DCACHE_LINE_WIDTH),
    .slv_ar_chan_t   (slv_ar_chan_t    ),
    .slv_aw_chan_t   (slv_aw_chan_t    ),
    .slv_b_chan_t    (slv_b_chan_t     ),
    .w_chan_t        (w_chan_t         ),
    .slv_r_chan_t    (slv_r_chan_t     ),
    .mst_ar_chan_t   (mst_ar_chan_t    ),
    .mst_aw_chan_t   (mst_aw_chan_t    ),
    .mst_b_chan_t    (mst_b_chan_t     ),
    .mst_r_chan_t    (mst_r_chan_t     ),
    .slv_req_t       (slv_req_t        ),
    .slv_resp_t      (slv_resp_t       ),
    .mst_req_t       (mst_req_t        ),
    .mst_resp_t      (mst_resp_t       ),
    .snoop_ac_t      (snoop_ac_t       ),
    .snoop_cr_t      (snoop_cr_t       ),
    .snoop_cd_t      (snoop_cd_t       ),
    .snoop_req_t     (snoop_req_t      ),
    .snoop_resp_t    (snoop_resp_t     ),
    .domain_mask_t   (domain_mask_t    ),
    .domain_set_t    (domain_set_t     )
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
