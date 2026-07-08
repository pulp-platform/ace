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
//  serialized by an age matrix (an entry may dispatch only when no older,
//  still-live, same-hash entry exists), while different addresses dispatch in
//  parallel. An entry retires on its RACK. The dispatched AR is held back
//  while it collides with an inflight write (RAW hazard against the write
//  engine). Storage is bounded by the number of inflight transactions, not by
//  the FIFO grid it replaces.
module ccu_ar_dispatch
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t  ccuCfg          = '{default: '0},
    parameter type          ccu_ace_ar_t    = logic,
    localparam int unsigned numEntries      = ccuCfg.u.numShareableTransactions,
    localparam int unsigned entryIndexWidth = ccuCfg.transactionIndexWidth
) (
    input  logic clk_i,
    input  logic rst_ni,

    //  Incoming AR
    input  ccu_ace_ar_t ar_i,
    input  logic        ar_valid_i,
    output logic        ar_ready_o,

    //  Dispatched AR (to the snoop pipeline)
    output ccu_ace_ar_t ar_o,
    output logic        ar_valid_o,
    input  logic        ar_ready_i,

    //  RAW hazard check against the write engine inflight addresses
    output logic                                aw_addr_check_o,
    output logic [ccuCfg.addressCheckWidth-1:0] aw_addr_slice_o,
    input  logic                                aw_addr_hazard_i,

    //  RACK of the dispatched ARs, matched by id to retire the entry
    input  logic [ccuCfg.u.numSubordinates-1:0]                          rack_valid_i,
    input  logic [ccuCfg.u.numSubordinates-1:0][ccuCfg.axiCcuIdWidth-1:0] rack_id_i
);

//  Pool storage
//  {{{
    logic        [numEntries-1:0]      valid_q,    valid_d;
    logic        [numEntries-1:0]      inflight_q, inflight_d;
    ccu_ace_ar_t [numEntries-1:0]      entry_ar_q;
    //  older_q[i][j] = entry i is older than entry j
    logic        [numEntries-1:0][numEntries-1:0]  older_q,    older_d;

    logic [numEntries-1:0]             eligible;
    logic [numEntries-1:0]             gnt;
    logic [numEntries-1:0]             dispatch;
    logic [numEntries-1:0]             retire;
    logic [entryIndexWidth-1:0]        alloc_slot;
    logic                              pool_full;
    logic                              alloc;
    logic                              arb_req;
    logic                              arb_gnt;
//  }}}

//  Allocation: pick a free slot; ready when the pool is not full
//  {{{
    lzc #(
        .WIDTH (numEntries),
        .MODE  (1'b0)
    ) u_alloc_lzc (
        .in_i    (~valid_q),
        .cnt_o   (alloc_slot),
        .empty_o (pool_full)
    );

    assign ar_ready_o = !pool_full;
    assign alloc      = ar_valid_i && ar_ready_o;
//  }}}

//  Age matrix: on allocation the new slot is younger than every live entry
//  {{{
    always_comb begin : older_comb
        older_d = older_q;
        if (alloc) begin
            for (int unsigned i = 0; i < numEntries; i++) begin
                older_d[alloc_slot][i] = 1'b0;         //  new slot is oldest of none
                older_d[i][alloc_slot] = valid_q[i];   //  live entries are older
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) older_q <= '0;
        else         older_q <= older_d;
    end
//  }}}

//  Per-entry logic
//  {{{
    for (genvar e = 0; e < numEntries; e++) begin : gen_entry
        logic [ccuCfg.addressCheckWidth-1:0] hash;
        logic [numEntries-1:0]               blockers;
        logic                                alloc_this;
        logic                                rack_hit;

        assign hash       = entry_ar_q[e].addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
        assign alloc_this = alloc && alloc_slot == entryIndexWidth'(e);

        //  Blocked by any older, still-live, same-hash entry
        for (genvar j = 0; j < numEntries; j++) begin : gen_block
            logic [ccuCfg.addressCheckWidth-1:0] hash_j;
            assign hash_j      = entry_ar_q[j].addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
            assign blockers[j] = valid_q[j] && older_q[j][e] && hash_j == hash;
        end

        assign eligible[e] = valid_q[e] && !inflight_q[e] && ~|blockers;

        //  RACK retirement (match by id)
        always_comb begin : rack_comb
            rack_hit = 1'b0;
            for (int unsigned s = 0; s < ccuCfg.u.numSubordinates; s++) begin
                if (rack_valid_i[s] && rack_id_i[s] == entry_ar_q[e].id)
                    rack_hit = 1'b1;
            end
        end
        assign retire[e] = valid_q[e] && inflight_q[e] && rack_hit;

        always_comb begin : entry_comb
            valid_d[e]    = valid_q[e];
            inflight_d[e] = inflight_q[e];
            unique case (1'b1)
                alloc_this: begin
                    valid_d[e]    = 1'b1;
                    inflight_d[e] = 1'b0;
                end
                retire[e]: begin
                    valid_d[e]    = 1'b0;
                    inflight_d[e] = 1'b0;
                end
                dispatch[e]: begin
                    inflight_d[e] = 1'b1;
                end
                default: ;
            endcase
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                valid_q[e]    <= 1'b0;
                inflight_q[e] <= 1'b0;
                entry_ar_q[e] <= '0;
            end else begin
                valid_q[e]    <= valid_d[e];
                inflight_q[e] <= inflight_d[e];
                if (alloc_this) entry_ar_q[e] <= ar_i;
            end
        end
    end
//  }}}

//  Dispatch arbitration and RAW hazard gating
//  {{{
    rr_arb_tree #(
        .NumIn     (numEntries),
        .DataType  (ccu_ace_ar_t),
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
        .data_i  (entry_ar_q),
        .req_o   (arb_req),
        .gnt_i   (arb_gnt),
        .data_o  (ar_o),
        .idx_o   ()
    );

    assign aw_addr_check_o = arb_req;
    assign aw_addr_slice_o = ar_o.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];

    stream_filter u_ar_hazard_drop (
        .valid_i (arb_req),
        .ready_o (arb_gnt),
        .drop_i  (aw_addr_hazard_i),
        .valid_o (ar_valid_o),
        .ready_i (ar_ready_i)
    );

    assign dispatch = aw_addr_hazard_i ? '0 : gnt;
//  }}}
endmodule
