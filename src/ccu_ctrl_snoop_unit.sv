module ccu_ctrl_snoop_unit import ccu_ctrl_pkg::*;
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
    input                                clk_i,
    input                                rst_ni,
    // CCU Request In and response out
    output mst_r_chan_t                  r_o,
    output logic                         r_valid_o,
    input  logic                         r_ready_i,

    input  snoop_cd_t                    cd_i,
    input  logic                         cd_handshake_i,
    output logic                         cd_fifo_full_o,

    input  mst_req_t                     ccu_req_holder_i,
    output logic                         su_ready_o,
    input  logic                         su_valid_i,
    input  su_op_e                       su_op_i,
    input  logic                         shared_i,
    input  logic                         dirty_i
);

localparam FIFO_DEPTH = 2;

enum {
      IDLE,
      SEND_LOWER_HALF,
      SEND_UPPER_HALF,
      WAIT_R_READY,
      WAIT_CD_LAST
} state_d, state_q;

logic [AxiDataWidth-1:0] fifo_data_in, fifo_data_out;
logic [$clog2(DcacheLineWords)-1:0] fifo_usage;

logic sample_dec_data;

mst_req_t ccu_req_holder_q;
logic shared_q;
logic dirty_q;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        ccu_req_holder_q <= '0;
        shared_q <= '0;
        dirty_q <= '0;
    end else if(sample_dec_data) begin
        ccu_req_holder_q <= ccu_req_holder_i;
        shared_q <= shared_i;
        dirty_q <= dirty_i;
    end
end

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        state_q <= IDLE;
    end else begin
        state_q <= state_d;
    end
end

logic ar_addr_offset;

assign ar_addr_offset = ccu_req_holder_q.ar.addr[3];

logic fifo_full, fifo_empty, fifo_push, fifo_pop;

assign cd_fifo_full_o = fifo_full;

always_comb begin

    state_d = state_q;

    su_ready_o = 1'b0;

    r_o = '0;
    r_valid_o = 1'b0;

    fifo_pop  = 1'b0;

    sample_dec_data = 1'b0;

    case (state_q)
        IDLE: begin
            su_ready_o = 1'b1;
            if (su_valid_i) begin
                if (su_op_i == SEND_INVALID_ACK_R) begin
                    r_o       =   '0;
                    r_o.id    =   ccu_req_holder_i.ar.id;
                    r_o.last  =   'b1;
                    r_valid_o =   'b1;
                    if (!r_ready_i) begin
                        state_d = WAIT_R_READY;
                        sample_dec_data = 1'b1;
                    end
                end else if (su_op_i == READ_SNP_DATA) begin
                    sample_dec_data = 1'b1;
                    state_d = SEND_LOWER_HALF;
                end
            end
        end

        SEND_LOWER_HALF: begin
            // Prepare request
            r_o.data    = fifo_data_out;
            r_o.id      = ccu_req_holder_q.ar.id;
            r_o.resp[3] = shared_q; // update if shared
            r_o.resp[2] = dirty_q;  // update if any line dirty

            if (!fifo_empty) begin
                // Single data request
                if (ccu_req_holder_q.ar.len == 0) begin
                    // The lower 64 bits are required
                    if (!ar_addr_offset) begin
                        r_o.last    = 1'b1;
                        r_valid_o   = 1'b1; // There is something to send
                        if (r_ready_i) begin
                            state_d = WAIT_CD_LAST;
                            fifo_pop = 1'b1;
                        end
                    end else begin
                        // The lower 64 bits are not needed
                        // Consume them and move the upper 64 bits
                        state_d = SEND_UPPER_HALF;
                        fifo_pop = 1'b1;
                    end
                end else begin
                    // Full cacheline request
                    r_o.last    = 1'b0;
                    r_valid_o   = 1'b1; // There is something to send
                    if (r_ready_i) begin
                        state_d = SEND_UPPER_HALF;
                        fifo_pop = 1'b1;
                    end
                end
            end
        end

        SEND_UPPER_HALF: begin
            // Prepare request
            r_o.data    = fifo_data_out;
            r_o.id      = ccu_req_holder_q.ar.id;
            r_o.resp[3] = shared_q; // Update if shared
            r_o.resp[2] = dirty_q;  // Update if any line dirty
            r_o.last    = 1'b1;     // No further transactions

            if (!fifo_empty) begin
                r_valid_o = 1'b1;

                if (r_ready_i) begin
                    fifo_pop = 1'b1;
                    state_d = IDLE;
                end
            end
        end

        WAIT_R_READY: begin
            r_o        =   '0;
            r_o.id     =   ccu_req_holder_q.ar.id;
            r_o.last   =   'b1;
            r_valid_o  =   'b1;

            if (r_ready_i)
                state_d = IDLE;
        end
    endcase
end

assign fifo_push    = cd_handshake_i;
assign fifo_flush   = 1'b0;
assign fifo_data_in = cd_i.data;


  fifo_v3 #(
    .FALL_THROUGH(0),
    .DATA_WIDTH(AxiDataWidth),
    .DEPTH(FIFO_DEPTH)
  ) cd_snoop_fifo_i (
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

endmodule
