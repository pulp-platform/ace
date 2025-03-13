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

module ace_ccu_conflict_manager #(
    parameter int unsigned AxiAddrWidth  = 0,
    parameter int unsigned NoRespPorts   = 0,
    parameter int unsigned MaxRespTrans  = 0,
    parameter int unsigned MaxSnoopTrans = 0,
    parameter int unsigned CmAddrWidth   = 0,

    localparam type cm_addr_t            = logic [CmAddrWidth-1:0]
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    input  logic                       cm_snoop_valid_i,
    input  logic                       cm_snoop_ready_i,
    input  cm_addr_t                   cm_snoop_addr_i,
    output logic                       cm_snoop_stall_o,
    input  logic     [NoRespPorts-1:0] cm_x_req_i,
    input  cm_addr_t [NoRespPorts-1:0] cm_x_addr_i
);

localparam int unsigned IdxWidth   = 4;
localparam int unsigned NumWays    = 2;
localparam int unsigned NumSets    = 2**IdxWidth;
localparam int unsigned TagWidth   = CmAddrWidth - IdxWidth;

typedef logic [TagWidth-1:0] tag_t;
typedef logic [IdxWidth-1:0] idx_t;

typedef struct packed {
    tag_t tag;
    idx_t idx;
} addr_t;

typedef struct packed {
    tag_t tag;
    logic valid;
} entry_t;

entry_t [NumWays-1:0][NumSets-1:0]         entries_q, entries_d;
logic   [NumWays-1:0][NumSets-1:0]         set, clear;
logic   [NumSets-1:0][$clog2(NumWays)-1:0] lowest_free;
logic   [NumSets-1:0]                      any_free;
logic                                      tag_hit;

addr_t                   snoop_addr;
addr_t [NoRespPorts-1:0] x_addr;

assign snoop_addr = cm_snoop_addr_i;

for (genvar r = 0; r < NoRespPorts; r++)
    assign x_addr[r] = cm_x_addr_i[r];

for (genvar s = 0; s < NumSets; s++) begin
    always_comb begin
        lowest_free[s] = '0;
        any_free   [s] = '0;
        for (int unsigned w = 0; w < NumWays; w++) begin
            if (!entries_q[w][s].valid) begin
                lowest_free[s] = w;
                any_free   [s] = 1'b1;
                break;
            end
        end
    end
end

always_comb begin
    entries_d = entries_q;

    for (int unsigned w = 0; w < NumWays; w++) begin
        for (int unsigned s = 0; s < NumSets; s++) begin
            if (clear[w][s]) begin
                entries_d[w][s].valid = 1'b0;
            end else if (set[w][s]) begin
                entries_d[w][s].valid = 1'b1;
                entries_d[w][s].tag   = snoop_addr.tag;
            end
        end
    end
end

assign cm_snoop_stall_o = !any_free[snoop_addr.idx] || tag_hit;

always_comb begin
    tag_hit = 1'b0;

    if (cm_snoop_valid_i) begin
        for (int unsigned w = 0; w < NumWays; w++) begin
            if (entries_q[w][snoop_addr.idx].valid &&
                entries_q[w][snoop_addr.idx].tag == snoop_addr.tag) begin
                tag_hit = 1'b1;
                break;
            end
        end
    end
end

always_comb begin
    clear = '0;

    for (int unsigned r = 0; r < NoRespPorts; r++) begin
        if (cm_x_req_i[r]) begin
            for (int unsigned w = 0; w < NumWays; w++) begin
                if (entries_q[w][x_addr[r].idx].valid &&
                    entries_q[w][x_addr[r].idx].tag == x_addr[r].tag) begin
                    clear[w][x_addr[r].idx] = 1'b1;
                end
            end
        end
    end
end

always_comb begin
    set = '0;

    if (cm_snoop_valid_i && cm_snoop_ready_i && !cm_snoop_stall_o)
        set[lowest_free[snoop_addr.idx]][snoop_addr.idx] = 1'b1;
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        entries_q <= '0;
    end else begin
        entries_q <= entries_d;
    end
end

endmodule
