`include "ace/assign.svh"
`include "ace/typedef.svh"

module ace_ccu_top import ace_pkg::*;
#(
  parameter int unsigned AxiAddrWidth    = 0,
  parameter int unsigned AxiDataWidth    = 0,
  parameter int unsigned AxiUserWidth    = 0,
  parameter int unsigned AxiSlvIdWidth   = 0,
  parameter int unsigned NoSlvPorts      = 0,
  parameter int unsigned NoSlvPerGroup   = 0,
  parameter int unsigned DcacheLineWidth = 0,
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
  parameter type domain_mask_t           = logic,
  parameter type domain_set_t            = logic
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  domain_set_t [NoSlvPorts-1:0] domain_set_i,
  input  slv_req_t    [NoSlvPorts-1:0] slv_req_i,
  output slv_resp_t   [NoSlvPorts-1:0] slv_resp_o,
  output snoop_req_t  [NoSlvPorts-1:0] snoop_req_o,
  input  snoop_resp_t [NoSlvPorts-1:0] snoop_resp_i,
  output mst_req_t                     mst_req_o,
  input  slv_resp_t                    mst_resp_i
);

  // Local parameters
  localparam NoGroups             = NoSlvPorts / NoSlvPerGroup;
  localparam NoSnoopPortsPerGroup = 2;
  localparam NoSnoopPorts         = NoSnoopPortsPerGroup * NoGroups;

  // To snoop interconnect
  domain_mask_t [NoSnoopPorts-1:0] snoop_sel;
  snoop_req_t   [NoSnoopPorts-1:0] snoop_reqs;
  snoop_resp_t  [NoSnoopPorts-1:0] snoop_resps;

  ace_ccu_master_path #(
    .AxiAddrWidth      (AxiAddrWidth),
    .AxiDataWidth      (AxiDataWidth),
    .AxiUserWidth      (AxiUserWidth),
    .AxiSlvIdWidth     (AxiSlvIdWidth),
    .NoSlvPorts        (NoSlvPorts),
    .NoSlvPerGroup     (NoSlvPerGroup),
    .DcacheLineWidth   (DcacheLineWidth),
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
    .snoop_resp_t      (snoop_resp_t)
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
    .snoop_masks_o     (snoop_sel)
  );

  ace_ccu_snoop_interconnect #(
    .NumInp       (NoSnoopPorts),
    .NumOup       (NoSlvPorts),
    .BufferReq    (1),
    .BufferResp   (1),
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
    .oup_resp_i        (snoop_resp_i)
  );

endmodule
