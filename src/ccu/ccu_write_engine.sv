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

module ccu_write_engine
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg       = '{default: '0},
    parameter type         ccu_axi_aw_t = logic,
    parameter type         ccu_w_t      = logic,
    parameter type         ccu_axi_b_t  = logic
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    input  logic                                aw_valid_i,
    output logic                                aw_ready_o,
    input  ccu_axi_aw_t                         aw_i,
    input  logic                                w_valid_i,
    output logic                                w_ready_o,
    input  ccu_w_t                              w_i,
    output logic                                b_valid_o,
    input  logic                                b_ready_i,
    output ccu_axi_b_t                          b_o,

    input  logic                                writeback_aw_valid_i,
    output logic                                writeback_aw_ready_o,
    input  ccu_axi_aw_t                         writeback_aw_i,
    input  logic                                writeback_w_valid_i,
    output logic                                writeback_w_ready_o,
    input  ccu_w_t                              writeback_w_i,

    output logic                                aw_valid_o,
    input  logic                                aw_ready_i,
    output ccu_axi_aw_t                         aw_o,
    output logic                                w_valid_o,
    input  logic                                w_ready_i,
    output ccu_w_t                              w_o,
    input  logic                                b_valid_i,
    output logic                                b_ready_o,
    input  ccu_axi_b_t                          b_i,

    input  logic                                read_engine_addr_check_i,
    output logic                                read_engine_addr_hit_o,
    input  logic [ccuCfg.addressCheckWidth-1:0] read_engine_addr_slice_i
);

//  Inflight addresses associative map
//  {{{
    logic [ccuCfg.addressCheckWidth-1:0] write_inflight_map_wdata;
    logic                                write_inflight_map_push;
    logic                                write_inflight_map_pop;
    logic                                write_inflight_map_full;

    assign write_inflight_map_wdata = aw_o.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
    assign write_inflight_map_push  = aw_valid_o && aw_ready_i;
    assign write_inflight_map_pop   = b_valid_i && b_ready_o;

    id_queue #(
        .ID_WIDTH            (ccuCfg.axiManagerIdWidth),
        .CAPACITY            (ccuCfg.u.numWriteTransactions),
        .FULL_BW             (1'b1),
        .CUT_OUP_POP_INP_GNT (1'b1),
        .NUM_CMP_PORTS       (1),
        .data_t              (logic [ccuCfg.addressCheckWidth-1:0])
    ) u_write_inflight_map (
        .clk_i,
        .rst_ni,
        .inp_id_i         (aw_o.id),
        .inp_data_i       (write_inflight_map_wdata),
        .inp_req_i        (write_inflight_map_push),
        .inp_gnt_o        (),
        .exists_data_i    (read_engine_addr_slice_i),
        .exists_mask_i    ('1),
        .exists_req_i     (read_engine_addr_check_i),
        .exists_o         (read_engine_addr_hit_o),
        .exists_gnt_o     (),
        .oup_id_i         (b_i.id),
        .oup_pop_i        (1'b1),
        .oup_req_i        (write_inflight_map_pop),
        .oup_data_o       (),
        .oup_data_valid_o (),
        .oup_gnt_o        (),
        .full_o           (write_inflight_map_full),
        .empty_o          ()
    );
//  }}}

//  AW channel
//  {{{

    logic w_ctrl_fifo_valid_in;
    logic w_ctrl_fifo_ready_in;
    logic aw_is_writeback;

    rr_arb_tree #(
        .NumIn     (2),
        .DataType  (ccu_axi_aw_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_aw_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   ({writeback_aw_valid_i, aw_valid_i}),
        .gnt_o   ({writeback_aw_ready_o, aw_ready_o}),
        .data_i  ({writeback_aw_i      , aw_i      }),
        .req_o   (aw_valid),
        .gnt_i   (aw_ready),
        .data_o  (aw_o),
        .idx_o   (aw_is_writeback)
    );

    stream_fork_dynamic #(
        .N_OUP(2)
    ) u_aw_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (aw_valid),
        .ready_o     (aw_ready),
        .sel_i       ('1),
        .sel_valid_i (!write_inflight_map_full),
        .sel_ready_o (),
        .valid_o     ({aw_valid_o, w_ctrl_fifo_valid_in}),
        .ready_i     ({aw_ready_i, w_ctrl_fifo_ready_in})
    );
//  }}}

//  W muxing
//  {{{
    logic w_ctrl_fifo_valid_out;
    logic w_ctrl_fifo_ready_out;
    logic w_is_writeback;
    logic w_mux_valid_out;
    logic w_mux_ready_out;

    stream_fifo #(
        .FALL_THROUGH(1'b1),
        .DATA_WIDTH  (1),
        .DEPTH       (2)
    ) u_w_ctrl_fifo (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .usage_o   (),
        .data_i    (aw_is_writeback),
        .valid_i   (w_ctrl_fifo_valid_in),
        .ready_o   (w_ctrl_fifo_ready_in),
        .data_o    (w_is_write_back),
        .valid_o   (w_ctrl_fifo_valid_out),
        .ready_i   (w_ctrl_fifo_ready_out && w_o.last)
    );

    stream_mux #(
        .DATA_T(ccu_w_t),
        .N_INP (2)
    ) u_w_mux (
        .inp_data_i ({writeback_w_i      , w_i}),
        .inp_valid_i({writeback_w_valid_i, w_valid_i}),
        .inp_ready_o({writeback_w_ready_o, w_ready_o}),
        .inp_sel_i  (w_is_write_back),
        .oup_data_o (w_o),
        .oup_valid_o(w_mux_valid_out),
        .oup_ready_i(w_mux_ready_out)
    );

    stream_join #(
        .N_INP(2)
    ) u_w_join (
        .inp_valid_i({w_ctrl_fifo_valid_out, w_mux_valid_out}),
        .inp_ready_o({w_ctrl_fifo_ready_out, w_mux_ready_out}),
        .oup_valid_o(w_valid_o),
        .oup_ready_i(w_ready_i)
    );
//  }}}

//  B channel filtering
//  {{{
    logic b_is_write_back;

    //  The additional ID bit is used to uniquely identify
    //  writeback operations
    //  TODO: this might be overkill?
    assign b_is_write_back = b_i.id[ccuCfg.axiCcuIdWidth];

    stream_filter u_b_filter (
        .valid_i(b_valid_i),
        .ready_o(b_ready_o),
        .drop_i (b_is_write_back),
        .valid_o(b_valid_o),
        .ready_i(b_ready_i)
    );

    `AXI_ASSIGN_B_STRUCT(b_o, b_i)
//  }}}
endmodule
