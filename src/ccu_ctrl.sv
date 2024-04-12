// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "ace/assign.svh"
`include "ace/typedef.svh"

module ccu_ctrl import ccu_ctrl_pkg::*;
#(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiDataWidth = 0,
    parameter int unsigned NoMstPorts = 4,
    parameter int unsigned SlvAxiIDWidth = 0,
    parameter type mst_aw_chan_t = logic,
    parameter type w_chan_t      = logic,
    parameter type mst_b_chan_t  = logic,
    parameter type mst_ar_chan_t = logic,
    parameter type mst_r_chan_t  = logic,
    parameter type mst_req_t     = logic,
    parameter type mst_resp_t    = logic,
    parameter type snoop_ac_t    = logic,
    parameter type snoop_cr_t    = logic,
    parameter type snoop_cd_t    = logic,
    parameter type snoop_req_t   = logic,
    parameter type snoop_resp_t  = logic
) (
    //clock and reset
    input                               clk_i,
    input                               rst_ni,
    // CCU Request In and response out
    input  mst_req_t                    ccu_req_i,
    output mst_resp_t                   ccu_resp_o,
    //CCU Request Out and response in
    output mst_req_t                    ccu_req_o,
    input  mst_resp_t                   ccu_resp_i,
    // Snoop channel resuest and response
    output snoop_req_t  [NoMstPorts-1:0] s2m_req_o,
    input  snoop_resp_t [NoMstPorts-1:0] m2s_resp_i
);

localparam bit Legacy = 1;

localparam int unsigned DcacheLineWords = DcacheLineWidth / AxiDataWidth;
localparam int unsigned MstIdxBits      = $clog2(NoMstPorts);


mst_resp_t mu_ccu_resp;
mst_req_t  mu_ccu_req;

su_op_e su_op;
mu_op_e mu_op;

logic su_valid, mu_valid;

logic su_ready, mu_ready;

mst_req_t dec_ccu_req_holder;

logic dec_shared, dec_dirty;

logic [MstIdxBits-1:0] dec_first_responder;

logic [NoMstPorts-1:0] su_cd_ready, mu_cd_ready;
logic su_cd_busy, mu_cd_busy;

mst_r_chan_t su_r;
logic        su_r_valid, su_r_ready;

logic [NoMstPorts-1:0] data_available;

logic ccu_ar_ready, ccu_aw_ready;

snoop_req_t [NoMstPorts-1:0] dec_snoop_req;

snoop_cd_t [NoMstPorts-1:0] cd;
logic [NoMstPorts-1:0] cd_valid;

for (genvar i = 0; i < NoMstPorts; i++) begin
    assign cd[i] = m2s_resp_i[i].cd;
    assign cd_valid[i] = m2s_resp_i[i].cd_valid;
end

ccu_ctrl_decoder  #(
    .Legacy          (Legacy),
    .DcacheLineWidth (DcacheLineWidth),
    .AxiDataWidth    (AxiDataWidth),
    .NoMstPorts      (NoMstPorts),
    .SlvAxiIDWidth   (SlvAxiIDWidth),
    .mst_aw_chan_t   (mst_aw_chan_t),
    .w_chan_t        (w_chan_t),
    .mst_b_chan_t    (mst_b_chan_t),
    .mst_ar_chan_t   (mst_ar_chan_t),
    .mst_r_chan_t    (mst_r_chan_t),
    .mst_req_t       (mst_req_t),
    .mst_resp_t      (mst_resp_t),
    .snoop_ac_t      (snoop_ac_t),
    .snoop_cr_t      (snoop_cr_t),
    .snoop_cd_t      (snoop_cd_t),
    .snoop_req_t     (snoop_req_t),
    .snoop_resp_t    (snoop_resp_t)
) ccu_ctrl_decoder_i (
    .clk_i,
    .rst_ni,

    .ccu_req_i,

    .s2m_req_o            (dec_snoop_req),
    .m2s_resp_i,

    .slv_aw_ready_o       (ccu_aw_ready),
    .slv_ar_ready_o       (ccu_ar_ready),

    .ccu_req_holder_o     (dec_ccu_req_holder),
    .su_ready_i           (su_ready),
    .mu_ready_i           (mu_ready),
    .su_valid_o           (su_valid),
    .mu_valid_o           (mu_valid),
    .su_op_o              (su_op),
    .mu_op_o              (mu_op),
    .shared_o             (dec_shared),
    .dirty_o              (dec_dirty),
    .data_available_o     (data_available),
    .first_responder_o    (dec_first_responder)
);

ccu_ctrl_snoop_unit #(
    .DcacheLineWidth (DcacheLineWidth),
    .AxiDataWidth    (AxiDataWidth),
    .NoMstPorts      (NoMstPorts),
    .SlvAxiIDWidth   (SlvAxiIDWidth),
    .mst_aw_chan_t   (mst_aw_chan_t),
    .w_chan_t        (w_chan_t),
    .mst_b_chan_t    (mst_b_chan_t),
    .mst_ar_chan_t   (mst_ar_chan_t),
    .mst_r_chan_t    (mst_r_chan_t),
    .mst_req_t       (mst_req_t),
    .mst_resp_t      (mst_resp_t),
    .snoop_ac_t      (snoop_ac_t),
    .snoop_cr_t      (snoop_cr_t),
    .snoop_cd_t      (snoop_cd_t),
    .snoop_req_t     (snoop_req_t),
    .snoop_resp_t    (snoop_resp_t)
) ccu_ctrl_snoop_unit_i (
    .clk_i,
    .rst_ni,
    .r_o               (su_r),
    .r_valid_o         (su_r_valid),
    .r_ready_i         (su_r_ready),
    .cd_i              (cd),
    .cd_valid_i        (cd_valid),
    .cd_ready_o        (su_cd_ready),
    .cd_busy_o         (su_cd_busy),
    .ccu_req_holder_i  (dec_ccu_req_holder),
    .su_ready_o        (su_ready),
    .su_valid_i        (su_valid),
    .su_op_i           (su_op),
    .shared_i          (dec_shared),
    .dirty_i           (dec_dirty),
    .data_available_i  (data_available),
    .first_responder_i (dec_first_responder)
);

ccu_ctrl_memory_unit #(
    .Legacy          (Legacy),
    .DcacheLineWidth (DcacheLineWidth),
    .AxiDataWidth    (AxiDataWidth),
    .NoMstPorts      (NoMstPorts),
    .SlvAxiIDWidth   (SlvAxiIDWidth),
    .mst_aw_chan_t   (mst_aw_chan_t),
    .w_chan_t        (w_chan_t),
    .mst_b_chan_t    (mst_b_chan_t),
    .mst_ar_chan_t   (mst_ar_chan_t),
    .mst_r_chan_t    (mst_r_chan_t),
    .mst_req_t       (mst_req_t),
    .mst_resp_t      (mst_resp_t),
    .snoop_ac_t      (snoop_ac_t),
    .snoop_cr_t      (snoop_cr_t),
    .snoop_cd_t      (snoop_cd_t),
    .snoop_req_t     (snoop_req_t),
    .snoop_resp_t    (snoop_resp_t)
) ccu_ctrl_memory_unit_i (
    .clk_i,
    .rst_ni,

    .ccu_req_i         (mu_ccu_req),
    .ccu_resp_o        (mu_ccu_resp),

    .ccu_req_o,
    .ccu_resp_i,

    .cd_i              (cd),
    .cd_valid_i        (cd_valid),
    .cd_ready_o        (mu_cd_ready),
    .cd_busy_o         (mu_cd_busy),

    .ccu_req_holder_i  (dec_ccu_req_holder),
    .mu_ready_o        (mu_ready),
    .mu_valid_i        (mu_valid),
    .mu_op_i           (mu_op),
    .data_available_i  (data_available),
    .first_responder_i (dec_first_responder)
);

    logic [1:0] r_valid_in, r_ready_in;
    mst_r_chan_t [1:0] r_chans_in;

    mst_r_chan_t       r_chan_out;
    logic              r_valid_out, r_ready_out;

    always_comb begin
        mu_ccu_req = ccu_req_i;

        r_valid_in = {mu_ccu_resp.r_valid, su_r_valid};
        r_chans_in = {mu_ccu_resp.r, su_r};
        {mu_ccu_req.r_ready, su_r_ready} = r_ready_in;
    end

    rr_arb_tree #(
      .NumIn    ( 2             ),
      .DataType ( mst_r_chan_t  ),
      .AxiVldRdy( 1'b1          ),
      .LockIn   ( 1'b1          )
    ) r_arbiter_i (
      .clk_i  ( clk_i           ),
      .rst_ni ( rst_ni          ),
      .flush_i( 1'b0            ),
      .rr_i   ( '0              ),
      .req_i  ( r_valid_in      ),
      .gnt_o  ( r_ready_in      ),
      .data_i ( r_chans_in      ),
      .gnt_i  ( r_ready_out     ),
      .req_o  ( r_valid_out     ),
      .data_o ( r_chan_out      ),
      .idx_o  (                 )
    );



always_comb begin
    // Resp
    ccu_resp_o = mu_ccu_resp;

    ccu_resp_o.r = r_chan_out;
    ccu_resp_o.r_valid = r_valid_out;
    r_ready_out = ccu_req_i.r_ready;

    ccu_resp_o.ar_ready = ccu_ar_ready;
    ccu_resp_o.aw_ready = ccu_aw_ready;

    // Snoop
    for (int unsigned i = 0; i < NoMstPorts; i++) begin
        s2m_req_o[i] = '0;
        s2m_req_o[i].ac = dec_snoop_req[i].ac;
        s2m_req_o[i].ac_valid = dec_snoop_req[i].ac_valid;
        s2m_req_o[i].cr_ready = dec_snoop_req[i].cr_ready;
        s2m_req_o[i].cd_ready = su_cd_ready[i] || mu_cd_ready[i]; // TODO arb tree
    end
end

endmodule
