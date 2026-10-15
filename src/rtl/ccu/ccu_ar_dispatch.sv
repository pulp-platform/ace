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
//  Serializes same-address ARs via predecessor chains; different addresses
//  dispatch in parallel. Entries retire on RACK.
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
    output logic                 sf_lookup_valid_o,
    output logic [addrWidth-1:0] sf_lookup_addr_o,
    input  logic [numSub-1:0]    sf_present_i,

    //  Entries whose RACK arrived this cycle, one bit per scoreboard entry
    input  logic [numEntries-1:0] rack_mask_i,

    //  Those of them whose read errored; the line was never cached
    input  logic [numEntries-1:0] rack_error_i,

    //  Transaction dropped downstream, so it allocates nothing
    input  logic                 drop_valid_i,
    input  logic [sbIdxWidth-1:0] drop_tid_i,

    //  Snoop filter allocation, raised at RACK and held until it retires
    output logic [numSub-1:0]                 sf_insert_valid_o,
    output logic [numSub-1:0][addrWidth-1:0]  sf_insert_addr_o,
    input  logic [numSub-1:0]                 sf_insert_ready_i,

    //  Scoreboard ids, indexed by tid to restore the id of a memory read
    output logic [numEntries-1:0][ccuCfg.axiCcuIdWidth-1:0] sb_id_o,

    //  Back-invalidation attempts, one per subordinate, straight off the filter
    input  logic [numSub-1:0][addrWidth-1:0] bi_addr_i,
    input  logic [numSub-1:0]                bi_busy_i,
    output logic [numSub-1:0]                bi_hazard_o
);

//  Dispatch queue: holds the AR only until it is dispatched
//  {{{
    typedef struct packed {
        ccu_ace_ar_t             ar;
        logic [sbIdxWidth-1:0]   sb_idx;
        logic [numSub-1:0]       mask;
        logic                    mask_valid;
    } queue_entry_t;

    queue_entry_t [numQueue-1:0]      queue_q, queue_d;
    logic         [numQueue-1:0]      queue_valid_q, queue_valid_d;
    logic         [queueIdxWidth-1:0] queue_alloc_idx;
    logic                             queue_full;

    logic [numQueue-1:0]      eligible;
    logic [numQueue-1:0]      arb_ready;
    logic [numQueue-1:0]      dispatch;
    queue_entry_t             issue_entry;

    logic          alloc;
    ccu_ar_flags_t ar_flags;
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
    logic [numEntries-1:0]                               sb_valid;
    logic [numEntries-1:0][lineWidth-1:0]                sb_line;
    logic [numEntries-1:0][ccuCfg.axiCcuIdWidth-1:0]     sb_id;
    logic [sbIdxWidth-1:0]                               sb_alloc_idx;
    logic                                                sb_full;
    logic [numEntries-1:0]                               sb_free;
    logic [numEntries-1:0]                               alloc_q, alloc_d;
    logic [numEntries-1:0]                               sb_retired;
    logic [numEntries-1:0]                               ins_req_set, ins_req_clear;

    //  Full line address for the filter; chains match on the hazard slice
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

    //  Untracked port: no snoops, no Evicts, so its lines are never tracked
    localparam logic [subIdWidth-1:0] untrackedId = subIdWidth'(ccuCfg.u.untrackedArId);

    assign ar_untracked   = ccuCfg.u.hasUntrackedArId &&
                            ar_i.id[subIdWidth-1:0] == untrackedId;

    assign ar_flags = ccu_ar_decode(ar_i.bar[0], ar_i.domain,
                                    ar_i.snoop,  ar_i.lock);
    assign ar_flags_alloc = !ar_untracked && ar_flags.allocates;

//  }}}

