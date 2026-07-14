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

    //  Initiator R towards the frontend
    output logic                                r_valid_o,
    input  logic                                r_ready_i,
    output ccu_ace_r_t                          r_o,

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

//  R channel: arbitrate memory reads and snoop-pipeline responses
//  {{{
    ccu_ace_r_t r_mem;
    logic [1:0] r_arbiter_valid;
    logic [1:0] r_arbiter_ready;
    logic [1:0] mask_d;
    logic [1:0] mask_q;

    `AXI_TO_ACE_ASSIGN_R_STRUCT(r_mem, r_i)

    assign r_arbiter_valid = {r_valid_i, snoop_pipeline_r_valid_i} & ~mask_q;
    assign {r_ready_o, snoop_pipeline_r_ready_o} = r_arbiter_ready & ~mask_q;

    always_comb begin : mask_comb
        mask_d = mask_q;
        if (r_valid_o && r_ready_i && r_o.last)
            mask_d = '0;
        else if (r_valid_o && r_ready_i)
            mask_d = ~(r_arbiter_valid & r_arbiter_ready);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) mask_q <= '0;
        else         mask_q <= mask_d;
    end

    rr_arb_tree #(
        .NumIn     (2),
        .DataType  (ccu_ace_r_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_r_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (r_arbiter_valid),
        .gnt_o   (r_arbiter_ready),
        .data_i  ({r_mem, snoop_pipeline_r_i}),
        .req_o   (r_valid_o),
        .gnt_i   (r_ready_i),
        .data_o  (r_o),
        .idx_o   ()
    );
//  }}}
endmodule
