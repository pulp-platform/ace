module ccu_ctrl_memory_unit import ccu_ctrl_pkg::*;
#(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiDataWidth = 0,
    parameter int unsigned NoMstPorts = 4,
    parameter int unsigned SlvAxiIDWidth = 0,
    parameter type mst_aw_chan_t = logic,
    parameter type w_chan_t      = logic,
    parameter type mst_b_chan_t  = logic,
    parameter type mst_ar_chan_t = logic,
    parameter type mst_r_chan_t  = logic,
    parameter type mst_req_t     = logic,
    parameter type mst_resp_t    = logic,
    parameter type snoop_ac_t    = logic,
    parameter type snoop_cr_t    = logic,
    parameter type snoop_cd_t    = logic,
    parameter type snoop_req_t   = logic,
    parameter type snoop_resp_t  = logic,
    localparam int unsigned DcacheLineWords = DcacheLineWidth / AxiDataWidth,
    localparam int unsigned MstIdxBits      = $clog2(NoMstPorts)
) (
    //clock and reset
    input                               clk_i,
    input                               rst_ni,
    // CCU Request In and response out
    input  mst_req_t                    ccu_req_i,
    output mst_resp_t                   ccu_resp_o,
    //CCU Request Out and response in
    output mst_req_t                    ccu_req_o,
    input  mst_resp_t                   ccu_resp_i,

    input  snoop_cd_t   [NoMstPorts-1:0] cd_i,
    input  logic        [NoMstPorts-1:0] cd_valid_i,
    output logic        [NoMstPorts-1:0] cd_ready_o,
    output logic                         cd_busy_o,

    input  mst_req_t                     ccu_req_holder_i,
    output logic                         mu_ready_o,
    input  logic                         mu_valid_i,
    input  mu_op_e                       mu_op_i,
    input  logic        [NoMstPorts-1:0] data_available_i,
    input  logic        [MstIdxBits-1:0] first_responder_i
);

localparam FIFO_DEPTH = 2;

mst_req_t  ccu_req_out;
mst_resp_t ccu_resp_in;

mst_req_t ccu_req_holder_q;
logic [MstIdxBits-1:0] first_responder_q, fifo_first_responder_q, fifo_first_responder_d;
logic [NoMstPorts-1:0] data_available_q;

logic sample_dec_data;

logic fifo_push, fifo_flush, fifo_pop, fifo_full, fifo_empty;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        ccu_req_holder_q <= '0;
        first_responder_q <= '0;
        data_available_q <= '0;
    end else if (sample_dec_data) begin
        ccu_req_holder_q <= ccu_req_holder_i;
        first_responder_q <= first_responder_i;
        data_available_q <= data_available_i;
    end
end

logic ax_busy_q, ax_busy_d;
mu_op_e ax_op_q, ax_op_d;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        ax_busy_q <= 1'b0;
        ax_op_q <= SEND_AXI_REQ_R;
    end else begin
        ax_busy_q <= ax_busy_d;
        ax_op_q <= ax_op_d;
    end
end

mst_ar_chan_t ar_out;
mst_aw_chan_t aw_out;

logic ar_valid_out, aw_valid_out;

logic cd_data_incoming;

logic w_last_d, w_last_q;

logic [$bits(ccu_resp_in.b.id)-1:0] wb_id_q, wb_id_d;

logic wb_expected_q;

