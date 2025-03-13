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
`include "ace/convert.svh"

// FSM to control write snoop transactions
// This module assumes that snooping happens
// Non-snooping transactions should be handled outside
module ccu_ctrl_wr_snoop import ace_pkg::*; #(
    /// Request channel type towards cached master
    parameter type slv_req_t          = logic,
    /// Response channel type towards cached master
    parameter type slv_resp_t         = logic,
    /// Request channel type towards memory
    parameter type mst_req_t          = logic,
    /// Response channel type towards memory
    parameter type mst_resp_t         = logic,
    /// AW channel type towards cached master
    parameter type slv_aw_chan_t      = logic,
    /// W channel type towards cached master
    parameter type slv_w_chan_t       = logic,
    /// Snoop request type
    parameter type mst_snoop_req_t    = logic,
    /// Snoop response type
    parameter type mst_snoop_resp_t   = logic,
    /// AW channel type towards memory
    parameter type mst_aw_chan_t      = logic,
    /// W channel type towards memory
    parameter type mst_w_chan_t       = logic,
    /// Domain masks set for each master
    parameter type domain_set_t       = logic,
    /// Domain mask type
    parameter type domain_mask_t      = logic,
    /// Fixed value for AXLEN for write back
    parameter int unsigned AXLEN      = 0,
    /// Fixed value for AXSIZE for write back
    parameter int unsigned AXSIZE     = 0,
    /// Fixed value to align CD writeback addresses,
    parameter int unsigned ALIGN_SIZE = 0,
    /// Depth of FIFO that stores AW requests
    parameter int unsigned FIFO_DEPTH = 2
) (
    /// Clock
    input                               clk_i,
    /// Reset
    input                               rst_ni,
    /// Request channel towards cached master
    input  slv_req_t                    slv_req_i,
    /// Decoded snoop transaction
    /// Assumed to be valid when slv_req_i is valid
    input  acsnoop_t                    snoop_trs_i,
    /// Response channel towards cached master
    output slv_resp_t                   slv_resp_o,
    /// Request channel towards memory
    output mst_req_t                    mst_req_o,
    /// Response channel towards memory
    input  mst_resp_t                   mst_resp_i,
    /// Response channel towards snoop crossbar
    input  mst_snoop_resp_t             snoop_resp_i,
    /// Request channel towards snoop crossbar
    output mst_snoop_req_t              snoop_req_o,
    /// Domain masks set for the current AW initiator
    input  domain_set_t                 domain_set_i,
    /// Ax mask to be used for the snoop request
    output domain_mask_t                domain_mask_o,
    /// AW is a writeback request
    output logic                        aw_wb_o,
    /// B is a writeback response
    input  logic                        b_wb_i
);

/* WIP BEGIN */

logic slv_aw_valid, slv_aw_ready;
logic slv_b_valid, slv_b_ready;

logic wb_b_valid, wb_b_ready;

logic mst_b_valid, mst_b_ready;

logic mst_aw_fifo_valid_in, mst_aw_fifo_ready_in;
logic mst_aw_fifo_valid_out, mst_aw_fifo_ready_out;
mst_aw_chan_t mst_aw_fifo_in, mst_aw_fifo_out;

logic mst_w_fifo_valid_in, mst_w_fifo_ready_in;
logic mst_w_fifo_valid_out, mst_w_fifo_ready_out;
mst_w_chan_t mst_w_fifo_in, mst_w_fifo_out;

mst_aw_chan_t wb_aw;
mst_w_chan_t  wb_w;
logic wb_aw_valid, wb_aw_ready;
logic wb_w_valid, wb_w_ready;

mst_aw_chan_t mst_aw;
mst_w_chan_t  mst_w;
logic mst_aw_valid, mst_aw_ready;
logic mst_w_valid, mst_w_ready;

logic aw_sel;
logic aw_cnt_en, aw_cnt_clr;
logic aw_cnt;

logic w_sel;
logic w_cnt_en, w_cnt_clr;
logic w_cnt;

logic w_sel_fifo_in, w_sel_fifo_out;
logic w_sel_fifo_valid_in, w_sel_fifo_ready_in;
logic w_sel_fifo_valid_out, w_sel_fifo_ready_out;

logic ac_valid, ac_ready;
logic cr_valid, cr_ready;
logic cd_valid, cd_ready, cd_last;

logic cd_drop_fifo_in, cd_drop_fifo_out;
logic cd_drop_fifo_valid_in, cd_drop_fifo_ready_in;
logic cd_drop_fifo_valid_out, cd_drop_fifo_ready_out;
logic cd_drop;

logic mst_aw_mux_valid_out, mst_aw_mux_ready_out;
logic mst_w_mux_valid_out, mst_w_mux_ready_out;

stream_fork #(
    .N_OUP (2)
) i_aw_fork (
    .clk_i,
    .rst_ni,
    .valid_i (slv_aw_valid),
    .ready_o (slv_aw_ready),
    .valid_o ({mst_aw_fifo_valid_in, ac_valid}),
    .ready_i ({mst_aw_fifo_ready_in, ac_ready})
);

stream_fifo_optimal_wrap #(
    .Depth  (FIFO_DEPTH),
    .type_t (mst_aw_chan_t)
) i_mst_aw_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .usage_o    (),
    .valid_i    (mst_aw_fifo_valid_in),
    .ready_o    (mst_aw_fifo_ready_in),
    .data_i     (mst_aw_fifo_in),
    .valid_o    (mst_aw_fifo_valid_out),
    .ready_i    (mst_aw_fifo_ready_out),
    .data_o     (mst_aw_fifo_out)
);

stream_fifo #(
    .FALL_THROUGH (1'b1),
    .DEPTH        (FIFO_DEPTH),
    .T            (logic)
) i_aw_sel_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .usage_o    (),
    .data_i     (aw_sel_fifo_in),
    .valid_i    (aw_sel_fifo_valid_in),
    .ready_o    (aw_sel_fifo_ready_in),
    .data_o     (aw_sel_fifo_out),
    .valid_o    (aw_sel_fifo_valid_out),
    .ready_i    (aw_sel_fifo_ready_out && (aw_sel == 1'b0))
);

stream_mux #(
    .DATA_T    (mst_aw_chan_t),
    .N_INP     (2)
) i_mst_aw_mux (
    .inp_data_i  ({wb_aw, mst_aw_fifo_out}),
    .inp_valid_i ({wb_aw_valid, mst_aw_fifo_valid_out}),
    .inp_ready_o ({wb_aw_ready, mst_aw_fifo_ready_out}),
    .inp_sel_i   (aw_sel),
    .oup_data_o  (mst_aw),
    .oup_valid_o (mst_aw_mux_valid_out),
    .oup_ready_i (mst_aw_mux_ready_out)
);

counter #(
    .WIDTH (1)
) i_aw_cnt (
    .clk_i,
    .rst_ni,
    .clear_i    (aw_cnt_clr),
    .en_i       (aw_cnt_en),
    .load_i     ('0),
    .down_i     ('0),
    .d_i        ('0),
    .q_o        (aw_cnt),
    .overflow_o ()
);

assign aw_cnt_clr = (aw_sel == 1'b0) && mst_aw_mux_valid_out && mst_aw_mux_ready_out;
assign aw_cnt_en  = (aw_sel == 1'b1) && mst_aw_mux_valid_out && mst_aw_mux_ready_out;
assign aw_sel     = aw_cnt != aw_sel_fifo_out;
assign aw_wb_o    = aw_sel == 1'b1;

stream_join #(
    .N_INP (2)
) i_mst_aw_join (
    .inp_valid_i ({mst_aw_mux_valid_out, aw_sel_fifo_valid_out}),
    .inp_ready_o ({mst_aw_mux_ready_out, aw_sel_fifo_ready_out}),
    .oup_valid_o (mst_aw_valid),
    .oup_ready_i (mst_aw_ready)
);

stream_fifo #(
    .FALL_THROUGH (1'b1),
    .DEPTH        (FIFO_DEPTH),
    .T            (logic)
) i_w_sel_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .usage_o    (),
    .data_i     (w_sel_fifo_in),
    .valid_i    (w_sel_fifo_valid_in),
    .ready_o    (w_sel_fifo_ready_in),
    .data_o     (w_sel_fifo_out),
    .valid_o    (w_sel_fifo_valid_out),
    .ready_i    (w_sel_fifo_ready_out && mst_w.last && (w_sel == 1'b0))
);

stream_fifo_optimal_wrap #(
    .Depth  (FIFO_DEPTH),
    .type_t (mst_w_chan_t)
) i_mst_w_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .usage_o    (),
    .valid_i    (mst_w_fifo_valid_in),
    .ready_o    (mst_w_fifo_ready_in),
    .data_i     (mst_w_fifo_in),
    .valid_o    (mst_w_fifo_valid_out),
    .ready_i    (mst_w_fifo_ready_out),
    .data_o     (mst_w_fifo_out)
);

stream_mux #(
    .DATA_T    (mst_w_chan_t),
    .N_INP     (2)
) i_mst_w_mux (
    .inp_data_i  ({wb_w, mst_w_fifo_out}),
    .inp_valid_i ({wb_w_valid, mst_w_fifo_valid_out}),
    .inp_ready_o ({wb_w_ready, mst_w_fifo_ready_out}),
    .inp_sel_i   (w_sel),
    .oup_data_o  (mst_w),
    .oup_valid_o (mst_w_mux_valid_out),
    .oup_ready_i (mst_w_mux_ready_out)
);

counter #(
    .WIDTH (1)
) i_w_cnt (
    .clk_i,
    .rst_ni,
    .clear_i    (w_cnt_clr),
    .en_i       (w_cnt_en),
    .load_i     ('0),
    .down_i     ('0),
    .d_i        ('0),
    .q_o        (w_cnt),
    .overflow_o ()
);

assign w_cnt_clr = (w_sel == 1'b0) && mst_w_mux_valid_out && mst_w_mux_ready_out && mst_w.last;
assign w_cnt_en  = (w_sel == 1'b1) && mst_w_mux_valid_out && mst_w_mux_ready_out && mst_w.last;
assign w_sel     = w_cnt != w_sel_fifo_out;

stream_join #(
    .N_INP (2)
) i_mst_w_join (
    .inp_valid_i ({mst_w_mux_valid_out, w_sel_fifo_valid_out}),
    .inp_ready_o ({mst_w_mux_ready_out, w_sel_fifo_ready_out}),
    .oup_valid_o (mst_w_valid),
    .oup_ready_i (mst_w_ready)
);

stream_fork_dynamic #(
    .N_OUP (3)
) i_cr_fork (
    .clk_i,
    .rst_ni,
    .valid_i     (cr_valid),
    .ready_o     (cr_ready),
    .sel_valid_i ('1),
    .sel_ready_o (),
    .sel_i       ({2'b11, cd_drop_fifo_in}),
    .valid_o     ({aw_sel_fifo_valid_in, w_sel_fifo_valid_in, cd_drop_fifo_valid_in}),
    .ready_i     ({aw_sel_fifo_ready_in, w_sel_fifo_ready_in, cd_drop_fifo_ready_in})
);

assign {aw_sel_fifo_in, w_sel_fifo_in} =
{2{snoop_resp_i.cr_resp.DataTransfer && snoop_resp_i.cr_resp.PassDirty}};

assign wb_aw_valid = mst_aw_fifo_valid_out;
// wb_w_ready unused

// Write-back AW channel
always_comb begin
    `AXI_SET_AW_STRUCT(wb_aw, mst_aw_fifo_out)
    wb_aw.addr  = axi_pkg::aligned_addr(mst_aw_fifo_out.addr, ALIGN_SIZE);
    wb_aw.burst = axi_pkg::BURST_WRAP;
    wb_aw.len   = AXLEN;
    wb_aw.size  = AXSIZE;
    wb_aw.atop  = '0;
    wb_aw.lock  = '0;
