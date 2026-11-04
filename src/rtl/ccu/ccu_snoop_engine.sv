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

//! Snoop engine
//
//  Fans a token's snoop out to the selected ports, collects CRs per tid, resolves on the last CR.
module ccu_snoop_engine
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg   = '{default: '0},
    parameter  type         se_tok_t = logic,
    parameter  type         ac_req_t = logic,
    parameter  type         cr_ret_t = logic,
    parameter  type         se_resolve_t = logic,
    localparam int unsigned numSub   = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW  = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids  = ccuCfg.numTids,
    localparam int unsigned tidW     = ccuCfg.tidWidth
) (
    input  logic                           clk_i,
    input  logic                           rst_ni,

    //  An ordered entry, with everything its snoop needs
    input  se_tok_t                        tok_i,
    input  logic                           tok_valid_i,
    output logic                           tok_ready_o,

    output ac_req_t [numSub-1:0]           ac_o,
    output logic    [numSub-1:0]           ac_valid_o,
    input  logic    [numSub-1:0]           ac_ready_i,

    //  Never back-pressured
    input  cr_ret_t [numSub-1:0]           cr_i,
    input  logic    [numSub-1:0]           cr_valid_i,

    output se_resolve_t                    resolve_o,
    output logic                           resolve_valid_o,
    input  logic                           resolve_ready_i,

    //  The table released these tids
    input  logic    [numTids-1:0]          free_i,

    //  Last writeback slot rule
    input  logic                           writeback_scarce_i,
    input  logic    [numSub-1:0]           cd_head_valid_i,
    input  logic    [numSub-1:0][tidW-1:0] cd_head_tid_i,

    //  Ports that can take one more snoop
    output logic    [numSub-1:0]           ac_room_o,

    output ccu_snoop_events_t              events_o
);

//  AC fan-out: a token comes only once every port it selects has room
//  {{{
    logic [numSub-1:0] ac_full, ac_empty;

    assign tok_ready_o = 1'b1;

    for (genvar p = 0; p < numSub; p++) begin : gen_ac
        //  Registered, so the token issue path ends here
        fifo_v3 #(
            .FALL_THROUGH (1'b0),
            .DEPTH        (ccuCfg.u.numSnoopTransactions),
            .dtype        (ac_req_t)
        ) u_ac_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (ac_full[p]),
            .empty_o    (ac_empty[p]),
            .usage_o    (),
            .data_i     (ac_req_t'{ac: tok_i.ac, tid: tok_i.tid}),
            .push_i     (tok_valid_i && tok_i.sel[p]),
            .data_o     (ac_o[p]),
            .pop_i      (ac_valid_o[p] && ac_ready_i[p])
        );

        assign ac_valid_o[p] = !ac_empty[p];
        assign ac_room_o[p]  = !ac_full[p];
    end
//  }}}

//  CR collection, per tid
//  {{{
    logic          [tidW-1:0]                resolve_idx;
    logic          [numTids-1:0]             live_q,       live_d;
    logic          [numTids-1:0]             sent_q,       sent_d;
    ccu_op_e       [numTids-1:0]             op_q,         op_d;
    ccu_excl_t     [numTids-1:0]             excl_q,       excl_d;
    acsnoop_t      [numTids-1:0]             acsnoop_q,    acsnoop_d;
    logic          [numTids-1:0][numSub-1:0] sel_q,        sel_d;
    logic          [numTids-1:0][numSub-1:0] cr_pending_q, cr_pending_d;
    logic          [numTids-1:0][numSub-1:0] dt_q,         dt_d;
    logic          [numTids-1:0][numSub-1:0] is_q,         is_d;
    crresp_t       [numTids-1:0]             cr_acc_q,     cr_acc_d;

    always_comb begin : collect_comb
        live_d       = live_q;
        sent_d       = sent_q;
        op_d         = op_q;
        excl_d       = excl_q;
        acsnoop_d    = acsnoop_q;
        sel_d        = sel_q;
        cr_pending_d = cr_pending_q;
        dt_d         = dt_q;
        is_d         = is_q;
        cr_acc_d     = cr_acc_q;

        for (int unsigned t = 0; t < numTids; t++) begin
            if (free_i[t]) begin
                live_d[t] = 1'b0;
                sent_d[t] = 1'b0;
            end
        end

        if (tok_valid_i) begin
            live_d[tok_i.tid]       = 1'b1;
            sent_d[tok_i.tid]       = 1'b0;
            op_d[tok_i.tid]         = tok_i.op;
            excl_d[tok_i.tid]       = tok_i.excl;
            acsnoop_d[tok_i.tid]    = tok_i.ac.snoop;
            sel_d[tok_i.tid]        = tok_i.sel;
            cr_pending_d[tok_i.tid] = tok_i.sel;
            dt_d[tok_i.tid]         = '0;
            is_d[tok_i.tid]         = '0;
            cr_acc_d[tok_i.tid]     = '0;
        end

        for (int unsigned p = 0; p < numSub; p++) begin
            if (cr_valid_i[p]) begin
                cr_pending_d[cr_i[p].tid][p] = 1'b0;
                dt_d[cr_i[p].tid][p]         = cr_i[p].resp.DataTransfer;
                is_d[cr_i[p].tid][p]         = cr_i[p].resp.IsShared;
                cr_acc_d[cr_i[p].tid]        = cr_acc_d[cr_i[p].tid] | cr_i[p].resp;
            end
        end

        if (resolve_valid_o && resolve_ready_i) sent_d[resolve_idx] = 1'b1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            live_q       <= '0;
            sent_q       <= '0;
            op_q         <= ccu_op_e'('0);
            excl_q       <= '0;
            acsnoop_q    <= '0;
            sel_q        <= '0;
            cr_pending_q <= '0;
            dt_q         <= '0;
            is_q         <= '0;
            cr_acc_q     <= '0;
        end else begin
            live_q       <= live_d;
            sent_q       <= sent_d;
            op_q         <= op_d;
            excl_q       <= excl_d;
            acsnoop_q    <= acsnoop_d;
            sel_q        <= sel_d;
            cr_pending_q <= cr_pending_d;
            dt_q         <= dt_d;
            is_q         <= is_d;
            cr_acc_q     <= cr_acc_d;
        end
    end
