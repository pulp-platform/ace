`include "ace/typedef.svh"
`include "ace/assign.svh"

module ace_ccu_snoop_path import ace_pkg::*; import ccu_pkg::*; #(
    parameter int unsigned NoRules         = 0,
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiDataWidth    = 0,
    parameter int unsigned AxiSlvIdWidth   = 0,
    parameter type ace_aw_chan_t           = logic, // AW Channel Type
    parameter type ace_ar_chan_t           = logic, // AR Channel Type
    parameter type ace_req_t               = logic, // Request type, without FSM route bits
    parameter type ace_resp_t              = logic, // Response type, without FSM route bits
    parameter type axi_aw_chan_t           = logic, // AW Channel Type
    parameter type axi_w_chan_t            = logic, // AW Channel Type
    parameter type axi_req_t               = logic, // Request type, with FSM route bits
    parameter type axi_resp_t              = logic, // Response type, with FSM route bits
    parameter type snoop_ac_t              = logic, // AC channel, snoop port
    parameter type snoop_cr_t              = logic, // CR channel, snoop port
    parameter type snoop_cd_t              = logic, // CD channel, snoop port
    parameter type snoop_req_t             = logic, // Snoop port request type
    parameter type snoop_resp_t            = logic, // Snoop port response type
    parameter type domain_mask_t           = logic,
    parameter type domain_set_t            = logic
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    input  ace_req_t                   slv_req_i,
    output ace_resp_t                  slv_resp_o,
    output axi_req_t                   mst_req_o,
    input  axi_resp_t                  mst_resp_i,
    input  domain_set_t  [NoRules-1:0] domain_set_i,
    output snoop_req_t   [1:0]         snoop_reqs_o,
    input  snoop_resp_t  [1:0]         snoop_resps_i,
    output domain_mask_t [1:0]         snoop_masks_o
);
    axi_req_t  [1:0] mst_reqs;
    axi_resp_t [1:0] mst_resps;
    localparam RuleIdBits = $clog2(NoRules);
    typedef logic [RuleIdBits-1:0] rule_idx_t;

    ace_req_t  slv_read_req, slv_write_req;
    ace_resp_t slv_read_resp, slv_write_resp;

    localparam WB_AXLEN  = DcacheLineWidth/AxiDataWidth-1;
    localparam WB_AXSIZE = $clog2(AxiDataWidth/8);
    localparam ID_WIDTH  = AxiSlvIdWidth + RuleIdBits;
    ///////////
    // SPLIT //
    ///////////

    ace_rw_split #(
        .axi_req_t  (ace_req_t),
        .axi_resp_t (ace_resp_t)
    ) i_snoop_rw_split (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .slv_req_i        (slv_req_i),
        .slv_resp_o       (slv_resp_o),
        .mst_read_req_o   (slv_read_req),
        .mst_read_resp_i  (slv_read_resp),
        .mst_write_req_o  (slv_write_req),
        .mst_write_resp_i (slv_write_resp)
    );

    ////////////////
    // WRITE PATH //
    ////////////////

    acsnoop_t  write_acsnoop;
    rule_idx_t write_rule_idx;

    if (NoRules == 1)
        assign write_rule_idx = 1'b0;
    else
        assign write_rule_idx = slv_write_req.aw.id[AxiSlvIdWidth+:RuleIdBits];

    ace_aw_transaction_decoder #(
        .aw_chan_t (ace_aw_chan_t)
    ) i_write_decoder (
        .aw_i          (slv_write_req.aw),
        .snooping_o    (),
        .acsnoop_o     (write_acsnoop),
        .illegal_trs_o ()
    );

    ccu_ctrl_wr_snoop #(
        .slv_req_t           (ace_req_t),
        .slv_resp_t          (ace_resp_t),
        .slv_aw_chan_t       (ace_aw_chan_t),
        .mst_req_t           (axi_req_t),
        .mst_resp_t          (axi_resp_t),
        .mst_snoop_req_t     (snoop_req_t),
        .mst_snoop_resp_t    (snoop_resp_t),
        .domain_set_t        (domain_set_t),
        .domain_mask_t       (domain_mask_t),
        .AXLEN               (WB_AXLEN),
        .AXSIZE              (WB_AXSIZE),
        .FIFO_DEPTH          (2)
    ) i_ccu_ctrl_wr_snoop (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .slv_req_i     (slv_write_req),
        .slv_resp_o    (slv_write_resp),
        .snoop_trs_i   (write_acsnoop),
        .mst_req_o     (mst_reqs       [0]),
        .mst_resp_i    (mst_resps      [0]),
        .snoop_req_o   (snoop_reqs_o   [0]),
        .snoop_resp_i  (snoop_resps_i  [0]),
        .domain_set_i  (domain_set_i[write_rule_idx]),
        .domain_mask_o (snoop_masks_o  [0])
    );

    ///////////////
    // READ PATH //
    ///////////////

    snoop_info_t read_snoop_info;
    rule_idx_t   read_rule_idx;

    if (NoRules == 1)
        assign read_rule_idx = 1'b0;
    else
        assign read_rule_idx = slv_read_req.ar.id[AxiSlvIdWidth+:RuleIdBits];

    ace_ar_transaction_decoder #(
        .ar_chan_t (ace_ar_chan_t)
    ) i_read_decoder (
        .ar_i          (slv_read_req.ar),
        .snooping_o    (),
        .snoop_info_o  (read_snoop_info),
        .illegal_trs_o ()
    );

    ccu_ctrl_r_snoop #(
        .slv_req_t           (ace_req_t),
        .slv_resp_t          (ace_resp_t),
        .slv_ar_chan_t       (ace_ar_chan_t),
        .mst_req_t           (axi_req_t),
        .mst_resp_t          (axi_resp_t),
        .mst_snoop_req_t     (snoop_req_t),
        .mst_snoop_resp_t    (snoop_resp_t),
        .domain_set_t        (domain_set_t),
        .domain_mask_t       (domain_mask_t),
        .AXLEN               (WB_AXLEN),
        .AXSIZE              (WB_AXSIZE),
        .FIFO_DEPTH          (2)
    ) i_ccu_ctrl_r_snoop (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .slv_req_i     (slv_read_req),
        .slv_resp_o    (slv_read_resp),
        .snoop_info_i  (read_snoop_info),
        .mst_req_o     (mst_reqs       [1]),
        .mst_resp_i    (mst_resps      [1]),
        .snoop_req_o   (snoop_reqs_o   [1]),
        .snoop_resp_i  (snoop_resps_i  [1]),
        .domain_set_i  (domain_set_i[read_rule_idx]),
        .domain_mask_o (snoop_masks_o  [1])
    );

    ccu_mem_ctrl #(
        .AxiIdWidth (ID_WIDTH),
        .req_t      (axi_req_t),
        .resp_t     (axi_resp_t),
        .aw_chan_t  (axi_aw_chan_t),
        .w_chan_t   (axi_w_chan_t)
    ) i_ccu_mem_ctrl (
        .clk_i,
        .rst_ni,
        .wr_mst_req_i  (mst_reqs[1]),
        .wr_mst_resp_o (mst_resps[1]),
        .r_mst_req_i   (mst_reqs[0]),
        .r_mst_resp_o  (mst_resps[0]),
        .mst_req_o,
        .mst_resp_i
    );

endmodule