end

assign cd_drop_fifo_in = snoop_resp_i.cr_resp.DataTransfer && !snoop_resp_i.cr_resp.PassDirty;

stream_fifo #(
    .FALL_THROUGH (1'b1),
    .DEPTH        (FIFO_DEPTH),
    .T            (logic)
) i_cd_drop_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .usage_o    (),
    .data_i     (cd_drop_fifo_in),
    .valid_i    (cd_drop_fifo_valid_in),
    .ready_o    (cd_drop_fifo_ready_in),
    .data_o     (cd_drop_fifo_out),
    .valid_o    (cd_drop_fifo_valid_out),
    .ready_i    (cd_drop_fifo_ready_out)
);

assign cd_last                = snoop_resp_i.cd.last;
assign cd_drop_fifo_ready_out = cd_valid && cd_ready && cd_last;
assign cd_drop                = cd_drop_fifo_valid_out && cd_drop_fifo_out;

stream_filter i_cd_filter (
    .valid_i (cd_valid),
    .ready_o (cd_ready),
    .drop_i  (cd_drop),
    .valid_o (wb_w_valid),
    .ready_i (wb_w_ready)
);

// Write-back W channel
assign wb_w.data = snoop_resp_i.cd.data;
assign wb_w.strb = '1;
assign wb_w.last = snoop_resp_i.cd.last;
assign wb_w.user = '0;

