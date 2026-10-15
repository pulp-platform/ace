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

//  Ordered fork: the selected outputs take the input one at a time, in index order
module stream_iterator #(
    parameter int unsigned N_OUP     = 32'd2,
    /// Dependent parameter, do not override
    parameter int unsigned IDX_WIDTH = (N_OUP > 32'd1) ? unsigned'($clog2(N_OUP)) : 32'd1
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic             valid_i,
    output logic             ready_o,
    input  logic [N_OUP-1:0] sel_i,
    output logic [N_OUP-1:0] valid_o,
    input  logic [N_OUP-1:0] ready_i
);

    logic [IDX_WIDTH-1:0] cnt_q, idx;
    logic [N_OUP-1:0]     pending;
    logic                 none, oup_ready, oup_hs, last;

    //  Selected outputs not yet served
    for (genvar i = 0; i < N_OUP; i++) begin : gen_pending
        assign pending[i] = sel_i[i] && IDX_WIDTH'(i) >= cnt_q;
    end

    lzc #(
        .WIDTH (N_OUP),
        .MODE  (1'b0)
    ) u_lzc (
        .in_i    (pending),
        .cnt_o   (idx),
        .empty_o (none)
    );

    stream_demux #(
        .N_OUP (N_OUP)
    ) u_demux (
        .inp_valid_i (valid_i && !none),
        .inp_ready_o (oup_ready),
        .oup_sel_i   (idx),
        .oup_valid_o (valid_o),
        .oup_ready_i (ready_i)
    );

    assign oup_hs  = valid_i && !none && oup_ready;
    assign last    = pending == (N_OUP'(1) << idx);
    assign ready_o = none || (oup_hs && last);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)                 cnt_q <= '0;
        else if (valid_i && ready_o) cnt_q <= '0;
        else if (oup_hs)             cnt_q <= idx + 1'b1;
    end

    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        valid_i && !ready_o |=> valid_i && $stable(sel_i))
        else $error("input withdrawn or selection changed during an iteration");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        !valid_i |-> cnt_q == '0)
        else $error("iteration left unfinished");

    initial assert (N_OUP > 0) else $fatal(1, "N_OUP must be at least 1");
    `endif
    // pragma translate_on

endmodule
