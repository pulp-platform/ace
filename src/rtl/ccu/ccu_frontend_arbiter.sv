// Copyright (c) 2026 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Authors:
// - Riccardo Tedeschi <riccardo.tedeschi6@unibo.it>

module ccu_frontend_arbiter
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter int unsigned numSubordinates = 0,
    parameter int unsigned aceSubordinateIdWidth = 0,
    parameter int unsigned maxWTrans = 0,
    parameter int unsigned fallThrough = 0,

    parameter type ccu_ace_manager_ar_t   = logic,
    parameter type ccu_ace_manager_aw_t   = logic,
    parameter type ccu_w_t                = logic,
    parameter type ccu_ace_manager_r_t    = logic,
    parameter type ccu_ace_manager_b_t    = logic,
    parameter type ccu_ace_manager_req_t  = logic,
    parameter type ccu_ace_manager_resp_t = logic,

    parameter type ccu_ace_subordinate_ar_t   = logic,
    parameter type ccu_ace_subordinate_aw_t   = logic,
    parameter type ccu_ace_subordinate_r_t    = logic,
    parameter type ccu_ace_subordinate_b_t    = logic,
    parameter type ccu_ace_subordinate_req_t  = logic,
    parameter type ccu_ace_subordinate_resp_t = logic

) (
    input  logic clk_i,
    input  logic rst_ni,

    input  ccu_ace_subordinate_req_t  [numSubordinates-1:0] subordinate_req_i,
    output ccu_ace_subordinate_resp_t [numSubordinates-1:0] subordinate_resp_o,
    output ccu_ace_manager_req_t                                     manager_req_o,
    input  ccu_ace_manager_resp_t                                    manager_resp_i
);

localparam int unsigned subordinateIndexWidth = numSubordinates > 1 ? $clog2(numSubordinates) : 1;
localparam int unsigned aceManagerIdWidth     = subordinateIndexWidth + aceSubordinateIdWidth;

ccu_ace_manager_aw_t [numSubordinates-1:0] subordinate_aw;
logic                [numSubordinates-1:0] subordinate_aw_valid;
logic                [numSubordinates-1:0] subordinate_aw_ready;
ccu_w_t              [numSubordinates-1:0] subordinate_w;
logic                [numSubordinates-1:0] subordinate_w_valid;
logic                [numSubordinates-1:0] subordinate_w_ready;
ccu_ace_manager_b_t  [numSubordinates-1:0] subordinate_b;
logic                [numSubordinates-1:0] subordinate_b_valid;
logic                [numSubordinates-1:0] subordinate_b_ready;
ccu_ace_manager_ar_t [numSubordinates-1:0] subordinate_ar;
logic                [numSubordinates-1:0] subordinate_ar_valid;
logic                [numSubordinates-1:0] subordinate_ar_ready;
ccu_ace_manager_r_t  [numSubordinates-1:0] subordinate_r;
logic                [numSubordinates-1:0] subordinate_r_valid;
logic                [numSubordinates-1:0] subordinate_r_ready;

logic aw_arbiter_valid;
logic aw_arbiter_ready;

