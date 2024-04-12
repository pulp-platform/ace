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

mst_req_t ccu_req_holder_q;
logic [MstIdxBits-1:0] first_responder_q, fifo_first_responder_q, fifo_first_responder_d;
logic [NoMstPorts-1:0] data_available_q;

logic sample_dec_data;

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

enum {Ax_IDLE, Ax_BUSY} ax_state_q, ax_state_d;
mu_op_e ax_op_q, ax_op_d;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        ax_state_q <= Ax_IDLE;
        ax_op_q <= SEND_AXI_REQ_R;
    end else begin
        ax_state_q <= ax_state_d;
        ax_op_q <= ax_op_d;
    end
end

mst_ar_chan_t ar_out;
mst_aw_chan_t aw_out;

logic ar_valid_out, aw_valid_out;

logic cd_data_incoming;

localparam Legacy = 1;

always_comb begin
    mu_ready_o = 1'b0;
    ax_state_d = ax_state_q;
    ax_op_d = ax_op_q;

    sample_dec_data = 1'b0;

    ar_out = '0;
    aw_out = '0;
    ar_valid_out = 1'b0;
    aw_valid_out = 1'b0;

    cd_data_incoming = 1'b0;

    case (ax_state_q)
        Ax_IDLE: begin
            mu_ready_o = 1'b1;
            if (mu_valid_i) begin
                sample_dec_data = 1'b1;
                ax_op_d = mu_op_i;
                ax_state_d = Ax_BUSY;
            end
        end
        Ax_BUSY: begin
            case (ax_op_q)
                SEND_AXI_REQ_R: begin
                    // If a lock is present, wait for W to complete
                    if (!ccu_req_holder_q.ar.lock || ccu_resp_i.w_ready) begin
                        ar_valid_out  = 'b1;
                        ar_out        = ccu_req_holder_q.ar;
                        if (ccu_resp_i.ar_ready) begin
                            if (Legacy)
                                ax_op_d = LEGACY_WAIT_READ;
                            else
                                ax_state_d = Ax_IDLE;
                        end
                    end
                end
                SEND_AXI_REQ_WRITE_BACK_R: begin
                    cd_data_incoming = 1'b1;
                    // send writeback request
                    aw_valid_out     = 'b1;
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
                    if (ccu_resp_i.aw_ready) begin
                        if (ccu_req_holder_q.ar.lock)
                            ax_op_d = SEND_AXI_REQ_R;
                        else if (Legacy)
                            ax_op_d = LEGACY_WAIT_WB;
                        else
                            ax_state_d = Ax_IDLE;
                    end
                end
                SEND_AXI_REQ_W: begin
                    aw_valid_out  = 'b1;
                    aw_out        = ccu_req_holder_q.aw;
                    if (ccu_resp_i.aw_ready) begin
                        if (Legacy)
                            ax_op_d = LEGACY_WAIT_WRITE;
                        else
                            ax_state_d = Ax_IDLE;
                    end
                end
                SEND_AXI_REQ_WRITE_BACK_W: begin
                    cd_data_incoming = 1'b1;
                    // send writeback request
                    aw_valid_out     = 'b1;
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
                    if (ccu_resp_i.aw_ready) begin
                        if (Legacy)
                            ax_op_d = LEGACY_WAIT_WB;
                        else
                            ax_state_d = Ax_IDLE;
                    end
                end
                LEGACY_WAIT_WRITE: begin
                    if(ccu_resp_i.b_valid && ccu_req_i.b_ready)
                        ax_state_d = Ax_IDLE;
                end
                LEGACY_WAIT_READ: begin
                    if(ccu_resp_i.r_valid && ccu_req_i.r_ready && ccu_resp_i.r.last)
                        ax_state_d = Ax_IDLE;
                end
                LEGACY_WAIT_WB: begin
                    if(ccu_resp_i.b_valid && ccu_req_o.b_ready)
                        ax_state_d = Ax_IDLE;
                end
            endcase
        end
    endcase
end

logic [AxiDataWidth-1:0] fifo_data_in, fifo_data_out;
logic [$clog2(DcacheLineWords)-1:0] fifo_usage;

enum { FIFO_IDLE, FIFO_LOWER_HALF, FIFO_UPPER_HALF, FIFO_WAIT } fifo_state_q, fifo_state_d;

