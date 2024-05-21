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
    parameter type ar_msg_t      = logic,
    parameter type snp_flags_t   = logic,
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

    output logic                         su_gnt_o,
    input  logic                         su_req_i,

    input ar_msg_t                       ar_msg_i,
    input snp_flags_t                    snp_flags_i
);

localparam FIFO_DEPTH = 2;

logic [AxiDataWidth-1:0] fifo_data_in, fifo_data_out;
logic [$clog2(DcacheLineWords)-1:0] fifo_usage;

logic su_busy_d, su_busy_q;
logic r_last_d, r_last_q;

slv_ar_chan_t ar_q, ar_d;
logic shared_q, shared_d;
logic dirty_q, dirty_d;

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        ar_q     <= '0;
        shared_q <= '0;
        dirty_q  <= '0;
    end else begin
        ar_q     <= ar_d;
        shared_q <= shared_d;
        dirty_q  <= dirty_d;
    end
end

always_ff @(posedge clk_i , negedge rst_ni) begin
    if(!rst_ni) begin
        su_busy_q <= '0;
        r_last_q  <= '0;
    end else begin
        su_busy_q <= su_busy_d;
        r_last_q  <= r_last_d;
    end
end

logic ar_addr_offset;

assign ar_addr_offset = ar_msg_i.ar.addr[3];

logic fifo_full, fifo_empty, fifo_push, fifo_pop;

assign cd_fifo_full_o = fifo_full;

assign ar_d     = su_busy_q ? ar_q     : ar_msg_i.ar;
assign shared_d = su_busy_q ? shared_q : snp_flags_i.shared;
assign dirty_d  = su_busy_q ? dirty_q  : snp_flags_i.dirty;

always_comb begin
    su_gnt_o = 1'b0;

    r_o = '0;
    // Prepare request
    r_o.data    = fifo_data_out;
    r_o.id      = ar_d.id;
    r_o.resp[3] = shared_d; // update if shared
    r_o.resp[2] = dirty_d;  // update if any line dirty
    r_o.last    = r_last_q; // No further transactions

    r_valid_o = 1'b0;

    fifo_pop  = 1'b0;

    su_busy_d = su_busy_q;
    r_last_d  = r_last_q;

    if (su_req_i || su_busy_q) begin
        su_gnt_o  = !su_busy_q;
        su_busy_d = 1'b1;

        if (r_last_q) begin
            r_valid_o = !fifo_empty;
            if (r_ready_i && !fifo_empty) begin
                fifo_pop  = 1'b1;
                su_busy_d = 1'b0;
                r_last_d  = 1'b0;
            end
        end else begin
            // Single data request
            if (ar_d.len == 0) begin
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
