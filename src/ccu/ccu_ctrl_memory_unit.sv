module ccu_ctrl_memory_unit import ccu_ctrl_pkg::*;
#(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiDataWidth = 0,
    parameter int unsigned NoMstPorts = 4,
    parameter int unsigned SlvAxiIDWidth = 0,
    parameter bit          PerfCounters  = 0,
    parameter type mst_aw_chan_t = logic,
    parameter type w_chan_t      = logic,
    parameter type mst_b_chan_t  = logic,
    parameter type mst_ar_chan_t = logic,
    parameter type mst_r_chan_t  = logic,
    parameter type mst_req_t     = logic,
    parameter type mst_resp_t    = logic,
    parameter type slv_aw_chan_t = logic,
    parameter type slv_b_chan_t  = logic,
    parameter type slv_ar_chan_t = logic,
    parameter type slv_r_chan_t  = logic,
    parameter type slv_req_t     = logic,
    parameter type slv_resp_t    = logic,
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
    input  slv_req_t                    ccu_req_i,
    output slv_resp_t                   ccu_resp_o,
    //CCU Request Out and response in
    output mst_req_t                    ccu_req_o,
    input  mst_resp_t                   ccu_resp_i,

    input  snoop_cd_t                   cd_i,
    input  logic                        cd_handshake_i,
    output logic                        cd_fifo_full_o,


    input  slv_req_t                     ccu_req_holder_i,
    output logic                         mu_gnt_o,
    input  logic                         mu_req_i,
    input  mu_op_e                       mu_op_i,
    input  logic        [MstIdxBits-1:0] first_responder_i,

    output logic                   [7:0] perf_evt_o
);

localparam CD_FIFO_DEPTH  = 4;
localparam AXI_FIFO_DEPTH = 0; // Passthrough
localparam W_FIFO_DEPTH   = 2;

mst_req_t  ccu_req_out;
mst_resp_t ccu_resp_in;

slv_req_t ccu_req_holder_q, ccu_req_holder_d;
logic [MstIdxBits-1:0] first_responder_q, first_responder_d;

logic cd_fifo_pop, cd_fifo_empty;
logic [AxiDataWidth-1:0] cd_fifo_data_out;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        ccu_req_holder_q <= '0;
        first_responder_q <= '0;
    end else if (mu_gnt_o && mu_req_i) begin
        ccu_req_holder_q <= ccu_req_holder_d;
        first_responder_q <= first_responder_d;
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

logic w_last_d, w_last_q;

typedef enum logic {W_PASSTHROUGH, W_FROM_FIFO} w_state_t;

logic w_fifo_full, w_fifo_empty;
logic w_fifo_push, w_fifo_pop;
w_state_t w_fifo_data_in, w_fifo_data_out;

assign first_responder_d = !ax_busy_q ? first_responder_i : first_responder_q;
assign ccu_req_holder_d  = !ax_busy_q ? ccu_req_holder_i  : ccu_req_holder_q;
assign mu_gnt_o          = !ax_busy_q ? mu_req_i          : 1'b0;

