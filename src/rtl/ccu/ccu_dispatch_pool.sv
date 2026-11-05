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

`include "axi/assign.svh"

//! Dispatch pool
//
//  Operations from admission to issue; a tid is taken only at issue.
module ccu_dispatch_pool
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg       = '{default: '0},
    parameter  type         domain_map_t = logic,
    parameter  type         ar_hdr_t     = logic,
    parameter  type         se_tok_t     = logic,
    parameter  type         mgr_ar_t     = logic,
    parameter  type         excl_req_t   = logic,
    parameter  type         issue_t      = logic,
    localparam int unsigned numSub       = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW      = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids      = ccuCfg.numTids,
    localparam int unsigned numReads     = ccuCfg.u.numShareableTransactions,
    localparam int unsigned tidW         = ccuCfg.tidWidth,
    localparam int unsigned numDispatch  = ccuCfg.u.numDispatchSlots,
    localparam int unsigned numBi        = ccuCfg.u.numBackInvalSlots,
    localparam int unsigned biW          = numBi > 1 ? $clog2(numBi) : 1,
    localparam int unsigned numSlots     = numDispatch + numBi,
    localparam int unsigned slotW        = numSlots > 1 ? $clog2(numSlots) : 1,
    localparam int unsigned readPickW    = numDispatch > 1 ? $clog2(numDispatch) : 1,
    localparam int unsigned rSlotW       = ccuCfg.rSlotWidth,
    localparam int unsigned lineW        = ccuCfg.numLineWidth,
    localparam int unsigned offW         = ccuCfg.cachelineByteIndexWidth,
    localparam int unsigned subIdW       = ccuCfg.u.axiSubordinateIdWidth
) (
    input  logic                                   clk_i,
    input  logic                                   rst_ni,

    input  domain_map_t [numSub-1:0]               domain_map_i,

    //  Admission: reads from the ports, back-invalidations on reserved slots
    input  ar_hdr_t     [numSub-1:0]               ar_i,
    input  logic        [numSub-1:0]               ar_valid_i,
    output logic        [numSub-1:0]               ar_ready_o,
    input  logic        [numSub-1:0]               bi_valid_i,
    input  logic        [numSub-1:0][lineW-1:0]    bi_line_i,
    output logic        [numSub-1:0]               bi_ready_o,

    //  Snoop filter lookup at admission; the answer comes two cycles later
    output logic                                   lookup_valid_o,
    output logic        [lineW-1:0]                lookup_line_o,
    input  logic        [numSub-1:0]               lookup_present_i,
    input  logic                                   lookup_ready_i,

    //  Completion buffer: free tids, and the live entries to chain behind
    input  logic        [tidW-1:0]                 cb_read_tid_i,
    input  logic                                   cb_read_full_i,
    input  logic        [tidW-1:0]                 cb_bi_tid_i,
    input  logic                                   cb_bi_full_i,
    input  logic        [numTids-1:0]              cb_live_i,
    input  logic        [numTids-1:0]              cb_tail_i,
    input  logic        [numTids-1:0][lineW-1:0]   cb_line_i,
    input  logic        [numTids-1:0][subIdxW-1:0] cb_port_i,
    input  logic        [numTids-1:0]              cb_insert_pending_i,
    output logic        [numTids-1:0]              cb_tail_clear_o,
    input  logic        [numTids-1:0]              cb_released_i,

    //  Exclusive monitor, asked the cycle before an exclusive issues
    output excl_req_t                              excl_req_o,
    output logic                                   excl_req_valid_o,
    input  ccu_excl_t                              excl_i,

    //  Issue: snoop token, R-slot bind, completion entry
    output se_tok_t                                se_tok_o,
    output logic                                   se_tok_valid_o,
    input  logic                                   se_tok_ready_i,
    input  logic        [numSub-1:0]               ac_room_i,
    output logic        [numSub-1:0]               bind_valid_o,
    output logic        [rSlotW-1:0]               bind_rslot_o,
    output logic        [tidW-1:0]                 bind_tid_o,
    output logic                                   issue_valid_o,
    output logic        [tidW-1:0]                 issue_tid_o,
    output issue_t                                 issue_o,
    output mgr_ar_t                                issue_request_o,

    //  Registered by the table
    output ccu_tt_events_t                         events_o
);

//  Slots
//  {{{
    typedef struct packed {
        logic                valid;
        logic                bi;
        ccu_op_e             op;
        logic [lineW-1:0]    line;
        logic [subIdxW-1:0]  port;
        logic [rSlotW-1:0]   rslot;
        logic                excl_load;
        logic                excl_store;
        logic                owes_insert;
        logic [numSub-1:0]   sel;
        logic                sel_valid;
        //  Ports that predecessors may still add to the filter after our lookup
        logic [numSub-1:0]   chain_mask;
    } slot_t;

    slot_t [numSlots-1:0] slot_q, slot_d;

    function automatic logic [numSub-1:0] port_bit(logic [subIdxW-1:0] port);
        return numSub'(1) << port;
    endfunction
//  }}}

//  Admission: one per cycle, a port read or a back-invalidation
//  {{{
    logic [numSlots-1:0]         read_free;
    logic [slotW-1:0]            read_slot;
    logic                        pool_full;
    logic [numBi-1:0]            bi_free;
    logic [biW-1:0]              bi_slot;
    logic                        bi_slots_full;
    logic [2*numSub-1:0]         admit_req, admit_gnt;
    logic [$clog2(2*numSub)-1:0] admit_idx;
    logic                        admit_valid, admit_is_bi, admit_untracked;
    logic [subIdxW-1:0]          admit_port;
    logic [slotW-1:0]            admit_slot;
    ar_hdr_t                     admit_ar;
    logic [lineW-1:0]            admit_line;
    ccu_op_e                     admit_op;
    logic [numSub-1:0]           admit_domain_sel;
    mgr_ar_t                     admit_mgr_ar;
    slot_t                       admit_init;

    //  Reserved back-invalidation slots are never handed to a read
    for (genvar s = 0; s < numSlots; s++) begin : gen_read_free
        assign read_free[s] = s < numDispatch && !slot_q[s].valid;
    end

    for (genvar k = 0; k < numBi; k++) begin : gen_bi_free
        assign bi_free[k] = !slot_q[numDispatch + k].valid;
    end

    lzc #(
        .WIDTH (numBi),
        .MODE  (1'b0)
    ) u_bi_lzc (
        .in_i    (bi_free),
        .cnt_o   (bi_slot),
        .empty_o (bi_slots_full)
    );

    lzc #(
        .WIDTH (numSlots),
        .MODE  (1'b0)
    ) u_read_lzc (
        .in_i    (read_free),
        .cnt_o   (read_slot),
        .empty_o (pool_full)
    );

    assign admit_req = {bi_valid_i & {numSub{!bi_slots_full}},
                        ar_valid_i & {numSub{!pool_full && lookup_ready_i}}};

    rr_arb_tree #(
        .NumIn     (2*numSub),
        .DataType  (logic),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b0)
    ) u_admit_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (admit_req),
        .gnt_o   (admit_gnt),
        .data_i  ('0),
        .req_o   (admit_valid),
        .gnt_i   (1'b1),
        .data_o  (),
        .idx_o   (admit_idx)
    );

    //  The arbiter grants without a request, so mask here
    assign ar_ready_o  = admit_gnt[numSub-1:0]        & admit_req[numSub-1:0];
    assign bi_ready_o  = admit_gnt[2*numSub-1:numSub] & admit_req[2*numSub-1:numSub];
    assign admit_is_bi = admit_idx >= numSub;
    assign admit_port  = admit_is_bi ? subIdxW'(admit_idx - numSub) : subIdxW'(admit_idx);
    assign admit_slot  = admit_is_bi ? slotW'(numDispatch) + slotW'(bi_slot) : read_slot;
    assign admit_ar    = ar_i[admit_port];
    assign admit_line  = admit_is_bi ? bi_line_i[admit_port] : admit_ar.ar.addr[offW +: lineW];
    assign admit_op    = admit_is_bi ? OpBackInval :
                         ccu_op_decode(admit_ar.ar.bar[0], admit_ar.ar.domain, admit_ar.ar.snoop);

    //  NonShareable and System lines snoop nobody, and nobody snoops its own requester
    always_comb begin : domain_sel_comb
        unique case (admit_ar.ar.domain)
            InnerShareable: admit_domain_sel = domain_map_i[admit_port].inner;
            OuterShareable: admit_domain_sel = domain_map_i[admit_port].outer;
            default:        admit_domain_sel = '0;
        endcase
        admit_domain_sel &= ~port_bit(admit_port);
    end

    //  The memory AR, fixed at admission; its ARID is the tid, set at issue
    always_comb begin : admit_mgr_ar_comb
        `AXI_SET_AR_STRUCT(admit_mgr_ar, admit_ar.ar)
        admit_mgr_ar.id = '0;
        //  The CCU's monitor holds a shareable reservation, not memory's
        if (admit_ar.ar.lock && admit_op inside {OpReadShared, OpReadClean})
            admit_mgr_ar.lock = 1'b0;
        //  A back-invalidation takes no memory AR; its writeback stays modifiable
        if (admit_is_bi) begin
            admit_mgr_ar       = '0;
            admit_mgr_ar.cache = axi_pkg::CACHE_BUFFERABLE | axi_pkg::CACHE_MODIFIABLE |
                                 axi_pkg::CACHE_RD_ALLOC   | axi_pkg::CACHE_WR_ALLOC;
        end
    end

    //  A requester without a snoopable cache never sends an Evict, so its lines stay out
    assign admit_untracked = ccuCfg.u.hasUntrackedArId && !admit_is_bi &&
                             admit_ar.ar.id[subIdW-1:0] == subIdW'(ccuCfg.u.untrackedArId);

    assign lookup_valid_o = admit_valid && !admit_is_bi;
    assign lookup_line_o  = admit_line;
