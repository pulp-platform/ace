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

//! Snoop filter of one slice
//
//  One tag array per port, registered read data; lookups answer two cycles later.
module ccu_snoop_filter
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg   = '{default: '0},
    localparam int unsigned numSub   = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW  = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids  = ccuCfg.numTids,
    localparam int unsigned tidW     = ccuCfg.tidWidth,
    localparam int unsigned lineW    = ccuCfg.numLineWidth,
    localparam int unsigned setW     = ccuCfg.snoopFilterSetWidth,
    localparam int unsigned tagW     = ccuCfg.snoopFilterTagWidth,
    localparam int unsigned offW     = ccuCfg.cachelineByteIndexWidth,
    localparam int unsigned trackW   = ccuCfg.u.snoopFilterAddrWidth
) (
    input  logic                            clk_i,
    input  logic                            rst_ni,

    input  logic                            lookup_valid_i,
    input  logic [lineW-1:0]                lookup_line_i,
    output logic [numSub-1:0]               lookup_present_o,

    //  One insert channel, taken at once by a free table; done once the line is in it
    input  logic                            insert_valid_i,
    input  logic [subIdxW-1:0]              insert_port_i,
    input  logic [lineW-1:0]                insert_line_i,
    input  logic [tidW-1:0]                 insert_tid_i,
    output logic [numSub-1:0]               insert_free_o,
    output logic [numSub-1:0]               insert_done_o,
    output logic [numSub-1:0][tidW-1:0]     insert_done_tid_o,

    //  A port's own WriteBack, WriteEvict or Evict
    input  logic [numSub-1:0]               aw_remove_valid_i,
    input  logic [numSub-1:0][lineW-1:0]    aw_remove_line_i,
    output logic [numSub-1:0]               aw_remove_ready_o,

    //  From a resolved snoop: one line, every responder that dropped it
    input  logic                            cr_remove_valid_i,
    input  logic [numSub-1:0]               cr_remove_sel_i,
    input  logic [lineW-1:0]                cr_remove_line_i,
    input  logic [tidW-1:0]                 cr_remove_tid_i,
    output logic                            cr_remove_ready_o,

    //  A victim to back-invalidate, when an insert finds its set full
    output logic [numSub-1:0]               bi_valid_o,
    output logic [numSub-1:0][lineW-1:0]    bi_line_o,
    input  logic [numSub-1:0]               bi_ready_i,

    output ccu_filter_events_t              events_o
);

    localparam int unsigned numSets = ccuCfg.u.subordinateCacheSets;
    localparam int unsigned numWays = ccuCfg.u.subordinateCacheWays;
    localparam int unsigned entryW  = ccuCfg.snoopFilterEntryWidth;
    localparam int unsigned wayW    = numWays > 1 ? $clog2(numWays) : 1;

    typedef struct packed {
        logic            valid;
        logic [tagW-1:0] tag;
    } entry_t;

    typedef enum logic [1:0] { OpAwRemove, OpCrRemove, OpInsert } op_e;

    typedef enum logic [1:0] { BiIdle, BiSend, BiOwed } bi_state_e;

    typedef struct packed {
        logic [lineW-1:0] line;
        logic [tidW-1:0]  tid;
    } cr_rm_t;

    //  Shift: a part-select would not elaborate at trackW == offW + lineW
    function automatic logic tracked(logic [lineW-1:0] line);
        return ({line, {offW{1'b0}}} >> trackW) == '0;
    endfunction

    function automatic logic [setW-1:0] set_of(logic [lineW-1:0] line);
        return line[setW-1:0];
    endfunction

    function automatic logic [tagW-1:0] tag_of(logic [lineW-1:0] line);
        return line[setW +: tagW];
    endfunction

    //  A lookup in flight, with the update written in its read cycle
    typedef struct packed {
        logic                 patch;
        logic [setW-1:0]      patch_set;
        logic [numWays-1:0]   patch_be;
        entry_t               patch_entry;
        logic [setW-1:0]      set;
        logic [tagW-1:0]      tag;
        logic                 forced;
    } lookup_pending_t;

    //  CR removals go to every selected table; each holds a tid at most once
    assign cr_remove_ready_o = 1'b1;

    logic [numSub-1:0] evt_busy, evt_stuck, evt_remove_miss;

    for (genvar s = 0; s < numSub; s++) begin : gen_table
        entry_t [numWays-1:0] upd_rdata, lkp_rdata, upd_wdata;
        logic   [numWays-1:0] upd_be;
        logic   [setW-1:0]    upd_addr;
        logic                 upd_req, upd_we;

        logic                 init_done_q;
        logic [setW:0]        init_cnt_q;

        //  Update queues: removals before inserts, so no insert overtakes a removal
        logic [lineW-1:0]     aw_head;
        logic                 aw_valid, aw_pop, aw_fifo_ready;
        cr_rm_t               cr_head;
        logic                 cr_full, cr_empty, cr_pop;
        logic                 rm_turn_q;

        //  An update reads its set, waits a cycle, then decides and writes
        logic                 read_q, busy_q;
        op_e                  op_q;
        logic [lineW-1:0]     op_line_q;
        logic [tidW-1:0]      op_tid_q;
        logic                 start;
        op_e                  start_op;
        logic [lineW-1:0]     start_line;
        logic [tidW-1:0]      start_tid;

        logic [numWays-1:0]   way_match, way_free;
        logic [wayW-1:0]      match_idx, free_idx;
        logic                 match_none, free_none;
        logic                 insert_held, insert_stuck;
        logic                 hold_valid_q, hold_take;
        logic [lineW-1:0]     hold_line_q;
        logic [tidW-1:0]      hold_tid_q;

        bi_state_e            bi_state_q, bi_state_d;
        logic [wayW-1:0]      victim_q;
        logic [lineW-1:0]     bi_line_q;

        lookup_pending_t      lookup_read_q, lookup_answer_q;
        entry_t [numWays-1:0] lookup_ways;
        logic [numWays-1:0]   lookup_match;

        stream_fifo #(
            .FALL_THROUGH (1'b0),
            .DEPTH        (2),
            .DATA_WIDTH   (lineW)
        ) u_aw_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .usage_o    (),
            .data_i     (aw_remove_line_i[s]),
            .valid_i    (aw_remove_valid_i[s] && tracked(aw_remove_line_i[s])),
            .ready_o    (aw_fifo_ready),
            .data_o     (aw_head),
            .valid_o    (aw_valid),
            .ready_i    (aw_pop)
        );

        //  An untracked line is dropped at once
        assign aw_remove_ready_o[s] = aw_fifo_ready || !tracked(aw_remove_line_i[s]);

        fifo_v3 #(
            .FALL_THROUGH (1'b0),
            .DEPTH        (numTids),
            .dtype        (cr_rm_t)
        ) u_cr_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (cr_full),
            .empty_o    (cr_empty),
            .usage_o    (),
            .data_i     (cr_rm_t'{line: cr_remove_line_i, tid: cr_remove_tid_i}),
            .push_i     (cr_remove_valid_i && cr_remove_sel_i[s] && tracked(cr_remove_line_i)),
            .data_o     (cr_head),
            .pop_i      (cr_pop)
        );

        //  The tag array has no content reset, so clear it before use
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                init_cnt_q  <= '0;
                init_done_q <= 1'b0;
            end else if (!init_done_q) begin
                init_cnt_q  <= init_cnt_q + 1'b1;
                init_done_q <= init_cnt_q == (setW+1)'(numSets - 1);
            end
        end

        //  One update in flight: read the set, then write the way it decides on
        always_comb begin : start_comb
            start      = 1'b0;
            start_op   = OpAwRemove;
            start_line = aw_head;
            start_tid  = '0;
            if (init_done_q && !read_q && !busy_q) begin
                if (aw_valid && (rm_turn_q || cr_empty)) begin
                    start = 1'b1;
                end else if (!cr_empty) begin
                    start      = 1'b1;
                    start_op   = OpCrRemove;
                    start_line = cr_head.line;
                    start_tid  = cr_head.tid;
                end else if (hold_valid_q && tracked(hold_line_q) && bi_state_q == BiIdle) begin
                    start      = 1'b1;
                    start_op   = OpInsert;
                    start_line = hold_line_q;
                    start_tid  = hold_tid_q;
                end
            end
        end

        assign aw_pop = start && start_op == OpAwRemove;
        assign cr_pop = start && start_op == OpCrRemove;

        for (genvar w = 0; w < numWays; w++) begin : gen_way
            assign way_match[w] = upd_rdata[w].valid && upd_rdata[w].tag == tag_of(op_line_q);
            assign way_free[w]  = !upd_rdata[w].valid;
        end

        lzc #(
            .WIDTH (numWays),
            .MODE  (1'b0)
        ) u_match_lzc (
            .in_i    (way_match),
            .cnt_o   (match_idx),
            .empty_o (match_none)
        );

        lzc #(
            .WIDTH (numWays),
            .MODE  (1'b0)
        ) u_free_lzc (
            .in_i    (way_free),
            .cnt_o   (free_idx),
            .empty_o (free_none)
        );

        //  The held insert stays until it lands, so the one read is the one decided
        assign insert_held  = busy_q && op_q == OpInsert;
        assign insert_stuck = insert_held && match_none && free_none;

        //  An untracked insert lands at once
        assign hold_take            = insert_valid_i && insert_port_i == subIdxW'(s);
        assign insert_free_o[s]     = !hold_valid_q;
        assign insert_done_o[s]     = hold_valid_q && (!tracked(hold_line_q) ||
                                                       (insert_held && !insert_stuck));
        assign insert_done_tid_o[s] = hold_tid_q;

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                hold_valid_q <= 1'b0;
                hold_line_q  <= '0;
                hold_tid_q   <= '0;
            end else if (hold_take) begin
                hold_valid_q <= 1'b1;
                hold_line_q  <= insert_line_i;
                hold_tid_q   <= insert_tid_i;
            end else if (insert_done_o[s]) begin
                hold_valid_q <= 1'b0;
            end
        end

        always_comb begin : update_port_comb
            upd_req   = 1'b0;
            upd_we    = 1'b0;
            upd_addr  = set_of(start_line);
            upd_be    = '0;
            upd_wdata = '0;
            if (!init_done_q) begin
                upd_req  = 1'b1;
                upd_we   = 1'b1;
                upd_addr = init_cnt_q[setW-1:0];
                upd_be   = '1;
            end else if (busy_q) begin
                upd_addr  = set_of(op_line_q);
                if (op_q == OpInsert) begin
                    upd_req   = insert_held && match_none && !free_none;
                    upd_be    = numWays'(1) << free_idx;
                    upd_wdata = {numWays{entry_t'{valid: 1'b1, tag: tag_of(op_line_q)}}};
                end else begin
                    upd_req   = !match_none;
                    upd_be    = numWays'(1) << match_idx;
                end
                upd_we = upd_req;
            end else if (read_q) begin
                upd_addr = set_of(op_line_q);
            end else begin
                upd_req = start;
            end
        end

        tc_sram #(
            .NumWords  (numSets),
            .DataWidth (numWays * entryW),
            .ByteWidth (entryW),
            .NumPorts  (32'd2),
            .Latency   (32'd2)
        ) u_tag_array (
            .clk_i,
            .rst_ni,
            .req_i   ({lookup_valid_i, upd_req}),
            .we_i    ({1'b0, upd_we}),
            .addr_i  ({set_of(lookup_line_i), upd_addr}),
            .wdata_i ({{(numWays * entryW){1'b0}}, upd_wdata}),
            .be_i    ({{numWays{1'b0}}, upd_be}),
            .rdata_o ({lkp_rdata, upd_rdata})
        );

        //  The back-invalidation stands until a removal of its victim is applied
        always_comb begin : bi_comb
            bi_state_d = bi_state_q;
            unique case (bi_state_q)
                BiIdle:  if (insert_stuck)  bi_state_d = BiSend;
                BiSend:  if (bi_ready_i[s]) bi_state_d = BiOwed;
                BiOwed:  if (busy_q && op_q != OpInsert && op_line_q == bi_line_q)
                             bi_state_d = BiIdle;
                default: bi_state_d = BiIdle;
            endcase
        end

        assign bi_valid_o[s] = bi_state_q == BiSend;
        assign bi_line_o[s]  = bi_line_q;

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                read_q     <= 1'b0;
                busy_q     <= 1'b0;
                op_q       <= OpAwRemove;
                op_line_q  <= '0;
                op_tid_q   <= '0;
                rm_turn_q  <= 1'b0;
                bi_state_q <= BiIdle;
                victim_q   <= '0;
                bi_line_q  <= '0;
            end else begin
                read_q     <= start;
                busy_q     <= read_q;
                bi_state_q <= bi_state_d;
                if (start) begin
                    op_q      <= start_op;
                    op_line_q <= start_line;
                    op_tid_q  <= start_tid;
                    if (start_op != OpInsert) rm_turn_q <= start_op == OpCrRemove;
                end
                //  Rotating victim: the policy only has to not keep picking one way
                if (insert_stuck) begin
                    bi_line_q <= {upd_rdata[victim_q].tag, set_of(op_line_q)};
                    victim_q  <= victim_q == wayW'(numWays - 1) ? '0 : victim_q + 1'b1;
                end
            end
        end

        //  Lookup, patched with the update written in the cycle it read
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                lookup_read_q   <= '{forced: 1'b1, default: '0};
                lookup_answer_q <= '{forced: 1'b1, default: '0};
            end else begin
                lookup_read_q.patch       <= upd_req && upd_we && init_done_q;
                lookup_read_q.patch_set   <= upd_addr;
                lookup_read_q.patch_be    <= upd_be;
                lookup_read_q.patch_entry <= upd_wdata[0];
                if (lookup_valid_i) begin
                    lookup_read_q.set    <= set_of(lookup_line_i);
                    lookup_read_q.tag    <= tag_of(lookup_line_i);
                    lookup_read_q.forced <= !init_done_q || !tracked(lookup_line_i);
                end
                lookup_answer_q <= lookup_read_q;
            end
        end

        for (genvar w = 0; w < numWays; w++) begin : gen_lookup_match
            assign lookup_ways[w]  = lookup_answer_q.patch && lookup_answer_q.patch_be[w] &&
                                     lookup_answer_q.patch_set == lookup_answer_q.set ?
                                     lookup_answer_q.patch_entry : lkp_rdata[w];
            assign lookup_match[w] = lookup_ways[w].valid &&
                                     lookup_ways[w].tag == lookup_answer_q.tag;
        end

        assign lookup_present_o[s] = lookup_answer_q.forced || |lookup_match;

        assign evt_busy[s]        = read_q || busy_q;
        assign evt_stuck[s]       = insert_stuck;
        assign evt_remove_miss[s] = busy_q && op_q != OpInsert && match_none;
    end

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    for (genvar s = 0; s < numSub; s++) begin : gen_table_assertions
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            gen_table[s].busy_q |-> $onehot0(gen_table[s].way_match))
            else $error("a set holds the same line twice");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            gen_table[s].insert_held |-> gen_table[s].hold_valid_q &&
                                         gen_table[s].hold_tid_q  == gen_table[s].op_tid_q &&
                                         gen_table[s].hold_line_q == gen_table[s].op_line_q)
            else $error("an insert changed while its set was read");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            gen_table[s].hold_take |-> !gen_table[s].hold_valid_q)
            else $error("an insert sent to a table already holding one");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            cr_remove_valid_i && cr_remove_sel_i[s] |-> !gen_table[s].cr_full)
            else $error("CR removal queue overflow");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            gen_table[s].insert_stuck |-> gen_table[s].bi_state_q == BiIdle)
            else $error("an insert got stuck while its back-invalidation was in flight");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            bi_valid_o[s] && !bi_ready_i[s] |=> bi_valid_o[s] && $stable(bi_line_o[s]))
            else $error("a back-invalidation was withdrawn before it was admitted");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            gen_table[s].upd_req && gen_table[s].upd_we && gen_table[s].init_done_q |->
            $onehot(gen_table[s].upd_be))
            else $error("an update wrote more than one way");

        //  A removal is never held off by lookups, only by the updates ahead of it
        int unsigned aw_wait_q;
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni)
                aw_wait_q <= 0;
            else if (!gen_table[s].aw_valid || gen_table[s].aw_pop || !gen_table[s].init_done_q)
                aw_wait_q <= 0;
            else
                aw_wait_q <= aw_wait_q + 1;
        end

        //  Not while the array is cleared after reset
        assert property (@(posedge clk_i) disable iff (!rst_ni || !gen_table[s].init_done_q)
            aw_wait_q < 6 * (numTids + 2))
            else $error("a write-channel removal waited %0d cycles", aw_wait_q);
    end
    `endif
    // pragma translate_on
//  }}}

//  Performance events
//  {{{
    ccu_filter_events_t events_d;
    logic [1:0]         lookup_issued_q;

    always_comb begin : events_comb
        events_d                     = '0;
        events_d.lookup              = lookup_valid_i;
        events_d.lookup_present_none = lookup_issued_q[1] && lookup_present_o == '0;
        events_d.lookup_present_all  = lookup_issued_q[1] && &lookup_present_o;
        events_d.update_busy         = |evt_busy;
        events_d.insert_stuck        = |evt_stuck;
        events_d.back_inval          = |(bi_valid_o & bi_ready_i);
        events_d.remove_miss         = |evt_remove_miss;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lookup_issued_q <= '0;
            events_o        <= '0;
        end else begin
            lookup_issued_q <= {lookup_issued_q[0], lookup_valid_i};
            events_o        <= events_d;
        end
    end
//  }}}

endmodule
