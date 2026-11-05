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

//! Completion buffer entry
//
//  One issued operation, from snoop token to free.
module ccu_completion_entry
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg    = '{default: '0},
    parameter  type         init_t    = logic,
    parameter  type         state_t   = logic,
    parameter  type         status_t  = logic,
    localparam int unsigned numSub    = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW   = ccuCfg.subordinateIndexWidth,
    localparam int unsigned wSlotW    = ccuCfg.wSlotWidth
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,

    //  Issued into this entry, with everything fixed at issue
    input  logic                         issue_i,
    input  init_t                        init_i,
    //  The snoops resolved, and a writeback slot taken if the outcome writes back
    input  logic                         resolve_i,
    input  ccu_outcome_t                 outcome_i,
    input  logic [subIdxW-1:0]           src_i,
    input  logic [numSub-1:0]            dt_i,
    input  logic [wSlotW-1:0]            wslot_i,
    //  This entry's CD consumed, per port; its memory R landed; its RACK
    input  logic [numSub-1:0]            cd_done_i,
    input  logic                         mem_done_i,
    input  logic                         rack_i,
    //  Its filter insert sent to its table, and landed there
    input  logic                         ins_sent_i,
    input  logic                         ins_done_i,
    //  A successor admitted behind it took the tail
    input  logic                         tail_clear_i,

    output status_t                      status_o
);

    state_t q, d;

    function automatic logic [numSub-1:0] port_bit(logic [subIdxW-1:0] port);
        return numSub'(1) << port;
    endfunction

//  Release points
//  {{{
    logic settled, freeing, acked_now;
    logic src_done;

    assign settled   = q.acked && !q.ins_owed;
    assign freeing   = q.valid && settled && q.cd_wait == '0;
    assign acked_now = q.acked || rack_i;
    assign src_done  = q.valid && q.resolved && |(cd_done_i & port_bit(q.src));
//  }}}

//  Next state
//  {{{
    always_comb begin : entry_comb
        d = q;

        if (freeing) begin
            d.valid      = 1'b0;
            d.tail       = 1'b0;
            d.resolved   = 1'b0;
            d.responding = 1'b0;
            d.acked      = 1'b0;
        end

        if (tail_clear_i) d.tail     = 1'b0;
        if (ins_sent_i)   d.ins_sent = 1'b1;
        if (ins_done_i) begin
            d.ins_owed = 1'b0;
            d.ins_sent = 1'b0;
        end

        if (resolve_i) begin
            d.resolved   = 1'b1;
            d.pending    = outcome_i.actions;
            d.is_shared  = outcome_i.is_shared;
            d.pass_dirty = outcome_i.pass_dirty;
            d.src        = src_i;
            d.wslot      = wslot_i;
            d.cd_wait    = dt_i;
            //  An ACK that carries a writeback waits for its data
            d.responding = !q.bi && (outcome_i.actions.mem_rd || outcome_i.actions.cd_r ||
                                     (outcome_i.actions.ack_r && !outcome_i.actions.cd_wb));
        end

        d.cd_wait &= ~cd_done_i;
        if (src_done) begin
            d.done.cd_r  = q.pending.cd_r;
            d.done.cd_wb = q.pending.cd_wb;
            if (q.pending.ack_r && q.pending.cd_wb) d.responding = 1'b1;
        end
        if (mem_done_i) d.done.mem_rd = 1'b1;

        //  ACKED: the RACK, or for a back-invalidation its last CD
        if (rack_i) d.acked = 1'b1;
        if (q.valid && q.bi && q.resolved && d.cd_wait == '0) d.acked = 1'b1;
        //  Lands even if the line was dropped meanwhile: over-reporting is safe
        if (q.valid && !q.acked && d.acked) d.ins_owed = q.owes_insert;

        if (issue_i) begin
            d             = '0;
            d.valid       = 1'b1;
            d.bi          = init_i.bi;
            d.line        = init_i.line;
            d.port        = init_i.port;
            d.rslot       = init_i.rslot;
            d.tail        = init_i.tail;
            d.owes_insert = init_i.owes_insert;
            d.exokay      = init_i.exokay;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) q <= '0;
        else         q <= d;
    end
//  }}}

//  Status
//  {{{
    always_comb begin : status_comb
        status_o           = '0;
        status_o.state     = q;
        status_o.freeing   = freeing;
        status_o.acked_now = acked_now;
        status_o.respond_late = src_done && q.pending.ack_r && q.pending.cd_wb && !q.responding;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    localparam int unsigned livenessBound = 100000;

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        issue_i |-> !q.valid)
        else $error("issue into a live entry");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        q.valid |-> (q.done & ~q.pending) == '0)
        else $error("an action done that was never pending");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        rack_i |-> q.valid && q.responding && !q.acked && !q.bi)
        else $error("RACK for an entry that sent no R");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        |cd_done_i |-> q.valid && q.resolved && (cd_done_i & ~q.cd_wait) == '0)
        else $error("CD consumed for a tid not waiting on it");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        resolve_i |-> q.valid && !q.resolved)
        else $error("resolve for an entry not snooping");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ins_sent_i |-> q.ins_owed && !q.ins_sent)
        else $error("insert sent for an entry that owed none or had sent it");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ins_done_i |-> q.ins_owed && q.ins_sent)
        else $error("insert landed for an entry that never sent one");

    //  Every entry frees: nothing it waits on is unbounded
    int unsigned age_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)                   age_q <= 0;
        else if (!q.valid || freeing)  age_q <= 0;
        else                           age_q <= age_q + 1;
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        age_q < livenessBound)
        else $error("entry live for %0d cycles: resolved %b responding %b acked %b", livenessBound,
               q.resolved, q.responding, q.acked);
    `endif
    // pragma translate_on
//  }}}
endmodule
