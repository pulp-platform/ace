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

//! Transaction scoreboard
//
//  Tracks one address slice and id per live transaction. Up to two allocation
//  ports each get a distinct free index in the same cycle, so callers whose
//  allocation events are independent never collide. Entries are freed by a
//  bitvector, so any number may retire together. Matching by slice answers
//  same-line queries. The array is exposed so a caller can layer ordering on it.
module ccu_scoreboard #(
    parameter  int unsigned numEntries = 8,
    parameter  int unsigned sliceWidth = 16,
    parameter  int unsigned idWidth    = 5,
    parameter  int unsigned numAlloc   = 1,
    parameter  int unsigned numQueries = 0,
    localparam int unsigned idxWidth   = numEntries > 1 ? $clog2(numEntries) : 1,
    //  A port count of zero would give a reversed [-1:0] range, so the
    //  array keeps one element and the unused generate loop emits nothing
    localparam int unsigned nQuery     = numQueries > 0 ? numQueries : 1
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [numAlloc-1:0]                 alloc_valid_i,
    input  logic [numAlloc-1:0][sliceWidth-1:0] alloc_slice_i,
    input  logic [numAlloc-1:0][idWidth-1:0]    alloc_id_i,
    output logic [numAlloc-1:0][idxWidth-1:0]   alloc_idx_o,
    //  full_o[a] means port a has no free entry once ports below it have taken theirs
    output logic [numAlloc-1:0]                 full_o,

    input  logic [numEntries-1:0]               retire_mask_i,
    input  logic [numEntries-1:0]               free_mask_i,
    output logic [numEntries-1:0]               retired_o,

    input  logic [nQuery-1:0][sliceWidth-1:0]   query_slice_i,
    output logic [nQuery-1:0]                   query_hit_o,

    output logic [numEntries-1:0]               valid_o,
    output logic [numEntries-1:0][sliceWidth-1:0] slice_o,
    output logic [numEntries-1:0][idWidth-1:0]    id_o
);

    logic [numEntries-1:0]                 valid_q,   valid_d;
    logic [numEntries-1:0]                 retired_q, retired_d;
    logic [numEntries-1:0][sliceWidth-1:0] slice_q,   slice_d;
    logic [numEntries-1:0][idWidth-1:0]    id_q,      id_d;

    //  Port 0 takes the lowest free entry, port 1 the highest. They can only
    //  coincide when a single entry is free, which is exactly what closes port 1
    logic [numEntries-1:0] free_set;

    assign free_set = ~valid_q;

    if (numAlloc > 2) begin : gen_unsupported
        $error("ccu_scoreboard supports at most two allocation ports");
    end

    lzc #(
        .WIDTH (numEntries),
        .MODE  (1'b0)
    ) u_alloc_low_lzc (
        .in_i    (free_set),
        .cnt_o   (alloc_idx_o[0]),
        .empty_o (full_o[0])
    );

    if (numAlloc > 1) begin : gen_alloc_high
        logic [idxWidth-1:0] high_zeros;

        lzc #(
            .WIDTH (numEntries),
            .MODE  (1'b1)
        ) u_alloc_high_lzc (
            .in_i    (free_set),
            .cnt_o   (high_zeros),
            .empty_o ()
        );

        assign alloc_idx_o[1] = idxWidth'(numEntries - 1) - high_zeros;
        assign full_o[1]      = full_o[0] || alloc_idx_o[0] == alloc_idx_o[1];
    end

    for (genvar q = 0; q < numQueries; q++) begin : gen_query
        logic [numEntries-1:0] hit;
        for (genvar e = 0; e < numEntries; e++) begin : gen_hit
            assign hit[e] = valid_q[e] && slice_q[e] == query_slice_i[q];
        end
        assign query_hit_o[q] = |hit;
    end

    if (numQueries == 0) begin : gen_no_query
        assign query_hit_o = '0;
    end

    assign retired_d = (retired_q | retire_mask_i) & ~free_mask_i;

    always_comb begin : entry_comb
        valid_d = valid_q & ~free_mask_i;
        slice_d = slice_q;
        id_d    = id_q;

        for (int unsigned a = 0; a < numAlloc; a++) begin
            if (alloc_valid_i[a]) begin
                valid_d[alloc_idx_o[a]] = 1'b1;
                slice_d[alloc_idx_o[a]] = alloc_slice_i[a];
                id_d[alloc_idx_o[a]]    = alloc_id_i[a];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q   <= '0;
            retired_q <= '0;
            slice_q   <= '0;
            id_q      <= '0;
        end else begin
            valid_q   <= valid_d;
            retired_q <= retired_d;
            slice_q   <= slice_d;
            id_q      <= id_d;
        end
    end

    assign valid_o   = valid_q;
    assign retired_o = retired_q;
    assign slice_o = slice_q;
    assign id_o    = id_q;

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    for (genvar a = 0; a < numAlloc; a++) begin : gen_alloc_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            alloc_valid_i[a] |-> !full_o[a])
            else $error("allocation with no free entry");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            alloc_valid_i[a] |-> !valid_q[alloc_idx_o[a]])
            else $error("allocation targets a live entry");

        for (genvar b = a + 1; b < numAlloc; b++) begin : gen_distinct
            assert property (@(posedge clk_i) disable iff (!rst_ni)
                (alloc_valid_i[a] && alloc_valid_i[b]) |-> alloc_idx_o[a] != alloc_idx_o[b])
                else $error("two allocations claimed the same entry");
        end
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (free_mask_i & ~valid_q) == '0)
        else $error("freeing an entry that is not live");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (free_mask_i & ~(retire_mask_i | retired_q)) == '0)
        else $error("freeing an entry that has not retired");
    `endif
    // pragma translate_on
//  }}}

endmodule
