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

module ace_ccu_ax_arbiter
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg   = '{default: '0},
    parameter type          ccu_aw_t = logic,
    parameter type          ccu_ar_t = logic,
    parameter type          ccu_ax_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input logic replay_full_i,

    input  ccu_aw_t aw_i,
    input  logic    aw_valid_i,
    output logic    aw_ready_o,
    input  ccu_ar_t ar_i,
    input  logic    ar_valid_i,
    output logic    ar_ready_o,
    input  ccu_ar_t replay_ar_i,
    input  logic    replay_ar_valid_i,
    output logic    replay_ar_ready_o,

    output ccu_ax_t   ax_o,
    output logic      ax_valid_o,
    input  logic      ax_ready_i,
    output logic      ax_is_write_o,
    output logic      ax_is_replay_o,
    output acsnoop_t  ax_acsnoop_o,
    output logic      ar_accepts_dirty_o,
    output logic      ar_accepts_dirty_shared_o,
    output logic      ar_accepts_shared_o,
    output axdomain_t ax_domain_o
);

    //  Internal signals
    //  {{{
    ccu_ar_t  ar_muxed;
    ccu_ax_t  aw_in;
    ccu_ax_t  ar_in;
    ccu_ax_t  ax;
    ccu_ax_t  replay_ar;
    logic     ax_valid;
    logic     ax_ready;
    logic     ax_arb_valid;
    logic     ax_arb_ready;
    logic     ax_is_write;
    acsnoop_t aw_acsnoop;
    acsnoop_t ar_acsnoop;
    logic     ar_accepts_dirty;
    logic     ar_accepts_dirty_shared;
    logic     ar_accepts_shared;
    //  }}}

    //  Coherence decoding
    //  {{{
    assign ar_muxed = ax_is_replay_o ? replay_ar_i : ar_i;
    // ACSNOOP computed from AWSNOOP
    assign aw_acsnoop = aw_acsnoop_map(aw_i.bar[0], aw_i.domain, aw_i.snoop);
    // ACSNOOP computed from ARSNOOP
    assign ar_acsnoop = ar_acsnoop_map(
        ar_muxed.bar[0], ar_muxed.domain, ar_muxed.snoop, ar_muxed.lock
    );
    // Read transaction can accept a cacheline in Dirty state
    assign ar_accepts_dirty = ar_resp_accepts_dirty(
        ar_muxed.bar[0], ar_muxed.domain, ar_muxed.snoop
    );
    // Read transaction can accept a cacheline in Dirty and Shared state
    assign ar_accepts_dirty_shared = ar_resp_accepts_dirty_shared(
        ar_muxed.bar[0], ar_muxed.domain, ar_muxed.snoop
    );
    // Read transaction can accept a cacheline in Shared state
    assign ar_accepts_shared = ar_resp_accepts_shared(
        ar_muxed.bar[0], ar_muxed.domain, ar_muxed.snoop
    );
    // Mux output signals
    always_comb begin : output_mux
        // AR request (input or replay)
        ax_is_write_o             = 1'b0;
        ax_acsnoop_o              = ar_acsnoop;
        ar_accepts_dirty_o        = ar_accepts_dirty;
        ar_accepts_dirty_shared_o = ar_accepts_dirty_shared;
        ar_accepts_shared_o       = ar_accepts_shared;
        ax_domain_o               = ar_muxed.domain;

        if (!ax_is_replay_o && ax_is_write) begin
            // AW request (input)
            ax_is_write_o = 1'b1;
            ax_acsnoop_o  = aw_acsnoop;
            ax_domain_o   = aw_i.domain;
        end
    end
    //  }}}

    //  Input AX arbiter
    //  {{{
    // Assign AW to internal AX data type
    always_comb begin
        aw_in = '0;
        `AXI_SET_AW_STRUCT(aw_in, aw_i)
    end

    // Assign AR to internal AX data type
    always_comb begin
        ar_in = '0;
        `AXI_SET_AR_STRUCT(ar_in, ar_i)
    end

    rr_arb_tree #(
        .NumIn    (2),
        .DataType (ccu_ax_t),
        .AxiVldRdy(1'b1),
        .LockIn   (1'b1)
    ) u_ax_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .rr_i   (1'b0),
        .req_i  ({aw_valid_i, ar_valid_i}),
        .gnt_o  ({aw_ready_o, ar_ready_o}),
        .data_i ({aw_in, ar_in}),
        .req_o  (ax_arb_valid),
        .gnt_i  (ax_arb_ready),
        .data_o (ax),
        .idx_o  (ax_is_write)
    );

    assign ax_valid     = !replay_full_i && ax_arb_valid;
    assign ax_arb_ready = !replay_full_i && ax_ready;
    //  }}}

    //  Replay arbiter
    //  {{{
    // Assign replay AR to internal AX data type
    always_comb begin
        replay_ar = '0;
        `AXI_SET_AR_STRUCT(replay_ar, replay_ar_i)
    end

    rr_arb_tree #(
        .NumIn    (2),
        .DataType (ccu_ax_t),
        .AxiVldRdy(1'b1),
        .LockIn   (1'b0),
        .ExtPrio  (1'b1)
    ) u_replay_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .rr_i   ('1),
        .req_i  ({replay_ar_valid_i, ax_valid}),
        .gnt_o  ({replay_ar_ready_o, ax_ready}),
        .data_i ({replay_ar, ax}),
        .req_o  (ax_valid_o),
        .gnt_i  (ax_ready_i),
        .data_o (ax_o),
        .idx_o  (ax_is_replay_o)
    );
    //  }}}

endmodule
