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

//! AR dispatch
//
//  A flat pool of at most `numEntries` inflight ARs. Same-address ARs are
//  serialized by predecessor chains (an entry links behind the current tail
//  of its address chain and may dispatch once its predecessor retired),
//  while different addresses dispatch in parallel. An entry retires on its
//  RACK. Storage is bounded by the number of inflight transactions.
module ccu_ar_dispatch
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t  ccuCfg          = '{default: '0},
    parameter type          ccu_ace_ar_t    = logic,
    localparam int unsigned numEntries      = ccuCfg.u.numShareableTransactions,
    localparam int unsigned sbIdxWidth      = ccuCfg.transactionIndexWidth,
    localparam int unsigned numQueue        = ccuCfg.u.numDispatchQueue,
    localparam int unsigned queueIdxWidth   = numQueue > 1 ? $clog2(numQueue) : 1
) (
    input  logic clk_i,
    input  logic rst_ni,

    //  Incoming AR
    input  ccu_ace_ar_t ar_i,
    input  logic        ar_valid_i,
    output logic        ar_ready_o,

    //  Dispatched AR (to the snoop pipeline)
    output ccu_ace_ar_t ar_o,
    output ccu_ar_flags_t ar_flags_o,
    output logic [sbIdxWidth-1:0] ar_tid_o,
    output logic        ar_valid_o,
    input  logic        ar_ready_i,

    //  Entries whose RACK arrived this cycle, one bit per scoreboard entry
    input  logic [numEntries-1:0] free_mask_i,

    //  Scoreboard ids, indexed by tid to restore the id of a memory read
    output logic [numEntries-1:0][ccuCfg.axiCcuIdWidth-1:0] sb_id_o
);

//  Dispatch queue: holds the AR only until it is dispatched
//  {{{
    typedef struct packed {
        ccu_ace_ar_t             ar;
        logic [sbIdxWidth-1:0]   sb_idx;
    } queue_entry_t;

    queue_entry_t [numQueue-1:0]      queue_q;
    logic         [numQueue-1:0]      queue_valid_q, queue_valid_d;
    logic         [queueIdxWidth-1:0] queue_alloc_idx;
    logic                             queue_full;

    logic [numQueue-1:0] eligible;
    logic [numQueue-1:0] gnt;
    logic [numQueue-1:0] dispatch;
    queue_entry_t        issue_entry;

    logic alloc;
    logic arb_req;
    logic arb_gnt;

    lzc #(
        .WIDTH (numQueue),
        .MODE  (1'b0)
    ) u_queue_lzc (
        .in_i    (~queue_valid_q),
        .cnt_o   (queue_alloc_idx),
        .empty_o (queue_full)
    );
//  }}}

//  Scoreboard: one entry per inflight transaction, freed on its RACK
//  {{{
    logic [numEntries-1:0]                             sb_valid;
    logic [numEntries-1:0][ccuCfg.addressCheckWidth-1:0] sb_slice;
    logic [numEntries-1:0][ccuCfg.axiCcuIdWidth-1:0]     sb_id;
    logic [sbIdxWidth-1:0]                             sb_alloc_idx;
    logic                                              sb_full;

    ccu_scoreboard #(
        .numEntries (numEntries),
        .sliceWidth (ccuCfg.addressCheckWidth),
        .idWidth    (ccuCfg.axiCcuIdWidth),
        .numAlloc   (1),
        .numQueries (0)
    ) u_scoreboard (
        .clk_i,
        .rst_ni,
        .alloc_valid_i (alloc),
        .alloc_slice_i (ar_i.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb]),
        .alloc_id_i    (ar_i.id),
        .alloc_idx_o   (sb_alloc_idx),
        .full_o        (sb_full),
        .free_mask_i   (free_mask_i),
        .query_slice_i ('0),
        .query_hit_o   (),
        .valid_o       (sb_valid),
        .slice_o       (sb_slice),
        .id_o          (sb_id)
    );

    assign sb_id_o = sb_id;

    //  Both resources are reserved before the AR is accepted
    assign ar_ready_o = !queue_full && !sb_full;
    assign alloc      = ar_valid_i && ar_ready_o;
//  }}}

