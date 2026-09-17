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

//! R channel arbiter with burst locking
//
//  Round-robin arbiter locking onto a burst: once a beat wins, the other
//  inputs are masked until the last beat. `r_t` must have a `last` field.
module ccu_r_arbiter #(
    parameter  int unsigned numInputs = 0,
    parameter  type         r_t       = logic,
    localparam int unsigned idxWidth  = numInputs > 1 ? $clog2(numInputs) : 1
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [numInputs-1:0] valid_i,
    output logic [numInputs-1:0] ready_o,
    input  r_t   [numInputs-1:0] r_i,

    output logic                 valid_o,
    input  logic                 ready_i,
    output r_t                   r_o,
    output logic [idxWidth-1:0]  idx_o
);

    logic [numInputs-1:0] arb_valid;
    logic [numInputs-1:0] arb_ready;
    logic [numInputs-1:0] mask_d, mask_q;

    assign arb_valid = valid_i   & ~mask_q;
    assign ready_o   = arb_ready & ~mask_q;

    always_comb begin : mask_comb
        mask_d = mask_q;
        if (valid_o && ready_i && r_o.last)
            mask_d = '0;
        else if (valid_o && ready_i)
            mask_d = ~(arb_valid & arb_ready);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) mask_q <= '0;
        else         mask_q <= mask_d;
    end

    rr_arb_tree #(
        .NumIn     (numInputs),
        .DataType  (r_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (arb_valid),
        .gnt_o   (arb_ready),
        .data_i  (r_i),
        .req_o   (valid_o),
        .gnt_i   (ready_i),
        .data_o  (r_o),
        .idx_o   (idx_o)
    );

endmodule
