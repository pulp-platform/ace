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

`include "ace/typedef.svh"
`include "ace/assign.svh"

module ace_demux_simple #(
    parameter int unsigned AxiIdWidth = 32'd0,
    parameter bit AtopSupport = 1'b1,
    parameter type aw_chan_t = logic,
    parameter type w_chan_t = logic,
    parameter type ar_chan_t = logic,
    parameter type req_t = logic,
    parameter type resp_t = logic,
    parameter int unsigned NoMstPorts = 32'd0,
    parameter int unsigned MaxTrans = 32'd8,
    parameter int unsigned AxiLookBits = 32'd3,
    parameter bit UniqueIds = 1'b0,
    localparam int unsigned SelectWidth = (NoMstPorts > 32'd1) ? $clog2(NoMstPorts) : 32'd1,
    localparam type select_t = logic [SelectWidth-1:0]
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  logic                     test_i,
    // Slave Port
    input  req_t                     slv_req_i,
    input  select_t                  slv_aw_select_i,
    input  select_t                  slv_ar_select_i,
    output resp_t                    slv_resp_o,
    // Master Ports
    output req_t    [NoMstPorts-1:0] mst_reqs_o,
    input  resp_t   [NoMstPorts-1:0] mst_resps_i
);

    // All subsequent ACE defines will not use RACK/WACKS
    `define __ACE_NO_ACKS

    // ACE request structure without RACK and WACK
    `ACE_TYPEDEF_REQ_T(__req_t, aw_chan_t, w_chan_t, ar_chan_t)

    __req_t                   slv_req;
    __req_t  [NoMstPorts-1:0] mst_reqs;
    resp_t   [NoMstPorts-1:0] mst_resps;

    select_t                  mst_b_idx;
    select_t                  mst_r_idx;
    select_t                  wack_idx;
    select_t                  rack_idx;

    logic    [NoMstPorts-1:0] mst_wacks;
    logic    [NoMstPorts-1:0] mst_racks;

    `ACE_ASSIGN_REQ_STRUCT(slv_req, slv_req_i)

    //  AXI demux simple instance
    //  {{{
    axi_demux_simple #(
        .AxiIdWidth (AxiIdWidth),
        .AtopSupport(AtopSupport),
        .axi_req_t  (__req_t),
        .axi_resp_t (resp_t),
        .NoMstPorts (NoMstPorts),
        .MaxTrans   (MaxTrans),
        .AxiLookBits(AxiLookBits),
        .UniqueIds  (UniqueIds)
    ) u_axi_demux (
        .clk_i,
        .rst_ni,
        .test_i         (test_i),
        .slv_req_i      (slv_req),
        .slv_resp_o     (slv_resp_o),
        .slv_aw_select_i(slv_aw_select_i),
        .slv_ar_select_i(slv_ar_select_i),
        .mst_reqs_o     (mst_reqs),
        .mst_resps_i    (mst_resps),
        .mst_b_idx_o    (mst_b_idx),
        .mst_r_idx_o    (mst_r_idx)
    );
    //  }}}

    // xACKs generation
    //  {{{
    fifo_v3 #(
        .FALL_THROUGH(1'b0),
        .DEPTH       (MaxTrans),
        .dtype       (select_t)
    ) i_switch_w_fifo (
        .clk_i,
        .rst_ni,
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (mst_b_stall),
        .empty_o   (),
        .usage_o   (),
        .data_i    (mst_b_idx),
        .push_i    (slv_resp_o.b_valid && slv_req_i.b_ready),
        .data_o    (wack_idx),
        .pop_i     (slv_req_i.wack)
    );

    fifo_v3 #(
        .FALL_THROUGH(1'b0),
        .DEPTH       (MaxTrans),
        .dtype       (select_t)
    ) i_switch_r_fifo (
        .clk_i,
        .rst_ni,
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (mst_r_stall),
        .empty_o   (),
        .usage_o   (),
        .data_i    (mst_r_idx),
        .push_i    (slv_resp_o.r_valid && slv_req_i.r_ready && slv_resp_o.r.last),
        .data_o    (rack_idx),
        .pop_i     (slv_req_i.rack)
    );

    always_comb begin
        mst_wacks = '0;
        mst_racks = '0;

        if (slv_req_i.rack) mst_racks[rack_idx] = 1'b1;
        if (slv_req_i.wack) mst_wacks[wack_idx] = 1'b1;
    end

    always_comb begin
        for (int i = 0; i < NoMstPorts; i++) begin
            `ACE_SET_REQ_STRUCT(mst_reqs_o[i], mst_reqs[i])
            `ACE_SET_RESP_STRUCT(mst_resps[i], mst_resps_i[i])
            mst_reqs_o[i].rack = mst_racks[i];
            mst_reqs_o[i].wack = mst_wacks[i];

            if (mst_r_stall) begin
                mst_resps[i].r_valid  = 1'b0;
                mst_reqs_o[i].r_ready = 1'b0;
            end

            if (mst_b_stall) begin
                mst_resps[i].b_valid  = 1'b0;
                mst_reqs_o[i].b_ready = 1'b0;
            end
        end
    end
    // }}}

    `undef __ACE_NO_ACKS

endmodule
