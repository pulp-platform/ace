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

//! One write port, one read port of one-cycle latency, in flops or on a `tc_sram`
module ccu_buffer_mem #(
    parameter  int unsigned NumWords = 32'd1,
    parameter  bit          UseFlops = 1'b0,
    parameter  type         word_t   = logic,
    localparam int unsigned AddrW    = NumWords > 1 ? $clog2(NumWords) : 1
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    input  logic             wr_valid_i,
    input  logic [AddrW-1:0] wr_addr_i,
    input  word_t            wr_data_i,

    input  logic             rd_valid_i,
    input  logic [AddrW-1:0] rd_addr_i,
    output word_t            rd_data_o
);

    if (UseFlops) begin : gen_flops
        word_t [NumWords-1:0] mem_q;

        //  A read in the cycle of a write to its word returns the old word
        always_ff @(posedge clk_i) begin
            if (wr_valid_i) mem_q[wr_addr_i] <= wr_data_i;
            if (rd_valid_i) rd_data_o        <= mem_q[rd_addr_i];
        end
    end else begin : gen_sram
        word_t [1:0] sram_rdata;

        tc_sram #(
            .NumWords  (NumWords),
            .DataWidth ($bits(word_t)),
            .ByteWidth ($bits(word_t)),
            .NumPorts  (32'd2),
            .Latency   (32'd1)
        ) u_sram (
            .clk_i,
            .rst_ni,
            .req_i   ({rd_valid_i, wr_valid_i}),
            .we_i    ({1'b0, 1'b1}),
            .addr_i  ({rd_addr_i, wr_addr_i}),
            .wdata_i ({word_t'('0), wr_data_i}),
            .be_i    ('1),
            .rdata_o (sram_rdata)
        );

        assign rd_data_o = sram_rdata[1];
    end

endmodule
