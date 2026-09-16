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
    localparam int unsigned queueIdxWidth   = numQueue > 1 ? $clog2(numQueue) : 1,
    localparam int unsigned numSub          = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxWidth     = ccuCfg.subordinateIndexWidth,
    localparam int unsigned addrWidth       = ccuCfg.u.axiAddressWidth,
    localparam int unsigned offWidth        = ccuCfg.cachelineByteIndexWidth,
    localparam int unsigned lineWidth       = addrWidth - offWidth,
    localparam int unsigned chainWidth      = ccuCfg.addressCheckWidth,
    localparam int unsigned subIdWidth      = ccuCfg.u.axiSubordinateIdWidth
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
    output logic [numSub-1:0]     ar_present_o,
    output logic        ar_valid_o,
    input  logic        ar_ready_i,

    //  Snoop filter lookup; the mask answers one cycle later
    output logic                  sf_lookup_valid_o,
    output logic [addrWidth-1:0]  sf_lookup_addr_o,
    input  logic [numSub-1:0]     sf_present_i,

    //  Entries whose RACK arrived this cycle, one bit per scoreboard entry
    input  logic [numEntries-1:0] rack_mask_i,

    //  Those of them whose read errored; the line was never cached
    input  logic [numEntries-1:0] rack_error_i,

    //  Transaction dropped downstream, so it allocates nothing
    input  logic                  drop_valid_i,
    input  logic [sbIdxWidth-1:0] drop_tid_i,

    //  Snoop filter allocation, raised at RACK and held until it retires
    output logic [numSub-1:0]                  sf_insert_valid_o,
    output logic [numSub-1:0][addrWidth-1:0]   sf_insert_addr_o,
    input  logic [numSub-1:0]                  sf_insert_ready_i,

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

    logic [numQueue-1:0]      eligible;
    logic [numQueue-1:0]      gnt;
    logic [numQueue-1:0]      dispatch;
    queue_entry_t             issue_entry;
    logic [queueIdxWidth-1:0] issue_idx;

    logic          alloc;
    logic          arb_req;
    logic          arb_gnt;
    logic          ar_flags_alloc;
    logic          ar_untracked;

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
    logic [numEntries-1:0]                           sb_valid;
    logic [numEntries-1:0][lineWidth-1:0]            sb_line;
    logic [numEntries-1:0][ccuCfg.axiCcuIdWidth-1:0] sb_id;
    logic [sbIdxWidth-1:0]                           sb_alloc_idx;
    logic                                            sb_full;
    logic [numEntries-1:0]                           sb_free;
    logic [numEntries-1:0]                           alloc_q, alloc_d;
    logic [numEntries-1:0]                           sb_retired;
    logic [numEntries-1:0]                           ins_req_set, ins_req_clear;

    //  The scoreboard holds the whole line address for the filter, while the
    //  chain still matches on the narrower hazard slice
    ccu_scoreboard #(
        .numEntries (numEntries),
        .sliceWidth (lineWidth),
        .idWidth    (ccuCfg.axiCcuIdWidth),
        .numAlloc   (1),
        .numQueries (0)
    ) u_scoreboard (
        .clk_i,
        .rst_ni,
        .alloc_valid_i (alloc),
        .alloc_slice_i (ar_i.addr[addrWidth-1:offWidth]),
        .alloc_id_i    (ar_i.id),
        .alloc_idx_o   (sb_alloc_idx),
        .full_o        (sb_full),
        .retire_mask_i (rack_mask_i),
        .free_mask_i   (sb_free),
        .retired_o     (sb_retired),
        .query_slice_i ('0),
        .query_hit_o   (),
        .valid_o       (sb_valid),
        .slice_o       (sb_line),
        .id_o          (sb_id)
    );

    assign sb_id_o = sb_id;

    //  Both resources are reserved before the AR is accepted
    assign ar_ready_o = !queue_full && !sb_full;
    assign alloc      = ar_valid_i && ar_ready_o;

    //  Such a port answers no snoop and issues no Evict, so a tracked line of
    //  its would hold a way the mirror can never reclaim
    localparam logic [subIdWidth-1:0] untrackedId = subIdWidth'(ccuCfg.u.untrackedArId);

    assign ar_untracked   = ccuCfg.u.hasUntrackedArId &&
                            ar_i.id[subIdWidth-1:0] == untrackedId;

    assign ar_flags_alloc = !ar_untracked &&
                            ccu_ar_decode(ar_i.bar[0], ar_i.domain,
                                          ar_i.snoop,  ar_i.lock).allocates;
//  }}}

//  Same-address chains: link behind the tail on allocation, become the tail
//  {{{
    logic [numEntries-1:0]                    tail_q,        tail_d;
    logic [numEntries-1:0]                    pred_valid_q,  pred_valid_d;
    logic [numEntries-1:0][sbIdxWidth-1:0]    pred_idx_q,    pred_idx_d;
    logic [numEntries-1:0]                    chain_alloc_q, chain_alloc_d;
    logic [numEntries-1:0]                    tail_match;
    logic [sbIdxWidth-1:0]                    tail_idx;

    for (genvar e = 0; e < numEntries; e++) begin : gen_tail_match
        assign tail_match[e] = sb_valid[e] && tail_q[e] && !sb_free[e] &&
            sb_line[e][chainWidth-1:0] == ar_i.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
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

        //  A predecessor releases its successor only once its line is in the
        //  filter, so the successor's lookup cannot miss it
        for (int unsigned e = 0; e < numEntries; e++) begin
            if (pred_valid_q[e] && sb_free[pred_idx_q[e]])
                pred_valid_d[e] = 1'b0;
        end

        if (alloc) begin
            tail_d[sb_alloc_idx]       = 1'b1;
            pred_valid_d[sb_alloc_idx] = |tail_match;
            pred_idx_d[sb_alloc_idx]   = tail_idx;
            if (|tail_match) tail_d[tail_idx] = 1'b0;
        end
    end

    //  Inherited down the chain: any allocator ahead of us inserts before we
    //  dispatch, which would leave an early lookup stale
    always_comb begin : chain_alloc_comb
        chain_alloc_d = chain_alloc_q;
        if (alloc)
            chain_alloc_d[sb_alloc_idx] = |tail_match &&
                                          (alloc_q[tail_idx] || chain_alloc_q[tail_idx]);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tail_q        <= '0;
            pred_valid_q  <= '0;
            pred_idx_q    <= '0;
            chain_alloc_q <= '0;
        end else begin
            tail_q        <= tail_d;
            pred_valid_q  <= pred_valid_d;
            pred_idx_q    <= pred_idx_d;
            chain_alloc_q <= chain_alloc_d;
        end
    end
//  }}}

//  Snoop filter allocation: an entry lives until its line is in the filter
//  {{{
    logic [numSub-1:0][numEntries-1:0] ins_req_clear_sub;

    for (genvar e = 0; e < numEntries; e++) begin : gen_ins_entry
        //  A read that allocated and completed cleanly owes the filter its line
        assign ins_req_set[e] = rack_mask_i[e] && alloc_q[e] && !rack_error_i[e];
        //  So the entry outlives its RACK exactly when it owes one
        assign sb_free[e]     = (rack_mask_i[e] && !ins_req_set[e]) || ins_req_clear[e];
        assign alloc_d[e]     = alloc        && sb_alloc_idx == sbIdxWidth'(e) ? ar_flags_alloc :
                                drop_valid_i && drop_tid_i   == sbIdxWidth'(e) ? 1'b0           :
                                                                                 alloc_q[e];
    end

    for (genvar s = 0; s < numSub; s++) begin : gen_ins_port
        logic [numEntries-1:0] ins_sub_req;
        logic [sbIdxWidth-1:0] ins_sub_idx, ins_idx, ins_held_idx_q;
        logic                  ins_sub_none, ins_held_q;
        logic                  ins_handshake;

        for (genvar e = 0; e < numEntries; e++) begin : gen_ins_sub_req
            assign ins_sub_req[e] = sb_retired[e] &&
                sb_id[e][ccuCfg.u.axiSubordinateIdWidth +: subIdxWidth] == subIdxWidth'(s);
        end

        lzc #(
            .WIDTH (numEntries),
            .MODE  (1'b0)
        ) u_ins_lzc (
            .in_i    (ins_sub_req),
            .cnt_o   (ins_sub_idx),
            .empty_o (ins_sub_none)
        );

        //  A pending entry below the selected one would re-steer the lzc, so the
        //  selection is held until the handshake it belongs to retires
        assign ins_idx              = ins_held_q ? ins_held_idx_q : ins_sub_idx;
        assign sf_insert_valid_o[s] = ins_held_q || !ins_sub_none;
        assign sf_insert_addr_o[s]  = {sb_line[ins_idx], {offWidth{1'b0}}};
        assign ins_handshake        = sf_insert_valid_o[s] && sf_insert_ready_i[s];
        assign ins_req_clear_sub[s] = ins_handshake ? (numEntries'(1) << ins_idx) : '0;

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                ins_held_q     <= 1'b0;
                ins_held_idx_q <= '0;
            end else if (ins_handshake) begin
                ins_held_q     <= 1'b0;
            end else if (!ins_sub_none) begin
                ins_held_q     <= 1'b1;
                ins_held_idx_q <= ins_idx;
            end
        end
    end

    always_comb begin : ins_req_clear_comb
        ins_req_clear = '0;
        for (int unsigned s = 0; s < numSub; s++) ins_req_clear |= ins_req_clear_sub[s];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) alloc_q <= '0;
        else         alloc_q <= alloc_d;
    end
//  }}}

//  Snoop filter lookup: issued at admission, and again when a chain that
//  contains an allocator releases us, since that insert postdates the first
//  {{{
    logic [numQueue-1:0][numSub-1:0] present_q, present_d;
    logic [numQueue-1:0]             have_q, have_d;
    logic [numQueue-1:0]             relookup_q, relookup_d;
    logic [numQueue-1:0]             release_now;
    logic [numQueue-1:0]             bypass;
    logic [queueIdxWidth-1:0]        relookup_idx, lookup_target_q, lookup_target_d;
    logic                            relookup_none, lookup_pend_q;

    lzc #(
        .WIDTH (numQueue),
        .MODE  (1'b0)
    ) u_relookup_lzc (
        .in_i    (relookup_q),
        .cnt_o   (relookup_idx),
        .empty_o (relookup_none)
    );

    //  Admission wins the port; a re-lookup is only owed by a stalled entry
    assign sf_lookup_valid_o = alloc || !relookup_none;
    assign sf_lookup_addr_o  = alloc ? ar_i.addr
                                     : {sb_line[queue_q[relookup_idx].sb_idx], {offWidth{1'b0}}};
    assign lookup_target_d   = alloc ? queue_alloc_idx : relookup_idx;

    always_comb begin : lookup_state_comb
        present_d  = present_q;
        have_d     = have_q;
        relookup_d = relookup_q;

        if (lookup_pend_q) begin
            present_d[lookup_target_q] = sf_present_i;
            have_d[lookup_target_q]    = 1'b1;
        end
        if (sf_lookup_valid_o) relookup_d[lookup_target_d] = 1'b0;

        for (int unsigned e = 0; e < numQueue; e++) begin
            if (release_now[e]) begin
                have_d[e]     = 1'b0;
                relookup_d[e] = 1'b1;
            end
        end
        if (alloc) have_d[queue_alloc_idx] = 1'b0;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            present_q       <= '0;
            have_q          <= '0;
            relookup_q      <= '0;
            lookup_pend_q   <= 1'b0;
            lookup_target_q <= '0;
        end else begin
            present_q       <= present_d;
            have_q          <= have_d;
            relookup_q      <= relookup_d;
            lookup_pend_q   <= sf_lookup_valid_o;
            if (sf_lookup_valid_o) lookup_target_q <= lookup_target_d;
        end
    end
//  }}}

//  Queue entry logic
//  {{{
    for (genvar e = 0; e < numQueue; e++) begin : gen_queue
        logic alloc_this;

        assign alloc_this  = alloc && queue_alloc_idx == queueIdxWidth'(e);
        //  A chained entry is released only once its predecessor retired
        assign release_now[e] = queue_valid_q[e] &&
                                pred_valid_q[queue_q[e].sb_idx] &&
                                sb_free[pred_idx_q[queue_q[e].sb_idx]] &&
                                chain_alloc_q[queue_q[e].sb_idx];
        //  The mask lands the cycle the entry first becomes eligible, so it is
        //  read straight off the filter rather than a cycle later
        assign bypass[e]   = lookup_pend_q && lookup_target_q == queueIdxWidth'(e);
        //  An entry may dispatch once nothing precedes it and its mask is known
        assign eligible[e] = queue_valid_q[e] && !pred_valid_q[queue_q[e].sb_idx] &&
                             (have_q[e] || bypass[e]);

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
        .idx_o   (issue_idx)
    );

    assign ar_present_o = have_q[issue_idx] ? present_q[issue_idx] : sf_present_i;
    assign ar_o = issue_entry.ar;
    assign ar_tid_o = issue_entry.sb_idx;
    assign ar_flags_o = ccu_ar_decode(ar_o.bar[0], ar_o.domain, ar_o.snoop, ar_o.lock);

    assign ar_valid_o = arb_req;
    //  The arbiter is instantiated with AxiVldRdy, which drops the request
    //  qualification from its grant, so a bare ready would grant with nothing
    //  requesting and `dispatch` would retire a queue entry that never went out
    assign arb_gnt    = ar_valid_o && ar_ready_i;
    assign dispatch   = gnt;
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    //  managers must not reuse an id across inflight transactions
    //  One RACK per entry, so an entry can never already owe an insert
    for (genvar e = 0; e < numEntries; e++) begin : gen_single_rack_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            rack_mask_i[e] |-> !sb_retired[e])
            else $error("a RACK arrived for an entry that still owes an insert");
    end

    //  An untracked port reuses one id for every read, so it is exempt
    //  An entry outlives its RACK to reach the filter; the manager owns the id
    //  again from the RACK on, so only a pre-RACK entry still holds it
    for (genvar e = 0; e < numEntries; e++) begin : gen_unique_id_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            alloc && !ar_untracked |->
                !(sb_valid[e] && !(rack_mask_i[e] || sb_retired[e]) &&
                  sb_id[e] == ar_i.id))
            else $error("allocating an AR with an id already inflight");
    end

    //  a dispatch that reads the filter combinationally must be the entry
    //  whose lookup is in flight, or it takes another entry's mask
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_valid_o && !have_q[issue_idx] |->
            lookup_pend_q && lookup_target_q == issue_idx)
        else $error("dispatch bypassed a lookup issued for another entry");

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
        (rack_mask_i & ~sb_valid) == '0)
        else $error("RACK retires an entry that is not live");

    for (genvar e = 0; e < numQueue; e++) begin : gen_queue_retire_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            queue_valid_q[e] |-> !rack_mask_i[queue_q[e].sb_idx])
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