always_comb begin
    mu_ready_o = 1'b0;
    ax_busy_d = ax_busy_q;
    ax_op_d = ax_op_q;

    sample_dec_data = 1'b0;

    ar_out = '0;
    aw_out = '0;
    ar_valid_out = 1'b0;
    aw_valid_out = 1'b0;

    cd_data_incoming = 1'b0;

    wb_id_d = wb_id_q;

    case (ax_busy_q)
        1'b0: begin
            mu_ready_o = 1'b1;
            if (mu_valid_i) begin
                sample_dec_data = 1'b1;
                ax_op_d = mu_op_i;
                ax_busy_d = 1'b1;
            end
        end
        1'b1: begin
            case (ax_op_q)
                SEND_AXI_REQ_R: begin
                    ar_valid_out  = 'b1;
                    ar_out        = ccu_req_holder_q.ar;
                    if (ccu_resp_in.ar_ready) begin
                        ax_busy_d = 1'b0;
                    end
                end
                SEND_AXI_REQ_WRITE_BACK_R: begin
                    wb_id_d = {first_responder_q, ccu_req_holder_q.ar.id[SlvAxiIDWidth-1:0]};
                    cd_data_incoming = 1'b1;
                    // send writeback request
                    aw_valid_out     = fifo_empty;
                    aw_out           = '0; //default
                    aw_out.addr      = ccu_req_holder_q.ar.addr;
                    aw_out.addr[3:0] = 4'b0; // writeback is always full cache line
                    aw_out.size      = 2'b11;
                    aw_out.burst     = axi_pkg::BURST_INCR; // Use BURST_INCR for AXI regular transaction
                    aw_out.id        = {first_responder_q, ccu_req_holder_q.ar.id[SlvAxiIDWidth-1:0]}; // It should be visible this data originates from the responder, important e.g. for AMO operations
                    aw_out.len       = DcacheLineWords-1;
                    // WRITEBACK
                    aw_out.domain    = 2'b00;
                    aw_out.snoop     = 3'b011;
                    if (ccu_resp_in.aw_ready && fifo_empty) begin
                        if (ccu_req_holder_q.ar.lock)
                            // Blocking behavior for AMO operations
                            // TODO: check if truly needed
                            ax_op_d = AMO_WAIT_WB_R;
                        else
                            ax_busy_d = 1'b0;
                    end
                end
                SEND_AXI_REQ_W: begin
                    // This is a hotfix to avoid serving requests from the core
                    // with the same ID of the writeback
                    // TODO: add a bit to the ID to differentiate between WB issued
                    // by the CCU and requests forwarded from the cores
                    if (wb_id_q != ccu_req_holder_q.aw.id || !wb_expected_q) begin
                        aw_valid_out  = 'b1;
                        aw_out        = ccu_req_holder_q.aw;
                        if (ccu_resp_in.aw_ready) begin
                            if (ccu_req_holder_q.aw.atop[5])
                                // Blocking behavior for AMO operations
                                // TODO: check if truly needed
                                ax_op_d = AMO_WAIT_READ;
                            else
                                ax_busy_d = 1'b0;
                        end
                    end
                end
                SEND_AXI_REQ_WRITE_BACK_W: begin
                    wb_id_d = {first_responder_q, ccu_req_holder_q.aw.id[SlvAxiIDWidth-1:0]};
                    cd_data_incoming = 1'b1;
                    // send writeback request
                    aw_valid_out     = fifo_empty;
                    aw_out           = '0; //default
                    aw_out.addr      = ccu_req_holder_q.aw.addr;
                    aw_out.addr[3:0] = 4'b0; // writeback is always full cache line
                    aw_out.size      = 2'b11;
                    aw_out.burst     = axi_pkg::BURST_INCR; // Use BURST_INCR for AXI regular transaction
                    aw_out.id        = {first_responder_q, ccu_req_holder_q.aw.id[SlvAxiIDWidth-1:0]}; // It should be visible this data originates from the responder, important e.g. for AMO operations
                    aw_out.len       = DcacheLineWords-1;
                    // WRITEBACK
                    aw_out.domain    = 2'b00;
                    aw_out.snoop     = 3'b011;
                    if (ccu_resp_in.aw_ready && fifo_empty) begin
                        if (ccu_req_holder_q.aw.atop[5])
                            ax_op_d = AMO_WAIT_WB_W;
                        else
                            ax_op_d = SEND_AXI_REQ_W;
                    end
                end
                AMO_WAIT_READ: begin
                    if(ccu_resp_in.r_valid && ccu_req_i.r_ready && ccu_resp_in.r.last
                    && ccu_resp_in.r.id == ccu_req_holder_q.aw.id)
                        ax_busy_d = 1'b0;
                end
                AMO_WAIT_WB_R: begin
                    if(ccu_resp_in.b_valid && ccu_req_out.b_ready
                    && ccu_resp_in.b.id == {first_responder_q, ccu_req_holder_q.ar.id[SlvAxiIDWidth-1:0]})
                        ax_op_d = SEND_AXI_REQ_R;
                end
                AMO_WAIT_WB_W: begin
                    if(ccu_resp_in.b_valid && ccu_req_out.b_ready &&
                    ccu_resp_in.b.id == {first_responder_q, ccu_req_holder_q.aw.id[SlvAxiIDWidth-1:0]})
                        ax_op_d = SEND_AXI_REQ_W;
                end
            endcase
        end
    endcase