//  Same-address chains: link behind the tail on allocation, become the tail
//  {{{
    logic [numEntries-1:0]                 tail_q,        tail_d;
    logic [numEntries-1:0]                 pred_valid_q,  pred_valid_d;
    logic [numEntries-1:0][sbIdxWidth-1:0] pred_idx_q,    pred_idx_d;
    logic [numEntries-1:0]                 tail_match, tail_link;
    logic [sbIdxWidth-1:0]                 tail_idx;

    //  Match: a live tail on the line; link: the one we chain behind, unless it frees this cycle
    for (genvar e = 0; e < numEntries; e++) begin : gen_tail_match
        assign tail_match[e] = sb_valid[e] && tail_q[e] &&
            sb_line[e][chainWidth-1:0] == ar_i.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
        assign tail_link[e]  = tail_match[e] && !sb_free[e];
    end

    onehot_to_bin #(
        .ONEHOT_WIDTH (numEntries)
    ) u_tail_onehot_to_bin (
        .onehot (tail_link),
        .bin    (tail_idx)
    );

    always_comb begin : chain_comb
        tail_d       = tail_q;
        pred_valid_d = pred_valid_q;
        pred_idx_d   = pred_idx_q;

        //  Release the successor only once our line is in the filter
        for (int unsigned e = 0; e < numEntries; e++) begin
            if (pred_valid_q[e] && sb_free[pred_idx_q[e]])
                pred_valid_d[e] = 1'b0;
        end

        if (alloc) begin
            tail_d[sb_alloc_idx]       = 1'b1;
            pred_valid_d[sb_alloc_idx] = |tail_link;
            pred_idx_d[sb_alloc_idx]   = tail_idx;
            if (|tail_link) tail_d[tail_idx] = 1'b0;
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

    logic [numEntries-1:0][sbIdxWidth-1:0] ins_entry_idx;

    for (genvar e = 0; e < numEntries; e++) begin : gen_ins_entry_idx
        assign ins_entry_idx[e] = sbIdxWidth'(e);
    end

    //  Retired entries owe their insert; the scoreboard holds them until it lands
    for (genvar s = 0; s < numSub; s++) begin : gen_ins_port
        logic [numEntries-1:0] ins_sub_valid, ins_sub_ready;
        logic [sbIdxWidth-1:0] ins_idx;

        for (genvar e = 0; e < numEntries; e++) begin : gen_ins_sub_valid
            assign ins_sub_valid[e] = sb_retired[e] &&
                sb_id[e][ccuCfg.u.axiSubordinateIdWidth +: subIdxWidth] == subIdxWidth'(s);
        end

        stream_arbiter #(
            .DATA_T  (logic [sbIdxWidth-1:0]),
            .N_INP   (numEntries),
            .ARBITER ("rr")
        ) u_ins_arbiter (
            .clk_i,
            .rst_ni,
            .inp_data_i  (ins_entry_idx),
            .inp_valid_i (ins_sub_valid),
            .inp_ready_o (ins_sub_ready),
            .oup_data_o  (ins_idx),
            .oup_valid_o (sf_insert_valid_o[s]),
            .oup_ready_i (sf_insert_ready_i[s])
        );

        assign sf_insert_addr_o[s]  = {sb_line[ins_idx], {offWidth{1'b0}}};
        assign ins_req_clear_sub[s] = ins_sub_valid & ins_sub_ready;
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

//  Snoop filter lookup: unchained entries at admission, chained ones once released
//  {{{
    logic [numQueue-1:0]             lookup_need;
    logic [numQueue-1:0]             bi_blocked;
    logic [numQueue-1:0]             bypass;
    logic [queueIdxWidth-1:0]        need_idx, lookup_target_q, lookup_target_d;
    logic                            need_none, lookup_pend_q, admit_lookup;

    lzc #(
        .WIDTH (numQueue),
        .MODE  (1'b0)
    ) u_lookup_lzc (
        .in_i    (lookup_need),
        .cnt_o   (need_idx),
        .empty_o (need_none)
    );

    //  Admission wins the port; a chained entry's mask would go stale behind its predecessor
    //  A tail freed this cycle defers the lookup: sb_free depends on the filter's insert ready
    assign admit_lookup      = alloc && !(|tail_match);
    assign sf_lookup_valid_o = admit_lookup || !need_none;
    assign sf_lookup_addr_o  = admit_lookup ? ar_i.addr
                                            : {sb_line[queue_q[need_idx].sb_idx], {offWidth{1'b0}}};
    assign lookup_target_d   = admit_lookup ? queue_alloc_idx : need_idx;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lookup_pend_q    <= 1'b0;
            lookup_target_q  <= '0;
        end else begin
            lookup_pend_q    <= sf_lookup_valid_o;
            if (sf_lookup_valid_o) lookup_target_q <= lookup_target_d;
        end
    end
//  }}}

//  Back-invalidation hazards (C6.2): no snoop before the RACK, no R before the CR
//  {{{
    logic [numEntries-1:0] sb_queued;

    always_comb begin : sb_queued_comb
        sb_queued = '0;
        for (int unsigned e = 0; e < numQueue; e++)
            if (queue_valid_q[e]) sb_queued[queue_q[e].sb_idx] = 1'b1;
    end

    //  A queued entry that is not eligible is blocked from the first busy cycle instead
    for (genvar s = 0; s < numSub; s++) begin : gen_bi_hazard
        logic [numEntries-1:0] sent_hit;
        logic [numQueue-1:0]   eligible_hit;

        for (genvar e = 0; e < numEntries; e++) begin : gen_sent_hit
            assign sent_hit[e] = sb_valid[e] && !sb_queued[e] &&
                !sb_retired[e] && !rack_mask_i[e] &&
                sb_id[e][ccuCfg.u.axiSubordinateIdWidth +: subIdxWidth] == subIdxWidth'(s) &&
                sb_line[e][chainWidth-1:0] ==
                    bi_addr_i[s][ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
        end

        for (genvar e = 0; e < numQueue; e++) begin : gen_eligible_hit
            assign eligible_hit[e] = eligible[e] &&
                queue_q[e].ar.id[ccuCfg.u.axiSubordinateIdWidth +: subIdxWidth] == subIdxWidth'(s) &&
                queue_q[e].ar.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb] ==
                    bi_addr_i[s][ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
        end

        assign bi_hazard_o[s] = |sent_hit || |eligible_hit;
    end
//  }}}

//  Queue entry logic
//  {{{
    for (genvar e = 0; e < numQueue; e++) begin : gen_queue
        logic                    alloc_this;
        logic [subIdxWidth-1:0]  queue_sub;

        assign alloc_this = alloc && queue_alloc_idx == queueIdxWidth'(e);
        assign queue_sub  = queue_q[e].ar.id[ccuCfg.u.axiSubordinateIdWidth +: subIdxWidth];
        //  Own subordinate is being snooped for this line, or still owes the CR
        assign bi_blocked[e] = bi_busy_i[queue_sub] &&
            bi_addr_i[queue_sub][ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb] ==
                queue_q[e].ar.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
        //  Take the mask straight off the filter on its lookup cycle
        assign bypass[e]      = lookup_pend_q && lookup_target_q == queueIdxWidth'(e);
        //  Nothing precedes it and no mask is known or answering
        assign lookup_need[e] = queue_valid_q[e] && !pred_valid_q[queue_q[e].sb_idx] &&
                                !queue_q[e].mask_valid && !bypass[e];
        //  An entry may dispatch once nothing precedes it and its mask is known
        assign eligible[e] = queue_valid_q[e] && !pred_valid_q[queue_q[e].sb_idx] &&
                             !bi_blocked[e] && (queue_q[e].mask_valid || bypass[e]);

        always_comb begin : queue_entry_comb
            queue_valid_d[e] = queue_valid_q[e];
            if (dispatch[e])       queue_valid_d[e] = 1'b0;
            else if (alloc_this)   queue_valid_d[e] = 1'b1;

            queue_d[e] = queue_q[e];
            if (bypass[e]) begin
                queue_d[e].mask       = sf_present_i;
                queue_d[e].mask_valid = 1'b1;
            end
            if (alloc_this)
                queue_d[e] = '{ar: ar_i, sb_idx: sb_alloc_idx, mask: '0, mask_valid: 1'b0};
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                queue_valid_q[e] <= 1'b0;
                queue_q[e]       <= '0;
            end else begin
                queue_valid_q[e] <= queue_valid_d[e];
                queue_q[e]       <= queue_d[e];
            end
        end
    end
//  }}}

//  Dispatch arbitration
//  {{{
    stream_arbiter #(
        .DATA_T  (queue_entry_t),
        .N_INP   (numQueue),
        .ARBITER ("rr")
    ) u_dispatch_arbiter (
        .clk_i,
        .rst_ni,
        .inp_data_i  (queue_q),
        .inp_valid_i (eligible),
        .inp_ready_o (arb_ready),
        .oup_data_o  (issue_entry),
        .oup_valid_o (ar_valid_o),
        .oup_ready_i (ar_ready_i)
    );

    //  A bypassed entry is dispatched on its lookup cycle
    assign ar_present_o = issue_entry.mask_valid ? issue_entry.mask : sf_present_i;
    assign ar_o         = issue_entry.ar;
    assign ar_tid_o     = issue_entry.sb_idx;
    assign ar_flags_o   = ccu_ar_decode(ar_o.bar[0], ar_o.domain, ar_o.snoop, ar_o.lock);
    assign dispatch     = eligible & arb_ready;
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    //  one RACK per entry
    for (genvar e = 0; e < numEntries; e++) begin : gen_single_rack_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            rack_mask_i[e] |-> !sb_retired[e])
            else $error("a RACK arrived for an entry that still owes an insert");
    end

    //  ids are unique among pre-RACK entries; untracked ports are exempt
    for (genvar e = 0; e < numEntries; e++) begin : gen_unique_id_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            alloc && !ar_untracked |->
                !(sb_valid[e] && !(rack_mask_i[e] || sb_retired[e]) &&
                  sb_id[e] == ar_i.id))
            else $error("allocating an AR with an id already inflight");
    end

    //  a bypassed mask belongs to the dispatched entry
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_valid_o && !issue_entry.mask_valid |->
            lookup_pend_q && queue_q[lookup_target_q].sb_idx == issue_entry.sb_idx)
        else $error("dispatch bypassed a lookup issued for another entry");

    //  an eligible entry never becomes blocked
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        $rose(|(bi_blocked & queue_valid_q)) |->
            !$past(|(~bi_blocked & queue_valid_q & eligible)))
        else $error("a back-invalidation blocked an entry that was eligible");

    //  nothing is presented for a line its subordinate is being back-invalidated for
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_valid_o |->
            !(bi_busy_i[issue_entry.ar.id[ccuCfg.u.axiSubordinateIdWidth +: subIdxWidth]] &&
              bi_addr_i[issue_entry.ar.id[ccuCfg.u.axiSubordinateIdWidth +: subIdxWidth]]
                       [ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb] ==
              issue_entry.ar.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb]))
        else $error("an AR was presented while its subordinate is back-invalidated for the line");

    //  every address chain has a single tail
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        alloc |-> $onehot0(tail_link))
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