//  }}}

//  Resolve: a tid whose CRs are all in, an empty selection at once
//  {{{
    logic    [numTids-1:0] resolve_candidate;
    logic    [subIdxW-1:0] src;
    logic                  src_none;
    se_resolve_t           resolution;

    //  A tid resolves in the cycle its last CR lands, from the bits landing with it
    logic [numTids-1:0][numSub-1:0] cr_landing;

    always_comb begin : cr_landing_comb
        cr_landing = '0;
        for (int unsigned p = 0; p < numSub; p++)
            if (cr_valid_i[p]) cr_landing[cr_i[p].tid][p] = 1'b1;
    end

    //  The last writeback slot goes only to a tid whose CD is next on every port
    logic [numSub-1:0][numTids-1:0] cd_head_at;
    logic [numTids-1:0][numSub-1:0] cd_next;
    logic [numTids-1:0]             writeback_blocked;

    for (genvar p = 0; p < numSub; p++) begin : gen_cd_head_at
        assign cd_head_at[p] = cd_head_valid_i[p] ? numTids'(1) << cd_head_tid_i[p] : '0;
    end

    for (genvar t = 0; t < numTids; t++) begin : gen_resolve_candidate
        for (genvar p = 0; p < numSub; p++) begin : gen_cd_next
            assign cd_next[t][p] = cd_head_at[p][t];
        end
        assign writeback_blocked[t] = writeback_scarce_i && cr_acc_d[t].PassDirty &&
                                      (dt_d[t] & ~cd_next[t]) != '0;
        assign resolve_candidate[t] = live_q[t] && !sent_q[t] && !writeback_blocked[t] &&
                                      (cr_pending_q[t] & ~cr_landing[t]) == '0;
    end

    rr_arb_tree #(
        .NumIn     (numTids),
        .DataType  (logic),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1)
    ) u_resolve_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (resolve_candidate),
        .gnt_o   (),
        .data_i  ('0),
        .req_o   (resolve_valid_o),
        .gnt_i   (resolve_ready_i),
        .data_o  (),
        .idx_o   (resolve_idx)
    );

    //  Lowest-indexed responder supplies the data, others are drained
    lzc #(
        .WIDTH (numSub),
        .MODE  (1'b0)
    ) u_src_lzc (
        .in_i    (dt_d[resolve_idx]),
        .cnt_o   (src),
        .empty_o (src_none)
    );

    always_comb begin : resolve_comb
        resolution     = '0;
        resolution.tid = resolve_idx;
        resolution.outcome = ccu_resolve(op_q[resolve_idx], excl_q[resolve_idx],
                                         cr_acc_d[resolve_idx]);
        resolution.src = src;
        resolution.dt  = dt_d[resolve_idx];
        //  A copy left behind keeps the line in that port's filter table
        unique case (acsnoop_q[resolve_idx])
            ReadUnique, CleanInvalid, MakeInvalid:
                resolution.remove = sel_q[resolve_idx];
            ReadClean, ReadNotSharedDirty, ReadShared:
                resolution.remove = sel_q[resolve_idx] & ~is_d[resolve_idx];
            default:
                resolution.remove = '0;
        endcase
    end

    assign resolve_o = resolution;
//  }}}

//  Performance events
//  {{{
    ccu_snoop_events_t events_d;

    always_comb begin : events_comb
        events_d          = '0;
        events_d.ac_sent  = |(ac_valid_o & ac_ready_i);
        events_d.ac_stall = |(ac_valid_o & ~ac_ready_i);
        events_d.cr       = |cr_valid_i;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) events_o <= '0;
        else         events_o <= events_d;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        tok_valid_i |-> !live_q[tok_i.tid] || free_i[tok_i.tid])
        else $error("snoop token for a tid already snooping");

    for (genvar p = 0; p < numSub; p++) begin : gen_port_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            tok_valid_i && tok_i.sel[p] |-> !ac_full[p])
            else $error("snoop issued to a port without room");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            cr_valid_i[p] |-> live_q[cr_i[p].tid] && cr_pending_q[cr_i[p].tid][p])
            else $error("CR for a tid not waiting on this port");
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        resolve_valid_o && resolution.outcome.actions.cd_wb |-> cr_acc_d[resolve_idx].PassDirty)
        else $error("a writeback outcome without PassDirty escapes the last writeback slot rule");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        resolve_valid_o |->
            !(cr_acc_d[resolve_idx].PassDirty && !cr_acc_d[resolve_idx].DataTransfer))
        else $error("PassDirty without DataTransfer");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        resolve_valid_o && acsnoop_q[resolve_idx] == MakeInvalid |->
            !cr_acc_d[resolve_idx].PassDirty)
        else $error("PassDirty on a MakeInvalid response");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        resolve_valid_o && (resolution.outcome.actions.cd_r || resolution.outcome.actions.cd_wb) |->
            !src_none)
        else $error("snoop data routed with no DataTransfer responder");
    `endif
    // pragma translate_on
//  }}}
endmodule
