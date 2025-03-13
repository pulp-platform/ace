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

module lookup_fifo #(
    parameter DEPTH        = 4,
    parameter DATA_WIDTH   = 32,
    parameter LOOKUP_PORTS = 1,
    parameter FALL_THROUGH = 0,
    parameter type dtype   = logic [DATA_WIDTH-1:0]
) (
    input  logic  clk_i,
    input  logic  rst_ni,
    // Push interface
    input  logic  push_i,
    output logic  full_o,
    input  dtype  data_i,
    // Pop interface
    input  logic  pop_i,
    output logic  empty_o,
    output dtype  data_o,
    // Lookup interface
    input  dtype [LOOKUP_PORTS-1:0] lookup_data_i,
    output logic [LOOKUP_PORTS-1:0] lookup_match_o
);

typedef logic [$clog2(DEPTH)-1:0] ptr_t;

// Internal FIFO storage
dtype [DEPTH-1:0] mem_q, mem_d;
logic [DEPTH-1:0] valid_q, valid_d;
ptr_t             head_q, head_d;
ptr_t             tail_q, tail_d;

logic empty;

assign full_o  = valid_q == '1;
assign empty   = valid_q == '0;
assign empty_o = empty && !(FALL_THROUGH && push_i);

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        head_q  <= '0;
        tail_q  <= '0;
        mem_q   <= '0;
        valid_q <= '0;
    end else begin
        head_q  <= head_d;
        tail_q  <= tail_d;
        mem_q   <= mem_d;
        valid_q <= valid_d;
    end
end

assign data_o = FALL_THROUGH && empty ? data_i : mem_q[tail_q];

always_comb begin
    mem_d   = mem_q;
    valid_d = valid_q;
    tail_d  = tail_q;
    head_d  = head_q;

    if (FALL_THROUGH && empty && push_i && pop_i) begin
        // Fall through logic
        /* Nothing to add here? */
    end else begin
        // Pop logic
        if (pop_i && !empty) begin
            valid_d[tail_q] = 0;
            tail_d          = ptr_t'(tail_q + 1);
        end
        // Push logic
        if (push_i && !full_o) begin
            mem_d[head_q]   = data_i;
            valid_d[head_q] = 1'b1;
            head_d          = ptr_t'(head_q + 1);
        end
    end
end

// Lookup logic
always_comb begin
    for (int unsigned p = 0; p < LOOKUP_PORTS; p++) begin
        lookup_match_o[p] = 1'b0;
        for (int unsigned d = 0; d < DEPTH; d++) begin : gen_lookup_loop
            if (valid_q[d] && (lookup_data_i[p] == mem_q[d])) begin
                lookup_match_o[p] = 1'b1;
                break;
            end
        end
    end
end

endmodule

module lookup_fifo_stream #(
    parameter DEPTH        = 4,
    parameter DATA_WIDTH   = 32,
    parameter LOOKUP_PORTS = 1,
    parameter FALL_THROUGH = 0,
    parameter type dtype   = logic [DATA_WIDTH-1:0]
) (
    input  logic  clk_i,
    input  logic  rst_ni,
    // Push interface
    input  logic  valid_i,
    output logic  ready_o,
    input  dtype  data_i,
    // Pop interface
    input  logic  ready_i,
    output logic  valid_o,
    output dtype  data_o,
    // Lookup interface
    input  dtype [LOOKUP_PORTS-1:0] lookup_data_i,
    output logic [LOOKUP_PORTS-1:0] lookup_match_o
);

    logic empty, full;

    assign ready_o = !full;
    assign valid_o = !empty;

    lookup_fifo #(
        .DEPTH        (DEPTH       ),
        .DATA_WIDTH   (DATA_WIDTH  ),
        .LOOKUP_PORTS (LOOKUP_PORTS),
        .FALL_THROUGH (FALL_THROUGH),
        .dtype        (dtype       )
    ) (
        .clk_i,
        .rst_ni,
        .push_i  (valid_i),
        .full_o  (full),
        .data_i,
        .pop_i   (ready_i),
        .empty_o (empty),
        .data_o,
        .lookup_data_i,
        .lookup_match_o
    );

endmodule