// Write-back B channel
assign wb_b_ready = 1'b1;
// wb_b_valid unused

stream_demux #(
  .N_OUP (2)
) i_b_demux (
    .inp_valid_i (mst_b_valid),
    .inp_ready_o (mst_b_ready),
    .oup_sel_i   (b_wb_i),
    .oup_valid_o ({wb_b_valid, slv_b_valid}),
    .oup_ready_i ({wb_b_ready, slv_b_ready})
);

//////////////
// Channels //
//////////////

/* SLV INTF */

// AR
assign slv_resp_o.ar_ready = 1'b0;
// R
assign slv_resp_o.r_valid = mst_resp_i.r_valid;
assign mst_req_o.r_ready  = slv_req_i.r_ready;
`AXI_TO_ACE_ASSIGN_R_STRUCT(slv_resp_o.r, mst_resp_i.r)
// AW
assign slv_resp_o.aw_ready = slv_aw_ready;
assign slv_aw_valid        = slv_req_i.aw_valid;
`AXI_ASSIGN_AW_STRUCT(mst_aw_fifo_in, slv_req_i.aw)
// W
assign slv_resp_o.w_ready  = mst_w_fifo_ready_in;
assign mst_w_fifo_valid_in = slv_req_i.w_valid;
`AXI_ASSIGN_W_STRUCT(mst_w_fifo_in, slv_req_i.w)
// B
assign slv_resp_o.b_valid = slv_b_valid;
assign slv_b_ready        = slv_req_i.b_ready;
`AXI_ASSIGN_B_STRUCT(slv_resp_o.b, mst_resp_i.b)

