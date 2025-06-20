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

module ace_ccu_frontend
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg     = '{default: '0},
    parameter type          slv_bv_t   = logic,
    parameter type          slv_idx_t  = logic,
    parameter type          slv_aw_t   = logic,
    parameter type          w_t        = logic,
    parameter type          slv_b_t    = logic,
    parameter type          slv_ar_t   = logic,
    parameter type          slv_r_t    = logic,
    parameter type          slv_req_t  = logic,
    parameter type          slv_resp_t = logic,
    parameter type          ccu_aw_t   = logic,
    parameter type          ccu_b_t    = logic,
    parameter type          ccu_ar_t   = logic,
    parameter type          ccu_r_t    = logic,
    parameter type          ccu_req_t  = logic,
    parameter type          ccu_resp_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_req_i,
    output slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_resp_o,

    output ccu_req_t  ccu_nonshareable_req_o,
    input  ccu_resp_t ccu_nonshareable_resp_i,
    output ccu_req_t  ccu_shareable_req_o,
    input  ccu_resp_t ccu_shareable_resp_i,

    output slv_bv_t ccu_shareable_rack_o,
    output slv_bv_t ccu_shareable_wack_o
);

    //  Internal signals
    //  {{{
    slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_req_cut;
    slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_resp_cut;

    slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_nonshareable_req;
    slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_nonshareable_resp;
    slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_shareable_req;
    slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_shareable_resp;

    slv_bv_t                           slv_r_nonshareable;
    slv_bv_t                           slv_b_nonshareable;
    slv_bv_t                           slv_rack_nonshareable;
    slv_bv_t                           slv_wack_nonshareable;
    //  }}}

    //  Slv demuxes
    //  {{{

    // Demux slv traffic into blocking and non-blocking traffic
    // Non-blocking traffic is expected to proceed even when the snoop
    // interface is stalling

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_slv_demux

        logic aw_is_nonblocking;
        logic ar_is_read_no_snoop;

        ace_cut #(
            .BypassAw  (!CcuCfg.u.CutSlvReq),
            .BypassW   (!CcuCfg.u.CutSlvReq),
            .BypassB   (!CcuCfg.u.CutSlvResp),
            .BypassAr  (!CcuCfg.u.CutSlvReq),
            .BypassR   (!CcuCfg.u.CutSlvResp),
            .BypassAck (1'b1),
            .aw_chan_t (slv_aw_t),
            .w_chan_t  (w_t),
            .b_chan_t  (slv_b_t),
            .ar_chan_t (slv_ar_t),
            .r_chan_t  (slv_r_t),
            .ace_req_t (slv_req_t),
            .ace_resp_t(slv_resp_t)
        ) u_ace_cut (
            .clk_i,
            .rst_ni,
            .slv_req_i (slv_req_i[i]),
            .slv_resp_o(slv_resp_o[i]),
            .mst_req_o (slv_req_cut[i]),
            .mst_resp_i(slv_resp_cut[i])
        );

        // Separate in each port blocking and non-blocking traffic
        assign aw_is_nonblocking = ace_aw_is_non_blocking(
            slv_req_cut[i].aw.bar[0], slv_req_cut[i].aw.domain, slv_req_cut[i].aw.snoop
        );

        assign ar_is_read_no_snoop = ace_is_read_no_snoop(
            slv_req_cut[i].ar.bar[0], slv_req_cut[i].ar.domain, slv_req_cut[i].ar.snoop
        );

        axi_demux_simple #(
            .AxiIdWidth (CcuCfg.u.AxiSlvIdWidth),
            .AtopSupport(1'b1),
            .axi_req_t  (slv_req_t),
            .axi_resp_t (slv_resp_t),
            .NoMstPorts (2),
            .MaxTrans   (CcuCfg.u.MaxTransactions),
            .AxiLookBits(CcuCfg.u.AxiIdLookupBits),
            .UniqueIds  (CcuCfg.u.AxiUniqueIds)
        ) u_ace_demux (
            .clk_i,
            .rst_ni,
            .test_i         (1'b0),
            .slv_req_i      (slv_req_cut[i]),
            .slv_resp_o     (slv_resp_cut[i]),
            .slv_aw_select_i(aw_is_nonblocking),
            .slv_ar_select_i(ar_is_read_no_snoop),
            .mst_reqs_o     ({slv_nonshareable_req[i], slv_shareable_req[i]}),
            .mst_resps_i    ({slv_nonshareable_resp[i], slv_shareable_resp[i]}),
            .mst_b_idx_o    (slv_b_nonshareable[i]),
            .mst_r_idx_o    (slv_r_nonshareable[i])
        );
    end
    //  }}}

    //  Nonshareable mux
    //  {{{
    axi_mux #(
        .SlvAxiIDWidth(CcuCfg.u.AxiSlvIdWidth),
        .slv_aw_chan_t(slv_aw_t),
        .mst_aw_chan_t(ccu_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (slv_b_t),
        .mst_b_chan_t (ccu_b_t),
        .slv_ar_chan_t(slv_ar_t),
        .mst_ar_chan_t(ccu_ar_t),
        .slv_r_chan_t (slv_r_t),
        .mst_r_chan_t (ccu_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (ccu_req_t),
        .mst_resp_t   (ccu_resp_t),
        .NoSlvPorts   (CcuCfg.u.SlvPorts),
        .MaxWTrans    (32'd8),
        .FallThrough  (1'b1),
        .SpillAw      (1'b0),
        .SpillW       (1'b0),
        .SpillB       (1'b0),
        .SpillAr      (1'b0),
        .SpillR       (1'b0)
    ) u_ace_nonshareable_mux (
        .clk_i,
        .rst_ni,
        .test_i     (1'b0),
        .slv_reqs_i (slv_nonshareable_req),
        .slv_resps_o(slv_nonshareable_resp),
        .mst_req_o  (ccu_nonshareable_req_o),
        .mst_resp_i (ccu_nonshareable_resp_i)
    );
    //  }}}

    //  Nonshareable demux
    //  {{{
    axi_mux #(
        .SlvAxiIDWidth(CcuCfg.u.AxiSlvIdWidth),
        .slv_aw_chan_t(slv_aw_t),
        .mst_aw_chan_t(ccu_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (slv_b_t),
        .mst_b_chan_t (ccu_b_t),
        .slv_ar_chan_t(slv_ar_t),
        .mst_ar_chan_t(ccu_ar_t),
        .slv_r_chan_t (slv_r_t),
        .mst_r_chan_t (ccu_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (ccu_req_t),
        .mst_resp_t   (ccu_resp_t),
        .NoSlvPorts   (CcuCfg.u.SlvPorts),
        .MaxWTrans    (32'd8),
        .FallThrough  (1'b1),
        .SpillAw      (1'b0),
        .SpillW       (1'b0),
        .SpillB       (1'b0),
        .SpillAr      (1'b0),
        .SpillR       (1'b0)
    ) u_ace_shareable_mux (
        .clk_i,
        .rst_ni,
        .test_i     (1'b0),
        .slv_reqs_i (slv_shareable_req),
        .slv_resps_o(slv_shareable_resp),
        .mst_req_o  (ccu_shareable_req_o),
        .mst_resp_i (ccu_shareable_resp_i)
    );
    //  }}}

    //  Sharebale xacks generation
    //  {{{
    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_xack_fifos
        logic r_push, b_push;

        assign r_push = slv_resp_cut[i].r_valid && slv_req_cut[i].r_ready && slv_resp_cut[i].r.last;
        assign b_push = slv_resp_cut[i].b_valid && slv_req_cut[i].b_ready;

        fifo_v3 #(
            .FALL_THROUGH(1'b0),
            .DATA_WIDTH  (1),
            .DEPTH       (CcuCfg.u.MaxTransactions)
        ) u_r_tid_fifo (
            .clk_i,
            .rst_ni,
            .flush_i   (1'b0),
            .testmode_i(1'b0),
            .full_o    (),
            .empty_o   (),
            .usage_o   (),
            .data_i    (slv_r_nonshareable[i]),
            .push_i    (r_push),
            .data_o    (slv_rack_nonshareable[i]),
            .pop_i     (slv_req_cut[i].rack)
        );

        fifo_v3 #(
            .FALL_THROUGH(1'b0),
            .DATA_WIDTH  (1),
            .DEPTH       (CcuCfg.u.MaxTransactions)
        ) u_b_tid_fifo (
            .clk_i,
            .rst_ni,
            .flush_i   (1'b0),
            .testmode_i(1'b0),
            .full_o    (),
            .empty_o   (),
            .usage_o   (),
            .data_i    (slv_b_nonshareable[i]),
            .push_i    (b_push),
            .data_o    (slv_wack_nonshareable[i]),
            .pop_i     (slv_req_cut[i].wack)
        );
    end

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_shareable_xacks
        assign ccu_shareable_rack_o[i] = slv_req_i[i].rack && !slv_rack_nonshareable[i];
        assign ccu_shareable_wack_o[i] = slv_req_i[i].wack && !slv_wack_nonshareable[i];
    end
    //  }}}

endmodule
