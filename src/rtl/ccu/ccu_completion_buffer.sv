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

//! Completion buffer
//
//  Issued operations by tid, from snoop token to free.
module ccu_completion_buffer
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg          = '{default: '0},
    parameter  type         issue_t         = logic,
    parameter  type         se_resolve_t    = logic,
    parameter  type         me_tok_t        = logic,
    parameter  type         mgr_ar_t        = logic,
    parameter  type         writeback_req_t = logic,
    parameter  type         route_t         = logic,
    parameter  type         r_info_t        = logic,
    localparam int unsigned numSub          = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW         = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids         = ccuCfg.numTids,
    localparam int unsigned numReads        = ccuCfg.u.numShareableTransactions,
    localparam int unsigned numBi           = ccuCfg.u.numBackInvalSlots,
    localparam int unsigned biW             = numBi > 1 ? $clog2(numBi) : 1,
    localparam int unsigned tidW            = ccuCfg.tidWidth,
    localparam int unsigned rSlotW          = ccuCfg.rSlotWidth,
    localparam int unsigned wSlotW          = ccuCfg.wSlotWidth,
    localparam int unsigned lineW           = ccuCfg.numLineWidth
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    //  Tids free for issue: the lowest free read tid and back-invalidation tid
    output logic        [tidW-1:0]              read_tid_o,
    output logic                                read_full_o,
    output logic        [tidW-1:0]              bi_tid_o,
    output logic                                bi_full_o,

    //  Issue from the dispatch pool, with the memory AR its ARID already set
    input  logic                                issue_valid_i,
    input  logic        [tidW-1:0]              issue_tid_i,
    input  issue_t                              issue_i,
    input  mgr_ar_t                             issue_request_i,

    //  What admission links behind and widens the snoop selection with
    output logic        [numTids-1:0]           live_o,
    output logic        [numTids-1:0]           tail_o,
    output logic        [numTids-1:0][lineW-1:0] line_o,
    output logic        [numTids-1:0][subIdxW-1:0] port_o,
    output logic        [numTids-1:0]           insert_pending_o,
    input  logic        [numTids-1:0]           tail_clear_i,
    //  A successor may go: its predecessor is acknowledged or freeing
    output logic        [numTids-1:0]           released_o,

    input  se_resolve_t                         se_resolve_i,
    input  logic                                se_resolve_valid_i,
    output logic                                se_resolve_ready_o,

    //  Write lane: a writeback slot for each snoop writeback
    output writeback_req_t                      writeback_o,
    output logic                                writeback_valid_o,
    input  logic                                writeback_ready_i,
    input  logic        [wSlotW-1:0]            writeback_slot_i,

    //  Memory engine
    output me_tok_t                             me_tok_o,
    output logic                                me_tok_valid_o,
    input  logic                                me_tok_ready_i,
    //  The memory AR of a tid, read by the memory engine when it issues
    input  logic        [tidW-1:0]              mem_ar_tid_i,
    output mgr_ar_t                             mem_ar_o,
    input  logic        [numTids-1:0]           mem_done_i,

    //  From the ports: a tid's CD consumed, a tid's RACK
    input  logic        [numSub-1:0]            cd_done_i,
    input  logic        [numSub-1:0][tidW-1:0]  cd_done_tid_i,
    input  logic        [numSub-1:0]            rack_i,
    input  logic        [numSub-1:0][tidW-1:0]  rack_tid_i,

    //  To the ports at resolve: CD routing to all, the R response to the initiator
    output logic                                route_valid_o,
    output route_t                              route_o,
    output logic        [numSub-1:0]            r_info_valid_o,
    output r_info_t                             r_info_o,
    //  R slots whose ACK waited for its writeback data and may go now
    output logic        [numSub-1:0][ccuCfg.u.numRSlots-1:0] r_go_o,

    //  Snoop filter updates: one insert channel to a free table, landings back per table
    output logic                                insert_valid_o,
    output logic        [subIdxW-1:0]           insert_port_o,
    output logic        [lineW-1:0]             insert_line_o,
    output logic        [tidW-1:0]              insert_tid_o,
    input  logic        [numSub-1:0]            insert_free_i,
    input  logic        [numSub-1:0]            insert_done_i,
    input  logic        [numSub-1:0][tidW-1:0]  insert_done_tid_i,
    output logic                                cr_remove_valid_o,
    output logic        [numSub-1:0]            cr_remove_sel_o,
    output logic        [lineW-1:0]             cr_remove_line_o,
    output logic        [tidW-1:0]              cr_remove_tid_o,
    input  logic                                cr_remove_ready_i,

    output ccu_tt_events_t                      events_o,
    output logic        [numTids-1:0]           acked_o,
    output logic        [numTids-1:0]           free_o
);