logic w_busy_d, w_busy_q;
logic w_last_d, w_last_q;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        fifo_state_q <= FIFO_IDLE;
        w_busy_q <= 1'b0;
        fifo_first_responder_q <= '0;
        w_last_q <= 1'b0;
    end else begin
        fifo_state_q <= fifo_state_d;
        w_busy_q <= w_busy_d;
        fifo_first_responder_q <= fifo_first_responder_d;
        w_last_q <= w_last_d;
    end
end

logic fifo_push, fifo_flush, fifo_pop, fifo_full, fifo_empty;

always_comb begin
    fifo_state_d = fifo_state_q;
    fifo_first_responder_d = fifo_first_responder_q;

    case (fifo_state_q)
        FIFO_IDLE: begin
            if (cd_data_incoming) begin
                fifo_state_d = FIFO_LOWER_HALF;
                fifo_first_responder_d = first_responder_q;
            end
        end
        FIFO_LOWER_HALF: begin
            if(cd_valid_i[fifo_first_responder_q] && cd_ready_o[fifo_first_responder_q]) begin
                fifo_state_d = FIFO_UPPER_HALF;
            end
        end
        FIFO_UPPER_HALF: begin
            if(cd_valid_i[fifo_first_responder_q] && cd_ready_o[fifo_first_responder_q]) begin
                fifo_state_d = FIFO_WAIT;
            end
        end
        FIFO_WAIT: begin
            if (ccu_resp_i.b_valid && ccu_req_o.b_ready)
                fifo_state_d = FIFO_IDLE;
        end
    endcase

end

assign cd_busy_o    = fifo_state_q != FIFO_IDLE;
assign fifo_push    = cd_busy_o && cd_valid_i[fifo_first_responder_q] && cd_ready_o[fifo_first_responder_q];
assign fifo_flush   = !cd_busy_o;
assign fifo_data_in = cd_i[fifo_first_responder_q].data;
assign fifo_pop     = w_busy_q ? '0 : ccu_resp_i.w_ready && ccu_req_o.w_valid;


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

logic [NoMstPorts-1:0] cd_last_q;

for (genvar i = 0; i < NoMstPorts; i = i + 1) begin
    always_ff @ (posedge clk_i, negedge rst_ni) begin
        if(!rst_ni) begin
            cd_last_q[i] <= '0;
        end else if(!cd_busy_o) begin
            cd_last_q[i] <= '0;
        end else if(cd_valid_i[i]) begin
            cd_last_q[i] <= (cd_i[i].last & data_available_q[i]);
        end
    end
end

always_comb begin
    cd_ready_o = '0;

    if (cd_busy_o) begin
        for (int i = 0; i < NoMstPorts; i = i + 1) begin
            cd_ready_o[i] = !cd_last_q[i] && data_available_q[i];
        end

        if (fifo_full) begin
            cd_ready_o[fifo_first_responder_q] = 1'b0;
        end
    end

end

// AR
assign ccu_req_o.ar = ar_out;
assign ccu_req_o.ar_valid = ar_valid_out;

// AW
assign ccu_req_o.aw = aw_out;
assign ccu_req_o.aw_valid = aw_valid_out;

// R passthrough
assign ccu_resp_o.r = ccu_resp_i.r;
assign ccu_resp_o.r_valid = ccu_resp_i.r_valid;
assign ccu_req_o.r_ready = ccu_req_i.r_ready;

always_comb begin

    w_busy_d = 1'b0;
    w_last_d = 1'b0;

    // W and B
    // Connect the FIFO as long as the transmission is ongoing
    if (cd_busy_o && !w_busy_q) begin
        w_last_d = ccu_resp_i.w_ready && !fifo_empty;
        ccu_req_o.w_valid =  !fifo_empty;
        ccu_req_o.w.strb  =  '1;
        ccu_req_o.w.data  =  fifo_data_out;
        ccu_req_o.w.last  =  w_last_q;
        ccu_req_o.b_ready = 'b1;
    end else begin
        w_busy_d            =  (ccu_req_i.w_valid && !ccu_resp_i.w_ready) || (w_busy_q && !(ccu_resp_i.b_valid && ccu_req_i.b_ready));
        ccu_req_o.w         =  ccu_req_i.w;
        ccu_req_o.w_valid   =  ccu_req_i.w_valid;
        ccu_req_o.b_ready   =  ccu_req_i.b_ready;

        ccu_resp_o.b        =  ccu_resp_i.b;
        ccu_resp_o.b_valid  =  ccu_resp_i.b_valid;
        ccu_resp_o.w_ready  =  ccu_resp_i.w_ready;
    end
end

endmodule