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

`include "axi/assign.svh"
`include "ace/assign.svh"
`include "ace/convert.svh"

module ccu_read_engine
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg       = '{default: '0},
    parameter type         ccu_axi_ar_t = logic,
    parameter type         ccu_ace_r_t  = logic,
    parameter type         ccu_axi_r_t  = logic
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    //  Read request from the snoop pipeline
    input  logic                                ar_valid_i,
    output logic                                ar_ready_o,
    input  ccu_axi_ar_t                         ar_i,
    input  logic [ccuCfg.transactionIndexWidth-1:0] ar_tid_i,
    //  A peer kept a copy but supplied no data; sets IsShared on memory R
    input  logic                                ar_is_shared_i,
    //  Shareable exclusive load: the CCU monitor holds its reservation, not memory
    input  logic                                ar_exclusive_i,

    //  Initiator R sourced by the snoop pipeline (read data and acks)
    input  logic                                snoop_pipeline_r_valid_i,
    output logic                                snoop_pipeline_r_ready_o,
    input  ccu_ace_r_t                          snoop_pipeline_r_i,
    input  logic [ccuCfg.transactionIndexWidth-1:0] snoop_pipeline_r_tid_i,

    //  SC fail responses from the exclusive monitor
    input  logic                                sc_fail_r_valid_i,
    output logic                                sc_fail_r_ready_o,
    input  ccu_ace_r_t                          sc_fail_r_i,
    input  logic [ccuCfg.transactionIndexWidth-1:0] sc_fail_r_tid_i,

    //  Scoreboard ids, indexed by tid to restore the id of a memory read
    input  logic [ccuCfg.u.numShareableTransactions-1:0]
                 [ccuCfg.axiCcuIdWidth-1:0]     sb_id_i,

    //  Initiator R towards the frontend
    output logic                                r_valid_o,
    input  logic                                r_ready_i,
    output ccu_ace_r_t                          r_o,
    output logic [ccuCfg.transactionIndexWidth-1:0] r_tid_o,
    output logic                                r_sc_fail_o,

    //  Memory AR/R
    output logic                                ar_valid_o,
    input  logic                                ar_ready_i,
    output ccu_axi_ar_t                         ar_o,
    input  logic                                r_valid_i,
    output logic                                r_ready_o,
    input  ccu_axi_r_t                          r_i,

    //  Memory AR gate: stalled while a same-line write is in PoS .. B
    output logic                                mem_ar_addr_check_o,
    output logic [ccuCfg.addressCheckWidth-1:0] mem_ar_addr_slice_o,
    input  logic                                mem_ar_stall_i
);

//  AR channel: to memory, held while a same-line write is pending (C6.5.1)
//  {{{
    logic ar_committed_q;
    logic ar_allow;

    assign mem_ar_addr_check_o = ar_valid_i;
    assign mem_ar_addr_slice_o = ar_i.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];

    //  Ignore the stall once the AR is presented (C5.2.3)
    assign ar_allow   = ar_committed_q || !mem_ar_stall_i;
    assign ar_valid_o = ar_valid_i && ar_allow;
    assign ar_ready_o = ar_ready_i && ar_allow;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) ar_committed_q <= 1'b0;
        else         ar_committed_q <= ar_valid_o && !ar_ready_i;
    end

    //  The tid is the memory ARID
    always_comb begin : mem_ar_comb
        `AXI_SET_AR_STRUCT(ar_o, ar_i)
        ar_o.id   = ar_tid_i;
        ar_o.lock = ar_i.lock && !ar_exclusive_i;
    end
//  }}}

//  R channel: arbitrate memory reads, snoop-pipeline responses and SC fails
//  {{{
    typedef struct packed {
        ccu_ace_r_t                              r;
        logic [ccuCfg.transactionIndexWidth-1:0] tid;
        logic                                    sc_fail;
    } r_beat_t;

    ccu_ace_r_t r_mem;
    logic [ccuCfg.transactionIndexWidth-1:0] r_mem_tid;
    r_beat_t r_beat;

    assign r_mem_tid = r_i.id[ccuCfg.transactionIndexWidth-1:0];

    //  Indexed by tid, overwritten per AR, never cleared
    logic [ccuCfg.u.numShareableTransactions-1:0] ar_is_shared_q, ar_exclusive_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ar_is_shared_q <= '0;
            ar_exclusive_q <= '0;
        end else if (ar_valid_i && ar_ready_o) begin
            ar_is_shared_q[ar_tid_i] <= ar_is_shared_i;
            ar_exclusive_q[ar_tid_i] <= ar_exclusive_i;
        end
    end

    always_comb begin : mem_r_comb
        `AXI_TO_ACE_SET_R_STRUCT(r_mem, r_i)
        r_mem.id                            = sb_id_i[r_mem_tid];
        r_mem.resp[ace_pkg::RESP_IS_SHARED] = ar_is_shared_q[r_mem_tid];
        //  Errors pass through
        if (ar_exclusive_q[r_mem_tid] && r_i.resp == axi_pkg::RESP_OKAY)
            r_mem.resp[axi_pkg::RespWidth-1:0] = axi_pkg::RESP_EXOKAY;
    end

    ccu_r_arbiter #(
        .numInputs (3),
        .data_t    (r_beat_t)
    ) u_r_arbiter (
        .clk_i,
        .rst_ni,
        .valid_i ({sc_fail_r_valid_i, r_valid_i, snoop_pipeline_r_valid_i}),
        .ready_o ({sc_fail_r_ready_o, r_ready_o, snoop_pipeline_r_ready_o}),
        .data_i  ({r_beat_t'{sc_fail_r_i,        sc_fail_r_tid_i,        1'b1},
                   r_beat_t'{r_mem,              r_mem_tid,              1'b0},
                   r_beat_t'{snoop_pipeline_r_i, snoop_pipeline_r_tid_i, 1'b0}}),
        .last_i  ({sc_fail_r_i.last, r_i.last, snoop_pipeline_r_i.last}),
        .valid_o (r_valid_o),
        .ready_i (r_ready_i),
        .data_o  (r_beat)
    );

    `ACE_ASSIGN_R_STRUCT(r_o, r_beat.r)
    assign r_tid_o     = r_beat.tid;
    assign r_sc_fail_o = r_beat.sc_fail;
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    //  a pending write may never appear under a committed memory AR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_committed_q |-> !(mem_ar_stall_i && !$past(mem_ar_stall_i)))
        else $error("same-line write became pending under a committed memory AR");

    //  memory never sees the lock of a load the CCU monitor reserves
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        r_valid_i && ar_exclusive_q[r_mem_tid] |-> r_i.resp != axi_pkg::RESP_EXOKAY)
        else $error("memory answered EXOKAY to a load sent without ARLOCK");

    //  the memory AR is stable while stalled
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_valid_o && !ar_ready_i |=> ar_valid_o && $stable(ar_o))
        else $error("memory AR unstable while stalled");
    `endif
    // pragma translate_on
//  }}}
endmodule
