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

//! Memory engine
//
//  Issues a token's memory AR, ARID = tid, once no same-line write is pending; lands memory R by R slot.
module ccu_mem_engine
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg   = '{default: '0},
    parameter  type         me_tok_t = logic,
    parameter  type         mgr_ar_t = logic,
    parameter  type         mgr_r_t  = logic,
    parameter  type         rb_mem_t = logic,
    localparam int unsigned numSub   = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW  = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids  = ccuCfg.numTids,
    localparam int unsigned tidW     = ccuCfg.tidWidth,
    localparam int unsigned rSlotW   = ccuCfg.rSlotWidth,
    localparam int unsigned numSlots = ccuCfg.numWSlots,
    localparam int unsigned lineW    = ccuCfg.numLineWidth,
    localparam int unsigned offW     = ccuCfg.cachelineByteIndexWidth
) (
    input  logic                             clk_i,
    input  logic                             rst_ni,

    input  me_tok_t                          tok_i,
    input  logic                             tok_valid_i,
    output logic                             tok_ready_o,
    //  The head token's AR, kept by the table
    output logic [tidW-1:0]                  request_tid_o,
    input  mgr_ar_t                          request_i,

    //  Hazard query: every pending write, and those allocated this cycle
    input  logic [numSlots-1:0]              hazard_valid_i,
    input  logic [numSlots-1:0][lineW-1:0]   hazard_line_i,
    input  logic [1:0]                       hazard_alloc_i,
    input  logic [1:0][lineW-1:0]            hazard_alloc_line_i,

    output mgr_ar_t                          ar_o,
    output logic                             ar_valid_o,
    input  logic                             ar_ready_i,
    input  mgr_r_t                           r_i,
    input  logic                             r_valid_i,
    output logic                             r_ready_o,

    output rb_mem_t [numSub-1:0]             rb_o,
    output logic    [numSub-1:0]             rb_valid_o,

    //  The last beat of a tid's read landed
    output logic    [numTids-1:0]            done_o,

    output ccu_mem_events_t                  events_o
);

//  AR: in token order, held off by a same-line pending write
//  {{{
    me_tok_t          head;
    logic             head_valid, head_pop;
    logic [lineW-1:0] head_line;
    logic             hazard;
    logic             committed_q;

    stream_fifo #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (numTids),
        .T            (me_tok_t)
    ) u_tok_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .data_i     (tok_i),
        .valid_i    (tok_valid_i),
        .ready_o    (tok_ready_o),
        .data_o     (head),
        .valid_o    (head_valid),
        .ready_i    (head_pop)
    );

    assign request_tid_o = head.tid;
    assign head_line     = request_i.addr[offW +: lineW];

    always_comb begin : hazard_comb
        hazard = 1'b0;
        for (int unsigned s = 0; s < numSlots; s++)
            if (hazard_valid_i[s] && hazard_line_i[s] == head_line) hazard = 1'b1;
        for (int unsigned a = 0; a < 2; a++)
            if (hazard_alloc_i[a] && hazard_alloc_line_i[a] == head_line) hazard = 1'b1;
    end

    //  Once presented the AR stays
    assign ar_valid_o = head_valid && (committed_q || !hazard);
    assign ar_o       = request_i;
    assign head_pop   = ar_valid_o && ar_ready_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) committed_q <= 1'b0;
        else         committed_q <= ar_valid_o && !ar_ready_i;
    end
//  }}}

//  R: always accepted, its R slot was reserved at admission
//  {{{
    logic [numTids-1:0][subIdxW-1:0] port_q;
    logic [numTids-1:0][rSlotW-1:0]  rslot_q;
    logic [tidW-1:0]                 r_tid;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            port_q  <= '0;
            rslot_q <= '0;
        end else if (head_pop) begin
            port_q[head.tid]  <= head.port;
            rslot_q[head.tid] <= head.rslot;
        end
    end

    assign r_ready_o = 1'b1;
    assign r_tid     = r_i.id[tidW-1:0];

    for (genvar p = 0; p < numSub; p++) begin : gen_rb
        assign rb_valid_o[p] = r_valid_i && port_q[r_tid] == subIdxW'(p);
        assign rb_o[p]       = '{slot: rslot_q[r_tid], data: r_i.data, resp: r_i.resp,
                                 last: r_i.last};
    end

    assign done_o = r_valid_i && r_i.last ? numTids'(1) << r_tid : '0;
//  }}}

//  Performance events
//  {{{
    ccu_mem_events_t events_d;

    always_comb begin : events_comb
        events_d                 = '0;
        events_d.ar_issued       = head_pop;
        events_d.ar_stall_memory = ar_valid_o && !ar_ready_i;
        events_d.ar_stall_hazard = head_valid && !committed_q && hazard;
        events_d.r_beat          = r_valid_i;
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
        r_ready_o)
        else $error("memory R back-pressured");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_valid_o && !ar_ready_i |=> ar_valid_o && $stable(ar_o))
        else $error("memory AR unstable while stalled");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_valid_o |-> ar_o.len < ccuCfg.cachelineAxiTransfers)
        else $error("memory AR longer than the R slot it lands in");

    //  Each tid's burst matches its own AR, interleaved or not
    logic          [numTids-1:0] chk_out;
    axi_pkg::len_t [numTids-1:0] chk_len, chk_beat;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            chk_out  = '0;
            chk_len  = '0;
            chk_beat = '0;
        end else begin
            if (r_valid_i) begin
                assert (chk_out[r_tid]) else $error("memory R for tid %0d with no AR", r_tid);
                assert (r_i.last == (chk_beat[r_tid] == chk_len[r_tid]))
                    else $error("memory R burst for tid %0d: last on beat %0d, AR len %0d",
                                r_tid, chk_beat[r_tid], chk_len[r_tid]);
                chk_beat[r_tid] = r_i.last ? '0 : chk_beat[r_tid] + 1;
                if (r_i.last) chk_out[r_tid] = 1'b0;
            end
            if (head_pop) begin
                assert (!chk_out[head.tid]) else $error("memory AR reuses tid %0d", head.tid);
                chk_out[head.tid] = 1'b1;
                chk_len[head.tid] = request_i.len;
            end
        end
    end
    `endif
    // pragma translate_on
//  }}}
endmodule
