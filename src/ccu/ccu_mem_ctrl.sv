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

`include "axi/assign.svh"
// Memory controller
// Mux the two AW channel and keep locked until last W beat
// Add two bits to the ID to encode where response should be routed
// RID: 10 -> W FSM, else R FSM
// BID: 01 -> R FSM, else W FSM
// 00 is used for LR/SC sequence, where AWID and ARID must be the same
module ccu_mem_ctrl import ace_pkg::*; #(
    parameter type slv_req_t  = logic,
    parameter type slv_resp_t = logic,
    parameter type mst_req_t  = logic,
    parameter type mst_resp_t = logic,
    parameter type aw_chan_t  = logic,
    parameter type w_chan_t   = logic
)(
    input             clk_i,
    input             rst_ni,
    /// AXI request from W FSM
    input  slv_req_t  wr_mst_req_i,
    /// AXI response to W FSM
    output slv_resp_t wr_mst_resp_o,
    /// AXI request from R FSM
    input  slv_req_t  r_mst_req_i,
    /// AXI response to R FSM
    output slv_resp_t r_mst_resp_o,
    /// AXI request to main memory
    output mst_req_t  mst_req_o,
    /// AXI response from main memory
    input  mst_resp_t mst_resp_i,
    /// AW is write-back
    input  logic aw_wb_i,
    /// B is write-back
    output logic b_wb_o
);

localparam int unsigned FIFO_DEPTH = 4;
parameter int unsigned SlvAxiIdWidth = $bits(r_mst_req_i.aw.id); // ID width in slv_req_t

logic w_select, w_fifo_push, w_fifo_pop, w_fifo_empty, w_fifo_full;
logic w_select_fifo;
logic [$clog2(FIFO_DEPTH)-1:0] w_fifo_usage;
logic w_valid, w_ready;
logic aw_lock_d, aw_lock_q;
slv_req_t mst_req;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
        aw_lock_q <= 1'b0;
    end else begin
        aw_lock_q <= aw_lock_d;
    end
end

// AW Channel
rr_arb_tree #(
    .NumIn      (2),
    .DataType   (aw_chan_t),
    .ExtPrio    (1'b0),
    .AxiVldRdy  (1'b1),
    .LockIn     (1'b1)
) i_arbiter (
    .clk_i,
    .rst_ni,
    .flush_i ('0),
    .rr_i    ('0),
    .req_i   ({r_mst_req_i.aw_valid, wr_mst_req_i.aw_valid}),
    .gnt_o   ({r_mst_resp_o.aw_ready, wr_mst_resp_o.aw_ready}),
    .data_i  ({r_mst_req_i.aw, wr_mst_req_i.aw}),
    .req_o   (mst_req.aw_valid),
    .gnt_i   (mst_resp_i.aw_ready),
    .data_o  (mst_req.aw),
    .idx_o   (w_select)
);

// AR Channel (W-FSM cannot generate AR requests)
assign mst_req.ar             = r_mst_req_i.ar;
assign mst_req.ar_valid       = r_mst_req_i.ar_valid;
assign r_mst_resp_o.ar_ready  = mst_resp_i.ar_ready;
assign wr_mst_resp_o.ar_ready = 1'b0;

// ID Prepending
// Ensure that restrictive accesses get the same ID
always_comb begin
    mst_req_o.aw_valid = mst_req.aw_valid;
    mst_req_o.ar_valid = mst_req.ar_valid;
    `AXI_SET_AW_STRUCT(mst_req_o.aw, mst_req.aw)
    `AXI_SET_AR_STRUCT(mst_req_o.ar, mst_req.ar)
    if (mst_req.aw.lock) begin
        mst_req_o.aw.id = {2'b00, mst_req.aw.id[SlvAxiIdWidth-1:0]};
    end else begin
        mst_req_o.aw.id = {
            w_select  ? 2'b01 :
            aw_wb_i   ? 2'b11 :
                        2'b10,
            mst_req.aw.id[SlvAxiIdWidth-1:0]};
    end
    if (mst_req.ar.lock) begin
        mst_req_o.ar.id = {2'b00, mst_req.ar.id[SlvAxiIdWidth-1:0]};
    end else begin
        mst_req_o.ar.id = {2'b01, mst_req.ar.id[SlvAxiIdWidth-1:0]};
    end
end

// W Channel
// Index 0 - W FSM
// Index 1 - R FSM
stream_mux #(
    .DATA_T(w_chan_t),
    .N_INP (2)
) i_stream_mux_w (
    .inp_data_i ({r_mst_req_i.w, wr_mst_req_i.w}),
    .inp_valid_i({r_mst_req_i.w_valid, wr_mst_req_i.w_valid}),
    .inp_ready_o({r_mst_resp_o.w_ready, wr_mst_resp_o.w_ready}),
    .inp_sel_i  (w_select_fifo),
    .oup_data_o (mst_req.w),
    .oup_valid_o(w_valid),
    .oup_ready_i(w_ready)
);

// W index
fifo_v3 #(
    .FALL_THROUGH   (1'b1),
    .DATA_WIDTH     (1),
    .DEPTH          (FIFO_DEPTH)
) i_w_cmd_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (w_fifo_full),
    .empty_o    (),
    .usage_o    (w_fifo_usage),
    .data_i     (w_select),
    .push_i     (w_fifo_push),
    .data_o     (w_select_fifo),
    .pop_i      (w_fifo_pop)
);

assign w_fifo_push = ~aw_lock_q && mst_req_o.aw_valid;
assign w_fifo_pop  = mst_req_o.w_valid && mst_resp_i.w_ready && mst_req_o.w.last;
assign aw_lock_d   = ~mst_resp_i.aw_ready && (mst_req_o.aw_valid || aw_lock_q);

assign w_fifo_empty = w_fifo_usage == 0 && !w_fifo_full;

// Block handshake if fifo empty
`AXI_ASSIGN_W_STRUCT(mst_req_o.w, mst_req.w)
assign mst_req_o.w_valid = w_valid            && !w_fifo_empty;
assign w_ready           = mst_resp_i.w_ready && !w_fifo_empty;

