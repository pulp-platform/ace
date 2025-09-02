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

`include "axi/assign.svh"
`include "ace/convert.svh"

module ace_ccu_read
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg       = '{default: '0},
    parameter type          midend_ax_t  = logic,
    parameter type          tid_t        = logic,
    parameter type          backend_ar_t = logic,
    parameter type          backend_r_t  = logic,
    parameter type          midend_r_t   = logic,
    parameter type          slv_idx_t    = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // Ctrl
    input  logic       valid_i,
    output logic       ready_o,
    input  midend_ax_t ax_i,

    // Snp interface
    input  midend_r_t cd_r_i,
    input  logic      cd_r_valid_i,
    output logic      cd_r_ready_o,

    // Slv interface
    output midend_r_t   r_o,
    output logic        r_valid_o,
    input  logic        r_ready_i,
    // Mst interface
    output backend_ar_t ar_o,
    output logic        ar_valid_o,
    input  logic        ar_ready_i,
    input  backend_r_t  r_i,
    input  logic        r_valid_i,
    output logic        r_ready_o
);

    backend_ar_t ar_sync_wdata;
    midend_r_t   mem_r;

    //  AR channel
    //  {{{
    `AXI_ASSIGN_AR_STRUCT(ar_sync_wdata, ax_i)

    fall_through_register #(
        .T(backend_ar_t)
    ) u_ar_sync_reg (
        .clk_i,
        .rst_ni,
        .clr_i     (1'b0),
        .testmode_i(1'b0),
        .valid_i   (valid_i),
        .ready_o   (ready_o),
        .data_i    (ar_sync_wdata),
        .valid_o   (ar_valid_o),
        .ready_i   (ar_ready_i),
        .data_o    (ar_o)
    );
    //  }}}

    //  R channel
    //  {{{
    `AXI_TO_ACE_ASSIGN_R_STRUCT(mem_r, r_i)

    typedef struct packed {
        logic mem;
        logic cd;
    } req_mask_t;

    req_mask_t [CcuCfg.u.SlvPorts-1:0] req_mask_q;
    req_mask_t [CcuCfg.u.SlvPorts-1:0] req_mask_d;
    req_mask_t                         req_mask;

    rr_arb_tree #(
        .NumIn    (2),
        .DataType (midend_r_t),
        .AxiVldRdy(1'b1),
        .LockIn   (1'b1)
    ) u_r_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .rr_i   (1'b0),
        .req_i  ({r_valid_i, cd_r_valid_i} & ~req_mask),
        .gnt_o  ({r_ready_o, cd_r_ready_o}),
        .data_i ({mem_r, cd_r_i}),
        .req_o  (r_valid_o),
        .gnt_i  (r_ready_i),
        .data_o (r_o),
        .idx_o  (r_arb)
    );

    assign req_mask.mem = req_mask_q[mem_r.id>>CcuCfg.u.AxiSlvIdWidth].mem;
    assign req_mask.cd  = req_mask_q[cd_r_i.id>>CcuCfg.u.AxiSlvIdWidth].cd;

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin
        slv_idx_t slv_idx;
        logic     read_mem_q;
        logic     read_mem_d;
        logic     read_busy_q;
        logic     read_busy_d;

        assign slv_idx = r_o.id >> CcuCfg.u.AxiSlvIdWidth;

        always_comb begin
            read_busy_d   = read_busy_q;
            req_mask_d[i] = req_mask_q[i];

            if (read_busy_q) begin
                if (r_valid_o && r_ready_i && r_o.last) begin
                    read_busy_d   = 1'b0;
                    req_mask_d[i] = '0;
                end
            end else if (slv_idx == i && r_valid_o && r_ready_i && !r_o.last) begin
                read_busy_d       = 1'b1;
                req_mask_d[i].mem = ~r_arb;
                req_mask_d[i].cd  = r_arb;
            end
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                read_busy_q   <= 1'b0;
                req_mask_q[i] <= '0;
            end else begin
                read_busy_q   <= read_busy_d;
                req_mask_q[i] <= req_mask_d[i];
            end
        end
    end
    //  }}}



endmodule