//  }}}

//  Memory AR by slot, moved to the completion buffer at issue
//  {{{
    mgr_ar_t [numSlots-1:0] request_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)          request_q             <= '0;
        else if (admit_valid) request_q[admit_slot] <= admit_mgr_ar;
    end
//  }}}

//  Same-line matches of the admitted line, in the pool and the completion buffer
//  {{{
    logic [numSlots-1:0] pool_line_match;
    logic [numTids-1:0]  cb_line_match, cb_link;
    logic [numSub-1:0]   link_mask;

    for (genvar s = 0; s < numSlots; s++) begin : gen_pool_match
        assign pool_line_match[s] = slot_q[s].valid && slot_q[s].line == admit_line;
    end

    for (genvar t = 0; t < numTids; t++) begin : gen_cb_link
        assign cb_line_match[t] = cb_live_i[t] && cb_line_i[t] == admit_line;
        assign cb_link[t]       = cb_line_match[t] && cb_tail_i[t];
    end

    //  Ports whose insert of the line may still land after our lookup
    always_comb begin : link_mask_comb
        link_mask = '0;
        for (int unsigned s = 0; s < numSlots; s++)
            if (pool_line_match[s] && slot_q[s].owes_insert)
                link_mask |= port_bit(slot_q[s].port);
        for (int unsigned t = 0; t < numTids; t++)
            if (cb_line_match[t] && cb_insert_pending_i[t])
                link_mask |= port_bit(cb_port_i[t]);
    end