//  Entries
//  {{{
    typedef struct packed {
        logic                valid;
        logic                bi;
        logic [lineW-1:0]    line;
        logic [subIdxW-1:0]  port;
        logic [rSlotW-1:0]   rslot;
        logic                tail;
        logic                owes_insert;
        logic                exokay;
        //  Progress
        logic                resolved;
        ccu_actions_t        pending;
        ccu_actions_t        done;
        logic                is_shared;
        logic                pass_dirty;
        logic [subIdxW-1:0]  src;
        logic [wSlotW-1:0]   wslot;
        logic [numSub-1:0]   cd_wait;
        logic                responding;
        logic                acked;
        logic                ins_owed;
        logic                ins_sent;
    } state_t;

    typedef struct packed {
        state_t              state;
        logic                freeing;
        logic                acked_now;
        logic                respond_late;
    } status_t;

    status_t [numTids-1:0] st;
    logic    [numTids-1:0] valid, freeing;

    for (genvar t = 0; t < numTids; t++) begin : gen_status
        assign valid[t]            = st[t].state.valid;
        assign freeing[t]          = st[t].freeing;
        assign acked_o[t]          = st[t].state.acked;
        assign live_o[t]           = valid[t] && !freeing[t];
        assign tail_o[t]           = st[t].state.tail;
        assign line_o[t]           = st[t].state.line;
        assign port_o[t]           = st[t].state.port;
        assign insert_pending_o[t] = (st[t].state.owes_insert && !st[t].state.acked) ||
                                     st[t].state.ins_owed;
        assign released_o[t]       = freeing[t] || st[t].acked_now;
    end

    assign free_o = freeing;
//  }}}

//  Tid allocation: reserved back-invalidation tids are never handed to a read
//  {{{
    logic [numTids-1:0] read_free;
    logic [numBi-1:0]   bi_free;
    logic [biW-1:0]     bi_idx;

    for (genvar t = 0; t < numTids; t++) begin : gen_read_free
        assign read_free[t] = t < numReads && !valid[t];
    end

    for (genvar k = 0; k < numBi; k++) begin : gen_bi_free
        assign bi_free[k] = !valid[numReads + k];
    end

    lzc #(
        .WIDTH (numBi),
        .MODE  (1'b0)
    ) u_bi_lzc (
        .in_i    (bi_free),
        .cnt_o   (bi_idx),
        .empty_o (bi_full_o)
    );

    assign bi_tid_o = tidW'(numReads) + tidW'(bi_idx);

    lzc #(
        .WIDTH (numTids),
        .MODE  (1'b0)
    ) u_read_lzc (
        .in_i    (read_free),
        .cnt_o   (read_tid_o),
        .empty_o (read_full_o)
    );
//  }}}

//  Memory AR by tid, written at issue
//  {{{
    mgr_ar_t [numTids-1:0] request_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)            request_q              <= '0;
        else if (issue_valid_i) request_q[issue_tid_i] <= issue_request_i;
    end

    assign mem_ar_o = request_q[mem_ar_tid_i];
//  }}}

