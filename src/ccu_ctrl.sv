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
    parameter bit          CollisionOnSetOnly = 0,
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

import axi_pkg::*;
import ariane_pkg::*;

localparam int unsigned AxiAddrWidth     = 64;
localparam int unsigned DcacheLineWords  = DcacheLineWidth / AxiDataWidth;
localparam int unsigned DCacheByteOffset = $clog2(ariane_pkg::DCACHE_LINE_WIDTH/8);
localparam int unsigned MstIdxBits       = $clog2(NoMstPorts);

logic   [SlvAxiIDWidth:0] b_inp_id;
logic  [AxiAddrWidth-1:0] b_inp_data;
logic                     b_inp_req;
logic                     b_inp_gnt;

logic  [AxiAddrWidth-1:0] b_exists_data;
logic  [AxiAddrWidth-1:0] b_exists_mask;
logic                     b_exists_req;
logic                     b_exists;
logic                     b_exists_gnt;

logic   [SlvAxiIDWidth:0] b_oup_id;
logic                     b_oup_pop;
logic                     b_oup_req;
logic  [AxiAddrWidth-1:0] b_oup_data;
logic                     b_oup_data_valid;
logic                     b_oup_gnt;

logic  [SlvAxiIDWidth :0] r_inp_id;
logic  [AxiAddrWidth-1:0] r_inp_data;
logic                     r_inp_req;
logic                     r_inp_gnt;

logic  [AxiAddrWidth-1:0] r_exists_data;
logic  [AxiAddrWidth-1:0] r_exists_mask;
logic                     r_exists_req;
logic                     r_exists;
logic                     r_exists_gnt;

logic   [SlvAxiIDWidth:0] r_oup_id;
logic                     r_oup_pop;
logic                     r_oup_req;
logic  [AxiAddrWidth-1:0] r_oup_data;
logic                     r_oup_data_valid;
logic                     r_oup_gnt;


mst_resp_t mu_ccu_resp;
mst_req_t  mu_ccu_req;

su_op_e su_op;
mu_op_e mu_op;

logic su_valid, mu_valid;

logic su_ready, mu_ready;

mst_req_t dec_ccu_req_holder;

logic dec_shared, dec_dirty;

logic [MstIdxBits-1:0] dec_first_responder;

snoop_cd_t [NoMstPorts-1:0] cd;
logic [NoMstPorts-1:0] cd_valid, mu_cd_valid, su_cd_valid;
logic [NoMstPorts-1:0] cd_ready, mu_cd_ready, su_cd_ready;
logic mu_cd_busy, su_cd_busy;
logic mu_cd_done, su_cd_done;

mst_r_chan_t su_r;
logic        su_r_valid, su_r_ready;

logic [NoMstPorts-1:0] data_available;

logic ccu_ar_ready, ccu_aw_ready;

snoop_req_t [NoMstPorts-1:0] dec_snoop_req;

logic dec_lookup_req, dec_collision, dec_b_queue_full, dec_r_queue_full;

logic dec_cd_fifo_stall;

ccu_ctrl_decoder  #(
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
    .first_responder_o    (dec_first_responder),

    .lookup_req_o         (dec_lookup_req),
    .collision_i          (dec_collision),
    .cd_fifo_stall_i      (dec_cd_fifo_stall),
    .b_queue_full_i       (~b_inp_gnt),
    .r_queue_full_i       (~r_inp_gnt)
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
    .cd_valid_i        (su_cd_valid),
    .cd_ready_o        (su_cd_ready),
    .cd_busy_o         (su_cd_busy),
    .cd_done_o         (su_cd_done),
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
    .cd_valid_i        (mu_cd_valid),
    .cd_ready_o        (mu_cd_ready),
    .cd_busy_o         (mu_cd_busy),
    .cd_done_o         (mu_cd_done),

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
end

// Snoop AC and CR
for (genvar i = 0; i < NoMstPorts; i++) begin
    assign s2m_req_o[i].ac = dec_snoop_req[i].ac;
    assign s2m_req_o[i].ac_valid = dec_snoop_req[i].ac_valid;
    assign s2m_req_o[i].cr_ready = dec_snoop_req[i].cr_ready;
end

// Exists
assign dec_collision = (b_exists || r_exists);

// _gnt is not used as it is combinationally set when req = 1


