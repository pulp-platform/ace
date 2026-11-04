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

//! Exclusive monitor of one slice
//
//  Per manager, a line address monitor and a one-bit fallback; answers a cycle after the ask.
module ccu_excl_monitor
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg     = '{default: '0},
    parameter  type         excl_req_t = logic,
    localparam int unsigned numSub     = ccuCfg.u.numSubordinates,
    localparam int unsigned subIdxW    = ccuCfg.subordinateIndexWidth,
    localparam int unsigned numTids    = ccuCfg.numTids,
    localparam int unsigned tidW       = ccuCfg.tidWidth,
    localparam int unsigned lineW      = ccuCfg.numLineWidth
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,

    input  excl_req_t            req_i,
    input  logic                 req_valid_i,
    //  Registered, valid the cycle after the ask
    output ccu_excl_t            excl_o,

    //  Entries acknowledged by their initiator
    input  logic [numTids-1:0]   acked_i
);

    logic [numSub-1:0]             addr_valid_q, addr_valid_d;
    logic [numSub-1:0][lineW-1:0]  addr_tag_q,   addr_tag_d;
    logic [numSub-1:0]             min_bit_q,    min_bit_d;
    //  A passing store holds off other registrations until its RACK
    logic                          locked_q,     locked_d;
    logic [subIdxW-1:0]            lock_port_q,  lock_port_d;
    logic [tidW-1:0]               lock_tid_q,   lock_tid_d;

    logic store_pass, may_register;

    assign store_pass   = req_i.store &&
                          ((addr_valid_q[req_i.port] && addr_tag_q[req_i.port] == req_i.line) ||
                           min_bit_q[req_i.port]);
    assign may_register = !locked_q || lock_port_q == req_i.port;

    //  A load always registers its sequence and is answered EXOKAY
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)          excl_o <= '0;
        else if (req_valid_i) excl_o <= '{pass: req_i.load || store_pass,
                                          fail: req_i.store && !store_pass};
    end

    always_comb begin : monitor_comb
        addr_valid_d = addr_valid_q;
        addr_tag_d   = addr_tag_q;
        min_bit_d    = min_bit_q;
        locked_d     = locked_q;
        lock_port_d  = lock_port_q;
        lock_tid_d   = lock_tid_q;

        if (locked_q && acked_i[lock_tid_q]) locked_d = 1'b0;

        if (req_valid_i) begin
            if (store_pass) begin
                for (int unsigned p = 0; p < numSub; p++) begin
                    if (subIdxW'(p) != req_i.port) begin
                        min_bit_d[p] = 1'b0;
                        if (addr_tag_q[p] == req_i.line) addr_valid_d[p] = 1'b0;
                    end
                end
                locked_d    = 1'b1;
                lock_port_d = req_i.port;
                lock_tid_d  = req_i.tid;
            end
            //  A failed store registers too, so that its retry can pass
            if (may_register || store_pass) begin
                addr_valid_d[req_i.port] = 1'b1;
                addr_tag_d[req_i.port]   = req_i.line;
                min_bit_d[req_i.port]    = 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            addr_valid_q <= '0;
            addr_tag_q   <= '0;
            min_bit_q    <= '0;
            locked_q     <= 1'b0;
            lock_port_q  <= '0;
            lock_tid_q   <= '0;
        end else begin
            addr_valid_q <= addr_valid_d;
            addr_tag_q   <= addr_tag_d;
            min_bit_q    <= min_bit_d;
            locked_q     <= locked_d;
            lock_port_q  <= lock_port_d;
            lock_tid_q   <= lock_tid_d;
        end
    end

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        req_valid_i |-> req_i.load ^ req_i.store)
        else $error("exclusive that is neither a load nor a store");
    `endif
    // pragma translate_on
//  }}}
endmodule