//  Resolve: a writeback takes a writeback slot before the entry moves on
//  {{{
    logic            resolve_accept, remove_ok;
    ccu_actions_t    resolve_act;
    logic [tidW-1:0] resolve_tid;
    state_t          resolve_entry;

    assign resolve_tid    = se_resolve_i.tid;
    assign resolve_act    = se_resolve_i.outcome.actions;
    assign resolve_entry  = st[resolve_tid].state;
    assign remove_ok      = se_resolve_i.remove == '0 || !ccuCfg.u.enableSnoopFilter ||
                            cr_remove_ready_i;

    assign se_resolve_ready_o = (!resolve_act.cd_wb || writeback_ready_i) && remove_ok &&
                                (!resolve_act.mem_rd || me_tok_ready_i);
    assign resolve_accept     = se_resolve_valid_i && se_resolve_ready_o;

    assign writeback_valid_o = se_resolve_valid_i && resolve_act.cd_wb && remove_ok &&
                               (!resolve_act.mem_rd || me_tok_ready_i);
    assign writeback_o       = '{line:   resolve_entry.line,
                                 cache:  request_q[resolve_tid].cache,
                                 prot:   request_q[resolve_tid].prot,
                                 qos:    request_q[resolve_tid].qos,
                                 region: request_q[resolve_tid].region,
                                 user:   request_q[resolve_tid].user};

    assign me_tok_valid_o = se_resolve_valid_i && resolve_act.mem_rd && remove_ok &&
                            (!resolve_act.cd_wb || writeback_ready_i);
    assign me_tok_o       = '{tid: resolve_tid, port: resolve_entry.port,
                              rslot: resolve_entry.rslot};

    assign cr_remove_valid_o = ccuCfg.u.enableSnoopFilter && se_resolve_valid_i &&
                               se_resolve_i.remove != '0 &&
                               (!resolve_act.cd_wb || writeback_ready_i) &&
                               (!resolve_act.mem_rd || me_tok_ready_i);
    assign cr_remove_sel_o   = se_resolve_i.remove;
    assign cr_remove_line_o  = resolve_entry.line;
    assign cr_remove_tid_o   = resolve_tid;
//  }}}