end

typedef enum logic [1:0] {W_IDLE, W_PASSTHROUGH, W_FROM_FIFO_W, W_FROM_FIFO_R} w_state_t;

w_state_t w_state_q, w_state_d;

logic [AxiDataWidth-1:0] fifo_data_in, fifo_data_out;
logic [$clog2(DcacheLineWords)-1:0] fifo_usage;

enum { FIFO_IDLE, FIFO_LOWER_HALF, FIFO_UPPER_HALF, FIFO_WAIT_LAST_CD } fifo_state_q, fifo_state_d;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        fifo_state_q <= FIFO_IDLE;
        fifo_first_responder_q <= '0;
    end else begin
        fifo_state_q <= fifo_state_d;
        fifo_first_responder_q <= fifo_first_responder_d;
    end
end

logic [NoMstPorts-1:0] cd_last_q;

always_comb begin
    fifo_state_d = fifo_state_q;
    fifo_first_responder_d = fifo_first_responder_q;

    fifo_push = 1'b0;

    case (fifo_state_q)
        FIFO_IDLE: begin
            if (cd_data_incoming) begin
                fifo_state_d = FIFO_LOWER_HALF;
                fifo_first_responder_d = first_responder_q;
            end
        end
        FIFO_LOWER_HALF: begin
            if(cd_valid_i[fifo_first_responder_q] && cd_ready_o[fifo_first_responder_q]) begin
                fifo_push = 1'b1;
                fifo_state_d = FIFO_UPPER_HALF;
            end
        end
        FIFO_UPPER_HALF: begin
            if(cd_valid_i[fifo_first_responder_q] && cd_ready_o[fifo_first_responder_q]) begin
                fifo_push = 1'b1;
                fifo_state_d = cd_last_q == data_available_q ? FIFO_IDLE : FIFO_WAIT_LAST_CD;
            end
        end
        FIFO_WAIT_LAST_CD: begin
            if (cd_last_q == data_available_q)
                fifo_state_d = FIFO_IDLE;
        end
    endcase

end

