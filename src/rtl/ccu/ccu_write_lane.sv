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

//! Write lane
//
//  Every write to memory, stored whole before issue; same-line writes share a chain ID as AWID.
module ccu_write_lane
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg          = '{default: '0},
    parameter  type         aw_hdr_t        = logic,
    parameter  type         w_beat_t        = logic,
    parameter  type         cd_w_t          = logic,
    parameter  type         writeback_req_t = logic,
    parameter  type         b_ret_t         = logic,
    parameter  type         mgr_aw_t        = logic,
    parameter  type         mgr_w_t         = logic,
    parameter  type         mgr_b_t         = logic,
    localparam int unsigned numSub          = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW         = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numPort         = ccuCfg.u.numPortSlots,
    localparam int unsigned numWriteback    = ccuCfg.u.numWritebackSlots,
    localparam int unsigned numSlots        = ccuCfg.numWSlots,
    localparam int unsigned slotW           = ccuCfg.wSlotWidth,
    localparam int unsigned bSlotW          = ccuCfg.bSlotWidth,
    localparam int unsigned lineW           = ccuCfg.numLineWidth,
    localparam int unsigned offW            = ccuCfg.cachelineByteIndexWidth,
    localparam int unsigned numBeats        = ccuCfg.cachelineAxiTransfers,
    localparam int unsigned beatW           = ccuCfg.beatIndexWidth,
    localparam int unsigned dataW           = ccuCfg.u.axiDataWidth
) (
    input  logic                             clk_i,
    input  logic                             rst_ni,

    //  Non-blocking writes: a port slot each; W is named by the port's B slot
    input  aw_hdr_t   [numSub-1:0]           aw_i,
    input  logic      [numSub-1:0]           aw_valid_i,
    output logic      [numSub-1:0]           aw_ready_o,
    input  w_beat_t   [numSub-1:0]           w_i,
    input  logic      [numSub-1:0]           w_valid_i,
    output logic      [numSub-1:0]           w_ready_o,

    //  Snoop writebacks: a writeback slot, reserved at resolve
    input  writeback_req_t                   writeback_i,
    input  logic                             writeback_valid_i,
    output logic                             writeback_ready_o,
    output logic      [slotW-1:0]            writeback_slot_o,
    //  At most one writeback slot can be taken
    output logic                             writeback_scarce_o,
    input  cd_w_t     [numSub-1:0]           cd_i,
    input  logic      [numSub-1:0]           cd_valid_i,
    output logic      [numSub-1:0]           cd_ready_o,

    output b_ret_t    [numSub-1:0]           b_o,
    output logic      [numSub-1:0]           b_valid_o,

    //  Hazard query: every pending write, and those allocated this cycle
    output logic      [numSlots-1:0]             hazard_valid_o,
    output logic      [numSlots-1:0][lineW-1:0]  hazard_line_o,
    output logic      [1:0]                      hazard_alloc_o,
    output logic      [1:0][lineW-1:0]           hazard_alloc_line_o,

    output mgr_aw_t                          aw_o,
    output logic                             aw_valid_o,
    input  logic                             aw_ready_i,
    output mgr_w_t                           w_o,
    output logic                             w_valid_o,
    input  logic                             w_ready_i,
    input  mgr_b_t                           b_i,
    input  logic                             b_valid_i,
    output logic                             b_ready_o,

    output ccu_lane_events_t                 events_o
);

    localparam int unsigned numWords = numSlots * numBeats;
    localparam int unsigned wordW    = numWords > 1 ? $clog2(numWords) : 1;
    localparam int unsigned strbW    = dataW / 8;

    typedef struct packed {
        logic [strbW-1:0] strb;
        logic [dataW-1:0] data;
    } word_t;

    typedef struct packed {
        logic [slotW-1:0] slot;
        logic [dataW-1:0] data;
        logic [strbW-1:0] strb;
        logic             last;
    } beat_t;

    typedef struct packed {
        logic                writeback;
        logic [subIdxW-1:0]  port;
        logic [bSlotW-1:0]   bslot;
        logic [lineW-1:0]    line;
        mgr_aw_t             aw;
    } slot_info_t;

    function automatic logic [wordW-1:0] word_of(logic [slotW-1:0] slot, logic [beatW:0] beat);
        return wordW'(slot) * wordW'(numBeats) + wordW'(beat);
    endfunction

