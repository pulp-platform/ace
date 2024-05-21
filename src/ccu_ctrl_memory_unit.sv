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
    parameter type aw_msg_t      = logic,
    parameter type ar_msg_t      = logic,
    localparam int unsigned DcacheLineWords = DcacheLineWidth / AxiDataWidth,
    localparam int unsigned MstIdxBits      = $clog2(NoMstPorts)
) (
    //clock and reset
    input                           clk_i,
    input                           rst_ni,
    // CCU Request In and response out
    input  slv_req_t                ccu_req_i,
    output slv_resp_t               ccu_resp_o,
    //CCU Request Out and response in
    output mst_req_t                ccu_req_o,
    input  mst_resp_t               ccu_resp_i,

    input  snoop_cd_t               cd_i,
    input  logic                    cd_handshake_i,
    output logic                    cd_fifo_full_o,


    input  aw_msg_t                 mu_aw_msg_i,
    input  logic                    mu_aw_req_i,
    output logic                    mu_aw_gnt_o,

    input  ar_msg_t                 mu_ar_msg_i,
    input  logic                    mu_ar_req_i,
    output logic                    mu_ar_gnt_o,

    input  logic   [MstIdxBits-1:0] first_responder_i,

    output logic              [7:0] perf_evt_o
);

localparam CD_FIFO_DEPTH  = 4;
localparam AXI_FIFO_DEPTH = 0; // Passthrough
localparam W_FIFO_DEPTH   = 2;

mst_req_t  ccu_req_out;
mst_resp_t ccu_resp_in;

logic cd_fifo_pop, cd_fifo_empty;
logic [AxiDataWidth-1:0] cd_fifo_data_out;

logic aw_winner;

typedef struct packed {
    logic amo;
    logic wb;
    logic busy;
    logic [MstIdxBits-1:0] responder;
} aw_status_t;

typedef struct packed {
    logic busy;
} ar_status_t;

aw_status_t aw_status_q, aw_status_d;
aw_status_t ar_wb_status_q, ar_wb_status_d;
ar_status_t ar_status_q, ar_status_d;

slv_ar_chan_t ar_wb_q, ar_wb_d;
slv_ar_chan_t ar_q, ar_d;
slv_aw_chan_t aw_q, aw_d;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        {aw_status_q, aw_q}       <= '0;
        {ar_wb_status_q, ar_wb_q} <= '0;
        {ar_status_q, ar_q}       <= '0;
    end else begin
        {aw_status_q, aw_q}       <= {aw_status_d, aw_d};
        {ar_wb_status_q, ar_wb_q} <= {ar_wb_status_d, ar_wb_d};
        {ar_status_q, ar_q}       <= {ar_status_d, ar_d};
    end
end

assign mu_aw_gnt_o = mu_aw_req_i ? !aw_status_q.busy : '0;
assign mu_ar_gnt_o = mu_ar_req_i && (mu_ar_msg_i.wb ? !ar_wb_status_q.busy : !ar_status_q.busy);


mst_ar_chan_t ar_out;
mst_aw_chan_t aw_out;

logic ar_valid_out, aw_valid_out;

logic w_last_d, w_last_q;

typedef enum logic {W_PASSTHROUGH, W_FROM_FIFO} w_state_t;

logic w_fifo_full, w_fifo_empty;
logic w_fifo_push, w_fifo_pop;
w_state_t w_fifo_data_in, w_fifo_data_out;

logic         [1:0] aw_valid_in, aw_ready_in;
mst_aw_chan_t [1:0] aw_chans_in;

logic         [1:0] ar_valid_in, ar_ready_in;
mst_ar_chan_t [1:0] ar_chans_in;

w_state_t     [1:0] w_state;
logic         [1:0] w_req;

