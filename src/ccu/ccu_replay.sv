// Copyright (c) 2025 ETH Zurich, University of Bologna
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

module ccu_replay
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t  ccuCfg                    = '{default: '0},
    parameter type          ccu_ace_ar_t              = logic,
    localparam int unsigned numScoreboardEntries      = ccuCfg.u.numShareableTransactions,
    localparam int unsigned scoreboardEntryIndexWidth = ccuCfg.transactionIndexWidth

) (
    input  logic                                            clk_i,
    input  logic                                            rst_ni,
    input  logic                                            alloc_i,
    input  ccu_ace_ar_t                                     alloc_ar_i,
    input  logic        [scoreboardEntryIndexWidth-1:0]     alloc_scoreboard_entry_i,
    input  logic        [scoreboardEntryIndexWidth-1:0]     replay_scoreboard_entry_i,
    output ccu_ace_ar_t                                     replay_ar_o,
    output logic                                            replay_ar_valid_o,
    input  logic                                            replay_ar_ready_i,
    input  logic        [numScoreboardEntries-1:0]          scoreboard_dealloc_i,
    output logic                                            full_o
);

//  Shared signals
//  {{{
    typedef struct packed {
        ccu_ace_ar_t                          ar;
        logic [scoreboardEntryIndexWidth-1:0] dependency;
    } replay_entry_t;

    typedef struct packed {
        logic                                    head;
        logic                                    tail;
        logic [ccuCfg.replayEntryIndexWidth-1:0] next;
    } replay_linked_list_t;

    replay_entry_t       [ccuCfg.u.numReplayEntries-1:0]    entry_q;
    replay_entry_t       [ccuCfg.u.numReplayEntries-1:0]    entry_d;
    replay_linked_list_t [ccuCfg.u.numReplayEntries-1:0]    list_q;
    replay_linked_list_t [ccuCfg.u.numReplayEntries-1:0]    list_d;
    logic                [ccuCfg.u.numReplayEntries-1:0]    valid_q;
    logic                [ccuCfg.u.numReplayEntries-1:0]    valid_d;
    logic                [ccuCfg.u.numReplayEntries-1:0]    hazard_q;
    logic                [ccuCfg.u.numReplayEntries-1:0]    hazard_d;

    logic                [ccuCfg.replayEntryIndexWidth-1:0] alloc_entry;
    logic                                                   alloc_hazard;
    logic                                                   alloc_head;
    logic                [ccuCfg.addressCheckWidth-1:0]     alloc_addr_slice;

    logic                [ccuCfg.u.numReplayEntries-1:0]    address_hit;
    logic                [ccuCfg.u.numReplayEntries-1:0]    replay_req;
    logic                [ccuCfg.u.numReplayEntries-1:0]    replay_gnt;
    ccu_ace_ar_t         [ccuCfg.u.numReplayEntries-1:0]    replay_ar;
    logic                                                   replay_is_tail;
    logic        [ccuCfg.replayEntryIndexWidth-1:0]         replay_entry;
    logic                [ccuCfg.replayEntryIndexWidth-1:0] replay_next_entry;

    assign full_o = &valid_q;

    always_comb begin : alloc_entry_comb
        alloc_entry = '0;
        for (int unsigned e = 0; e < ccuCfg.u.numReplayEntries; e++) begin
            if (!valid_q[e]) begin
                alloc_entry = e;
                break;
            end
        end
    end

    //  Entries which are being allocated the same cycle the corresponding
    //  scoreboard entry is being deallocated AND are list heads can replay
    //  from the next cycle
    assign alloc_hazard     = !alloc_head || !scoreboard_dealloc_i[alloc_scoreboard_entry_i];
    assign alloc_head       = ~|(address_hit & valid_q);
    assign alloc_addr_slice = alloc_ar_i.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
//  }}}

//  Per-entry logic
//  {{{
    for (genvar e = 0; e < ccuCfg.u.numReplayEntries; e++) begin : gen_entry
        logic                                alloc;
        logic                                clear_hazard;
        logic                                link;
        logic                                make_head;
        logic [ccuCfg.addressCheckWidth-1:0] addr_slice;

        assign addr_slice     = entry_q[e].ar.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
        assign address_hit[e] = addr_slice == alloc_addr_slice;
        assign replay_ar[e]   = entry_q[e].ar;

        assign alloc         = alloc_entry       == e && alloc_i;
        assign make_head     = replay_next_entry == e && |replay_gnt && !replay_is_tail;
        assign link          = valid_q[e] && list_q[e].tail && address_hit[e] && alloc_i;
        assign clear_hazard  = valid_q[e] && list_q[e].head && scoreboard_dealloc_i[entry_q[e].dependency];
        assign replay_req[e] = valid_q[e] && list_q[e].head && !hazard_q[e];

        always_comb begin : entry_comb
            list_d  [e] = list_q  [e];
            entry_d [e] = entry_q [e];
            valid_d [e] = valid_q [e];
            hazard_d[e] = hazard_q[e];

            unique case (1'b1)
                //  The scoreboard dependency for a first allocation
                //  is given by the scoreboard entry with a colliding
                //  address
                alloc: begin
                    valid_d [e]            = 1'b1;
                    entry_d [e].ar         = alloc_ar_i;
                    entry_d [e].dependency = alloc_scoreboard_entry_i;
                    list_d  [e].tail       = 1'b1;
                    list_d  [e].head       = alloc_head;
                    hazard_d[e]            = alloc_hazard;
                end
                //  The scoreboard dependency for a node being promoted
                //  to list head is the scoreboard entry being allocated
                //  to the previous head of the list
                make_head: begin
                    entry_d [e].dependency = replay_scoreboard_entry_i;
                    list_d  [e].head       = 1'b1;
                end
                link: begin
                    list_d  [e].tail       = 1'b0;
                    list_d  [e].next       = alloc_entry;
                end
                replay_gnt[e]: begin
                    valid_d [e]            = 1'b0;
                end
                default: ;
            endcase

            //  Hazard clearing can happen concurrently
            //  to other events, thus it cannot be in the
            //  unique case statement above
            if (clear_hazard) begin
                hazard_d[e] = 1'b0;
            end
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                list_q  [e] <= '0;
                entry_q [e] <= '0;
                valid_q [e] <= '0;
                hazard_q[e] <= '0;
            end else begin
                list_q  [e] <= list_d  [e];
                entry_q [e] <= entry_d [e];
                valid_q [e] <= valid_d [e];
                hazard_q[e] <= hazard_d[e];
            end
        end
    end
//  }}}

//  Replay arbitration to snoop pipeline
//  {{{
    rr_arb_tree #(
        .NumIn     (ccuCfg.u.numReplayEntries),
        .DataType  (ccu_ace_ar_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_replay_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (replay_req),
        .gnt_o   (replay_gnt),
        .data_i  (replay_ar),
        .req_o   (replay_ar_valid_o),
        .gnt_i   (replay_ar_ready_i),
        .data_o  (replay_ar_o),
        .idx_o   (replay_entry)
    );

    assign replay_next_entry = list_q[replay_entry].next;
    assign replay_is_tail    = list_q[replay_entry].tail;
//  }}}
endmodule
