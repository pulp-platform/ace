`include "ace/typedef.svh"
`include "ace/assign.svh"

module ace_ccu_snoop_path import ace_pkg::*; import ccu_pkg::*; #(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiAddrWidth    = 0,
    parameter int unsigned AxiDataWidth    = 0,
    parameter int unsigned AxiUserWidth    = 0,
    parameter int unsigned AxiSlvIdWidth   = 0,
    parameter int unsigned AxiMstIdWidth   = 0,
    parameter type slv_aw_chan_t           = logic, // AW Channel Type, slave ports
    parameter type mst_aw_chan_t           = logic, // AW Channel Type, master port
    parameter type w_chan_t                = logic, //  W Channel Type, all ports
    parameter type slv_b_chan_t            = logic, //  B Channel Type, slave ports
    parameter type mst_b_chan_t            = logic, //  B Channel Type, master port
    parameter type slv_ar_chan_t           = logic, // AR Channel Type, slave ports
    parameter type mst_ar_chan_t           = logic, // AR Channel Type, master port
    parameter type slv_r_chan_t            = logic, //  R Channel Type, slave ports
    parameter type mst_r_chan_t            = logic, //  R Channel Type, master port
    parameter type slv_req_t               = logic, // Slave port request type
    parameter type slv_resp_t              = logic, // Slave port response type
    parameter type mst_req_t               = logic, // Master ports request type
    parameter type mst_resp_t              = logic, // Master ports response type
    parameter type snoop_ac_t              = logic, // AC channel, snoop port
    parameter type snoop_cr_t              = logic, // CR channel, snoop port
    parameter type snoop_cd_t              = logic, // CD channel, snoop port
    parameter type snoop_req_t             = logic, // Snoop port request type
    parameter type snoop_resp_t            = logic  // Snoop port response type
) (
    input  logic      clk_i,
    input  logic      rst_ni,

    input  slv_req_t  slv_req_i,
    output slv_resp_t slv_resp_o,

    output mst_req_t  mst_req_o,
    input  mst_resp_t mst_resp_i,

    output snoop_req_t  snoop_write_req_o,
    input  snoop_resp_t snoop_write_resp_i,
    output axdomain_t   snoop_write_domain_o,

    output snoop_req_t  snoop_read_req_o,
    input  snoop_resp_t snoop_read_resp_i,
    output axdomain_t   snoop_read_domain_o
);

    typedef logic [AxiSlvIdWidth-1:0]  slv_id_t;
    typedef logic [AxiMstIdWidth-1:0]  mst_id_t;
    typedef logic [AxiAddrWidth -1:0]  addr_t;
    typedef logic [AxiDataWidth-1:0]   data_t;
    typedef logic [AxiDataWidth/8-1:0] strb_t;
    typedef logic [AxiUserWidth-1:0]   user_t;

    `AXI_TYPEDEF_AW_CHAN_T(int_aw_chan_t, addr_t, slv_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T (int_b_chan_t, slv_id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(int_ar_chan_t, addr_t, slv_id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T (int_r_chan_t, data_t, slv_id_t, user_t)
    `AXI_TYPEDEF_REQ_T    (int_req_t, int_aw_chan_t, w_chan_t, int_ar_chan_t)
    `AXI_TYPEDEF_RESP_T   (int_resp_t, int_b_chan_t, int_r_chan_t)

    slv_req_t  slv_ace_req, slv_nosnoop_req;
    slv_resp_t slv_ace_resp, slv_nosnoop_resp;

    slv_req_t  slv_ace_read_req, slv_ace_write_req;
    slv_resp_t slv_ace_read_resp, slv_ace_write_resp;

    slv_req_t  mst_ace_read_req, mst_ace_write_req;
    slv_resp_t  mst_ace_read_resp, mst_ace_write_resp;

    int_req_t  mst_axi_read_req, mst_axi_write_req;
    int_resp_t mst_axi_read_resp, mst_axi_write_resp;

    ///////////
    // SPLIT //
    ///////////

    axi_rw_split #(
        .axi_req_t  (slv_req_t),
        .axi_resp_t (slv_resp_t)
    ) i_snoop_rw_split (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .slv_req_i        (slv_req_i),
        .slv_resp_o       (slv_resp_o),
        .mst_read_req_o   (slv_ace_read_req),
        .mst_read_resp_i  (slv_ace_read_resp),
        .mst_write_req_o  (slv_ace_write_req),
        .mst_write_resp_i (slv_ace_write_resp)
    );

    ////////////////
    // WRITE PATH //
    ////////////////

    acsnoop_t write_acsnoop;

    ace_aw_transaction_decoder #(
        .aw_chan_t (slv_aw_chan_t)
    ) i_write_decoder (
        .aw_i          (slv_ace_write_req.aw),
        .snooping_o    (),
        .acsnoop_o     (write_acsnoop),
        .illegal_trs_o ()
    );

    ccu_ctrl_wr_snoop #(
        .slv_req_t           (slv_req_t),
        .slv_resp_t          (slv_resp_t),
        .slv_aw_chan_t       (slv_aw_chan_t),
        .mst_req_t           (slv_req_t),
        .mst_resp_t          (slv_resp_t),
        .mst_snoop_req_t     (snoop_req_t),
        .mst_snoop_resp_t    (snoop_resp_t)
    ) i_ccu_ctrl_wr_snoop (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .slv_req_i           (slv_ace_write_req),
        .slv_resp_o          (slv_ace_write_resp),
        .snoop_trs_i         (write_acsnoop),
        .mst_req_o           (mst_ace_write_req),
        .mst_resp_i          (mst_ace_write_resp),
        .snoop_req_o         (snoop_write_req_o),
        .snoop_resp_i        (snoop_write_resp_i),
        .awdomain_o          (snoop_write_domain_o)
    );

    ace_to_axi #(
        .slv_req_t  (slv_req_t),
        .slv_resp_t (slv_resp_t),
        .mst_req_t  (int_req_t),
        .mst_resp_t (int_resp_t)
    ) i_wr_ace_to_axi (
        .ace_req_i  (mst_ace_write_req),
        .ace_resp_o (mst_ace_write_resp),
        .axi_req_o  (mst_axi_write_req),
        .axi_resp_i (mst_axi_write_resp)
    );

    ///////////////
    // READ PATH //
    ///////////////

    localparam WB_AXLEN  = DcacheLineWidth/AxiDataWidth-1;
    localparam WB_AXSIZE = $clog2(AxiDataWidth/8);

    snoop_info_t snoop_read_info;

    ace_ar_transaction_decoder #(
        .ar_chan_t (slv_ar_chan_t)
    ) i_read_decoder (
        .ar_i          (slv_ace_read_req.ar),
        .snooping_o    (),
        .snoop_info_o  (snoop_read_info),
        .illegal_trs_o ()
    );

    ccu_ctrl_r_snoop #(
        .slv_req_t           (slv_req_t),
        .slv_resp_t          (slv_resp_t),
        .slv_ar_chan_t       (slv_ar_chan_t),
        .mst_req_t           (int_req_t),
        .mst_resp_t          (int_resp_t),
        .mst_snoop_req_t     (snoop_req_t),
        .mst_snoop_resp_t    (snoop_resp_t),
        .AXLEN               (WB_AXLEN),
        .AXSIZE              (WB_AXSIZE)
    ) i_ccu_ctrl_r_snoop (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .slv_req_i           (slv_ace_read_req),
        .slv_resp_o          (slv_ace_read_resp),
        .snoop_info_i        (snoop_read_info),
        .mst_req_o           (mst_ace_read_req),
        .mst_resp_i          (mst_ace_read_resp),
        .snoop_req_o         (snoop_read_req_o),
        .snoop_resp_i        (snoop_read_resp_i),
        .ardomain_o          (snoop_read_domain_o)
    );

    ace_to_axi #(
        .slv_req_t  (slv_req_t),
        .slv_resp_t (slv_resp_t),
        .mst_req_t  (int_req_t),
        .mst_resp_t (int_resp_t)
    ) i_rd_ace_to_axi (
        .ace_req_i  (mst_ace_read_req),
        .ace_resp_o (mst_ace_read_resp),
        .axi_req_o  (mst_axi_read_req),
        .axi_resp_i (mst_axi_read_resp)
    );

    /////////
    // MUX //
    /////////

    axi_mux #(
        .SlvAxiIDWidth (AxiSlvIdWidth),
        .slv_aw_chan_t (int_aw_chan_t),
        .mst_aw_chan_t (mst_aw_chan_t),
        .w_chan_t      (w_chan_t),
        .slv_b_chan_t  (int_b_chan_t),
        .mst_b_chan_t  (mst_b_chan_t),
        .slv_ar_chan_t (int_ar_chan_t),
        .mst_ar_chan_t (mst_ar_chan_t),
        .slv_r_chan_t  (int_r_chan_t),
        .mst_r_chan_t  (mst_r_chan_t),
        .slv_req_t     (int_req_t),
        .slv_resp_t    (int_resp_t),
        .mst_req_t     (mst_req_t),
        .mst_resp_t    (mst_resp_t),
        .NoSlvPorts    (2),
        .MaxWTrans     (32'd8),
        .FallThrough   (1'b0),
        .SpillAw       (1'b1),
        .SpillW        (1'b0),
        .SpillB        (1'b0),
        .SpillAr       (1'b1),
        .SpillR        (1'b0)
    ) i_axi_mux (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .test_i      (1'b0),
        .slv_reqs_i  ({mst_axi_read_req, mst_axi_write_req}),
        .slv_resps_o ({mst_axi_read_resp, mst_axi_read_resp}),
        .mst_req_o   (mst_req_o),
        .mst_resp_i  (mst_resp_i)
    );

endmodule
