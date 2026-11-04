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

//! R reassembly buffer
//
//  One slot per admitted read; data lands by slot in any order and leaves whole, in order per id.
module ccu_r_buffer
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg    = '{default: '0},
    parameter  type         r_t       = logic,
    parameter  type         rb_mem_t  = logic,
    parameter  type         rb_cd_t   = logic,
    parameter  type         r_info_t  = logic,
    localparam int unsigned numSlots  = ccuCfg.u.numRSlots,
    localparam int unsigned slotW     = ccuCfg.rSlotWidth,
    localparam int unsigned numBeats  = ccuCfg.cachelineAxiTransfers,
    localparam int unsigned beatW     = ccuCfg.beatIndexWidth,
    localparam int unsigned numTids   = ccuCfg.numTids,
    localparam int unsigned tidW      = ccuCfg.tidWidth,
    localparam int unsigned dataW     = ccuCfg.u.axiDataWidth,
    localparam int unsigned subIdW    = ccuCfg.u.axiSubordinateIdWidth,
    localparam int unsigned userW     = ccuCfg.u.axiUserWidth
) (
    input  logic              clk_i,
    input  logic              rst_ni,

    //  Reservation at admission
    input  logic              alloc_i,
    input  logic [subIdW-1:0] alloc_id_i,
    input  logic [userW-1:0]  alloc_user_i,
    input  axi_pkg::len_t     alloc_len_i,
    output logic [slotW-1:0]  alloc_slot_o,
    output logic              full_o,

    //  Memory R, never back-pressured
    input  logic              mem_valid_i,
    input  rb_mem_t           mem_i,
    //  Snoop data; memory R takes the write port first
    input  logic              cd_valid_i,
    output logic              cd_ready_o,
    input  rb_cd_t            cd_i,
    //  The tid a slot's read got at issue, any time before its data
    input  logic                bind_valid_i,
    input  logic [slotW-1:0]    bind_slot_i,
    input  logic [tidW-1:0]     bind_tid_i,
    //  A slot's response, fixed at resolve
    input  logic                info_valid_i,
    input  r_info_t             info_i,
    //  Slots whose response may go from now on
    input  logic [numSlots-1:0] go_i,

    output logic              r_valid_o,
    input  logic              r_ready_i,
    output r_t                r_o,
    output logic [tidW-1:0]   r_tid_o,
    output logic [slotW-1:0]  r_slot_o,

    //  Released at the RACK
    input  logic              free_i,
    input  logic [slotW-1:0]  free_slot_i
);

    localparam int unsigned numWords = numSlots * numBeats;
    localparam int unsigned wordW    = numWords > 1 ? $clog2(numWords) : 1;

    typedef struct packed {
        axi_pkg::resp_t    resp;
        logic [dataW-1:0]  data;
    } word_t;

    typedef struct packed {
        r_t                r;
        logic [tidW-1:0]   tid;
        logic [slotW-1:0]  slot;
    } beat_t;

    function automatic logic [wordW-1:0] word_of(logic [slotW-1:0] slot, logic [beatW:0] beat);
        return wordW'(slot) * wordW'(numBeats) + wordW'(beat);
    endfunction

//  Slot state
//  {{{
    logic     [numSlots-1:0]               valid_q,      valid_d;
    logic     [numSlots-1:0]               issued_q,     issued_d;
    logic     [numSlots-1:0]               bound_q,      bound_d;
    logic     [numSlots-1:0][subIdW-1:0]   id_q,         id_d;
    logic     [numSlots-1:0][userW-1:0]    user_q,       user_d;
    axi_pkg::len_t [numSlots-1:0]          len_q,        len_d;
    logic     [numSlots-1:0][tidW-1:0]     tid_q,        tid_d;
    r_info_t  [numSlots-1:0]               info_q,       info_d;
    logic     [numSlots-1:0]               go_q,         go_d;
    logic     [numSlots-1:0][beatW:0]      wr_cnt_q,     wr_cnt_d;
    //  Older live slots of the same id, which leave first
    logic     [numSlots-1:0][numSlots-1:0] older_q,      older_d;


    lzc #(
        .WIDTH (numSlots),
        .MODE  (1'b0)
    ) u_alloc_lzc (
        .in_i    (~valid_q),
        .cnt_o   (alloc_slot_o),
        .empty_o (full_o)
    );
//  }}}

//  Write port: memory R first, snoop data waits
//  {{{
    logic             wr_req;
    logic [slotW-1:0] wr_slot;
    word_t            wr_word;

    assign cd_ready_o = !mem_valid_i;
    assign wr_req     = mem_valid_i || cd_valid_i;
    assign wr_slot    = mem_valid_i ? mem_i.slot : cd_i.slot;
    assign wr_word    = mem_valid_i ? word_t'{resp: mem_i.resp, data: mem_i.data} :
                                      word_t'{resp: axi_pkg::RESP_OKAY, data: cd_i.data};
//  }}}