//  Same-address chains: link behind the tail on allocation, become the tail
//  {{{
    logic [numEntries-1:0]                    tail_q,       tail_d;
    logic [numEntries-1:0]                    pred_valid_q, pred_valid_d;
    logic [numEntries-1:0][sbIdxWidth-1:0]    pred_idx_q,   pred_idx_d;
    logic [numEntries-1:0]                    tail_match;
    logic [sbIdxWidth-1:0]                    tail_idx;

    for (genvar e = 0; e < numEntries; e++) begin : gen_tail_match
        assign tail_match[e] = sb_valid[e] && tail_q[e] && !free_mask_i[e] &&
            sb_slice[e] == ar_i.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
    end

    onehot_to_bin #(
        .ONEHOT_WIDTH (numEntries)
    ) u_tail_onehot_to_bin (
        .onehot (tail_match),
        .bin    (tail_idx)
    );

    always_comb begin : chain_comb
        tail_d       = tail_q;
        pred_valid_d = pred_valid_q;
        pred_idx_d   = pred_idx_q;

        //  A retiring predecessor releases its successor
        for (int unsigned e = 0; e < numEntries; e++) begin
            if (pred_valid_q[e] && free_mask_i[pred_idx_q[e]])
                pred_valid_d[e] = 1'b0;
        end

        if (alloc) begin
            tail_d[sb_alloc_idx]       = 1'b1;
            pred_valid_d[sb_alloc_idx] = |tail_match;
            pred_idx_d[sb_alloc_idx]   = tail_idx;
            if (|tail_match) tail_d[tail_idx] = 1'b0;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tail_q       <= '0;
            pred_valid_q <= '0;
            pred_idx_q   <= '0;
        end else begin
            tail_q       <= tail_d;
            pred_valid_q <= pred_valid_d;
            pred_idx_q   <= pred_idx_d;
        end
    end
//  }}}

//  Queue entry logic
//  {{{
    for (genvar e = 0; e < numQueue; e++) begin : gen_queue
        logic alloc_this;

        assign alloc_this  = alloc && queue_alloc_idx == queueIdxWidth'(e);
        //  An entry may dispatch once nothing precedes it on its address
        assign eligible[e] = queue_valid_q[e] && !pred_valid_q[queue_q[e].sb_idx];

        always_comb begin : queue_entry_comb
            queue_valid_d[e] = queue_valid_q[e];
            if (dispatch[e])       queue_valid_d[e] = 1'b0;
            else if (alloc_this)   queue_valid_d[e] = 1'b1;
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                queue_valid_q[e] <= 1'b0;
                queue_q[e]       <= '0;
            end else begin
                queue_valid_q[e] <= queue_valid_d[e];
                if (alloc_this) queue_q[e] <= '{ar: ar_i, sb_idx: sb_alloc_idx};
            end
        end
    end
//  }}}

//  Dispatch arbitration
//  {{{
    rr_arb_tree #(
        .NumIn     (numQueue),
        .DataType  (queue_entry_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_dispatch_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (eligible),
        .gnt_o   (gnt),
        .data_i  (queue_q),
        .req_o   (arb_req),
        .gnt_i   (arb_gnt),
        .data_o  (issue_entry),
        .idx_o   ()
    );

    assign ar_o = issue_entry.ar;
    assign ar_tid_o = issue_entry.sb_idx;
    assign ar_flags_o = ccu_ar_decode(ar_o.bar[0], ar_o.domain, ar_o.snoop, ar_o.lock);

    assign ar_valid_o = arb_req;
    assign arb_gnt    = ar_ready_i;
    assign dispatch   = gnt;
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    //  managers must not reuse an id across inflight transactions
    for (genvar e = 0; e < numEntries; e++) begin : gen_unique_id_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            alloc |-> !(sb_valid[e] && sb_id[e] == ar_i.id))
            else $error("allocating an AR with an id already inflight");
    end

    //  every address chain has a single tail
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        alloc |-> $onehot0(tail_match))
        else $error("multiple tails match one address chain");

    //  a live waiter's predecessor is live
    for (genvar e = 0; e < numEntries; e++) begin : gen_chain_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            (sb_valid[e] && pred_valid_q[e]) |-> sb_valid[pred_idx_q[e]])
            else $error("chained entry waits on a dead predecessor");
    end

    //  a retiring entry must be live, and must not still sit in the queue
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (free_mask_i & ~sb_valid) == '0)
        else $error("RACK retires an entry that is not live");

    for (genvar e = 0; e < numQueue; e++) begin : gen_queue_retire_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            queue_valid_q[e] |-> !free_mask_i[queue_q[e].sb_idx])
            else $error("RACK retires an entry still awaiting dispatch");
    end

    //  an AR is accepted only with both a queue slot and a scoreboard entry
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        alloc |-> (!queue_full && !sb_full))
        else $error("AR accepted without reserving both resources");

    //  a dispatched entry leaves the queue
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        |dispatch |-> $onehot(dispatch))
        else $error("more than one queue entry dispatched");

    `endif
    // pragma translate_on
//  }}}
endmodule
