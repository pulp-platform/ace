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

module ace_ccu_read
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg       = '{default: '0},
    parameter type          midend_ax_t  = logic,
    parameter type          tid_t        = logic,
    parameter type          backend_ar_t = logic,
    parameter type          backend_r_t  = logic,
    parameter type          midend_r_t   = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // Ctrl
    input  logic       valid_i,
    output logic       ready_o,
    input  midend_ax_t ax_i,

    // Snp interface
    input  midend_r_t cd_r_i,
    input  logic      cd_r_valid_i,
    output logic      cd_r_ready_o,

    // Slv interface
    output midend_r_t   r_o,
    output logic        r_valid_o,
    input  logic        r_ready_i,
    // Mst interface
    output backend_ar_t ar_o,
    output logic        ar_valid_o,
    input  logic        ar_ready_i,
    input  backend_r_t  r_i,
    input  logic        r_valid_i,
    output logic        r_ready_o
);

    backend_ar_t ar_sync_wdata;
    midend_r_t   mem_r;

    //  AR channel
    //  {{{
    `AXI_ASSIGN_AR_STRUCT(ar_sync_wdata, ax_i)

    fall_through_register #(
        .T(backend_ar_t)
    ) u_ar_sync_reg (
        .clk_i,
        .rst_ni,
        .clr_i     (1'b0),
        .testmode_i(1'b0),
        .valid_i   (valid_i),
        .ready_o   (ready_o),
        .data_i    (ar_sync_wdata),
        .valid_o   (ar_valid_o),
        .ready_i   (ar_ready_i),
        .data_o    (ar_o)
    );
    //  }}}

    //  R channel
    //  {{{
    `AXI_TO_ACE_ASSIGN_R_STRUCT(mem_r, r_i)

    rr_arb_tree #(
        .NumIn    (2),
        .DataType (midend_r_t),
        .AxiVldRdy(1'b1),
        .LockIn   (1'b1)
    ) u_r_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .rr_i   (1'b0),
        .req_i  ({r_valid_i, cd_r_valid_i}),
        .gnt_o  ({r_ready_o, cd_r_ready_o}),
        .data_i ({mem_r, cd_r_i}),
        .req_o  (r_valid_o),
        .gnt_i  (r_ready_i),
        .data_o (r_o),
        .idx_o  ()
    );
    //  }}}



endmodule