//  Read port: one burst at a time, one beat ahead of the output
//  {{{
    logic [numSlots-1:0] candidate, candidate_gnt;
    logic [slotW-1:0]    candidate_idx;
    logic                cur_valid_q, cur_valid_d;
    logic [slotW-1:0]    cur_slot_q,  cur_slot_d;
    logic [beatW:0]      cur_beat_q,  cur_beat_d;

    logic                sel_valid, sel_available, sel_last, issue;
    logic [slotW-1:0]    sel_slot;
    logic [beatW:0]      sel_beat;
    logic [1:0]          space_q, space_d;

    logic                rd_valid_q;
    logic [slotW-1:0]    rd_slot_q;
    logic                rd_last_q;
    word_t [1:0]         sram_rdata;
    word_t               rd_word;
    beat_t               rd_beat;
    beat_t               out_beat;
    logic                out_empty, out_pop;

    for (genvar s = 0; s < numSlots; s++) begin : gen_candidate
        assign candidate[s] = valid_q[s] && bound_q[s] && go_q[s] && !issued_q[s] &&
                         !(cur_valid_q && cur_slot_q == slotW'(s)) &&
                         (older_q[s] & valid_q & ~issued_q) == '0 &&
                         (info_q[s].ack || wr_cnt_q[s] != '0);
    end

    rr_arb_tree #(
        .NumIn     (numSlots),
        .DataType  (logic),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b0)
    ) u_slot_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (candidate),
        .gnt_o   (candidate_gnt),
        .data_i  ('0),
        .req_o   (),
        .gnt_i   (!cur_valid_q && issue),
        .data_o  (),
        .idx_o   (candidate_idx)
    );

    assign sel_valid = cur_valid_q || |candidate;
    assign sel_slot  = cur_valid_q ? cur_slot_q : candidate_idx;
    assign sel_beat  = cur_valid_q ? cur_beat_q : '0;
    assign sel_available = info_q[sel_slot].ack || wr_cnt_q[sel_slot] > sel_beat;
    assign sel_last  = info_q[sel_slot].ack || sel_beat == (beatW+1)'(len_q[sel_slot]);
    assign issue     = sel_valid && sel_available && space_q != '0;

    always_comb begin : cur_comb
        cur_valid_d = cur_valid_q;
        cur_slot_d  = cur_slot_q;
        cur_beat_d  = cur_beat_q;
        if (issue) begin
            cur_valid_d = !sel_last;
            cur_slot_d  = sel_slot;
            cur_beat_d  = sel_beat + 1'b1;
        end
    end

    assign out_pop = r_valid_o && r_ready_i;
    assign space_d = space_q - 2'(issue) + 2'(out_pop);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cur_valid_q <= 1'b0;
            cur_slot_q  <= '0;
            cur_beat_q  <= '0;
            space_q     <= 2'd2;
            rd_valid_q  <= 1'b0;
            rd_slot_q   <= '0;
            rd_last_q   <= 1'b0;
        end else begin
            cur_valid_q <= cur_valid_d;
            cur_slot_q  <= cur_slot_d;
            cur_beat_q  <= cur_beat_d;
            space_q     <= space_d;
            rd_valid_q  <= issue;
            if (issue) begin
                rd_slot_q <= sel_slot;
                rd_last_q <= sel_last;
            end
        end
    end

    tc_sram #(
        .NumWords  (numWords),
        .DataWidth ($bits(word_t)),
        .ByteWidth ($bits(word_t)),
        .NumPorts  (32'd2),
        .Latency   (32'd1)
    ) u_data (
        .clk_i,
        .rst_ni,
        .req_i   ({issue && !info_q[sel_slot].ack, wr_req}),
        .we_i    ({1'b0, 1'b1}),
        .addr_i  ({word_of(sel_slot, sel_beat), word_of(wr_slot, wr_cnt_q[wr_slot])}),
        .wdata_i ({word_t'('0), wr_word}),
        .be_i    ('1),
        .rdata_o (sram_rdata)
    );

    assign rd_word = sram_rdata[1];

    always_comb begin : rd_beat_comb
        automatic r_info_t meta = info_q[rd_slot_q];

        rd_beat         = '0;
        rd_beat.tid     = tid_q[rd_slot_q];
        rd_beat.slot    = rd_slot_q;
        rd_beat.r.id    = id_q[rd_slot_q];
        rd_beat.r.user  = user_q[rd_slot_q];
        rd_beat.r.last  = rd_last_q;
        rd_beat.r.data  = meta.ack ? '0 : rd_word.data;
        rd_beat.r.resp[RESP_IS_SHARED] = meta.is_shared;
        rd_beat.r.resp[RESP_IS_DIRTY]  = meta.pass_dirty;
        //  Errors pass through; a held reservation upgrades OKAY
        if (meta.ack || rd_word.resp == axi_pkg::RESP_OKAY)
            rd_beat.r.resp[axi_pkg::RespWidth-1:0] = meta.exokay ? axi_pkg::RESP_EXOKAY :
                                                                    axi_pkg::RESP_OKAY;
        else
            rd_beat.r.resp[axi_pkg::RespWidth-1:0] = rd_word.resp;
    end

    //  The SRAM output is the register on this path
    fifo_v3 #(
        .FALL_THROUGH (1'b1),
        .DEPTH        (2),
        .dtype        (beat_t)
    ) u_out_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (),
        .empty_o    (out_empty),
        .usage_o    (),
        .data_i     (rd_beat),
        .push_i     (rd_valid_q),
        .data_o     (out_beat),
        .pop_i      (out_pop)
    );

    assign r_valid_o = !out_empty;
    assign r_o       = out_beat.r;
    assign r_tid_o   = out_beat.tid;
    assign r_slot_o  = out_beat.slot;
