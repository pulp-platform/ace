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

//! Optional register on a channel its sink always accepts
//
//  No ready to carry, so a flop where a spill register would need two.
module ccu_pulse_cut #(
    parameter bit  Bypass = 1'b0,
    parameter type T      = logic
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic valid_i,
    input  T     data_i,
    output logic valid_o,
    output T     data_o
);

    if (Bypass) begin : gen_bypass
        assign valid_o = valid_i;
        assign data_o  = data_i;
    end else begin : gen_cut
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                valid_o <= 1'b0;
                data_o  <= '0;
            end else begin
                valid_o <= valid_i;
                data_o  <= data_i;
            end
        end
    end

endmodule