assign cd_busy_o    = cd_last_q != data_available_q;
assign fifo_flush   = 1'b0;
assign fifo_data_in = cd_i[fifo_first_responder_q].data;
assign fifo_pop     = w_state_q inside {W_FROM_FIFO_W, W_FROM_FIFO_R} ? ccu_resp_in.w_ready && ccu_req_out.w_valid : '0;


  fifo_v3 #(
    .FALL_THROUGH(0),
    .DATA_WIDTH(AxiDataWidth),
    .DEPTH(FIFO_DEPTH)
  ) cd_memory_fifo_i (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (fifo_flush),
    .testmode_i (1'b0),
    .full_o     (fifo_full),
    .empty_o    (fifo_empty),
    .usage_o    (fifo_usage),
    .data_i     (fifo_data_in),
    .push_i     (fifo_push),
    .data_o     (fifo_data_out),
    .pop_i      (fifo_pop)
);

for (genvar i = 0; i < NoMstPorts; i = i + 1) begin
    always_ff @ (posedge clk_i, negedge rst_ni) begin
        if(!rst_ni) begin
            cd_last_q[i] <= '0;
        end else if(fifo_state_q == FIFO_IDLE) begin
            cd_last_q[i] <= '0;
        end else if(cd_valid_i[i]) begin
            cd_last_q[i] <= (cd_i[i].last & data_available_q[i]);
        end
    end
end

always_comb begin
    cd_ready_o = '0;

    if (fifo_state_q != FIFO_IDLE) begin
        for (int i = 0; i < NoMstPorts; i = i + 1) begin
            cd_ready_o[i] = !cd_last_q[i] && data_available_q[i];
        end

        if (fifo_full) begin
            cd_ready_o[fifo_first_responder_q] = 1'b0;
        end
    end

end

// AR
assign ccu_req_out.ar = ar_out;
assign ccu_req_out.ar_valid = ar_valid_out;

// AW
assign ccu_req_out.aw = aw_out;
assign ccu_req_out.aw_valid = aw_valid_out;

// R passthrough
assign ccu_resp_o.r = ccu_resp_in.r;
assign ccu_resp_o.r_valid = ccu_resp_in.r_valid;
assign ccu_req_out.r_ready = ccu_req_i.r_ready;

// W and B

always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        w_state_q <= W_IDLE;
        w_last_q <= 1'b0;
    end else begin
        w_state_q <= w_state_d;
        w_last_q <= w_last_d;
    end
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        wb_expected_q <= 1'b0;
        wb_id_q <= '0;
    end else if(ccu_resp_in.b_valid &&
                ccu_req_out.b_ready &&
                ccu_resp_in.b.id == wb_id_q) begin
        wb_expected_q <= 1'b0;
        wb_id_q <= '0;
    end else if(cd_data_incoming) begin
        wb_expected_q <= 1'b1;
        wb_id_q <= wb_id_d;
    end
end



always_comb begin
    w_last_d = w_last_q;
    w_state_d = w_state_q;

    ccu_req_out.w  = ccu_req_i.w;
    ccu_req_out.w_valid = 1'b0;
    ccu_resp_o.w_ready  =  1'b0;

    case (w_state_q)
        W_IDLE: begin
            w_last_d = 1'b0;
            if (ax_busy_q && ccu_req_out.aw_valid) begin
                case (ax_op_q)
                    SEND_AXI_REQ_WRITE_BACK_W: begin
                        w_state_d = W_FROM_FIFO_W;
                    end
                    SEND_AXI_REQ_WRITE_BACK_R:
                        w_state_d = W_FROM_FIFO_R;
                    SEND_AXI_REQ_W: begin
                        w_state_d = W_PASSTHROUGH;
                    end
                    default:
                        w_state_d = W_IDLE;
                endcase
            end
        end
        W_PASSTHROUGH: begin
            ccu_req_out.w_valid   =  ccu_req_i.w_valid;
            ccu_resp_o.w_ready  =  ccu_resp_in.w_ready;

            if(ccu_resp_in.w_ready && ccu_req_i.w_valid && ccu_req_i.w.last)
                w_state_d = W_IDLE;
        end
        W_FROM_FIFO_R, W_FROM_FIFO_W: begin
            // Connect the FIFO as long as the transmission is ongoing
            w_last_d = ccu_resp_in.w_ready && !fifo_empty;
            ccu_req_out.w_valid =  !fifo_empty;
            ccu_req_out.w.strb  =  '1;
            ccu_req_out.w.data  =  fifo_data_out;
            ccu_req_out.w.last  =  w_last_q;

            if(ccu_resp_in.w_ready && !fifo_empty && w_last_q)
                if (w_state_q == W_FROM_FIFO_W) begin
                    // This checks is just to ensure that the cores have visibility
                    // on the W channel only when we actually want to write something
                    // Removing it would cause a premature forwarding of a W req
                    // TODO: make this less convoluted
                    w_state_d = ax_busy_q && ax_op_q == AMO_WAIT_WB_W ? W_IDLE : W_PASSTHROUGH;
                end else begin
                    w_state_d = W_IDLE;
                end
        end
    endcase
end

assign ccu_resp_o.b =  ccu_resp_in.b;

always_comb begin
    ccu_req_out.b_ready = 1'b0;
    ccu_resp_o.b_valid  =  1'b0;

    if (wb_expected_q && ccu_resp_in.b.id == wb_id_q) begin
        ccu_req_out.b_ready = 'b1;
    end else begin
        ccu_req_out.b_ready =  ccu_req_i.b_ready;
        ccu_resp_o.b_valid  =  ccu_resp_in.b_valid;
    end
end


axi_fifo #(
    .Depth     (4),
    .aw_chan_t (mst_aw_chan_t),
    .w_chan_t  (w_chan_t),
    .b_chan_t  (mst_b_chan_t),
    .ar_chan_t (mst_ar_chan_t),
    .r_chan_t  (mst_r_chan_t),
    .axi_req_t (mst_req_t),
    .axi_resp_t(mst_resp_t)
) fifo_to_from_mem_i (
    .clk_i,
    .rst_ni,
    .test_i (1'b0),
    // slave port
    .slv_req_i (ccu_req_out),
    .slv_resp_o (ccu_resp_in),
    // master port
    .mst_req_o (ccu_req_o),
    .mst_resp_i (ccu_resp_i)
);


endmodule