//  Slot state
//  {{{
    logic       [numSlots-1:0]             valid_q,      valid_d;
    slot_info_t [numSlots-1:0]             info_q,       info_d;
    logic       [numSlots-1:0][beatW:0]    beats_q,      beats_d;
    logic       [numSlots-1:0]             issued_q,     issued_d;
    //  The write covers its whole line, every byte strobed
    logic       [numSlots-1:0]             full_q,       full_d;
    //  A writeback overtaken by a later full-line write of its line: never issued
    logic       [numSlots-1:0]             superseded_q, superseded_d;
    logic       [numSlots-1:0]             tail_q,       tail_d;
    logic       [numSlots-1:0]             pred_valid_q, pred_valid_d;
    logic       [numSlots-1:0][slotW-1:0]  pred_idx_q,   pred_idx_d;
    logic       [numSlots-1:0][slotW-1:0]  chain_q,      chain_d;
    logic       [numSlots-1:0]             complete;
    //  A chain ID stays taken while any write of its chain is pending
    logic       [numSlots-1:0]             id_busy;
    logic       [slotW-1:0]                port_new_id, writeback_new_id, id_leading_busy;
    logic       [numSlots-1:0]             free_mask;

    for (genvar s = 0; s < numSlots; s++) begin : gen_slot
        assign complete[s] = beats_q[s] == (beatW+1)'(info_q[s].aw.len) + 1'b1;
    end

    always_comb begin : id_busy_comb
        id_busy = '0;
        for (int unsigned s = 0; s < numSlots; s++)
            if (valid_q[s]) id_busy[chain_q[s]] = 1'b1;
    end
//  }}}