/* SNP INTF */

// AC
assign snoop_req_o.ac_valid = ac_valid;
assign ac_ready             = snoop_resp_i.ac_ready;
assign snoop_req_o.ac.addr  = slv_req_i.aw.addr;
assign snoop_req_o.ac.snoop = snoop_trs_i;
assign snoop_req_o.ac.prot  = slv_req_i.aw;

// CR
assign snoop_req_o.cr_ready = cr_ready;
assign cr_valid             = snoop_resp_i.cr_valid;

// CD
assign snoop_req_o.cd_ready = cd_ready;
assign cd_valid             = snoop_resp_i.cd_valid;

/* MST INTF */

// AR
assign mst_req_o.ar_valid = '0;
assign mst_req_o.ar       = '0;

// R
// passthrough from slv intf

// AW
assign mst_req_o.aw_valid  = mst_aw_valid;
assign mst_aw_ready        = mst_resp_i.aw_ready;
`AXI_ASSIGN_AW_STRUCT(mst_req_o.aw, mst_aw)

// W
assign mst_req_o.w_valid = mst_w_valid;
assign mst_w_ready       = mst_resp_i.w_ready;
`AXI_ASSIGN_W_STRUCT(mst_req_o.w, mst_w)

// B
assign mst_b_valid       = mst_resp_i.b_valid;
assign mst_req_o.b_ready = mst_b_ready;

// Domain mask generation
// Note: this signal should flow along with AC
always_comb begin
    domain_mask_o = '0;
    case (slv_req_i.aw.domain)
      NonShareable:   domain_mask_o = 0;
      InnerShareable: domain_mask_o = domain_set_i.inner;
      OuterShareable: domain_mask_o = domain_set_i.outer;
      System:         domain_mask_o = ~domain_set_i.initiator;
    endcase
end

endmodule
