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

//! FIFO exposing a masked query over its content
//
//  Derived from the common_cells `fifo_v3`.
module ccu_fifo #(
    parameter int unsigned  numEntries      = 8,
    parameter type          data_t          = logic,
    localparam int unsigned entryIndexWidth = numEntries > 1 ? $clog2(numEntries) : 1
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic flush_i,

    output logic                       full_o,
    output logic                       empty_o,
    output logic [entryIndexWidth-1:0] usage_o,

    input  data_t data_i,
    input  logic  push_i,
    output data_t data_o,
    input  logic  pop_i,

    input  data_t exists_data_i,
    input  data_t exists_mask_i,
    output logic  exists_o
);

//  Storage and pointers
//  {{{
    logic                  gate_clock;
    logic [entryIndexWidth-1:0] read_pointer_n,  read_pointer_q;
    logic [entryIndexWidth-1:0] write_pointer_n, write_pointer_q;
    logic [entryIndexWidth:0]   status_cnt_n,    status_cnt_q;
    data_t [numEntries-1:0]      mem_n, mem_q;

    assign usage_o = status_cnt_q[entryIndexWidth-1:0];
    assign full_o  = status_cnt_q == numEntries[entryIndexWidth:0];
    assign empty_o = status_cnt_q == '0;
//  }}}

//  Query port
//  {{{
    //  Occupancy mask: a thermometer of status_cnt_q ones rotated left
    //  by the read pointer
    logic [numEntries-1:0]   count_mask;
    logic [2*numEntries-1:0] count_mask_rotated;
    logic [numEntries-1:0]   occupancy_mask;
    logic [numEntries-1:0]   exists_match;

    for (genvar d = 0; d < numEntries; d++) begin : gen_count_mask
        assign count_mask[d] = (entryIndexWidth+1)'(d) < status_cnt_q;
    end

    assign count_mask_rotated = {2{count_mask}} << read_pointer_q;
    assign occupancy_mask     = count_mask_rotated[2*numEntries-1:numEntries];

    for (genvar d = 0; d < numEntries; d++) begin : gen_exists_match
        assign exists_match[d] = occupancy_mask[d] &&
                                 ((mem_q[d] & exists_mask_i) == (exists_data_i & exists_mask_i));
    end

    assign exists_o = |exists_match;
//  }}}

//  Read and write logic
//  {{{
    always_comb begin : read_write_comb
        read_pointer_n  = read_pointer_q;
        write_pointer_n = write_pointer_q;
        status_cnt_n    = status_cnt_q;
        data_o          = mem_q[read_pointer_q];
        mem_n           = mem_q;
        gate_clock      = 1'b1;

        if (push_i && !full_o) begin
            mem_n[write_pointer_q] = data_i;
            gate_clock             = 1'b0;
            if (write_pointer_q == numEntries[entryIndexWidth-1:0] - 1)
                write_pointer_n = '0;
            else
                write_pointer_n = write_pointer_q + 1;
            status_cnt_n = status_cnt_q + 1;
        end

        if (pop_i && !empty_o) begin
            if (read_pointer_n == numEntries[entryIndexWidth-1:0] - 1)
                read_pointer_n = '0;
            else
                read_pointer_n = read_pointer_q + 1;
            status_cnt_n = status_cnt_q - 1;
        end

        //  Keep the count stable on a simultaneous push and pop
        if (push_i && pop_i && !full_o && !empty_o)
            status_cnt_n = status_cnt_q;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            read_pointer_q  <= '0;
            write_pointer_q <= '0;
            status_cnt_q    <= '0;
        end else if (flush_i) begin
            read_pointer_q  <= '0;
            write_pointer_q <= '0;
            status_cnt_q    <= '0;
        end else begin
            read_pointer_q  <= read_pointer_n;
            write_pointer_q <= write_pointer_n;
            status_cnt_q    <= status_cnt_n;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mem_q <= {numEntries{data_t'('0)}};
        end else if (!gate_clock) begin
            mem_q <= mem_n;
        end
    end
//  }}}
endmodule