always_comb begin : aw_handler

    aw_status_d.busy      = aw_status_q.busy;
    aw_status_d.amo       = aw_status_q.amo;
    aw_status_d.wb        = aw_status_q.busy ? aw_status_q.wb        : mu_aw_msg_i.wb;
    aw_status_d.responder = aw_status_q.busy ? aw_status_q.responder : first_responder_i;
    aw_d                  = aw_status_q.busy ? aw_q                  : mu_aw_msg_i.aw;

    aw_chans_in[0] = aw_d;
    aw_valid_in[0] = 1'b0;
    w_state[0]     = W_PASSTHROUGH;
    w_req[0]       = 1'b0;

    if (mu_aw_req_i || aw_status_q.busy) begin
        aw_status_d.busy = 1'b1;
        if (aw_status_d.wb) begin
            if (aw_status_q.amo) begin
                if(ccu_resp_in.b_valid && ccu_req_out.b_ready &&
                ccu_resp_in.b.id == {1'b1, aw_status_q.responder, aw_q.id[SlvAxiIDWidth-1:0]}) begin
                    aw_status_d.wb  = 1'b0;
                    aw_status_d.amo = 1'b0;
                end
            end else begin
                // send writeback request
                aw_valid_in[0]           = !w_fifo_full;
                aw_chans_in[0]           = '0; //default
                aw_chans_in[0].addr      = aw_d.addr;
                aw_chans_in[0].addr[3:0] = 4'b0; // writeback is always full cache line
                aw_chans_in[0].size      = 2'b11;
                aw_chans_in[0].burst     = axi_pkg::BURST_INCR; // Use BURST_INCR for AXI regular transaction
                aw_chans_in[0].id        = {1'b1, aw_status_d.responder, aw_d.id[SlvAxiIDWidth-1:0]}; // It should be visible this data originates from the responder, important e.g. for AMO operations
                aw_chans_in[0].len       = DcacheLineWords-1;
                // WRITEBACK
                aw_chans_in[0].domain    = 2'b00;
                aw_chans_in[0].snoop     = 3'b011;

                w_state[0]               = W_FROM_FIFO;

                if (aw_ready_in[0] && !w_fifo_full) begin
                    w_req[0]        = 1'b1;
                    aw_status_d.amo = aw_d.atop[5];
                    aw_status_d.wb  = aw_d.atop[5];
                end
            end
        end else begin
            aw_valid_in[0] = !w_fifo_full;
            aw_chans_in[0] = aw_d;

            w_state[0]     = W_PASSTHROUGH;

            if (aw_ready_in[0] && !w_fifo_full) begin
                w_req[0]         = 1'b1;
                aw_status_d.busy = 1'b0;
            end
        end
    end
end

always_comb begin : ar_wb_handler

    ar_wb_status_d.busy      = ar_wb_status_q.busy;
    ar_wb_status_d.amo       = ar_wb_status_q.amo;
    ar_wb_status_d.wb        = ar_wb_status_q.busy ? ar_wb_status_q.wb        : mu_ar_msg_i.wb;
    ar_wb_status_d.responder = ar_wb_status_q.busy ? ar_wb_status_q.responder : first_responder_i;
    ar_wb_d                  = ar_wb_status_q.busy ? ar_wb_q                  : mu_ar_msg_i.ar;

    // AR
    ar_valid_in[1] = 1'b0;
    ar_chans_in[1] = ar_wb_q;

    // AW
    aw_valid_in[1] = 1'b0;
    w_state[1]     = W_FROM_FIFO;
    w_req[1]       = 1'b0;

    // Prepare writeback request
    aw_chans_in[1]           = '0; //default
    aw_chans_in[1].addr      = ar_wb_d.addr;
    aw_chans_in[1].addr[3:0] = 4'b0; // writeback is always full cache line
    aw_chans_in[1].size      = 2'b11;
    aw_chans_in[1].burst     = axi_pkg::BURST_INCR; // Use BURST_INCR for AXI regular transaction
    aw_chans_in[1].id        = {1'b1, ar_wb_status_d.responder, ar_wb_d.id[SlvAxiIDWidth-1:0]}; // It should be visible this data originates from the responder, important e.g. for AMO operations
    aw_chans_in[1].len       = DcacheLineWords-1;
    // WRITEBACK
    aw_chans_in[1].domain    = 2'b00;
    aw_chans_in[1].snoop     = 3'b011;

    if ((mu_ar_req_i && mu_ar_msg_i.wb) || ar_wb_status_q.busy) begin
        ar_wb_status_d.busy = 1'b1;
        if (ar_wb_status_d.wb) begin
            if (ar_wb_status_q.amo) begin
                if(ccu_resp_in.b_valid && ccu_req_out.b_ready
                    && ccu_resp_in.b.id == {1'b1, ar_wb_status_q.responder,ar_wb_q.id[SlvAxiIDWidth-1:0]}) begin
                        ar_wb_status_d.wb  = 1'b0;
                        ar_wb_status_d.amo = 1'b0;
                    end
            end else begin
                aw_valid_in[1] = !w_fifo_full;
                if (aw_ready_in[1] && !w_fifo_full) begin
                    w_req[1] = 1'b1;
                    // Blocking behavior for AMO operations
                    // TODO: check if truly needed
                    if (ar_wb_d.lock) begin
                        ar_wb_status_d.amo = 1'b1;
                        ar_wb_status_d.wb = 1'b1;
                        ar_wb_status_d.busy = 1'b1;
                    end else begin
                        ar_wb_status_d.amo = 1'b0;
                        ar_wb_status_d.wb = 1'b0;
                        ar_wb_status_d.busy = 1'b0;
                    end
                end
            end
        end else begin
            ar_valid_in[1] = 1'b1;
            if (ar_ready_in[1]) begin
                ar_wb_status_d.busy = 1'b0;
            end
        end
    end
end

always_comb begin : ar_handler
    ar_d        = ar_status_q.busy ? ar_q : mu_ar_msg_i.ar;
    ar_status_d = ar_status_q;

    ar_valid_in[0]  = 'b0;
    ar_chans_in[0]  = ar_d;

    if ((mu_ar_req_i && !mu_ar_msg_i.wb) || ar_status_q.busy) begin
        ar_status_d.busy = 1'b1;
        ar_valid_in[0]  = 'b1;
        if (ar_ready_in[0]) begin
            ar_status_d.busy = 1'b0;
        end
    end
end

rr_arb_tree #(
    .NumIn    ( 2             ),
    .DataType ( mst_aw_chan_t ),
    .AxiVldRdy( 1'b1          ),
    .LockIn   ( 1'b1          )
) aw_arbiter_i (
    .clk_i  ( clk_i               ),
    .rst_ni ( rst_ni              ),
    .flush_i( 1'b0                ),
    .rr_i   ( '0                  ),
    .req_i  ( aw_valid_in         ),
    .gnt_o  ( aw_ready_in         ),
    .data_i ( aw_chans_in         ),
    .gnt_i  ( aw_ready_out        ),
    .req_o  ( aw_valid_out        ),
    .data_o ( aw_out              ),
    .idx_o  ( aw_winner           )
);

rr_arb_tree #(
    .NumIn    ( 2             ),
    .DataType ( mst_ar_chan_t ),
    .AxiVldRdy( 1'b1          ),
    .LockIn   ( 1'b1          )
) ar_arbiter_i (
    .clk_i  ( clk_i               ),
    .rst_ni ( rst_ni              ),
    .flush_i( 1'b0                ),
    .rr_i   ( '0                  ),
    .req_i  ( ar_valid_in         ),
    .gnt_o  ( ar_ready_in         ),
    .data_i ( ar_chans_in         ),
    .gnt_i  ( ar_ready_out        ),
    .req_o  ( ar_valid_out        ),
    .data_o ( ar_out              ),
    .idx_o  (                     )
);

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
assign ar_ready_out = ccu_resp_in.ar_ready;

// AW
assign ccu_req_out.aw = aw_out;
assign ccu_req_out.aw_valid = aw_valid_out;
assign aw_ready_out = ccu_resp_in.aw_ready;

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

assign w_fifo_data_in = w_state[aw_winner];
assign w_fifo_push    = w_req[aw_winner];

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
    // assign ungranted_request = mu_req_i && !mu_gnt_o;

    // assign perf_send_axi_req_r            = ungranted_request && ax_op_q == SEND_AXI_REQ_R;
    // assign perf_send_axi_req_write_back_r = ungranted_request && ax_op_q == SEND_AXI_REQ_WRITE_BACK_R;
    // assign perf_send_axi_req_w            = ungranted_request && ax_op_q == SEND_AXI_REQ_W;
    // assign perf_send_axi_req_write_back_w = ungranted_request && ax_op_q == SEND_AXI_REQ_WRITE_BACK_W;
    // assign perf_amo_wait_wb_r             = ungranted_request && ax_op_q == AMO_WAIT_WB_R;
    // assign perf_amo_wait_wb_w             = ungranted_request && ax_op_q == AMO_WAIT_WB_W;
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