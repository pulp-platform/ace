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

//! Snoop cut
//
//  A register on each of the three snoop channels, each one bypassable on
//  its own.
module snoop_cut #(
    parameter bit  Bypass    = 1'b0,
    parameter bit  BypassAc  = Bypass,
    parameter bit  BypassCr  = Bypass,
    parameter bit  BypassCd  = Bypass,
    parameter type ac_chan_t = logic,
    parameter type cr_chan_t = logic,
    parameter type cd_chan_t = logic,
    parameter type req_t     = logic,
    parameter type resp_t    = logic
) (
    input  logic  clk_i,
    input  logic  rst_ni,
    //  Toward the interconnect, which issues the snoops
    input  req_t  req_i,
    output resp_t resp_o,
    //  Toward the snooped cache
    output req_t  req_o,
    input  resp_t resp_i
);

    spill_register #(
        .T      (ac_chan_t),
        .Bypass (BypassAc)
    ) u_ac (
        .clk_i,
        .rst_ni,
        .valid_i (req_i.ac_valid),
        .ready_o (resp_o.ac_ready),
        .data_i  (req_i.ac),
        .valid_o (req_o.ac_valid),
        .ready_i (resp_i.ac_ready),
        .data_o  (req_o.ac)
    );

    spill_register #(
        .T      (cr_chan_t),
        .Bypass (BypassCr)
    ) u_cr (
        .clk_i,
        .rst_ni,
        .valid_i (resp_i.cr_valid),
        .ready_o (req_o.cr_ready),
        .data_i  (resp_i.cr),
        .valid_o (resp_o.cr_valid),
        .ready_i (req_i.cr_ready),
        .data_o  (resp_o.cr)
    );

    spill_register #(
        .T      (cd_chan_t),
        .Bypass (BypassCd)
    ) u_cd (
        .clk_i,
        .rst_ni,
        .valid_i (resp_i.cd_valid),
        .ready_o (req_o.cd_ready),
        .data_i  (resp_i.cd),
        .valid_o (resp_o.cd_valid),
        .ready_i (req_i.cd_ready),
        .data_o  (resp_o.cd)
    );

endmodule