assign b_exists_data = axi_pkg::aligned_addr(dec_ccu_req_holder.aw.addr,dec_ccu_req_holder.aw.size);
assign b_exists_mask = CollisionOnSetOnly ? {ariane_pkg::DCACHE_INDEX_WIDTH{1'b1}} << DCacheByteOffset
                                          : ~{DCacheByteOffset{1'b1}};
assign b_exists_req  = dec_lookup_req;

assign r_exists_data = axi_pkg::aligned_addr(dec_ccu_req_holder.ar.addr,dec_ccu_req_holder.ar.size);
assign r_exists_mask = CollisionOnSetOnly ? {ariane_pkg::DCACHE_INDEX_WIDTH{1'b1}} << DCacheByteOffset
                                          : ~{DCacheByteOffset{1'b1}};
assign r_exists_req  = dec_lookup_req;

// Oup
assign b_oup_id  = ccu_resp_o.b.id;
assign b_oup_pop = 1'b1;
assign b_oup_req = ccu_resp_o.b_valid && ccu_req_i.b_ready;

assign r_oup_id  = ccu_resp_o.r.id;
assign r_oup_pop = 1'b1;
assign r_oup_req = ccu_resp_o.r_valid && ccu_req_i.r_ready && ccu_resp_o.r.last;

// _data_* not used
// _gnt is not used as it is combinationally set when req = 1

// Inp
assign b_inp_id   = ccu_req_i.aw.id;
assign b_inp_data = axi_pkg::aligned_addr(ccu_req_i.aw.addr,ccu_req_i.aw.size);
assign b_inp_req  = ccu_req_i.aw_valid && ccu_resp_o.aw_ready;

assign r_inp_id   = ccu_req_i.ar.id;
assign r_inp_data = axi_pkg::aligned_addr(ccu_req_i.ar.addr,ccu_req_i.ar.size);
assign r_inp_req  = ccu_req_i.ar_valid && ccu_resp_o.ar_ready;


typedef logic [AxiAddrWidth-1:0] id_queue_data_t;

id_queue #(
    .ID_WIDTH (SlvAxiIDWidth+1),
    .CAPACITY (4),
    .FULL_BW  (1),
    .data_t   (id_queue_data_t)
) b_id_queue (
    .clk_i,
    .rst_ni,

    .inp_id_i         (b_inp_id),
    .inp_data_i       (b_inp_data),
    .inp_req_i        (b_inp_req),
    .inp_gnt_o        (b_inp_gnt),

    .exists_data_i    (b_exists_data),
    .exists_mask_i    (b_exists_mask),
    .exists_req_i     (b_exists_req),
    .exists_o         (b_exists),
    .exists_gnt_o     (b_exists_gnt),

    .oup_id_i         (b_oup_id),
    .oup_pop_i        (b_oup_pop),
    .oup_req_i        (b_oup_req),
    .oup_data_o       (b_oup_data),
    .oup_data_valid_o (b_oup_data_valid),
    .oup_gnt_o        (b_oup_gnt)
);

id_queue #(
    .ID_WIDTH (SlvAxiIDWidth+1),
    .CAPACITY (4),
    .FULL_BW  (1),
    .data_t   (id_queue_data_t)
) r_id_queue (
    .clk_i,
    .rst_ni,

    .inp_id_i         (r_inp_id),
    .inp_data_i       (r_inp_data),
    .inp_req_i        (r_inp_req),
    .inp_gnt_o        (r_inp_gnt),

    .exists_data_i    (r_exists_data),
    .exists_mask_i    (r_exists_mask),
    .exists_req_i     (r_exists_req),
    .exists_o         (r_exists),
    .exists_gnt_o     (r_exists_gnt),

    .oup_id_i         (r_oup_id),
    .oup_pop_i        (r_oup_pop),
    .oup_req_i        (r_oup_req),
    .oup_data_o       (r_oup_data),
    .oup_data_valid_o (r_oup_data_valid),
    .oup_gnt_o        (r_oup_gnt)
);

logic mu_wb_op, su_wb_op;

logic cd_user_pop, cd_user_push, cd_user_empty, cd_user_full;

typedef enum logic { MEMORY_UNIT, SNOOP_UNIT } cd_user_t;

cd_user_t cd_user_in, cd_user_out;

assign mu_wb_op = mu_op inside {SEND_AXI_REQ_WRITE_BACK_R, SEND_AXI_REQ_WRITE_BACK_W};
assign su_wb_op = su_op == READ_SNP_DATA;

assign dec_cd_fifo_stall = cd_user_full;

always_comb begin
    cd_user_push = 1'b0;
    cd_user_in    = '0;
    if (mu_ready && mu_valid && mu_wb_op) begin
        cd_user_push = 1'b1;
        cd_user_in   = MEMORY_UNIT;
    end else if (su_ready && su_valid && su_wb_op) begin
        cd_user_push = 1'b1;
        cd_user_in   = SNOOP_UNIT;
    end
end

always_comb begin
    su_cd_valid = '0;
    mu_cd_valid = '0;
    cd_ready    = '0;
    cd_user_pop = 1'b0;

    if (mu_cd_busy || su_cd_busy) begin
        case (cd_user_out)
            MEMORY_UNIT: begin
                mu_cd_valid = cd_valid;
                cd_ready = mu_cd_ready;
                cd_user_pop = mu_cd_done;
            end
            SNOOP_UNIT: begin
                su_cd_valid = cd_valid;
                cd_ready = su_cd_ready;
                cd_user_pop = su_cd_done;
            end
        endcase
    end
end

for (genvar i = 0; i < NoMstPorts; i++) begin
    assign cd[i] = m2s_resp_i[i].cd;
    assign cd_valid[i] = m2s_resp_i[i].cd_valid;
    assign s2m_req_o[i].cd_ready = cd_ready[i];
end

logic cd_user_out_temp;
assign cd_user_out = cd_user_t'(cd_user_out_temp);

fifo_v3 #(
    .FALL_THROUGH(0),
    .DATA_WIDTH(1),
    .DEPTH(4)
) cd_ordering_fifo_i (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (cd_user_full),
    .empty_o    (cd_user_empty),
    .usage_o    (),
    .data_i     (cd_user_in),
    .push_i     (cd_user_push),
    .data_o     (cd_user_out_temp),
    .pop_i      (cd_user_pop)
);

endmodule
