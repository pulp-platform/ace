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

`include "ace/typedef.svh"
`include "ace/assign.svh"

module ace_ccu_frontend
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg        = '{default: '0},
    parameter type          slv_bv_t      = logic,
    parameter type          slv_idx_t     = logic,
    parameter type          slv_aw_t      = logic,
    parameter type          w_t           = logic,
    parameter type          slv_b_t       = logic,
    parameter type          slv_ar_t      = logic,
    parameter type          slv_r_t       = logic,
    parameter type          slv_req_t     = logic,
    parameter type          slv_resp_t    = logic,
    parameter type          midend_aw_t   = logic,
    parameter type          midend_b_t    = logic,
    parameter type          midend_ar_t   = logic,
    parameter type          midend_r_t    = logic,
    parameter type          midend_req_t  = logic,
    parameter type          midend_resp_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_req_i,
    output slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_resp_o,

    output midend_req_t  ccu_nonshareable_req_o,
    input  midend_resp_t ccu_nonshareable_resp_i,
    output midend_req_t  ccu_shareable_req_o,
    input  midend_resp_t ccu_shareable_resp_i
);

    //  Internal signals
    //  {{{
    slv_req_t     [CcuCfg.u.SlvPorts-1:0] slv_req_cut;
    slv_resp_t    [CcuCfg.u.SlvPorts-1:0] slv_resp_cut;

    slv_req_t     [CcuCfg.u.SlvPorts-1:0] slv_nonshareable_req;
    slv_resp_t    [CcuCfg.u.SlvPorts-1:0] slv_nonshareable_resp;
    slv_req_t     [CcuCfg.u.SlvPorts-1:0] slv_shareable_req;
    slv_resp_t    [CcuCfg.u.SlvPorts-1:0] slv_shareable_resp;

    midend_req_t                          mux_shareable_req;
    midend_resp_t                         mux_shareable_resp;
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

        ace_demux_simple #(
            .AxiIdWidth (CcuCfg.u.AxiSlvIdWidth),
            .AtopSupport(1'b1),
            .aw_chan_t  (slv_aw_t),
            .w_chan_t   (w_t),
            .ar_chan_t  (slv_ar_t),
            .req_t      (slv_req_t),
            .resp_t     (slv_resp_t),
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
            .mst_resps_i    ({slv_nonshareable_resp[i], slv_shareable_resp[i]})
        );
    end
    //  }}}

    //  Nonshareable mux
    //  {{{
    ace_mux #(
        .SlvAxiIDWidth(CcuCfg.u.AxiSlvIdWidth),
        .slv_aw_chan_t(slv_aw_t),
        .mst_aw_chan_t(midend_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (slv_b_t),
        .mst_b_chan_t (midend_b_t),
        .slv_ar_chan_t(slv_ar_t),
        .mst_ar_chan_t(midend_ar_t),
        .slv_r_chan_t (slv_r_t),
        .mst_r_chan_t (midend_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (midend_req_t),
        .mst_resp_t   (midend_resp_t),
        .NoSlvPorts   (CcuCfg.u.SlvPorts),
        .MaxWTrans    (32'd8),
        .MaxBTrans    (CcuCfg.u.MaxTransactions),
        .MaxRTrans    (CcuCfg.u.MaxTransactions),
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
    ace_mux #(
        .SlvAxiIDWidth(CcuCfg.u.AxiSlvIdWidth),
        .slv_aw_chan_t(slv_aw_t),
        .mst_aw_chan_t(midend_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (slv_b_t),
        .mst_b_chan_t (midend_b_t),
        .slv_ar_chan_t(slv_ar_t),
        .mst_ar_chan_t(midend_ar_t),
        .slv_r_chan_t (slv_r_t),
        .mst_r_chan_t (midend_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (midend_req_t),
        .mst_resp_t   (midend_resp_t),
        .NoSlvPorts   (CcuCfg.u.SlvPorts),
        .MaxWTrans    (32'd8),
        .MaxBTrans    (CcuCfg.u.MaxTransactions),
        .MaxRTrans    (CcuCfg.u.MaxTransactions),
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
        .mst_req_o  (mux_shareable_req),
        .mst_resp_i (mux_shareable_resp)
    );
    //  }}}

    //  AMO LR/SC monitor
    //  {{{

    localparam longint unsigned ADDR_BEGIN = '0;
    localparam longint unsigned ADDR_END = {CcuCfg.u.AxiAddrWidth{1'b1}};

    // All subsequent ACE defines will not use RACK/WACKS
    `define __ACE_NO_ACKS

    // Internal request type without acks
    `ACE_TYPEDEF_REQ_T(__midend_req_t, midend_aw_t, w_t, midend_ar_t)

    __midend_req_t __mux_shareable_req;
    __midend_req_t __ccu_shareable_req;

    `ACE_ASSIGN_REQ_STRUCT(__mux_shareable_req, mux_shareable_req)
    `ACE_ASSIGN_REQ_STRUCT(ccu_shareable_req_o, __ccu_shareable_req)

    // xACK bypass
    assign ccu_shareable_req_o.wack = mux_shareable_req.wack;
    assign ccu_shareable_req_o.rack = mux_shareable_req.rack;

    `undef __ACE_NO_ACKS

    axi_riscv_lrsc_structs #(
        .ADDR_BEGIN         (ADDR_BEGIN),
        .ADDR_END           (ADDR_END),
        .AXI_ADDR_WIDTH     (CcuCfg.u.AxiAddrWidth),
        .AXI_DATA_WIDTH     (CcuCfg.u.AxiDataWidth),
        .AXI_ID_WIDTH       (CcuCfg.AxiMidendIdWidth),
        .AXI_USER_WIDTH     (CcuCfg.u.AxiUserWidth),
        .AXI_MAX_READ_TXNS  (CcuCfg.u.MaxTransactions),
        .AXI_MAX_WRITE_TXNS (CcuCfg.u.MaxTransactions),
        .AXI_USER_AS_ID     (CcuCfg.u.AmoAxiUserAsId),
        .AXI_USER_ID_MSB    (CcuCfg.u.AmoAxiUserIdMsb),
        .AXI_USER_ID_LSB    (CcuCfg.u.AmoAxiUserIdLsb),
        .AXI_ADDR_LSB       (CcuCfg.u.AmoAxiAddrLsb),
        .FULL_BANDWIDTH     (1),
        .CUT_OUP_POP_INP_GNT(0),
        .NUM_RESERVATIONS   (CcuCfg.u.AmoNumReservations),
        .aw_chan_t          (midend_aw_t),
        .b_chan_t           (midend_b_t),
        .r_chan_t           (midend_r_t),
        .req_t              (__midend_req_t),
        .resp_t             (midend_resp_t)
    ) u_axi_riscv_lrsc (
        .clk_i,
        .rst_ni,
        .slv_req_i (__mux_shareable_req),
        .slv_resp_o(mux_shareable_resp),
        .mst_req_o (__ccu_shareable_req),
        .mst_resp_i(ccu_shareable_resp_i)
    );
    //  }}}

endmodule