always_comb begin
    ax_busy_d = ax_busy_q;
    ax_op_d   = ax_busy_q ? ax_op_q : mu_op_i;

    ar_out = '0;
    aw_out = '0;
    ar_valid_out = 1'b0;
    aw_valid_out = 1'b0;

    w_fifo_push    = 1'b0;
    w_fifo_data_in = W_PASSTHROUGH;

    if (mu_req_i || ax_busy_q) begin
        ax_busy_d = 1'b1;
        case (ax_op_d)
            SEND_AXI_REQ_R: begin
                ar_valid_out  = 'b1;
                ar_out        = ccu_req_holder_d.ar;
                if (ccu_resp_in.ar_ready) begin
                    ax_busy_d = 1'b0;
                end
            end
            SEND_AXI_REQ_WRITE_BACK_R: begin
                // send writeback request
                aw_valid_out     = !w_fifo_full;
                aw_out           = '0; //default
                aw_out.addr      = ccu_req_holder_d.ar.addr;
                aw_out.addr[3:0] = 4'b0; // writeback is always full cache line
                aw_out.size      = 2'b11;
                aw_out.burst     = axi_pkg::BURST_INCR; // Use BURST_INCR for AXI regular transaction
                aw_out.id        = {1'b1, first_responder_d, ccu_req_holder_d.ar.id[SlvAxiIDWidth-1:0]}; // It should be visible this data originates from the responder, important e.g. for AMO operations
                aw_out.len       = DcacheLineWords-1;
                // WRITEBACK
                aw_out.domain    = 2'b00;
                aw_out.snoop     = 3'b011;

                w_fifo_data_in   = W_FROM_FIFO;

                if (ccu_resp_in.aw_ready && !w_fifo_full) begin
                    w_fifo_push = 1'b1;
                    if (ccu_req_holder_d.ar.lock) begin
                        // Blocking behavior for AMO operations
                        // TODO: check if truly needed
                        ax_op_d = AMO_WAIT_WB_R;
                    end else begin
                        ax_busy_d = 1'b0;
                    end
                end
            end
            SEND_AXI_REQ_W: begin
                aw_valid_out  = !w_fifo_full;
                aw_out        = ccu_req_holder_d.aw;

                w_fifo_data_in = W_PASSTHROUGH;

                if (ccu_resp_in.aw_ready && !w_fifo_full) begin
                    w_fifo_push = 1'b1;
                    ax_busy_d = 1'b0;
                end
            end
            SEND_AXI_REQ_WRITE_BACK_W: begin
                // send writeback request
                aw_valid_out     = !w_fifo_full;
                aw_out           = '0; //default
                aw_out.addr      = ccu_req_holder_d.aw.addr;
                aw_out.addr[3:0] = 4'b0; // writeback is always full cache line
                aw_out.size      = 2'b11;
                aw_out.burst     = axi_pkg::BURST_INCR; // Use BURST_INCR for AXI regular transaction
                aw_out.id        = {1'b1, first_responder_d, ccu_req_holder_d.aw.id[SlvAxiIDWidth-1:0]}; // It should be visible this data originates from the responder, important e.g. for AMO operations
                aw_out.len       = DcacheLineWords-1;
                // WRITEBACK
                aw_out.domain    = 2'b00;
                aw_out.snoop     = 3'b011;

                w_fifo_data_in   = W_FROM_FIFO;

                if (ccu_resp_in.aw_ready && !w_fifo_full) begin
                    w_fifo_push = 1'b1;
                    ax_busy_d   = 1'b1;
                    if (ccu_req_holder_d.aw.atop[5])
                        ax_op_d = AMO_WAIT_WB_W;
                    else
                        ax_op_d = SEND_AXI_REQ_W;
                end
            end
            AMO_WAIT_WB_R: begin
                if(ccu_resp_in.b_valid && ccu_req_out.b_ready
                && ccu_resp_in.b.id == {1'b1, first_responder_q, ccu_req_holder_q.ar.id[SlvAxiIDWidth-1:0]})
                    ax_op_d = SEND_AXI_REQ_R;
            end
            AMO_WAIT_WB_W: begin
                if(ccu_resp_in.b_valid && ccu_req_out.b_ready &&
                ccu_resp_in.b.id == {1'b1, first_responder_q, ccu_req_holder_q.aw.id[SlvAxiIDWidth-1:0]})
                    ax_op_d = SEND_AXI_REQ_W;
            end
        endcase
    end
end


assign cd_fifo_pop = w_fifo_data_out == W_FROM_FIFO &&
                     ccu_resp_in.w_ready && ccu_req_out.w_valid;

fifo_v3 #(
    .FALL_THROUGH(1),
    .DATA_WIDTH(AxiDataWidth),
    .DEPTH(CD_FIFO_DEPTH)
  ) cd_memory_fifo_i (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (cd_fifo_full_o),
    .empty_o    (cd_fifo_empty),
    .usage_o    (),
    .data_i     (cd_i.data),
    .push_i     (cd_handshake_i),
    .data_o     (cd_fifo_data_out),
    .pop_i      (cd_fifo_pop)
);

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
        w_last_q <= 1'b0;
    end else begin
        w_last_q <= w_last_d;
    end
end

fifo_v3 #(
    .FALL_THROUGH(1),
    .DEPTH(W_FIFO_DEPTH),
    .dtype(w_state_t)
  ) w_fifo_i (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (w_fifo_full),
    .empty_o    (w_fifo_empty),
    .usage_o    (),
    .data_i     (w_fifo_data_in),
    .push_i     (w_fifo_push),
    .data_o     (w_fifo_data_out),
    .pop_i      (w_fifo_pop)
);



always_comb begin
    ccu_req_out.w  = ccu_req_i.w;
    ccu_req_out.w_valid = 1'b0;
    ccu_resp_o.w_ready  =  1'b0;

    w_fifo_pop = 1'b0;

    w_last_d = w_last_q;

    if (!w_fifo_empty) begin
        case (w_fifo_data_out)
            W_PASSTHROUGH: begin
                ccu_req_out.w_valid =  ccu_req_i.w_valid;
                ccu_resp_o.w_ready  =  ccu_resp_in.w_ready;

                if(ccu_resp_in.w_ready && ccu_req_i.w_valid && ccu_req_i.w.last)
                    w_fifo_pop = 1'b1;
            end
            W_FROM_FIFO: begin
                // Connect the FIFO as long as the transmission is ongoing
                w_last_d            = (ccu_resp_in.w_ready && !cd_fifo_empty) || w_last_q;
                ccu_req_out.w_valid =  !cd_fifo_empty;
                ccu_req_out.w.strb  =  '1;
                ccu_req_out.w.data  =  cd_fifo_data_out;
                ccu_req_out.w.last  =  w_last_q;

                if(ccu_resp_in.w_ready && !cd_fifo_empty && w_last_q) begin
                    w_last_d = 1'b0;
                    w_fifo_pop = 1'b1;
                end
            end
        endcase
    end
end

assign ccu_resp_o.b = ccu_resp_in.b;

// An additional bit in the ID is used to verify whether the CCU
// issued the request or simply forwarded one from the core
logic is_wb_resp;
assign is_wb_resp = (ccu_resp_in.b.id[SlvAxiIDWidth+$clog2(NoMstPorts)] == 1'b1);

always_comb begin
    ccu_req_out.b_ready = 1'b0;
    ccu_resp_o.b_valid  =  1'b0;

    if (is_wb_resp) begin
        // Response to a WB issued by the CCU
        ccu_req_out.b_ready = 'b1;
    end else begin
        // Response to a core request
        ccu_req_out.b_ready =  ccu_req_i.b_ready;
        ccu_resp_o.b_valid  =  ccu_resp_in.b_valid;
    end
end


axi_fifo #(
    .Depth     (AXI_FIFO_DEPTH),
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
    .slv_req_i  (ccu_req_out),
    .slv_resp_o (ccu_resp_in),
    // master port
    .mst_req_o  (ccu_req_o),
    .mst_resp_i (ccu_resp_i)
);

if (PerfCounters) begin : gen_perf_events

    logic perf_send_axi_req_r;
    logic perf_send_axi_req_write_back_r;
    logic perf_send_axi_req_w;
    logic perf_send_axi_req_write_back_w;
    logic perf_cd_fifo_full;
    logic perf_amo_wait_wb_r;
    logic perf_amo_wait_wb_w;
    logic perf_w_fifo_full;

    logic ungranted_request;
    assign ungranted_request = mu_req_i && !mu_gnt_o;

    assign perf_send_axi_req_r            = ungranted_request && ax_op_q == SEND_AXI_REQ_R;
    assign perf_send_axi_req_write_back_r = ungranted_request && ax_op_q == SEND_AXI_REQ_WRITE_BACK_R;
    assign perf_send_axi_req_w            = ungranted_request && ax_op_q == SEND_AXI_REQ_W;
    assign perf_send_axi_req_write_back_w = ungranted_request && ax_op_q == SEND_AXI_REQ_WRITE_BACK_W;
    assign perf_amo_wait_wb_r             = ungranted_request && ax_op_q == AMO_WAIT_WB_R;
    assign perf_amo_wait_wb_w             = ungranted_request && ax_op_q == AMO_WAIT_WB_W;
    assign perf_cd_fifo_full              = cd_fifo_full_o;
    assign perf_w_fifo_full               = w_fifo_full;

    assign perf_evt_o = {
        perf_send_axi_req_r,
        perf_send_axi_req_write_back_r,
        perf_send_axi_req_w,
        perf_send_axi_req_write_back_w,
        perf_amo_wait_wb_r,
        perf_amo_wait_wb_w,
        perf_cd_fifo_full,
        perf_w_fifo_full
    };
end else begin
    assign perf_evt_o = '0;
end


endmodule