//  Allocation: port slots for non-blocking writes, writeback slots for writebacks
//  {{{
    logic [numSlots-1:0] port_free, writeback_free;
    logic [slotW-1:0]    port_idx,  writeback_idx;
    logic                port_none, writeback_none;
    logic                port_alloc, writeback_alloc;
    logic [subIdxW-1:0]  port_sel;
    logic [numSub-1:0]   aw_gnt;
    aw_hdr_t             aw_sel;
    logic                aw_sel_valid;

    for (genvar s = 0; s < numSlots; s++) begin : gen_free
        assign port_free[s]      = s <  numPort && !valid_q[s];
        assign writeback_free[s] = s >= numPort && !valid_q[s];
    end

    //  Two free slots leave two free IDs, so the two ends never meet
    lzc #(
        .WIDTH (numSlots),
        .MODE  (1'b0)
    ) u_port_id_lzc (
        .in_i    (~id_busy),
        .cnt_o   (port_new_id),
        .empty_o ()
    );

    lzc #(
        .WIDTH (numSlots),
        .MODE  (1'b1)
    ) u_writeback_id_lzc (
        .in_i    (~id_busy),
        .cnt_o   (id_leading_busy),
        .empty_o ()
    );

    //  The trailing count gives the highest free ID
    assign writeback_new_id = slotW'(numSlots - 1) - id_leading_busy;

    lzc #(
        .WIDTH (numSlots),
        .MODE  (1'b0)
    ) u_port_lzc (
        .in_i    (port_free),
        .cnt_o   (port_idx),
        .empty_o (port_none)
    );

    lzc #(
        .WIDTH (numSlots),
        .MODE  (1'b0)
    ) u_writeback_lzc (
        .in_i    (writeback_free),
        .cnt_o   (writeback_idx),
        .empty_o (writeback_none)
    );

    rr_arb_tree #(
        .NumIn     (numSub),
        .DataType  (aw_hdr_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b0)
    ) u_aw_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (aw_valid_i),
        .gnt_o   (aw_gnt),
        .data_i  (aw_i),
        .req_o   (aw_sel_valid),
        .gnt_i   (!port_none),
        .data_o  (aw_sel),
        .idx_o   (port_sel)
    );

    //  The arbiter grants its pick even when it is not requesting
    assign aw_ready_o   = aw_gnt & aw_valid_i & {numSub{!port_none}};
    assign port_alloc   = aw_sel_valid && !port_none;

    assign writeback_ready_o = !writeback_none;
    assign writeback_slot_o  = writeback_idx;
    assign writeback_alloc   = writeback_valid_i && !writeback_none;

    logic writeback_one_free;

    cc_onehot #(
        .Width (numWriteback)
    ) u_writeback_one_free (
        .d_i         (writeback_free[numSlots-1:numPort]),
        .is_onehot_o (writeback_one_free)
    );

    //  Scarce at none free as well as one
    assign writeback_scarce_o = writeback_one_free || writeback_none;

    logic [lineW-1:0] port_line, writeback_line;
    mgr_aw_t          port_aw,   writeback_aw;
    logic             port_full_shape;

    assign port_line = aw_sel.aw.addr[offW +: lineW];
    assign port_full_shape = aw_sel.aw.len == axi_pkg::len_t'(numBeats - 1) &&
                             aw_sel.aw.size == axi_pkg::size_t'(ccuCfg.axiDataSize) &&
                             aw_sel.aw.burst == axi_pkg::BURST_INCR &&
                             aw_sel.aw.addr[offW-1:0] == '0;
    assign writeback_line = writeback_i.line;

    always_comb begin : alloc_aw_comb
        `AXI_SET_AW_STRUCT(port_aw, aw_sel.aw)
        port_aw.atop     = '0;

        writeback_aw          = '0;
        writeback_aw.addr     = {writeback_i.line, {offW{1'b0}}};
        writeback_aw.len      = axi_pkg::len_t'(numBeats - 1);
        writeback_aw.size     = axi_pkg::size_t'(ccuCfg.axiDataSize);
        writeback_aw.burst    = axi_pkg::BURST_INCR;
        writeback_aw.cache    = writeback_i.cache;
        writeback_aw.prot     = writeback_i.prot;
        writeback_aw.qos      = writeback_i.qos;
        writeback_aw.region   = writeback_i.region;
        writeback_aw.user     = writeback_i.user;
    end

    assign hazard_valid_o      = valid_q;
    assign hazard_alloc_o      = {writeback_alloc, port_alloc};
    assign hazard_alloc_line_o = {writeback_line,  port_line};

    for (genvar s = 0; s < numSlots; s++) begin : gen_hazard
        assign hazard_line_o[s] = info_q[s].line;
    end
//  }}}

//  Beat writes: one beat at a time, from the beats that are present
//  {{{
    localparam int unsigned numBSlots = ccuCfg.numBSlots;

    //  Which slot each port's B slot was given
    logic  [numSub-1:0][numBSlots-1:0]            map_valid_q;
    logic  [numSub-1:0][numBSlots-1:0][slotW-1:0] map_slot_q;
    logic  [numSub-1:0]                           w_mapped;

    beat_t [2*numSub-1:0] wr_inp;
    logic  [2*numSub-1:0] wr_valid, wr_gnt;
    beat_t                wr_beat;
    logic                 wr_req;

    for (genvar p = 0; p < numSub; p++) begin : gen_wr_inp
        assign w_mapped[p]        = map_valid_q[p][w_i[p].bslot];
        assign wr_inp[p]          = '{slot: map_slot_q[p][w_i[p].bslot], data: w_i[p].w.data,
                                      strb: w_i[p].w.strb, last: w_i[p].w.last};
        assign wr_inp[numSub + p] = '{slot: cd_i[p].slot, data: cd_i[p].data,
                                      strb: '1, last: cd_i[p].last};
    end

    assign wr_valid = {cd_valid_i, w_valid_i & w_mapped};

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            map_valid_q <= '0;
            map_slot_q  <= '0;
        end else begin
            for (int unsigned s = 0; s < numSlots; s++)
                if (free_mask[s] && !info_q[s].writeback)
                    map_valid_q[info_q[s].port][info_q[s].bslot] <= 1'b0;
            if (port_alloc) begin
                map_valid_q[port_sel][aw_sel.bslot] <= 1'b1;
                map_slot_q[port_sel][aw_sel.bslot]  <= port_idx;
            end
        end
    end

    rr_arb_tree #(
        .NumIn     (2*numSub),
        .DataType  (beat_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b0)
    ) u_wr_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (wr_valid),
        .gnt_o   (wr_gnt),
        .data_i  (wr_inp),
        .req_o   (wr_req),
        .gnt_i   (1'b1),
        .data_o  (wr_beat),
        .idx_o   ()
    );

    assign w_ready_o  = wr_gnt[numSub-1:0] & w_mapped;
    assign cd_ready_o = wr_gnt[2*numSub-1:numSub];
//  }}}

//  Issue: a whole write, after its chain predecessor
//  {{{
    logic [numSlots-1:0] issue_candidate;
    logic [slotW-1:0]    issue_idx;
    logic                issue_handshake;
    logic                rd_issue, rd_last;
    logic                order_full, order_empty;
    logic [slotW-1:0]    order_head;

    //  A whole line may overtake a writeback still waiting for its snoop data
    logic [numSlots-1:0] skips_pred;

    for (genvar s = 0; s < numSlots; s++) begin : gen_issue_candidate
        logic [slotW-1:0] pred;

        assign pred          = pred_idx_q[s];
        assign skips_pred[s] = pred_valid_q[s] && full_q[s] && info_q[pred].writeback &&
                               !issued_q[pred] && !complete[pred] &&
                               (!pred_valid_q[pred] || issued_q[pred_idx_q[pred]]);
        assign issue_candidate[s] = valid_q[s] && complete[s] && !issued_q[s] && !superseded_q[s] &&
                                    (!pred_valid_q[s] || issued_q[pred] || skips_pred[s]);
    end

    rr_arb_tree #(
        .NumIn     (numSlots),
        .DataType  (logic),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1)
    ) u_issue_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (issue_candidate),
        .gnt_o   (),
        .data_i  ('0),
        .req_o   (aw_valid_o),
        .gnt_i   (aw_ready_i),
        .data_o  (),
        .idx_o   (issue_idx)
    );

    always_comb begin : aw_comb
        aw_o    = info_q[issue_idx].aw;
        aw_o.id = '0;
        aw_o.id[slotW-1:0] = chain_q[issue_idx];
    end

    assign issue_handshake = aw_valid_o && aw_ready_i;

    //  The memory W stream follows AW order
    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (numSlots),
        .DATA_WIDTH   (slotW)
    ) u_order_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (order_full),
        .empty_o    (order_empty),
        .usage_o    (),
        .data_i     (issue_idx),
        .push_i     (issue_handshake),
        .data_o     (order_head),
        .pop_i      (rd_issue && rd_last)
    );
//  }}}

//  W streamer: the order head's beats, read one ahead of the output
//  {{{
    logic [beatW:0] rd_beat_q;
    logic [1:0]     space_q;
    logic           rd_valid_q, rd_last_q;
    logic [slotW-1:0] rd_slot_q;
    word_t          rd_word;
    mgr_w_t         rd_w;
    logic           out_empty, out_pop;

    assign rd_last  = rd_beat_q == (beatW+1)'(info_q[order_head].aw.len);
    assign rd_issue = !order_empty && space_q != '0;
    assign out_pop  = w_valid_o && w_ready_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_beat_q  <= '0;
            space_q    <= 2'd2;
            rd_valid_q <= 1'b0;
            rd_last_q  <= 1'b0;
            rd_slot_q  <= '0;
        end else begin
            if (rd_issue) rd_beat_q <= rd_last ? '0 : rd_beat_q + 1'b1;
            space_q    <= space_q - 2'(rd_issue) + 2'(out_pop);
            rd_valid_q <= rd_issue;
            if (rd_issue) begin
                rd_last_q <= rd_last;
                rd_slot_q <= order_head;
            end
        end
    end

    ccu_buffer_mem #(
        .NumWords (numWords),
        .UseFlops (ccuCfg.u.flopBuffers),
        .word_t   (word_t)
    ) u_data (
        .clk_i,
        .rst_ni,
        .wr_valid_i (wr_req),
        .wr_addr_i  (word_of(wr_beat.slot, beats_q[wr_beat.slot])),
        .wr_data_i  (word_t'{strb: wr_beat.strb, data: wr_beat.data}),
        .rd_valid_i (rd_issue),
        .rd_addr_i  (word_of(order_head, rd_beat_q)),
        .rd_data_o  (rd_word)
    );

    always_comb begin : rd_w_comb
        rd_w      = '0;
        rd_w.data = rd_word.data;
        rd_w.strb = rd_word.strb;
        rd_w.last = rd_last_q;
        rd_w.user = info_q[rd_slot_q].aw.user;
    end

    fifo_v3 #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (2),
        .dtype        (mgr_w_t)
    ) u_out_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (),
        .empty_o    (out_empty),
        .usage_o    (),
        .data_i     (rd_w),
        .push_i     (rd_valid_q),
        .data_o     (w_o),
        .pop_i      (out_pop)
    );

    assign w_valid_o = !out_empty;
//  }}}

//  B: pops the head of its chain; a writeback's is dropped
//  {{{
    logic [slotW-1:0]    b_chain;
    logic [numSlots-1:0] b_head;
    logic [slotW-1:0]    b_slot;

    assign b_ready_o = 1'b1;
    assign b_chain   = b_i.id[slotW-1:0];

    for (genvar s = 0; s < numSlots; s++) begin : gen_b_head
        assign b_head[s] = valid_q[s] && issued_q[s] && !pred_valid_q[s] &&
                           chain_q[s] == b_chain;
    end

    onehot_to_bin #(
        .ONEHOT_WIDTH (numSlots)
    ) u_b_slot (
        .onehot (b_head),
        .bin    (b_slot)
    );

    //  A superseded writeback goes once its snoop data is in
    assign free_mask = (b_valid_i ? b_head : '0) | (valid_q & superseded_q & complete);

    for (genvar p = 0; p < numSub; p++) begin : gen_b
        assign b_valid_o[p] = b_valid_i && !info_q[b_slot].writeback &&
                              info_q[b_slot].port == subIdxW'(p);
        assign b_o[p]       = '{bslot: info_q[b_slot].bslot, resp: b_i.resp, user: b_i.user};
    end
//  }}}

//  Slot updates and chains
//  {{{
    logic [numSlots-1:0] port_tail_link, writeback_tail_link;
    logic [slotW-1:0]    port_tail_idx,  writeback_tail_idx;

    for (genvar s = 0; s < numSlots; s++) begin : gen_tail_link
        assign port_tail_link[s]      = valid_q[s] && tail_q[s] && !free_mask[s] &&
                                        info_q[s].line == port_line;
        assign writeback_tail_link[s] = valid_q[s] && tail_q[s] && !free_mask[s] &&
                                        info_q[s].line == writeback_line;
    end

    onehot_to_bin #(
        .ONEHOT_WIDTH (numSlots)
    ) u_port_tail (
        .onehot (port_tail_link),
        .bin    (port_tail_idx)
    );

    onehot_to_bin #(
        .ONEHOT_WIDTH (numSlots)
    ) u_writeback_tail (
        .onehot (writeback_tail_link),
        .bin    (writeback_tail_idx)
    );

    always_comb begin : slot_comb
        automatic logic same_line = port_alloc && port_line == writeback_line;

        valid_d      = valid_q & ~free_mask;
        info_d       = info_q;
        beats_d      = beats_q;
        issued_d     = issued_q & ~free_mask;
        full_d       = full_q;
        superseded_d = superseded_q & ~free_mask;
        tail_d       = tail_q & ~free_mask;
        pred_valid_d = pred_valid_q;
        pred_idx_d   = pred_idx_q;
        chain_d      = chain_q;

        for (int unsigned s = 0; s < numSlots; s++)
            if (pred_valid_q[s] && free_mask[pred_idx_q[s]]) pred_valid_d[s] = 1'b0;

        if (wr_req) begin
            beats_d[wr_beat.slot] = beats_q[wr_beat.slot] + 1'b1;
            if (!(&wr_beat.strb)) full_d[wr_beat.slot] = 1'b0;
        end

        if (issue_handshake) begin
            issued_d[issue_idx] = 1'b1;
            //  It takes the place of the writeback it overtook
            if (skips_pred[issue_idx]) begin
                superseded_d[pred_idx_q[issue_idx]] = 1'b1;
                pred_valid_d[issue_idx] = pred_valid_q[pred_idx_q[issue_idx]];
                pred_idx_d[issue_idx]   = pred_idx_q[pred_idx_q[issue_idx]];
            end
        end

        if (port_alloc) begin
            valid_d[port_idx]      = 1'b1;
            info_d[port_idx]       = '{writeback: 1'b0, port: port_sel, bslot: aw_sel.bslot,
                                       line: port_line, aw: port_aw};
            beats_d[port_idx]      = '0;
            full_d[port_idx]       = port_full_shape;
            superseded_d[port_idx] = 1'b0;
            tail_d[port_idx]       = 1'b1;
            pred_valid_d[port_idx] = |port_tail_link;
            pred_idx_d[port_idx]   = port_tail_idx;
            chain_d[port_idx]      = |port_tail_link ? chain_q[port_tail_idx] : port_new_id;
            if (|port_tail_link) tail_d[port_tail_idx] = 1'b0;
        end

        //  Behind the port write when both take the same line in one cycle
        if (writeback_alloc) begin
            valid_d[writeback_idx]      = 1'b1;
            info_d[writeback_idx]       = '{writeback: 1'b1, port: '0, bslot: '0,
                                            line: writeback_line, aw: writeback_aw};
            beats_d[writeback_idx]      = '0;
            full_d[writeback_idx]       = 1'b1;
            superseded_d[writeback_idx] = 1'b0;
            tail_d[writeback_idx]       = 1'b1;
            if (same_line) begin
                pred_valid_d[writeback_idx] = 1'b1;
                pred_idx_d[writeback_idx]   = port_idx;
                chain_d[writeback_idx]      = chain_d[port_idx];
                tail_d[port_idx]            = 1'b0;
            end else begin
                pred_valid_d[writeback_idx] = |writeback_tail_link;
                pred_idx_d[writeback_idx]   = writeback_tail_idx;
                chain_d[writeback_idx]      = |writeback_tail_link ? chain_q[writeback_tail_idx] :
                                                                     writeback_new_id;
                if (|writeback_tail_link) tail_d[writeback_tail_idx] = 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q      <= '0;
            info_q       <= '0;
            beats_q      <= '0;
            issued_q     <= '0;
            full_q       <= '0;
            superseded_q <= '0;
            tail_q       <= '0;
            pred_valid_q <= '0;
            pred_idx_q   <= '0;
            chain_q      <= '0;
        end else begin
            valid_q      <= valid_d;
            info_q       <= info_d;
            beats_q      <= beats_d;
            issued_q     <= issued_d;
            full_q       <= full_d;
            superseded_q <= superseded_d;
            tail_q       <= tail_d;
            pred_valid_q <= pred_valid_d;
            pred_idx_q   <= pred_idx_d;
            chain_q      <= chain_d;
        end
    end
//  }}}

//  Performance events
//  {{{
    ccu_lane_events_t events_d;

    always_comb begin : events_comb
        events_d                 = '0;
        events_d.port_alloc      = port_alloc;
        events_d.port_stall_full = |aw_valid_i && port_none;
        events_d.writeback_alloc = writeback_alloc;
        events_d.aw_issued       = issue_handshake;
        events_d.aw_stall_memory = aw_valid_o && !aw_ready_i;
        events_d.w_beat          = w_valid_o && w_ready_i;
        events_d.w_stall_memory  = w_valid_o && !w_ready_i;
        events_d.b               = b_valid_i;
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
        b_ready_o)
        else $error("memory B back-pressured");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        aw_valid_o |-> complete[issue_idx])
        else $error("memory AW issued for a write whose data is incomplete");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        aw_valid_o && !aw_ready_i |=> aw_valid_o && $stable(aw_o))
        else $error("memory AW unstable while stalled");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        w_valid_o && !w_ready_i |=> w_valid_o && $stable(w_o))
        else $error("memory W unstable while stalled");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (superseded_q & ~valid_q) == '0 && (superseded_q & issued_q) == '0)
        else $error("a superseded writeback was issued or outlived its slot");

    for (genvar s = 0; s < numSlots; s++) begin : gen_superseded_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            superseded_q[s] |-> info_q[s].writeback)
            else $error("a manager's own write was superseded");
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        b_valid_i |-> $onehot(b_head))
        else $error("memory B does not match the head of one chain");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wr_req |-> valid_q[wr_beat.slot] && !complete[wr_beat.slot])
        else $error("beat written to a slot that is not expecting one");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wr_req |->
            wr_beat.last == (beats_q[wr_beat.slot] == (beatW+1)'(info_q[wr_beat.slot].aw.len)))
        else $error("write burst does not match its AW");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        port_alloc |-> !map_valid_q[port_sel][aw_sel.bslot])
        else $error("a port's B slot mapped twice");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        port_alloc |-> $onehot0(port_tail_link))
        else $error("more than one tail for a line");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        writeback_alloc |-> $onehot0(writeback_tail_link))
        else $error("more than one tail for a line");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        port_alloc && !(|port_tail_link) |-> !id_busy[port_new_id])
        else $error("a new write chain took a busy ID");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        writeback_alloc && !(|writeback_tail_link) &&
        !(port_alloc && port_line == writeback_line) |->
            !id_busy[writeback_new_id] &&
            !(port_alloc && !(|port_tail_link) && port_new_id == writeback_new_id))
        else $error("a new writeback chain took a busy or shared ID");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        issue_handshake |-> !order_full)
        else $error("W order FIFO overflow");

    for (genvar s = 0; s < numSlots; s++) begin : gen_chain_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            valid_q[s] && pred_valid_q[s] |-> valid_q[pred_idx_q[s]] &&
                                              info_q[pred_idx_q[s]].line == info_q[s].line)
            else $error("chained write waits on a dead or foreign predecessor");
    end
    `endif
    // pragma translate_on
//  }}}
endmodule
