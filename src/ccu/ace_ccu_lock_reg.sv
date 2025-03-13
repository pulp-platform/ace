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

module ace_ccu_lock_reg #(
    parameter type dtype = logic
)(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic valid_i,
    output logic ready_o,
    input  dtype data_i,

    output logic valid_o,
    input  logic ready_i,
    output dtype data_o
);

logic clear_lock, set_lock;

logic lock_q, lock_d;
dtype data_q, data_d;

assign valid_o    = valid_i || lock_q;
assign ready_o    = (valid_o && ready_i) || !lock_q;
assign set_lock   = valid_i && (!ready_i || lock_q);
assign clear_lock = valid_o && ready_i;
assign lock_d     = set_lock || (!clear_lock && lock_q);
assign data_d     = valid_i && ready_o ? data_i : data_q;
assign data_o     = lock_q ? data_q : data_i;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        lock_q <= 1'b0;
        data_q <= dtype'('0);
    end else begin
        lock_q <= lock_d;
        data_q <= data_d;
    end
end

endmodule