for (genvar s = 0; s < numSubordinates; s++) begin : gen_id_prepend

    axi_id_prepend #(
        .NoBus             (32'd1),
        .AxiIdWidthSlvPort (aceSubordinateIdWidth),
        .AxiIdWidthMstPort (aceManagerIdWidth),
        .slv_aw_chan_t     (ccu_ace_subordinate_aw_t),
        .slv_w_chan_t      (ccu_w_t),
        .slv_b_chan_t      (ccu_ace_subordinate_b_t),
        .slv_ar_chan_t     (ccu_ace_subordinate_ar_t),
        .slv_r_chan_t      (ccu_ace_subordinate_r_t),
        .mst_aw_chan_t     (ccu_ace_manager_aw_t),
        .mst_w_chan_t      (ccu_w_t),
        .mst_b_chan_t      (ccu_ace_manager_b_t),
        .mst_ar_chan_t     (ccu_ace_manager_ar_t),
        .mst_r_chan_t      (ccu_ace_manager_r_t)
    ) u_id_prepend (
        .pre_id_i         (subordinateIndexWidth'(s)),
        .slv_aw_chans_i   (subordinate_req_i[s].aw),
        .slv_aw_valids_i  (subordinate_req_i[s].aw_valid),
        .slv_aw_readies_o (subordinate_resp_o[s].aw_ready),
        .slv_w_chans_i    (subordinate_req_i[s].w),
        .slv_w_valids_i   (subordinate_req_i[s].w_valid),
        .slv_w_readies_o  (subordinate_resp_o[s].w_ready),
        .slv_b_chans_o    (subordinate_resp_o[s].b),
        .slv_b_valids_o   (subordinate_resp_o[s].b_valid),
        .slv_b_readies_i  (subordinate_req_i[s].b_ready),
        .slv_ar_chans_i   (subordinate_req_i[s].ar),
        .slv_ar_valids_i  (subordinate_req_i[s].ar_valid),
        .slv_ar_readies_o (subordinate_resp_o[s].ar_ready),
        .slv_r_chans_o    (subordinate_resp_o[s].r),
        .slv_r_valids_o   (subordinate_resp_o[s].r_valid),
        .slv_r_readies_i  (subordinate_req_i[s].r_ready),
        .mst_aw_chans_o   (subordinate_aw[s]),
        .mst_aw_valids_o  (subordinate_aw_valid[s]),
        .mst_aw_readies_i (subordinate_aw_ready[s]),
        .mst_w_chans_o    (subordinate_w[s]),
        .mst_w_valids_o   (subordinate_w_valid[s]),
        .mst_w_readies_i  (subordinate_w_ready[s]),
        .mst_b_chans_i    (subordinate_b[s]),
        .mst_b_valids_i   (subordinate_b_valid[s]),
        .mst_b_readies_o  (subordinate_b_ready[s]),
        .mst_ar_chans_o   (subordinate_ar[s]),
        .mst_ar_valids_o  (subordinate_ar_valid[s]),
        .mst_ar_readies_i (subordinate_ar_ready[s]),
        .mst_r_chans_i    (subordinate_r[s]),
        .mst_r_valids_i   (subordinate_r_valid[s]),
        .mst_r_readies_o  (subordinate_r_ready[s])
    );
end

//  AW
//  {{{
    logic                             w_ctrl_fifo_valid_in;
    logic                             w_ctrl_fifo_ready_in;
    logic [subordinateIndexWidth-1:0] w_ctrl_fifo_wdata;
    logic                             aw_is_evict;

    rr_arb_tree #(
        .NumIn     (numSubordinates),
        .DataType  (ccu_ace_manager_aw_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_aw_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (subordinate_aw_valid),
        .gnt_o   (subordinate_aw_ready),
        .data_i  (subordinate_aw),
        .req_o   (aw_arbiter_valid),
        .gnt_i   (aw_arbiter_ready),
        .data_o  (manager_req_o.aw),
        .idx_o   (w_ctrl_fifo_wdata)
    );

    assign aw_is_evict = ace_is_evict(manager_req_o.aw.bar[0], manager_req_o.aw.domain, manager_req_o.aw.snoop);

    stream_fork_dynamic #(
        .N_OUP(2)
    ) u_aw_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (aw_arbiter_valid),
        .ready_o     (aw_arbiter_ready),
        .sel_i       ({!aw_is_evict, 1'b1}),
        .sel_valid_i (1'b1),
        .sel_ready_o (),
        .valid_o     ({w_ctrl_fifo_valid_in, manager_req_o.aw_valid}),
        .ready_i     ({w_ctrl_fifo_ready_in, manager_resp_i.aw_ready})
    );
//  }}}

//  W
//  {{{
    logic                             w_ctrl_fifo_valid_out;
    logic                             w_ctrl_fifo_ready_out;
    logic [subordinateIndexWidth-1:0] w_ctrl_fifo_rdata;
    logic                             w_mux_valid_out;
    logic                             w_mux_ready_out;

    stream_fifo #(
        .FALL_THROUGH(fallThrough),
        .DATA_WIDTH  (subordinateIndexWidth),
        .DEPTH       (maxWTrans)
    ) u_w_ctrl_fifo (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .usage_o   (),
        .data_i    (w_ctrl_fifo_wdata),
        .valid_i   (w_ctrl_fifo_valid_in),
        .ready_o   (w_ctrl_fifo_ready_in),
        .data_o    (w_ctrl_fifo_rdata),
        .valid_o   (w_ctrl_fifo_valid_out),
        .ready_i   (w_ctrl_fifo_ready_out && manager_req_o.w.last)
    );

    stream_mux #(
        .DATA_T(ccu_w_t),
        .N_INP (numSubordinates)
    ) u_w_mux (
        .inp_data_i (subordinate_w),
        .inp_valid_i(subordinate_w_valid),
        .inp_ready_o(subordinate_w_ready),
        .inp_sel_i  (w_ctrl_fifo_rdata),
        .oup_data_o (manager_req_o.w),
        .oup_valid_o(w_mux_valid_out),
        .oup_ready_i(w_mux_ready_out)
    );

    stream_join #(
        .N_INP(2)
    ) u_w_join (
        .inp_valid_i({w_ctrl_fifo_valid_out, w_mux_valid_out}),
        .inp_ready_o({w_ctrl_fifo_ready_out, w_mux_ready_out}),
        .oup_valid_o(manager_req_o.w_valid),
        .oup_ready_i(manager_resp_i.w_ready)
    );
//  }}}

//  B
//  {{{
logic [subordinateIndexWidth-1:0] b_demux_sel;

assign b_demux_sel = manager_resp_i.b.id[aceManagerIdWidth-1:aceSubordinateIdWidth];

stream_demux #(
  .N_OUP (numSubordinates)
) u_b_demux (
  .inp_valid_i (manager_resp_i.b_valid),
  .inp_ready_o (manager_req_o.b_ready),
  .oup_sel_i   (b_demux_sel),
  .oup_valid_o (subordinate_b_valid),
  .oup_ready_i (subordinate_b_ready)
);

assign subordinate_b = {numSubordinates{manager_resp_i.b}};
//  }}}

//  AR
//  {{{
    rr_arb_tree #(
        .NumIn     (numSubordinates),
        .DataType  (ccu_ace_manager_ar_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_ar_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (subordinate_ar_valid),
        .gnt_o   (subordinate_ar_ready),
        .data_i  (subordinate_ar),
        .req_o   (manager_req_o.ar_valid),
        .gnt_i   (manager_resp_i.ar_ready),
        .data_o  (manager_req_o.ar),
        .idx_o   ()
    );
//  }}}

//  R
//  {{{
logic [subordinateIndexWidth-1:0] r_demux_sel;

assign r_demux_sel = manager_resp_i.r.id[aceManagerIdWidth-1:aceSubordinateIdWidth];

stream_demux #(
  .N_OUP (numSubordinates)
) u_r_demux (
  .inp_valid_i (manager_resp_i.r_valid),
  .inp_ready_o (manager_req_o.r_ready),
  .oup_sel_i   (r_demux_sel),
  .oup_valid_o (subordinate_r_valid),
  .oup_ready_i (subordinate_r_ready)
);

assign subordinate_r = {numSubordinates{manager_resp_i.r}};
//  }}}


endmodule
