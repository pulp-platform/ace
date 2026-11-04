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

//! ACE cut
//
//  A register on each of the five channels, each one bypassable on its own.
module ace_cut #(
    parameter bit  Bypass    = 1'b0,
    parameter bit  BypassAw  = Bypass,
    parameter bit  BypassW   = Bypass,
    parameter bit  BypassB   = Bypass,
    parameter bit  BypassAr  = Bypass,
    parameter bit  BypassR   = Bypass,
    parameter type aw_chan_t = logic,
    parameter type w_chan_t  = logic,
    parameter type b_chan_t  = logic,
    parameter type ar_chan_t = logic,
    parameter type r_chan_t  = logic,
    parameter type req_t     = logic,
    parameter type resp_t    = logic
) (
    input  logic  clk_i,
    input  logic  rst_ni,
    //  Toward the requester
    input  req_t  req_i,
    output resp_t resp_o,
    //  Toward the responder
    output req_t  req_o,
    input  resp_t resp_i
);

    spill_register #(
        .T      (aw_chan_t),
        .Bypass (BypassAw)
    ) u_aw (
        .clk_i,
        .rst_ni,
        .valid_i (req_i.aw_valid),
        .ready_o (resp_o.aw_ready),
        .data_i  (req_i.aw),
        .valid_o (req_o.aw_valid),
        .ready_i (resp_i.aw_ready),
        .data_o  (req_o.aw)
    );

    spill_register #(
        .T      (w_chan_t),
        .Bypass (BypassW)
    ) u_w (
        .clk_i,
        .rst_ni,
        .valid_i (req_i.w_valid),
        .ready_o (resp_o.w_ready),
        .data_i  (req_i.w),
        .valid_o (req_o.w_valid),
        .ready_i (resp_i.w_ready),
        .data_o  (req_o.w)
    );

    spill_register #(
        .T      (b_chan_t),
        .Bypass (BypassB)
    ) u_b (
        .clk_i,
        .rst_ni,
        .valid_i (resp_i.b_valid),
        .ready_o (req_o.b_ready),
        .data_i  (resp_i.b),
        .valid_o (resp_o.b_valid),
        .ready_i (req_i.b_ready),
        .data_o  (resp_o.b)
    );

    spill_register #(
        .T      (ar_chan_t),
        .Bypass (BypassAr)
    ) u_ar (
        .clk_i,
        .rst_ni,
        .valid_i (req_i.ar_valid),
        .ready_o (resp_o.ar_ready),
        .data_i  (req_i.ar),
        .valid_o (req_o.ar_valid),
        .ready_i (resp_i.ar_ready),
        .data_o  (req_o.ar)
    );

    spill_register #(
        .T      (r_chan_t),
        .Bypass (BypassR)
    ) u_r (
        .clk_i,
        .rst_ni,
        .valid_i (resp_i.r_valid),
        .ready_o (req_o.r_ready),
        .data_i  (resp_i.r),
        .valid_o (resp_o.r_valid),
        .ready_i (req_i.r_ready),
        .data_o  (resp_o.r)
    );

endmodule
