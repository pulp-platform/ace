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
//
// Authors:
// - Riccardo Tedeschi <riccardo.tedeschi6@unibo.it>

`include "axi/assign.svh"
`include "ace/convert.svh"

module ccu_read_engine
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg       = '{default: '0},
    parameter type         ccu_axi_ar_t = logic,
    parameter type         ccu_ace_r_t  = logic,
    parameter type         ccu_axi_r_t  = logic
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    //  Read request from the snoop pipeline (already hazard-free)
    input  logic                                ar_valid_i,
    output logic                                ar_ready_o,
    input  ccu_axi_ar_t                         ar_i,

    //  Initiator R sourced by the snoop pipeline (read data and acks)
    input  logic                                snoop_pipeline_r_valid_i,
    output logic                                snoop_pipeline_r_ready_o,
    input  ccu_ace_r_t                          snoop_pipeline_r_i,

    //  SC fail responses from the exclusive monitor
    input  logic                                sc_fail_r_valid_i,
    output logic                                sc_fail_r_ready_o,
    input  ccu_ace_r_t                          sc_fail_r_i,

    //  Initiator R towards the frontend
    output logic                                r_valid_o,
    input  logic                                r_ready_i,
    output ccu_ace_r_t                          r_o,
    output logic                                r_sc_fail_o,

    //  Memory AR/R
    output logic                                ar_valid_o,
    input  logic                                ar_ready_i,
    output ccu_axi_ar_t                         ar_o,
    input  logic                                r_valid_i,
    output logic                                r_ready_o,
    input  ccu_axi_r_t                          r_i
);

//  AR channel: straight through to memory
//  {{{
    assign ar_valid_o = ar_valid_i;
    assign ar_ready_o = ar_ready_i;
    `AXI_ASSIGN_AR_STRUCT(ar_o, ar_i)
//  }}}

//  R channel: arbitrate memory reads, snoop-pipeline responses and SC fails
//  {{{
    ccu_ace_r_t r_mem;
    logic [1:0] r_idx;

    `AXI_TO_ACE_ASSIGN_R_STRUCT(r_mem, r_i)

    ccu_r_arbiter #(
        .numInputs (3),
        .r_t       (ccu_ace_r_t)
    ) u_r_arbiter (
        .clk_i,
        .rst_ni,
        .valid_i ({sc_fail_r_valid_i, r_valid_i, snoop_pipeline_r_valid_i}),
        .ready_o ({sc_fail_r_ready_o, r_ready_o, snoop_pipeline_r_ready_o}),
        .r_i     ({sc_fail_r_i,       r_mem,     snoop_pipeline_r_i}),
        .valid_o (r_valid_o),
        .ready_i (r_ready_i),
        .r_o     (r_o),
        .idx_o   (r_idx)
    );

    assign r_sc_fail_o = r_idx == 2'd2;
//  }}}
endmodule
