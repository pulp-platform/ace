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

module ace_ccu_cd_arbiter
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg = '0,
    parameter type          cd_t   = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic [CcuCfg.u.SlvPorts-1:0] cd_valid_i,
    output logic [CcuCfg.u.SlvPorts-1:0] cd_ready_o,
    input  cd_t  [CcuCfg.u.SlvPorts-1:0] cd_i,

    input  logic                         cd_sel_valid_i,
    output logic                         cd_sel_ready_o,
    input  logic [CcuCfg.u.SlvPorts-1:0] cd_sel_bv_i,

    output logic cd_valid_o,
    input  logic cd_ready_i,
    output cd_t  cd_o
);

    logic [     CcuCfg.u.SlvPorts-1:0] cd_sel_fork_out_valid;
    logic [     CcuCfg.u.SlvPorts-1:0] cd_sel_fork_out_ready;
    logic [     CcuCfg.u.SlvPorts-1:0] cd_last;
    logic [     CcuCfg.u.SlvPorts-1:0] cd_join_out_valid;
    logic [     CcuCfg.u.SlvPorts-1:0] cd_join_out_ready;
    logic [     CcuCfg.u.SlvPorts-1:0] cd_drop;
    logic [     CcuCfg.u.SlvPorts-1:0] cd_filter_out_valid;
    logic [     CcuCfg.u.SlvPorts-1:0] cd_filter_out_ready;

    logic [CcuCfg.SlvPortIdxWidth-1:0] cd_first_resp_d;
    logic [CcuCfg.SlvPortIdxWidth-1:0] cd_first_resp_q;
    logic [CcuCfg.SlvPortIdxWidth-1:0] cd_first_resp_idx;
    logic                              cd_first_resp_empty;
    logic                              cd_first_resp_valid_d;
    logic                              cd_first_resp_valid_q;

    stream_fork_dynamic #(
        .N_OUP(CcuCfg.u.SlvPorts)
    ) u_cd_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (cd_sel_valid_i),
        .ready_o    (cd_sel_ready_o),
        .sel_i      (cd_sel_bv_i),
        .sel_valid_i('1),
        .sel_ready_o(),
        .valid_o    (cd_sel_fork_out_valid),
        .ready_i    (cd_sel_fork_out_ready & cd_last)
    );

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_cd_filter

        assign cd_last[i] = cd_i[i].last;

        // Only selected channels can advance
        stream_join #(
            .N_INP(2)
        ) u_cd_join (
            .inp_valid_i({cd_sel_fork_out_valid[i], cd_valid_i[i]}),
            .inp_ready_o({cd_sel_fork_out_ready[i], cd_ready_o[i]}),
            .oup_valid_o(cd_join_out_valid[i]),
            .oup_ready_i(cd_join_out_ready[i])
        );

        // Drop non first responder
        stream_filter u_cd_filter (
            .valid_i(cd_join_out_valid[i]),
            .ready_o(cd_join_out_ready[i]),
            .drop_i (cd_drop[i]),
            .valid_o(cd_filter_out_valid[i]),
            .ready_i(cd_filter_out_ready[i])
        );

    end

    // Select the first responder among the CD channels
    stream_mux #(
        .N_INP (CcuCfg.u.SlvPorts),
        .DATA_T(cd_t)
    ) u_cd_mux (
        .inp_data_i (cd_i),
        .inp_valid_i(cd_filter_out_valid),
        .inp_ready_o(cd_filter_out_ready),
        .inp_sel_i  (cd_first_resp_d),
        .oup_data_o (cd_o),
        .oup_valid_o(cd_valid_o),
        .oup_ready_i(cd_ready_i)
    );

    lzc #(
        .WIDTH(CcuCfg.u.SlvPorts)
    ) u_cd_lzc (
        .in_i   (cd_join_out_valid),
        .cnt_o  (cd_first_resp_idx),
        .empty_o(cd_first_resp_empty)
    );

    always_comb begin
        cd_first_resp_valid_d = cd_first_resp_valid_q;
        cd_first_resp_d       = cd_first_resp_q;

        if (!cd_first_resp_valid_q && !cd_first_resp_empty) begin
            // There is a valid response and the first responder
            // has not been found yet
            // ~> save the LZC index
            cd_first_resp_d       = cd_first_resp_idx;
            // ~> mark the first responder as valid
            cd_first_resp_valid_d = 1'b1;
        end

        if (cd_sel_valid_i && cd_sel_ready_o) begin
            // All CD channels have been processed
            // ~> clean first responder valid
            cd_first_resp_valid_d = 1'b0;
        end
    end

    // Drop all selected CD channels which responded after the first responder
    assign cd_drop = cd_first_resp_valid_q ? ~(CcuCfg.u.SlvPorts'(1) << cd_first_resp_q) : '0;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cd_first_resp_q       <= '0;
            cd_first_resp_valid_q <= 1'b0;
        end else begin
            cd_first_resp_q       <= cd_first_resp_d;
            cd_first_resp_valid_q <= cd_first_resp_valid_d;
        end
    end

endmodule
