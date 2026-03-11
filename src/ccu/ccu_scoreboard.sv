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

module ccu_scoreboard
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t  ccuCfg                    = '{default: '0},
    localparam int unsigned numScoreboardEntries      = ccuCfg.u.numShareableTransactions,
    localparam int unsigned scoreboardEntryIndexWidth = ccuCfg.transactionIndexWidth

) (
    input  logic clk_i,
    input  logic rst_ni,

    output logic                                                               full_o,

    input  logic                                                               alloc_check_i,
    input  logic                                                               alloc_i,
    input  logic [ccuCfg.u.axiAddressWidth-1:0]                                alloc_addr_i,
    input  logic [ccuCfg.axiCcuIdWidth-1:0]                                    alloc_id_i,
    output logic                                                               alloc_hit_o,
    output logic [scoreboardEntryIndexWidth-1:0]                               alloc_hit_entry_o,
    output logic [scoreboardEntryIndexWidth-1:0]                               alloc_entry_o,

    input  logic                                                               dealloc_check_i,
    input  logic [ccuCfg.axiCcuIdWidth-1:0]                                    dealloc_id_i,
    output logic                                                               dealloc_hit_o,
    output logic [scoreboardEntryIndexWidth-1:0]                               dealloc_hit_entry_o,

    input  logic [ccuCfg.u.numSubordinates-1:0]                                dealloc_i,
    input  logic [ccuCfg.u.numSubordinates-1:0][scoreboardEntryIndexWidth-1:0] dealloc_entry_i,
    output logic [numScoreboardEntries-1:0]                                    dealloc_o
);

//  Shared signals
//  {{{
    typedef struct packed {
        logic [ccuCfg.addressCheckWidth-1:0] addr;
        logic [ccuCfg.axiCcuIdWidth-1:0]     id;
    } scoreboard_entry_t;

    logic              [ccuCfg.addressCheckWidth-1:0]                                alloc_addr_slice;

    logic              [numScoreboardEntries-1:0]                                    valid_q;
    logic              [numScoreboardEntries-1:0]                                    valid_d;
    scoreboard_entry_t [numScoreboardEntries-1:0]                                    entry_q;
    scoreboard_entry_t [numScoreboardEntries-1:0]                                    entry_d;
    logic              [numScoreboardEntries-1:0]                                    address_hit;
    logic              [numScoreboardEntries-1:0]                                    dealloc_id_hit;

    assign alloc_addr_slice = alloc_addr_i[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];

    assign alloc_hit_o   = alloc_check_i   && |(valid_q & address_hit);
    assign dealloc_hit_o = dealloc_check_i && |(valid_q & dealloc_id_hit);

    always_comb begin : alloc_entry_comb
        alloc_entry_o = '0;
        for (int unsigned e = 0; e < numScoreboardEntries; e++) begin
            if (!valid_q[e]) begin
                alloc_entry_o = e;
                break;
            end
        end
    end

    assign full_o = &valid_q;

    onehot_to_bin #(
        .ONEHOT_WIDTH (numScoreboardEntries)
    ) u_alloc_onehot_to_bin (
        .onehot (address_hit & valid_q),
        .bin    (alloc_hit_entry_o)
    );

    onehot_to_bin #(
        .ONEHOT_WIDTH (numScoreboardEntries)
    ) u_dealloc_onehot_to_bin (
        .onehot (dealloc_id_hit & valid_q),
        .bin    (dealloc_hit_entry_o)
    );
//  }}}

//  Per-entry logic
//  {{{
    for (genvar e = 0; e < numScoreboardEntries; e++) begin : gen_entry
        logic [ccuCfg.subordinateIndexWidth-1:0] subordinate_index;
        logic                                    alloc;
        assign subordinate_index = entry_q[e].id[ccuCfg.axiCcuIdWidth-1-:ccuCfg.subordinateIndexWidth];
        assign alloc             = alloc_i && alloc_entry_o == e && !full_o;
        assign dealloc_o[e]      = dealloc_i[subordinate_index] && dealloc_entry_i[subordinate_index] == e;
        assign address_hit[e]    = alloc_addr_slice == entry_q[e].addr;
        assign dealloc_id_hit[e] = dealloc_id_i == entry_q[e].id;

        always_comb begin : entry_comb
            valid_d[e] = valid_q[e];
            entry_d[e] = entry_q[e];

            unique case (1'b1)
                alloc: begin
                    valid_d[e]      = 1'b1;
                    entry_d[e].addr = alloc_addr_slice;
                    entry_d[e].id   = alloc_id_i;
                end
                dealloc_o[e]: begin
                    valid_d[e]      = 1'b0;
                end
                default: ;
            endcase
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                valid_q[e] <= 1'b0;
                entry_q[e] <= '0;
            end else begin
                valid_q[e] <= valid_d[e];
                entry_q[e] <= entry_d[e];
            end
        end
    end
//  }}}
endmodule
