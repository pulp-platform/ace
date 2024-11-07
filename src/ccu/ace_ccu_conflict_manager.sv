module ace_ccu_conflict_manager #(
    parameter int unsigned AxiAddrWidth  = 0,
    parameter int unsigned NoRespPorts   = 0,
    parameter int unsigned MaxRespTrans  = 0,
    parameter int unsigned MaxSnoopTrans = 0,
    parameter int unsigned LupAddrBase   = 0,
    parameter int unsigned LupAddrWidth  = 0,

    localparam type addr_t               = logic [AxiAddrWidth-1:0],
    localparam type lup_addr_t           = logic [LupAddrWidth-1:0]
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,

    input  logic  [NoRespPorts-1:0] x_valid_i,
    output logic  [NoRespPorts-1:0] x_ready_o,
    input  addr_t [NoRespPorts-1:0] x_addr_i,
    input  logic  [NoRespPorts-1:0] x_lasts_i,
    output logic  [NoRespPorts-1:0] x_valid_o,
    input  logic  [NoRespPorts-1:0] x_ready_i,

    input  logic  [NoRespPorts-1:0] x_ack_i,

    input  logic                    snoop_valid_i,
    output logic                    snoop_ready_o,
    input  logic                    snoop_clr_i,
    input  addr_t                   snoop_addr_i,
    output logic                    snoop_valid_o,
    input  logic                    snoop_ready_i
);

    logic [NoRespPorts-1:0] x_match, snoop_match;
    logic [NoRespPorts-1:0] addr_equal, addr_conflict;
    logic [NoRespPorts-1:0] snoop_valid, snoop_ready;
    logic [NoRespPorts-1:0] snoop_arb_valid, snoop_arb_ready;

    logic [NoRespPorts-1:0] sel_q, sel_d, sel;
    logic                   lock_q, lock_d;

    lup_addr_t                   snoop_addr;
    lup_addr_t [NoRespPorts-1:0] x_addr;


    for (genvar i = 0; i < NoRespPorts; i++) begin : gen_resp_path
        logic x_valid, x_ready;
        logic arb_valid, arb_ready;
        logic arb_sel;
        logic conflict_no_sel;

        logic fifo_push, fifo_full;

        logic x_valid_out, x_ready_in;

        assign x_addr[i] = x_addr_i[i][LupAddrBase+:LupAddrWidth];

        assign addr_equal[i]    = snoop_addr == x_addr[i];
        assign addr_conflict[i] = addr_equal[i] && x_valid_i[i];
        assign conflict_no_sel  = addr_conflict[i] && !sel_q[i] && lock_q;

        assign x_valid      = fifo_full || conflict_no_sel ? 1'b0 : x_valid_i[i];
        assign x_ready_o[i] = fifo_full || conflict_no_sel ? 1'b0 : x_ready;

        rr_arb_tree #(
            .NumIn      (2),
            .DataType   (logic),
            .ExtPrio    (1'b0),
            .AxiVldRdy  (1'b1),
            .LockIn     (1'b1)
        ) i_arb (
            .clk_i,
            .rst_ni,
            .flush_i ('0),
            .rr_i    ('0),
            .req_i   ({x_valid, snoop_valid[i]}),
            .gnt_o   ({x_ready, snoop_ready[i]}),
            .data_i  ('0),
            .req_o   (arb_valid),
            .gnt_i   (arb_ready),
            .data_o  (),
            .idx_o   (arb_sel)
        );

        stream_demux #(
            .N_OUP (2)
        ) i_arb_demux (
            .inp_valid_i (arb_valid),
            .inp_ready_o (arb_ready),
            .oup_sel_i   (arb_sel),
            .oup_valid_o ({x_valid_out, snoop_arb_valid[i]}),
            .oup_ready_i ({x_ready_in , snoop_arb_ready[i]})
        );

        assign x_valid_o[i] = x_match[i] ? 1'b0 : x_valid_out;
        assign x_ready_in   = x_match[i] ? 1'b0 : x_ready_i[i];

        assign fifo_push = x_valid_o[i] && x_ready_i[i] && x_lasts_i[i];

        lookup_fifo #(
            .DEPTH        (MaxRespTrans),
            .LOOKUP_PORTS (1),
            .dtype        (lup_addr_t)
        ) i_addr_fifo (
            .clk_i,
            .rst_ni,
            .push_i         (fifo_push),
            .full_o         (fifo_full),
            .data_i         (x_addr[i]),
            .pop_i          (x_ack_i[i]),
            .empty_o        (),
            .data_o         (),
            .lookup_data_i  (snoop_addr),
            .lookup_match_o (snoop_match[i])
        );
    end


    generate
    begin : gen_snoop_path
        logic snoop_fork_valid, snoop_fork_ready;
        logic snoop_valid_in, snoop_ready_out;
        logic snoop_valid_out, snoop_ready_in;
        logic fifo_full, fifo_push;

        assign snoop_addr = snoop_addr_i[LupAddrBase+:LupAddrWidth];

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                sel_q  <= '0;
                lock_q <= '0;
            end else begin
                sel_q  <= sel_d;
                lock_q <= lock_d;
            end
        end

        assign snoop_valid_in = fifo_full ? 1'b0 : snoop_valid_i;
        assign snoop_ready_o  = fifo_full ? 1'b0 : snoop_ready_out;

        assign sel = lock_q ? sel_q : addr_conflict;

        always_comb begin
            snoop_fork_valid = 1'b0;

            lock_d = lock_q;
            sel_d  = sel_q;

            case (lock_q)
                1'b0: begin
                    if (!fifo_full && snoop_valid_i && |addr_conflict) begin
                        snoop_fork_valid = 1'b1;
                        sel_d            = addr_conflict;
                        if (!snoop_fork_ready)
                            lock_d = 1'b1;
                    end
                end
                1'b1: begin
                    snoop_fork_valid = 1'b1;
                    if (snoop_fork_ready) begin
                        lock_d = 1'b0;
                    end
                end
            endcase
        end

        stream_fork_dynamic #(
            .N_OUP (NoRespPorts)
        ) i_snoop_fork (
            .clk_i,
            .rst_ni,
            .valid_i     (snoop_fork_valid),
            .ready_o     (snoop_fork_ready),
            .sel_i       (sel),
            .sel_valid_i (snoop_fork_valid),
            .sel_ready_o (),
            .valid_o     (snoop_valid),
            .ready_i     (snoop_ready)
        );

        stream_join_dynamic #(
            .N_INP (NoRespPorts+1)
        ) i_snoop_join (
            .inp_valid_i ({snoop_arb_valid, snoop_valid_in}),
            .inp_ready_o ({snoop_arb_ready, snoop_ready_out}),
            .sel_i       ({sel, 1'b1}),
            .oup_valid_o (snoop_valid_out),
            .oup_ready_i (snoop_ready_in)
        );

        assign snoop_valid_o  = |snoop_match ? 1'b0 : snoop_valid_out;
        assign snoop_ready_in = |snoop_match ? 1'b0 : snoop_ready_i;

        assign fifo_push = snoop_valid_o && snoop_ready_i;

        lookup_fifo #(
            .DEPTH        (MaxSnoopTrans),
            .LOOKUP_PORTS (NoRespPorts),
            .dtype        (lup_addr_t)
        ) i_addr_fifo (
            .clk_i,
            .rst_ni,
            .push_i         (fifo_push),
            .full_o         (fifo_full),
            .data_i         (snoop_addr),
            .pop_i          (snoop_clr_i),
            .empty_o        (),
            .data_o         (),
            .lookup_data_i  (x_addr),
            .lookup_match_o (x_match)
        );
    end
    endgenerate;
endmodule