//  }}}

//  Slot updates
//  {{{
    always_comb begin : slot_comb
        valid_d      = valid_q;
        issued_d     = issued_q;
        bound_d      = bound_q;
        id_d         = id_q;
        user_d       = user_q;
        len_d        = len_q;
        tid_d        = tid_q;
        wr_cnt_d     = wr_cnt_q;
        older_d      = older_q;
        info_d       = info_q;
        go_d         = go_q | go_i;

        if (info_valid_i) begin
            info_d[info_i.rslot] = info_i;
            if (info_i.go) go_d[info_i.rslot] = 1'b1;
        end

        if (wr_req)
            wr_cnt_d[wr_slot] = wr_cnt_q[wr_slot] + 1'b1;

        if (issue && sel_last) issued_d[sel_slot] = 1'b1;

        if (bind_valid_i) begin
            bound_d[bind_slot_i] = 1'b1;
            tid_d[bind_slot_i]   = bind_tid_i;
        end

        if (free_i) begin
            valid_d[free_slot_i]      = 1'b0;
            issued_d[free_slot_i]     = 1'b0;
            bound_d[free_slot_i]      = 1'b0;
            go_d[free_slot_i]         = 1'b0;
            wr_cnt_d[free_slot_i]     = '0;
            for (int unsigned s = 0; s < numSlots; s++) older_d[s][free_slot_i] = 1'b0;
        end

        if (alloc_i) begin
            valid_d[alloc_slot_o] = 1'b1;
            id_d[alloc_slot_o]    = alloc_id_i;
            user_d[alloc_slot_o]  = alloc_user_i;
            len_d[alloc_slot_o]   = alloc_len_i;
            for (int unsigned s = 0; s < numSlots; s++)
                older_d[alloc_slot_o][s] = valid_q[s] && !issued_q[s] && id_q[s] == alloc_id_i &&
                                           !(free_i && free_slot_i == slotW'(s));
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q      <= '0;
            issued_q     <= '0;
            bound_q      <= '0;
            id_q         <= '0;
            user_q       <= '0;
            len_q        <= '0;
            tid_q        <= '0;
            wr_cnt_q     <= '0;
            older_q      <= '0;
            info_q       <= '0;
            go_q         <= '0;
        end else begin
            valid_q      <= valid_d;
            issued_q     <= issued_d;
            bound_q      <= bound_d;
            id_q         <= id_d;
            user_q       <= user_d;
            len_q        <= len_d;
            tid_q        <= tid_d;
            wr_cnt_q     <= wr_cnt_d;
            older_q      <= older_d;
            info_q       <= info_d;
            go_q         <= go_d;
        end
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        alloc_i |-> !full_o)
        else $error("R slot allocated with none free");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wr_req |-> valid_q[wr_slot] && !info_q[wr_slot].ack)
        else $error("R data written to a slot that expects none");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wr_req |-> wr_cnt_q[wr_slot] <= (beatW+1)'(len_q[wr_slot]))
        else $error("R data written past the burst of its slot");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        mem_valid_i |-> mem_i.last == (wr_cnt_q[mem_i.slot] == (beatW+1)'(len_q[mem_i.slot])))
        else $error("memory R burst does not match its AR");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cd_valid_i && cd_ready_o |->
            cd_i.last == (wr_cnt_q[cd_i.slot] == (beatW+1)'(len_q[cd_i.slot])))
        else $error("forwarded CD burst does not match its AR");

    for (genvar s = 0; s < numSlots; s++) begin : gen_info_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            valid_q[s] && go_q[s] |=> !valid_q[s] || go_q[s])
            else $error("the response of a live slot was withdrawn");
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        bind_valid_i |-> (valid_q[bind_slot_i] || alloc_i && alloc_slot_o == bind_slot_i) &&
                         !bound_q[bind_slot_i])
        else $error("tid bound to a slot that is free or bound already");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (info_valid_i |-> valid_q[info_i.rslot] && bound_q[info_i.rslot]) and
        (go_i != '0 |-> (go_i & ~(valid_q & bound_q)) == '0))
        else $error("response for a slot that is free or unbound");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wr_req |-> bound_q[wr_slot])
        else $error("R data for a slot before its tid");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        free_i |-> valid_q[free_slot_i] && issued_q[free_slot_i])
        else $error("R slot released before its burst left");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        r_valid_o && !r_ready_i |=> r_valid_o && $stable(r_o))
        else $error("R channel unstable while stalled");
    `endif
    // pragma translate_on
//  }}}
endmodule