//  }}}

//  Issue at the head of the chain; an exclusive asks the monitor and issues a cycle later
//  {{{
    typedef struct packed {
        logic             valid;
        logic [slotW-1:0] slot;
        logic [tidW-1:0]  tid;
    } excl_ask_t;

    logic [numSlots-1:0] issue_cand, issue_ready, waiting;
    logic                issue_tail;
    logic [slotW-1:0]    pick_slot, issue_slot;
    logic                pick_valid, pick_excl, excl_ask, arb_gnt;
    logic                issue;
    logic [tidW-1:0]     pick_tid, issue_tid;
    slot_t               pick_entry, issue_entry;
    logic [numSub-1:0]   issue_sel;
    excl_ask_t           excl_ask_q;

    for (genvar s = 0; s < numSlots; s++) begin : gen_issue_ready
        assign issue_cand[s]  = slot_q[s].valid && slot_q[s].sel_valid && !waiting[s] &&
                                (slot_q[s].sel & ~ac_room_i) == '0;
        assign issue_ready[s] = issue_cand[s] && (slot_q[s].bi ? !cb_bi_full_i : !cb_read_full_i);
    end

    //  Separate pointers, so neither class moves the other's
    logic [numDispatch-1:0] read_issue_req;
    logic [numBi-1:0]       bi_issue_req;
    logic                   read_issue_gnt, bi_issue_gnt;
    logic [readPickW-1:0]   read_pick;
    logic [biW-1:0]         bi_pick;
    logic                   read_pick_valid, bi_pick_valid;

    assign read_issue_req = excl_ask_q.valid ? '0 : issue_ready[numDispatch-1:0];
    assign bi_issue_req   = excl_ask_q.valid ? '0 : issue_ready[numSlots-1:numDispatch];
    assign read_issue_gnt = arb_gnt && !bi_pick_valid;
    assign bi_issue_gnt   = arb_gnt;

    rr_arb_tree #(
        .NumIn     (numDispatch),
        .DataType  (logic),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b0)
    ) u_read_issue_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (read_issue_req),
        .gnt_o   (),
        .data_i  ('0),
        .req_o   (read_pick_valid),
        .gnt_i   (read_issue_gnt),
        .data_o  (),
        .idx_o   (read_pick)
    );

    rr_arb_tree #(
        .NumIn     (numBi),
        .DataType  (logic),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b0)
    ) u_bi_issue_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (bi_issue_req),
        .gnt_o   (),
        .data_i  ('0),
        .req_o   (bi_pick_valid),
        .gnt_i   (bi_issue_gnt),
        .data_o  (),
        .idx_o   (bi_pick)
    );

    //  A back-invalidation goes ahead of a read
    assign pick_valid = bi_pick_valid || read_pick_valid;
    assign pick_slot  = bi_pick_valid ? slotW'(numDispatch) + slotW'(bi_pick) : slotW'(read_pick);

    assign pick_entry = slot_q[pick_slot];
    assign pick_excl  = pick_entry.excl_load || pick_entry.excl_store;
    assign pick_tid   = pick_entry.bi ? cb_bi_tid_i : cb_read_tid_i;
    assign excl_ask   = pick_valid && pick_excl;

    assign issue_slot     = excl_ask_q.valid ? excl_ask_q.slot : pick_slot;
    assign issue_tid      = excl_ask_q.valid ? excl_ask_q.tid  : pick_tid;
    assign issue_entry    = slot_q[issue_slot];
    assign se_tok_valid_o = excl_ask_q.valid || (pick_valid && !pick_excl);
    assign issue          = se_tok_valid_o && se_tok_ready_i;
    assign arb_gnt        = excl_ask || (!excl_ask_q.valid && issue);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)       excl_ask_q <= '0;
        else if (excl_ask) excl_ask_q <= '{valid: 1'b1, slot: pick_slot, tid: pick_tid};
        else if (issue)    excl_ask_q <= '0;
    end

    //  Exclusives are decided here, in line order
    assign excl_req_valid_o = excl_ask;
    assign excl_req_o       = '{port:  pick_entry.port, line: pick_entry.line,
                                tid:   pick_tid,
                                load:  pick_entry.excl_load,
                                store: pick_entry.excl_store};

    //  A failed store-conditional snoops nobody
    assign issue_sel = excl_ask_q.valid && excl_i.fail ? '0 : issue_entry.sel;

    assign se_tok_o = '{
        tid:  issue_tid,
        op:   issue_entry.op,
        excl: excl_ask_q.valid ? excl_i : ccu_excl_t'('0),
        ac:   '{addr:  {issue_entry.line, {offW{1'b0}}},
                snoop: ccu_op_acsnoop(issue_entry.op),
                prot:  request_q[issue_slot].prot},
        sel:  issue_sel
    };

    for (genvar p = 0; p < numSub; p++) begin : gen_bind
        assign bind_valid_o[p] = issue && !issue_entry.bi && issue_entry.port == subIdxW'(p);
    end
    assign bind_rslot_o = issue_entry.rslot;
    assign bind_tid_o   = issue_tid;

    assign issue_valid_o = issue;
    assign issue_tid_o   = issue_tid;
    assign issue_o       = '{bi:          issue_entry.bi,
                             line:        issue_entry.line,
                             port:        issue_entry.port,
                             rslot:       issue_entry.rslot,
                             tail:        issue_tail,
                             //  A failed store-conditional changes no line state
                             owes_insert: issue_entry.owes_insert &&
                                          !(excl_ask_q.valid && excl_i.fail),
                             exokay:      excl_ask_q.valid && excl_i.pass};

    always_comb begin : issue_request_comb
        issue_request_o = request_q[issue_slot];
        issue_request_o.id[tidW-1:0] = issue_tid;
    end
