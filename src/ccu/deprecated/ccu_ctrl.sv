// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "ace/assign.svh"
`include "ace/typedef.svh"

module ccu_ctrl import ccu_ctrl_pkg::*; import axi_pkg::*;
#(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned DcacheIndexWidth = 0,
    parameter int unsigned AxiDataWidth = 0,
    parameter int unsigned AxiAddrWidth = 0,
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
    parameter type slv_aw_chan_t = logic,
    parameter type slv_b_chan_t  = logic,
    parameter type slv_ar_chan_t = logic,
    parameter type slv_r_chan_t  = logic,
    parameter type slv_req_t     = logic,
    parameter type slv_resp_t    = logic,
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
    input  slv_req_t                    ccu_req_i,
    output slv_resp_t                   ccu_resp_o,
    //CCU Request Out and response in
    output mst_req_t                    ccu_req_o,
    input  mst_resp_t                   ccu_resp_i,
    // Snoop channel resuest and response
    output snoop_req_t  [NoMstPorts-1:0] s2m_req_o,
    input  snoop_resp_t [NoMstPorts-1:0] m2s_resp_i,
    // Perf counters
    output logic                   [7:0] perf_evt_o
);

logic [7:0] perf_evt;

localparam int unsigned DcacheLineWords  = DcacheLineWidth / AxiDataWidth;
localparam int unsigned DCacheByteOffset = $clog2(DcacheLineWidth/8);
localparam int unsigned MstIdxBits       = $clog2(NoMstPorts);

localparam int unsigned IdQueueDataWidth = CollisionOnSetOnly ?
                                           DcacheIndexWidth   :
                                           AxiAddrWidth - DCacheByteOffset;

typedef logic [IdQueueDataWidth-1:0] id_queue_data_t;

logic           [SlvAxiIDWidth:0] b_inp_id;
id_queue_data_t                   b_inp_data;
logic                             b_inp_req;
logic                             b_inp_gnt;

id_queue_data_t                   b_exists_data;
id_queue_data_t                   b_exists_mask;
logic                             b_exists_req;
logic                             b_exists;
logic                             b_exists_gnt;

logic           [SlvAxiIDWidth:0] b_oup_id;
logic                             b_oup_pop;
logic                             b_oup_req;
id_queue_data_t                   b_oup_data;
logic                             b_oup_data_valid;
logic                             b_oup_gnt;

logic           [SlvAxiIDWidth:0] r_inp_id;
id_queue_data_t                   r_inp_data;
logic                             r_inp_req;
logic                             r_inp_gnt;

id_queue_data_t                   r_exists_data;
id_queue_data_t                   r_exists_mask;
logic                             r_exists_req;
logic                             r_exists;
logic                             r_exists_gnt;

logic           [SlvAxiIDWidth:0] r_oup_id;
logic                             r_oup_pop;
logic                             r_oup_req;
id_queue_data_t                   r_oup_data;
logic                             r_oup_data_valid;
logic                             r_oup_gnt;


slv_resp_t mu_ccu_resp;
slv_req_t  mu_ccu_req;

su_op_e su_op;
mu_op_e mu_op;

logic su_req, mu_req;

logic su_gnt, mu_gnt;

slv_req_t dec_ccu_req_holder;

logic dec_shared, dec_dirty;

logic [MstIdxBits-1:0] dec_first_responder, cd_first_responder_in, cd_first_responder_out;

snoop_cd_t [NoMstPorts-1:0] cd;
snoop_cd_t                  cd_first_responder;
logic                       cd_handshake, mu_cd_handshake, su_cd_handshake;
logic      [NoMstPorts-1:0] cd_valid;
logic      [NoMstPorts-1:0] cd_ready;
logic      [NoMstPorts-1:0] cd_data_available_in, cd_data_available_out;
logic      [NoMstPorts-1:0] cd_last_q;
logic                       cd_fifo_full, mu_cd_fifo_full, su_cd_fifo_full;

slv_r_chan_t su_r;
logic        su_r_valid, su_r_ready;

logic ccu_ar_ready, ccu_aw_ready;

snoop_req_t [NoMstPorts-1:0] dec_snoop_req;

logic                    dec_lookup_req;
logic [AxiAddrWidth-1:0] dec_lookup_addr;

slv_aw_chan_t b_queue_aw;
slv_ar_chan_t r_queue_ar;

logic b_queue_push, r_queue_push;

logic dec_cd_fifo_stall;

ccu_ctrl_decoder  #(
    .DcacheLineWidth (DcacheLineWidth),
    .AxiDataWidth    (AxiDataWidth),
    .AxiAddrWidth    (AxiAddrWidth),
    .NoMstPorts      (NoMstPorts),
    .SlvAxiIDWidth   (SlvAxiIDWidth),
    .slv_aw_chan_t   (slv_aw_chan_t),
    .w_chan_t        (w_chan_t),
    .slv_b_chan_t    (slv_b_chan_t),
    .slv_ar_chan_t   (slv_ar_chan_t),
    .slv_r_chan_t    (slv_r_chan_t),
    .slv_req_t       (slv_req_t),
    .slv_resp_t      (slv_resp_t),
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
    .su_gnt_i             (su_gnt),
    .mu_gnt_i             (mu_gnt),
    .su_req_o             (su_req),
    .mu_req_o             (mu_req),
    .su_op_o              (su_op),
    .mu_op_o              (mu_op),
    .shared_o             (dec_shared),
    .dirty_o              (dec_dirty),
    .data_available_o     (cd_data_available_in),
    .first_responder_o    (dec_first_responder),

    .lookup_req_o         (dec_lookup_req),
    .lookup_addr_o        (dec_lookup_addr),
    .cd_fifo_stall_i      (dec_cd_fifo_stall),

    .b_queue_full_i       (~b_inp_gnt),
    .r_queue_full_i       (~r_inp_gnt),
    .b_collision_i        (b_exists),
    .r_collision_i        (r_exists),
    .b_queue_push_o       (b_queue_push),
    .r_queue_push_o       (r_queue_push),
    .b_queue_aw_o         (b_queue_aw),
    .r_queue_ar_o         (r_queue_ar),

    .perf_evt_o           ()

);

ccu_ctrl_snoop_unit #(
    .DcacheLineWidth (DcacheLineWidth),
    .AxiDataWidth    (AxiDataWidth),
    .NoMstPorts      (NoMstPorts),
    .SlvAxiIDWidth   (SlvAxiIDWidth),
    .slv_aw_chan_t   (slv_aw_chan_t),
    .w_chan_t        (w_chan_t),
    .slv_b_chan_t    (slv_b_chan_t),
    .slv_ar_chan_t   (slv_ar_chan_t),
    .slv_r_chan_t    (slv_r_chan_t),
    .slv_req_t       (slv_req_t),
    .slv_resp_t      (slv_resp_t),
    .snoop_ac_t      (snoop_ac_t),
    .snoop_cr_t      (snoop_cr_t),
    .snoop_cd_t      (snoop_cd_t),
    .snoop_req_t     (snoop_req_t),
    .snoop_resp_t    (snoop_resp_t)
) ccu_ctrl_snoop_unit_i (
    .clk_i,
    .rst_ni,

    .r_o                   (su_r),
    .r_valid_o             (su_r_valid),
    .r_ready_i             (su_r_ready),

    .cd_i                  (cd_first_responder),
    .cd_handshake_i        (su_cd_handshake),
    .cd_fifo_full_o        (su_cd_fifo_full),

    .ccu_req_holder_i      (dec_ccu_req_holder),

    .su_gnt_o              (su_gnt),
    .su_req_i              (su_req),
    .su_op_i               (su_op),

    .shared_i              (dec_shared),
    .dirty_i               (dec_dirty)
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
    .slv_aw_chan_t   (slv_aw_chan_t),
    .slv_b_chan_t    (slv_b_chan_t),
    .slv_ar_chan_t   (slv_ar_chan_t),
    .slv_r_chan_t    (slv_r_chan_t),
    .slv_req_t       (slv_req_t),
    .slv_resp_t      (slv_resp_t),
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

    .cd_i              (cd_first_responder),
    .cd_handshake_i    (mu_cd_handshake),
    .cd_fifo_full_o    (mu_cd_fifo_full),

    .ccu_req_holder_i  (dec_ccu_req_holder),
    .mu_gnt_o          (mu_gnt),
    .mu_req_i          (mu_req),
    .mu_op_i           (mu_op),
    .first_responder_i (dec_first_responder),

    .perf_evt_o        (perf_evt)
);

///////////////////
// R arbitration //
///////////////////

logic [1:0] r_valid_in, r_ready_in;
slv_r_chan_t [1:0] r_chans_in;

slv_r_chan_t       r_chan_out;
logic              r_valid_out, r_ready_out;

always_comb begin
    mu_ccu_req = ccu_req_i;

    r_valid_in = {mu_ccu_resp.r_valid, su_r_valid};
    r_chans_in = {mu_ccu_resp.r, su_r};
    {mu_ccu_req.r_ready, su_r_ready} = r_ready_in;
end

rr_arb_tree #(
    .NumIn    ( 2             ),
    .DataType ( slv_r_chan_t  ),
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

/////////////////////
// Collision Check //
/////////////////////

logic [AxiAddrWidth-1:0] b_inp_aligned_addr;
logic [AxiAddrWidth-1:0] b_exists_aligned_addr;
logic [AxiAddrWidth-1:0] r_inp_aligned_addr;
logic [AxiAddrWidth-1:0] r_exists_aligned_addr;

assign b_inp_aligned_addr    = axi_pkg::aligned_addr(b_queue_aw.addr,b_queue_aw.size);
assign b_exists_aligned_addr = dec_lookup_addr;

assign r_inp_aligned_addr    = axi_pkg::aligned_addr(r_queue_ar.addr,r_queue_ar.size);
assign r_exists_aligned_addr = dec_lookup_addr;

// Exists

// _gnt is not used as it is combinationally set when req = 1

assign b_exists_data = b_exists_aligned_addr[DCacheByteOffset+:IdQueueDataWidth];
assign b_exists_mask = '1;
assign b_exists_req  = dec_lookup_req;

assign r_exists_data = r_exists_aligned_addr[DCacheByteOffset+:IdQueueDataWidth];
assign r_exists_mask = '1;
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
assign b_inp_id   = b_queue_aw.id;
assign b_inp_data = b_inp_aligned_addr[DCacheByteOffset+:IdQueueDataWidth];
assign b_inp_req  = b_queue_push;

assign r_inp_id   = r_queue_ar.id;
assign r_inp_data = r_inp_aligned_addr[DCacheByteOffset+:IdQueueDataWidth];
assign r_inp_req  = r_queue_push;

id_queue #(
    .ID_WIDTH (SlvAxiIDWidth+1),
    .CAPACITY (6),
    .FULL_BW  (1),
    .CUT_OUP_POP_INP_GNT (1),
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
    .CAPACITY (6),
    .FULL_BW  (1),
    .CUT_OUP_POP_INP_GNT (1),
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

////////////////////
// CD arbitration //
////////////////////

logic mu_wb_op, su_wb_op;

logic cd_user_pop, cd_user_push, cd_user_empty, cd_user_full;

typedef enum logic { MEMORY_UNIT, SNOOP_UNIT } cd_user_t;

cd_user_t cd_user_in, cd_user_out;

logic cd_done;

assign mu_wb_op = mu_op inside {SEND_AXI_REQ_WRITE_BACK_R, SEND_AXI_REQ_WRITE_BACK_W};
assign su_wb_op = su_op == READ_SNP_DATA;

assign dec_cd_fifo_stall = cd_user_full;

logic cd_user_pushed_d, cd_user_pushed_q;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        cd_user_pushed_q <= '0;
    end else begin
        cd_user_pushed_q <= cd_user_pushed_d;
    end
end

always_comb begin
    cd_user_pushed_d = cd_user_pushed_q;
    cd_user_push = 1'b0;
    cd_user_in    = MEMORY_UNIT;
    if (mu_req && mu_wb_op) begin
        cd_user_pushed_d = !mu_gnt;
        cd_user_push = !cd_user_pushed_q;
        cd_user_in   = MEMORY_UNIT;
    end else if (su_req && su_wb_op) begin
        cd_user_pushed_d = !su_gnt;
        cd_user_push = !cd_user_pushed_q;
        cd_user_in   = SNOOP_UNIT;
    end
end

always_comb begin
    su_cd_handshake = '0;
    mu_cd_handshake = '0;
    cd_fifo_full = '0;
    cd_done      = '0;

    if (!cd_user_empty) begin
        cd_done     = cd_last_q == cd_data_available_out;
        case (cd_user_out)
            MEMORY_UNIT: begin
                mu_cd_handshake = cd_handshake;
                cd_fifo_full    = mu_cd_fifo_full;
            end
            SNOOP_UNIT: begin
                su_cd_handshake = cd_handshake;
                cd_fifo_full    = su_cd_fifo_full;
            end
        endcase
    end
end

for (genvar i = 0; i < NoMstPorts; i++) begin
    assign cd_ready[i] = (cd_first_responder_out == i && cd_fifo_full) ? '0 :
                         !cd_user_empty && !cd_last_q[i] && cd_data_available_out[i];
end

for (genvar i = 0; i < NoMstPorts; i++) begin
    assign cd[i] = m2s_resp_i[i].cd;
    assign cd_valid[i] = m2s_resp_i[i].cd_valid;
    assign s2m_req_o[i].cd_ready = cd_ready[i];
end

logic cd_user_out_temp, cd_user_in_temp;
assign cd_user_in_temp        = logic'(cd_user_in);
assign cd_user_out            = cd_user_t'(cd_user_out_temp);
assign cd_first_responder_in  = dec_first_responder;

assign cd_user_pop            = cd_done;

fifo_v3 #(
    .FALL_THROUGH(1),
    .DATA_WIDTH(1 + NoMstPorts + MstIdxBits),
    .DEPTH(4)
) cd_ordering_fifo_i (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (cd_user_full),
    .empty_o    (cd_user_empty),
    .usage_o    (),
    .data_i     ({cd_user_in_temp, cd_first_responder_in, cd_data_available_in}),
    .push_i     (cd_user_push),
    .data_o     ({cd_user_out_temp, cd_first_responder_out, cd_data_available_out}),
    .pop_i      (cd_user_pop)
);

for (genvar i = 0; i < NoMstPorts; i = i + 1) begin
    always_ff @ (posedge clk_i, negedge rst_ni) begin
        if(!rst_ni) begin
            cd_last_q[i] <= '0;
        end else if(cd_done) begin
            cd_last_q[i] <= '0;
        end else if(cd_valid[i]) begin
            cd_last_q[i] <= (cd[i].last & cd_data_available_out[i]);
        end
    end
end

assign cd_first_responder = cd[cd_first_responder_out];
assign cd_handshake       = cd_valid[cd_first_responder_out] && cd_ready[cd_first_responder_out];

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        perf_evt_o <= '0;
    end else begin
        perf_evt_o <= perf_evt;
    end
end

endmodule
