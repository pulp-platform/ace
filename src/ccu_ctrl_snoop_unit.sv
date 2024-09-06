module ccu_ctrl_snoop_unit import ccu_ctrl_pkg::*;
#(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiDataWidth = 0,
    parameter int unsigned NoMstPorts = 4,
    parameter int unsigned SlvAxiIDWidth = 0,
    parameter type slv_aw_chan_t = logic,
    parameter type w_chan_t      = logic,
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
    input                                clk_i,
    input                                rst_ni,
    // CCU Request In and response out
    output slv_r_chan_t                  r_o,
    output logic                         r_valid_o,
    input  logic                         r_ready_i,

    input  snoop_cd_t                    cd_i,
    input  logic                         cd_handshake_i,
    output logic                         cd_fifo_full_o,

    input  slv_req_t                     ccu_req_holder_i,
    output logic                         su_gnt_o,
    input  logic                         su_req_i,
    input  su_op_e                       su_op_i,
    input  logic                         shared_i,
    input  logic                         dirty_i
);

localparam FIFO_DEPTH = 2;

logic [AxiDataWidth-1:0] fifo_data_in, fifo_data_out;
logic [$clog2(DcacheLineWords)-1:0] fifo_usage;

logic su_busy_d, su_busy_q;
logic r_last_d, r_last_q;
su_op_e su_op_d, su_op_q;

slv_req_t ccu_req_holder_q, ccu_req_holder_d;
logic shared_q, shared_d;
logic dirty_q, dirty_d;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        ccu_req_holder_q <= '0;
        shared_q <= '0;
        dirty_q <= '0;
    end else begin
        ccu_req_holder_q <= ccu_req_holder_d;
        shared_q <= shared_d;
        dirty_q <= dirty_d;
    end
end

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        su_busy_q <= '0;
        su_op_q   <= READ_SNP_DATA;
        r_last_q  <= '0;
    end else begin
        su_busy_q <= su_busy_d;
        su_op_q   <= su_op_d;
        r_last_q  <= r_last_d;
    end
end

logic ar_addr_offset;

assign ar_addr_offset = ccu_req_holder_i.ar.addr[3];

logic fifo_full, fifo_empty, fifo_push, fifo_pop;

assign cd_fifo_full_o = fifo_full;

assign ccu_req_holder_d = su_busy_q ? ccu_req_holder_q : ccu_req_holder_i;
assign shared_d         = su_busy_q ? shared_q         : shared_i;
assign dirty_d          = su_busy_q ? dirty_q          : dirty_i;
assign su_op_d          = su_busy_q ? su_op_q          : su_op_i;

always_comb begin
    su_gnt_o = 1'b0;

    r_o = '0;
    r_valid_o = 1'b0;

    fifo_pop  = 1'b0;

    su_busy_d = su_busy_q;
    r_last_d  = r_last_q;

    if (su_req_i || su_busy_q) begin
        su_gnt_o  = !su_busy_q;
        su_busy_d = 1'b1;
        case (su_op_d)
            READ_SNP_DATA: begin
                // Prepare request
                r_o.data    = fifo_data_out;
                r_o.id      = ccu_req_holder_d.ar.id;
                r_o.resp[3] = shared_d; // update if shared
                r_o.resp[2] = dirty_d;  // update if any line dirty
                r_o.last    = r_last_q; // No further transactions

                if (r_last_q) begin
                    r_valid_o = !fifo_empty;
                    if (r_ready_i && !fifo_empty) begin
                        fifo_pop  = 1'b1;
                        su_busy_d = 1'b0;
                        r_last_d  = 1'b0;
                    end
                end else begin
                    // Single data request
                    if (ccu_req_holder_d.ar.len == 0) begin
                        // The lower 64 bits are required
                        if (!ar_addr_offset) begin
                            r_o.last    = 1'b1;
                            r_valid_o   = !fifo_empty; // There is something to send
                            if (r_ready_i && !fifo_empty) begin
                                fifo_pop  = 1'b1;
                                su_busy_d = 1'b0;
                            end
                        end else begin
                            // The lower 64 bits are not needed
                            // Consume them and move the upper 64 bits
                            r_last_d = 1'b1;
                            fifo_pop = 1'b1;
                        end
                    end else begin
                        // Full cacheline request
                        r_valid_o   = !fifo_empty; // There is something to send
                        if (r_ready_i && !fifo_empty) begin
                            fifo_pop = 1'b1;
                            r_last_d = 1'b1;
                        end
                    end
                end
            end
            SEND_INVALID_ACK_R: begin
                r_o       =   '0;
                r_o.id    =   ccu_req_holder_d.ar.id;
                r_o.last  =   'b1;
                r_valid_o =   'b1;
                if (r_ready_i) begin
                    su_busy_d = 1'b0;
                end
            end
        endcase
    end
end

assign fifo_push    = cd_handshake_i;
assign fifo_flush   = !(su_req_i || su_busy_q);
assign fifo_data_in = cd_i.data;


  fifo_v3 #(
    .FALL_THROUGH(1),
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