//  }}}

//  Line chains; a back-invalidation goes ahead of unissued reads
//  {{{
    logic [numSlots-1:0] pool_committed;

    //  Issuing now, or an exclusive that won the arbiter and issues next cycle
    for (genvar s = 0; s < numSlots; s++) begin : gen_pool_committed
        assign pool_committed[s] = (issue && issue_slot == slotW'(s)) ||
                                   (excl_ask && pick_slot == slotW'(s)) ||
                                   (excl_ask_q.valid && excl_ask_q.slot == slotW'(s));
    end

    ccu_line_chain #(
        .numSlots (numSlots),
        .numTids  (numTids)
    ) u_line_chain (
        .clk_i,
        .rst_ni,
        .admit_valid_i   (admit_valid),
        .admit_slot_i    (admit_slot),
        .admit_ahead_i   (admit_is_bi),
        .line_match_i    (pool_line_match),
        .cb_link_i       (cb_link),
        .cb_tail_clear_o,
        .issue_valid_i   (issue),
        .issue_slot_i    (issue_slot),
        .issue_tid_i     (issue_tid),
        .committed_i     (pool_committed),
        .issue_tail_o    (issue_tail),
        .released_i      (cb_released_i),
        .waiting_o       (waiting)
    );
//  }}}

//  The filter answer lands two cycles after admission, with the chain's superset
//  {{{
    typedef struct packed {
        logic              valid;
        logic [slotW-1:0]  slot;
        logic [numSub-1:0] domain;
    } lookup_pending_t;

    lookup_pending_t   lookup_read_q, lookup_answer_q;
    logic [numSub-1:0] lookup_sel;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lookup_read_q   <= '0;
            lookup_answer_q <= '0;
        end else begin
            lookup_read_q   <= lookup_pending_t'{
                valid:  lookup_valid_o && ccuCfg.u.enableSnoopFilter,
                slot:   admit_slot,
                domain: admit_domain_sel
            };
            lookup_answer_q <= lookup_read_q;
        end
    end

    assign lookup_sel = lookup_answer_q.domain &
                        (lookup_present_i | slot_q[lookup_answer_q.slot].chain_mask);
//  }}}

//  Slot updates
//  {{{
    always_comb begin : admit_init_comb
        admit_init             = '0;
        admit_init.valid       = 1'b1;
        admit_init.bi          = admit_is_bi;
        admit_init.op          = admit_op;
        admit_init.line        = admit_line;
        admit_init.port        = admit_port;
        admit_init.rslot       = admit_is_bi ? '0 : admit_ar.rslot;
        admit_init.excl_load   = !admit_is_bi && admit_ar.ar.lock &&
                                 admit_op inside {OpReadShared, OpReadClean};
        admit_init.excl_store  = !admit_is_bi && admit_ar.ar.lock && admit_op == OpCleanUnique;
        admit_init.owes_insert = !admit_is_bi && ccuCfg.u.enableSnoopFilter &&
                                 ccu_op_allocates(admit_op) && !admit_untracked;
        //  A back-invalidation snoops its table's port alone
        admit_init.sel         = admit_is_bi                  ? port_bit(admit_port) :
                                 !ccuCfg.u.enableSnoopFilter ? admit_domain_sel     : '0;
        admit_init.sel_valid   = admit_is_bi || !ccuCfg.u.enableSnoopFilter;
        admit_init.chain_mask  = link_mask;
    end

    for (genvar s = 0; s < numSlots; s++) begin : gen_slot
        always_comb begin : slot_comb
            slot_d[s] = slot_q[s];

            if (lookup_answer_q.valid && lookup_answer_q.slot == slotW'(s)) begin
                slot_d[s].sel       = lookup_sel;
                slot_d[s].sel_valid = 1'b1;
            end

            if (issue && issue_slot == slotW'(s)) slot_d[s] = '0;

            if (admit_valid && admit_slot == slotW'(s)) slot_d[s] = admit_init;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) slot_q <= '0;
        else         slot_q <= slot_d;
    end
//  }}}

//  Performance events
//  {{{
    logic [numSlots-1:0] wait_ac_room, wait_tid;

    for (genvar s = 0; s < numSlots; s++) begin : gen_event_taps
        assign wait_ac_room[s] = slot_q[s].valid && slot_q[s].sel_valid && !waiting[s] &&
                                (slot_q[s].sel & ~ac_room_i) != '0;
        assign wait_tid[s]    = issue_cand[s] && !issue_ready[s];
    end

    always_comb begin : events_comb
        events_o                    = '0;
        events_o.admit_read         = admit_valid && !admit_is_bi;
        events_o.admit_back_inval   = admit_valid && admit_is_bi;
        events_o.admit_stall_full   = |ar_valid_i && pool_full;
        events_o.chained            = admit_valid && (|pool_line_match || |cb_link);
        events_o.snoop_token        = issue;
        events_o.snoop_stall_ac_full = |wait_ac_room;
        events_o.issue_stall_tid    = |wait_tid;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    localparam int unsigned livenessBound = 100000;

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        $countones({ar_ready_o & ar_valid_i, bi_ready_o & bi_valid_i}) == (admit_valid ? 1 : 0))
        else $error("an admission handshake without an admission, or the reverse");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        admit_valid |-> !slot_q[admit_slot].valid)
        else $error("admission into a live slot");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        admit_valid && !admit_is_bi |-> admit_slot < numDispatch)
        else $error("a read took a reserved back-invalidation slot");

    for (genvar s = 0; s < numSlots; s++) begin : gen_slot_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            slot_q[s].valid && u_line_chain.link_q[s].pred_valid &&
            u_line_chain.link_q[s].pred_in_pool |->
                slot_q[u_line_chain.link_q[s].pred_idx].valid &&
                slot_q[u_line_chain.link_q[s].pred_idx].line == slot_q[s].line)
            else $error("chained slot waits on a free or foreign pool slot");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            slot_q[s].valid && u_line_chain.link_q[s].pred_valid &&
            !u_line_chain.link_q[s].pred_in_pool |->
                cb_line_i[u_line_chain.link_q[s].pred_idx] == slot_q[s].line)
            else $error("chained slot waits on a foreign tid");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            slot_q[s].valid && s >= numDispatch |-> slot_q[s].bi)
            else $error("a reserved slot holds a read");

        //  Every slot issues: nothing it waits on is unbounded
        int unsigned age_q;
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni)                                    age_q <= 0;
            else if (!slot_q[s].valid || issue && issue_slot == slotW'(s)) age_q <= 0;
            else                                            age_q <= age_q + 1;
        end

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            age_q < livenessBound)
            else $error("pool slot %0d waited %0d cycles to issue", s, livenessBound);
    end

    //  A slot requesting at every read grant is passed over fewer times than there are slots
    for (genvar s = 0; s < numDispatch; s++) begin : gen_read_fairness_assert
        int unsigned passed_q;

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni)                                           passed_q <= 0;
            else if (!read_issue_gnt)                              passed_q <= passed_q;
            else if (!read_issue_req[s])                           passed_q <= 0;
            else if (read_pick == readPickW'(s))                   passed_q <= 0;
            else                                                   passed_q <= passed_q + 1;
        end

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            passed_q < numDispatch)
            else $error("read slot %0d passed over by %0d read issues", s, numDispatch);
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        excl_ask_q.valid |-> issue_cand[excl_ask_q.slot] && !cb_live_i[excl_ask_q.tid])
        else $error("an exclusive lost its readiness while the monitor answered");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        |bi_ready_o |-> !bi_slots_full)
        else $error("back-invalidation admitted with no reserved slot free");
    `endif
    // pragma translate_on
//  }}}
endmodule