// B Channel
`AXI_ASSIGN_B_STRUCT(r_mst_resp_o.b, mst_resp_i.b)
`AXI_ASSIGN_B_STRUCT(wr_mst_resp_o.b, mst_resp_i.b)
always_comb begin
    r_mst_resp_o.b_valid  = 1'b0;
    wr_mst_resp_o.b_valid = 1'b0;
    if (mst_resp_i.b.id[SlvAxiIdWidth+1:SlvAxiIdWidth] == 2'b01) begin
        r_mst_resp_o.b_valid = mst_resp_i.b_valid;
        mst_req_o.b_ready    = r_mst_req_i.b_ready;
    end
    else begin
        wr_mst_resp_o.b_valid = mst_resp_i.b_valid;
        mst_req_o.b_ready     = wr_mst_req_i.b_ready;
    end
end

assign b_wb_o = mst_resp_i.b.id[SlvAxiIdWidth+1:SlvAxiIdWidth] == 2'b11;

// R Channel
`AXI_ASSIGN_R_STRUCT(r_mst_resp_o.r, mst_resp_i.r)
`AXI_ASSIGN_R_STRUCT(wr_mst_resp_o.r, mst_resp_i.r)
always_comb begin
    wr_mst_resp_o.r_valid = 1'b0;
    r_mst_resp_o.r_valid  = 1'b0;
    if (mst_resp_i.r.id[SlvAxiIdWidth+1:SlvAxiIdWidth] == 2'b10) begin
        wr_mst_resp_o.r_valid = mst_resp_i.r_valid;
        mst_req_o.r_ready     = wr_mst_req_i.r_ready;
    end
    else begin
        r_mst_resp_o.r_valid = mst_resp_i.r_valid;
        mst_req_o.r_ready    = r_mst_req_i.r_ready;
    end
end

// pragma translate_off
`ifndef VERILATOR
initial begin : b_assert
    assert(($bits(mst_req_o.aw.id) - $bits(r_mst_req_i.aw.id)) == 2)
        else $fatal(1, "Difference in AW ID widths should be 2");
    assert(($bits(mst_req_o.ar.id) - $bits(r_mst_req_i.ar.id)) == 2)
        else $fatal(1, "Difference in AR ID widths should be 2");
end
`endif
// pragma translate_on

endmodule
