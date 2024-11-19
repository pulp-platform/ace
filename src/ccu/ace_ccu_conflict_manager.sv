module ace_ccu_conflict_manager #(
    parameter int unsigned AxiAddrWidth  = 0,
    parameter int unsigned NoRespPorts   = 0,
    parameter int unsigned MaxRespTrans  = 0,
    parameter int unsigned MaxSnoopTrans = 0,
    parameter int unsigned CmIdxBase     = 0,
    parameter int unsigned CmIdxWidth    = 0,

    localparam type cm_idx_t             = logic [CmIdxWidth-1:0]
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,

    input  logic                      cm_snoop_req_i,
    input  cm_idx_t                   cm_snoop_addr_i,
    output logic                      cm_snoop_stall_o,
    input  logic    [NoRespPorts-1:0] cm_x_req_i,
    input  cm_idx_t [NoRespPorts-1:0] cm_x_addr_i
);

localparam int unsigned NumEntries = 2**CmIdxWidth;

logic  [NumEntries-1:0]  valid_q, valid_d;
logic  [NumEntries-1:0]  set, clear;

assign valid_d = ~clear & (set | valid_q);

assign cm_snoop_stall_o = valid_q[cm_snoop_addr_i];

always_comb begin
    clear = '0;

    for (int unsigned p = 0; p < NoRespPorts; p++) begin
        if (cm_x_req_i[p])
            clear[cm_x_addr_i[p]] = 1'b1;
    end
end

always_comb begin
    set = '0;
    if (cm_snoop_req_i)
        set[cm_snoop_addr_i] = 1'b1;
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        valid_q <= '0;
    end else begin
        valid_q <= valid_d;
    end
end

endmodule