//  Filter inserts, owed from the ACK: sent to a free table, owed until they land
//  {{{
    logic [numTids-1:0] ins_req, ins_sent, ins_done;

    for (genvar t = 0; t < numTids; t++) begin : gen_ins_req
        assign ins_req[t]  = st[t].state.ins_owed && !st[t].state.ins_sent &&
                             insert_free_i[st[t].state.port];
        assign ins_sent[t] = insert_valid_o && insert_tid_o == tidW'(t);
    end

    always_comb begin : ins_done_comb
        ins_done = '0;
        for (int unsigned p = 0; p < numSub; p++)
            if (insert_done_i[p]) ins_done[insert_done_tid_i[p]] = 1'b1;
    end

    //  A free table takes the insert at once, so nothing waits on the pick
    rr_arb_tree #(
        .NumIn     (numTids),
        .DataType  (logic),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b0)
    ) u_ins_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (ins_req),
        .gnt_o   (),
        .data_i  ('0),
        .req_o   (insert_valid_o),
        .gnt_i   (1'b1),
        .data_o  (),
        .idx_o   (insert_tid_o)
    );

    assign insert_port_o = st[insert_tid_o].state.port;
    assign insert_line_o = st[insert_tid_o].state.line;
//  }}}

//  Per-tid events, and the entries
//  {{{
    logic [numTids-1:0]             rack_mask;
    logic [numTids-1:0][numSub-1:0] cd_done_port;

    always_comb begin : port_events_comb
        rack_mask    = '0;
        cd_done_port = '0;
        for (int unsigned p = 0; p < numSub; p++) begin
            if (rack_i[p])    rack_mask[rack_tid_i[p]] = 1'b1;
            if (cd_done_i[p]) cd_done_port[cd_done_tid_i[p]][p] = 1'b1;
        end
    end

    for (genvar t = 0; t < numTids; t++) begin : gen_entry
        ccu_completion_entry #(
            .ccuCfg   (ccuCfg),
            .init_t   (issue_t),
            .state_t  (state_t),
            .status_t (status_t)
        ) u_entry (
            .clk_i,
            .rst_ni,
            .issue_i      (issue_valid_i && issue_tid_i == tidW'(t)),
            .init_i       (issue_i),
            .resolve_i    (resolve_accept && resolve_tid == tidW'(t)),
            .outcome_i    (se_resolve_i.outcome),
            .src_i        (se_resolve_i.src),
            .dt_i         (se_resolve_i.dt),
            .wslot_i      (writeback_slot_i),
            .cd_done_i    (cd_done_port[t]),
            .mem_done_i   (mem_done_i[t]),
            .rack_i       (rack_mask[t]),
            .ins_sent_i   (ins_sent[t]),
            .ins_done_i   (ins_done[t]),
            .tail_clear_i (tail_clear_i[t]),
            .status_o     (st[t])
        );
    end
//  }}}

//  Messages to the ports, registered there
//  {{{
    logic [numSub-1:0][ccuCfg.u.numRSlots-1:0] r_go_d;

    assign route_valid_o = resolve_accept && se_resolve_i.dt != '0;
    assign route_o       = '{tid:    resolve_tid,
                             src:    se_resolve_i.src,
                             to_r:   resolve_act.cd_r,
                             r_port: resolve_entry.port,
                             r_slot: resolve_entry.rslot,
                             to_w:   resolve_act.cd_wb,
                             w_slot: writeback_slot_i};

    for (genvar p = 0; p < numSub; p++) begin : gen_r_info
        assign r_info_valid_o[p] = resolve_accept && !resolve_entry.bi &&
                                   resolve_entry.port == subIdxW'(p);
    end

    //  An ACK that carries a writeback waits for its data
    assign r_info_o = '{rslot:      resolve_entry.rslot,
                        go:         resolve_act.mem_rd || resolve_act.cd_r ||
                                    (resolve_act.ack_r && !resolve_act.cd_wb),
                        ack:        resolve_act.ack_r,
                        is_shared:  se_resolve_i.outcome.is_shared,
                        pass_dirty: se_resolve_i.outcome.pass_dirty,
                        exokay:     resolve_entry.exokay};

    always_comb begin : r_go_comb
        r_go_d = '0;
        for (int unsigned t = 0; t < numTids; t++)
            if (st[t].respond_late) r_go_d[st[t].state.port][st[t].state.rslot] = 1'b1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) r_go_o <= '0;
        else         r_go_o <= r_go_d;
    end
//  }}}

//  Performance events, registered by the table
//  {{{
    logic [numTids-1:0] ins_owed;

    for (genvar t = 0; t < numTids; t++) begin : gen_event_taps
        assign ins_owed[t] = st[t].state.ins_owed;
    end

    always_comb begin : events_comb
        events_o                         = '0;
        events_o.resolve                 = resolve_accept;
        events_o.resolve_stall_writeback = se_resolve_valid_i && resolve_act.cd_wb &&
                                           !writeback_ready_i;
        events_o.resolve_stall_memory    = se_resolve_valid_i && resolve_act.mem_rd &&
                                           !me_tok_ready_i;
        events_o.insert_owed             = |ins_owed;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        resolve_accept && resolve_act.mem_rd |-> me_tok_ready_i)
        else $error("memory token dropped");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        issue_valid_i |-> !valid[issue_tid_i])
        else $error("issue into a live tid");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        issue_valid_i && !issue_i.bi |-> issue_tid_i < numReads)
        else $error("a read took a reserved back-invalidation tid");

    for (genvar t = 0; t < numTids; t++) begin : gen_entry_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            valid[t] && t >= numReads |-> st[t].state.bi)
            else $error("a reserved tid holds a read");
    end
    `endif
    // pragma translate_on
//  }}}
endmodule
