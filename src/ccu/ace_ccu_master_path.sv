`include "ace/typedef.svh"
`include "ace/assign.svh"
`include "ace/convert.svh"

module ace_ccu_master_path import ace_pkg::*;
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
  parameter type domain_set_t            = logic,
  // Local parameters
  localparam NoGroups                    = NoSlvPorts / NoSlvPerGroup,
  localparam NoSnoopPortsPerGroup        = 2,
  localparam NoSnoopPorts                = NoSnoopPortsPerGroup * NoGroups
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  input  domain_set_t [NoSlvPorts-1:0]   domain_set_i,
  input  slv_req_t    [NoSlvPorts-1:0]   slv_req_i,
  output slv_resp_t   [NoSlvPorts-1:0]   slv_resp_o,
  output snoop_req_t  [NoSnoopPorts-1:0] snoop_req_o,
  output axdomain_t   [NoSnoopPorts-1:0] snoop_masks_o,
  input  snoop_resp_t [NoSnoopPorts-1:0] snoop_resp_i,
  output mst_req_t                       mst_req_o,
  input  mst_resp_t                      mst_resp_i
);

  typedef logic [AxiAddrWidth -1:0]  addr_t;
  typedef logic [AxiDataWidth-1:0]   data_t;
  typedef logic [AxiDataWidth/8-1:0] strb_t;
  typedef logic [AxiUserWidth-1:0]   user_t;

  slv_req_t  [NoSlvPorts-1:0] ace_snooping_req,  ace_nonsnooping_req;
  slv_resp_t [NoSlvPorts-1:0] ace_snooping_resp, ace_nonsnooping_resp;

  localparam AxiIntIdWidth = AxiSlvIdWidth + $clog2(NoSlvPerGroup);
  typedef logic [AxiIntIdWidth-1:0] int_id_t;

  `ACE_TYPEDEF_AW_CHAN_T(int_ace_aw_chan_t, addr_t, int_id_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T (int_ace_b_chan_t, int_id_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(int_ace_ar_chan_t, addr_t, int_id_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T (int_ace_r_chan_t, data_t, int_id_t, user_t)
  `ACE_TYPEDEF_REQ_T    (int_ace_req_t, int_ace_aw_chan_t, w_chan_t, int_ace_ar_chan_t)
  `ACE_TYPEDEF_RESP_T   (int_ace_resp_t, int_ace_b_chan_t, int_ace_r_chan_t)

  `AXI_TYPEDEF_AW_CHAN_T(int_axi_aw_chan_t, addr_t, int_id_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T (int_axi_b_chan_t, int_id_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(int_axi_ar_chan_t, addr_t, int_id_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T (int_axi_r_chan_t, data_t, int_id_t, user_t)
  `AXI_TYPEDEF_REQ_T    (int_axi_req_t, int_axi_aw_chan_t, w_chan_t, int_axi_ar_chan_t)
  `AXI_TYPEDEF_RESP_T   (int_axi_resp_t, int_axi_b_chan_t, int_axi_r_chan_t)

  // Three ports per group: non snooping, write snooping, read snooping
  localparam NoMemPortsPerGroup = 3;
  localparam NoMemPorts         = NoMemPortsPerGroup*NoGroups;
  int_axi_req_t  [NoMemPorts-1:0] axi_memory_reqs;
  int_axi_resp_t [NoMemPorts-1:0] axi_memory_resps;

  ///////////
  // DEMUX //
  ///////////

  for (genvar i = 0; i < NoSlvPorts; i++) begin : gen_demux

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
        .ar_chan_t (slv_ar_chan_t)
    ) i_read_decoder (
        .ar_i          (slv_req_i[i].ar),
        .snooping_o    (slv_ar_snooping),
        .snoop_info_o  (),
        .illegal_trs_o ()
    );

    axi_demux #(
      .AxiIdWidth  (AxiSlvIdWidth),
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
      .SpillAw     (1'b1),
      .SpillW      (1'b0),
      .SpillB      (1'b0),
      .SpillAr     (1'b1),
      .SpillR      (1'b0)
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

  for (genvar i = 0; i < NoGroups; i++) begin : gen_snoop

    int_ace_req_t  ace_snooping_muxed_req;
    int_ace_resp_t ace_snooping_muxed_resp;

    int_ace_req_t  [1:0] ace_memory_reqs;
    int_ace_resp_t [1:0] ace_memory_resps;

    /////////
    // MUX //
    /////////

    axi_mux #(
        .SlvAxiIDWidth (AxiSlvIdWidth),
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
        .NoSlvPorts    (NoSlvPerGroup),
        .MaxWTrans     (32'd8),
        .FallThrough   (1'b0),
        .SpillAw       (1'b1),
        .SpillW        (1'b0),
        .SpillB        (1'b0),
        .SpillAr       (1'b1),
        .SpillR        (1'b0)
    ) i_snoop_mux (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .test_i      (1'b0),
        .slv_reqs_i  (ace_snooping_req [(NoSlvPerGroup*i)+:NoSlvPerGroup]),
        .slv_resps_o (ace_snooping_resp[(NoSlvPerGroup*i)+:NoSlvPerGroup]),
        .mst_req_o   (ace_snooping_muxed_req),
        .mst_resp_i  (ace_snooping_muxed_resp)
    );

    ////////////////
    // SNOOP PATH //
    ////////////////

    ace_ccu_snoop_path #(
      .NoRules         (NoSlvPorts),
      .DcacheLineWidth (DcacheLineWidth),
      .AxiDataWidth    (AxiDataWidth),
      .AxiSlvIdWidth   (AxiSlvIdWidth),
      .aw_chan_t       (int_ace_aw_chan_t),
      .w_chan_t        (w_chan_t),
      .b_chan_t        (int_ace_b_chan_t),
      .ar_chan_t       (int_ace_ar_chan_t),
      .r_chan_t        (int_ace_r_chan_t),
      .req_t           (int_ace_req_t),
      .resp_t          (int_ace_resp_t),
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
      .slv_req_i      (ace_snooping_muxed_req),
      .slv_resp_o     (ace_snooping_muxed_resp),
      .mst_reqs_o     (ace_memory_reqs),
      .mst_resps_i    (ace_memory_resps),
      .domain_set_i   (domain_set_i),
      .snoop_reqs_o   (snoop_req_o    [(2*i)+:2]),
      .snoop_resps_i  (snoop_resp_i   [(2*i)+:2]),
      .snoop_masks_o  (snoop_masks_o  [(2*i)+:2])
    );

    for (genvar j = 1; j < NoMemPortsPerGroup; j++) begin : gen_ace_to_axi
      `ACE_TO_AXI_ASSIGN_REQ(axi_memory_reqs[NoMemPortsPerGroup*i+j], ace_memory_reqs[j])
      `AXI_TO_ACE_ASSIGN_RESP(ace_memory_resps[j], axi_memory_resps[NoMemPortsPerGroup*i+j])
    end
  end

  //////////////////
  // NOSNOOP PATH //
  //////////////////

  for (genvar i = 0; i < NoGroups; i++) begin : gen_nosnoop

    int_ace_req_t  ace_nonsnooping_muxed_req;
    int_ace_resp_t ace_nonsnooping_muxed_resp;

    axi_mux #(
      .SlvAxiIDWidth (AxiSlvIdWidth),
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
      .NoSlvPorts    (NoSlvPerGroup),
      .MaxWTrans     (32'd8),
      .FallThrough   (1'b0),
      .SpillAw       (1'b1),
      .SpillW        (1'b0),
      .SpillB        (1'b0),
      .SpillAr       (1'b1),
      .SpillR        (1'b0)
    ) i_nosnoop_mux (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),
      .test_i      (1'b0),
      .slv_reqs_i  (ace_nonsnooping_req [i+:NoSlvPerGroup]),
      .slv_resps_o (ace_nonsnooping_resp[i+:NoSlvPerGroup]),
      .mst_req_o   (ace_nonsnooping_muxed_req),
      .mst_resp_i  (ace_nonsnooping_muxed_resp)
    );

    // TODO: cleanup code once it is clear this module is not needed
    // axi_id_prepend #(
    //   .NoBus             (1),
    //   .AxiIdWidthSlvPort (AxiSlvIdWidth),
    //   .AxiIdWidthMstPort (AxiIntIdWidth),
    //   .slv_aw_chan_t     (slv_aw_chan_t),
    //   .slv_w_chan_t      (slv_w_chan_t ),
    //   .slv_b_chan_t      (slv_b_chan_t ),
    //   .slv_ar_chan_t     (slv_ar_chan_t),
    //   .slv_r_chan_t      (slv_r_chan_t ),
    //   .mst_aw_chan_t     (int_aw_chan_t),
    //   .mst_w_chan_t      (int_w_chan_t ),
    //   .mst_b_chan_t      (int_b_chan_t ),
    //   .mst_ar_chan_t     (int_ar_chan_t),
    //   .mst_r_chan_t      (int_r_chan_t )
    // ) i_nosnoop_id_prepend (
    //   .pre_id_i         ('0),
    //   .slv_aw_chans_i   (ace_nonsnooping_req[i].aw),
    //   .slv_aw_valids_i  (ace_nonsnooping_req[i].aw_valid),
    //   .slv_aw_readies_o (ace_nonsnooping_resp[i].aw_ready),
    //   .slv_w_chans_i    (ace_nonsnooping_req[i].w),
    //   .slv_w_valids_i   (ace_nonsnooping_req[i].w_valid),
    //   .slv_w_readies_o  (ace_nonsnooping_resp[i].w_ready),
    //   .slv_b_chans_o    (ace_nonsnooping_resp[i].b),
    //   .slv_b_valids_o   (ace_nonsnooping_resp[i].b_valid),
    //   .slv_b_readies_i  (ace_nonsnooping_req[i].b_ready),
    //   .slv_ar_chans_i   (ace_nonsnooping_req[i].ar),
    //   .slv_ar_valids_i  (ace_nonsnooping_req[i].ar_valid),
    //   .slv_ar_readies_o (ace_nonsnooping_resp[i].ar_ready),
    //   .slv_r_chans_o    (ace_nonsnooping_resp[i].r),
    //   .slv_r_valids_o   (ace_nonsnooping_resp[i].r_valid),
    //   .slv_r_readies_i  (ace_nonsnooping_req[i].r_ready),
    //   .mst_aw_chans_o   (ace_nonsnooping_prepended_req.aw),
    //   .mst_aw_valids_o  (ace_nonsnooping_prepended_req.aw_valid),
    //   .mst_aw_readies_i (ace_nonsnooping_prepended_resp.aw_ready),
    //   .mst_w_chans_o    (ace_nonsnooping_prepended_req.w),
    //   .mst_w_valids_o   (ace_nonsnooping_prepended_req.w_valid),
    //   .mst_w_readies_i  (ace_nonsnooping_prepended_resp.w_ready),
    //   .mst_b_chans_i    (ace_nonsnooping_prepended_resp.b),
    //   .mst_b_valids_i   (ace_nonsnooping_prepended_resp.b_valid),
    //   .mst_b_readies_o  (ace_nonsnooping_prepended_req.b_ready),
    //   .mst_ar_chans_o   (ace_nonsnooping_prepended_req.ar),
    //   .mst_ar_valids_o  (ace_nonsnooping_prepended_req.ar_valid),
    //   .mst_ar_readies_i (ace_nonsnooping_prepended_resp.ar_ready),
    //   .mst_r_chans_i    (ace_nonsnooping_prepended_resp.r),
    //   .mst_r_valids_i   (ace_nonsnooping_prepended_resp.r_valid),
    //   .mst_r_readies_o  (ace_nonsnooping_prepended_req.r_ready)
    // );

    `ACE_TO_AXI_ASSIGN_REQ (axi_memory_reqs[NoMemPortsPerGroup*i], ace_nonsnooping_muxed_req)
    `AXI_TO_ACE_ASSIGN_RESP(ace_nonsnooping_muxed_resp, axi_memory_resps[NoMemPortsPerGroup*i])
  end

  ///////////////
  // FINAL MUX //
  ///////////////

  axi_mux #(
    .SlvAxiIDWidth (AxiIntIdWidth),
    .slv_aw_chan_t (int_axi_aw_chan_t),
    .mst_aw_chan_t (mst_aw_chan_t),
    .w_chan_t      (w_chan_t),
    .slv_b_chan_t  (int_axi_b_chan_t),
    .mst_b_chan_t  (mst_b_chan_t),
    .slv_ar_chan_t (int_axi_ar_chan_t),
    .mst_ar_chan_t (mst_ar_chan_t),
    .slv_r_chan_t  (int_axi_r_chan_t),
    .mst_r_chan_t  (mst_r_chan_t),
    .slv_req_t     (int_axi_req_t),
    .slv_resp_t    (int_axi_resp_t),
    .mst_req_t     (mst_req_t),
    .mst_resp_t    (mst_resp_t),
    .NoSlvPorts    (NoMemPorts),
    .MaxWTrans     (32'd8),
    .FallThrough   (1'b0),
    .SpillAw       (1'b1),
    .SpillW        (1'b0),
    .SpillB        (1'b0),
    .SpillAr       (1'b1),
    .SpillR        (1'b0)
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
