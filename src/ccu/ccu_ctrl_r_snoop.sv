import ace_pkg::*;
import ccu_ctrl_pkg::*;

// FSM to control write snoop transactions
// This module assumes that snooping happens
// Non-snooping transactions should be handled outside
module ccu_ctrl_rd_snoop #(
    /// Request channel type towards cached master
    parameter type slv_req_t         = logic,
    /// Response channel type towards cached master
    parameter type slv_resp_t        = logic,
    /// Request channel type towards memory
    parameter type mst_req_t         = logic,
    /// Response channel type towards memory
    parameter type mst_resp_t        = logic,
    // /// AW channel type towards cached master
    parameter type slv_aw_chan_t     = logic,
    /// Snoop request type
    parameter type mst_snoop_req_t   = logic,
    /// Snoop response type
    parameter type mst_snoop_resp_t  = logic,

    localparam int unsigned AXLEN = 0,
    localparam int unsigned AXSIZE = 0,
    localparam int unsigned FIFODEPTH = 2
) (
    /// Clock
    input                               clk_i,
    /// Reset
    input                               rst_ni,
    /// Request channel towards cached master
    input  slv_req_t                    slv_req_i,
    /// Decoded snoop transaction
    /// Assumed to be valid when slv_req_i is valid
    input  snoop_info_t                 snoop_info_i,
    /// Response channel towards cached master
    output slv_resp_t                   slv_resp_o,
    /// Request channel towards memory
    output mst_req_t                    mst_req_o,
    /// Response channel towards memory
    input  mst_resp_t                   mst_resp_i,
    /// Response channel towards snoop crossbar
    input  mst_snoop_resp_t             snoop_resp_i,
    /// Request channel towards snoop crossbar
    output mst_snoop_req_t              snoop_req_o
);

logic illegal_trs;
logic snoop_info_holder_q, snoop_info_holder_d;
logic ar_holder_d, ar_holder_q;
logic ignore_cd_d, ignore_cd_q;
logic aw_valid_d, aw_valid_q;
logic ac_handshake;
rresp_t rresp_d, rresp_q;
logic fifo_flush, fifo_full, fifo_empty, fifo_push, fifo_pop;
logic [AxiDataWidth-1:0] fifo_data_in, fifo_data_out;
logic [$clog2(DcacheLineWords)-1:0] fifo_usage;
logic [4:0] arlen_counter;
logic arlen_counter_en, arlen_counter_reset;

assign ac_handshake = snoop_req_o.ac_valid  && snoop_resp_i.ac_ready;

typedef enum logic [2:0] { SNOOP_REQ, SNOOP_RESP, READ_CD, WRITE_CD, READ_R } r_fsm_t;
r_fsm_t fsm_state_d, fsm_state_q;

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        arlen_counter <= '0;
    end else begin
        if (arlen_counter_reset) begin 
            arlen_counter <= '0;
        end else if (arlen_counter_en) begin
            arlen_counter <= arlen_counter + 1'b1;
        end
    end
end

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        fsm_state_q  <= SNOOP_REQ;
        ignore_cd_q  <= 1'b0;
        rresp_q[3:2] <= '0;
    end else begin
        fsm_state_q  <= fsm_state_d;
        ignore_cd_q  <= ignore_cd_d;
        rresp_q[3:2] <= rresp_d[3:2];
    end
end

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        ar_holder_q        <= '0;
        snoop_info_holder_q <= '0;
    end else begin
        if (load_ar_holder) begin
            ar_holder_q        <= slv_req_i.ar;
            snoop_info_holder_q <= snoop_info_i;
        end
    end
end

always_comb begin
    load_ar_holder = 1'b0;
    rresp_d[3:2]   = rresp_q[3:2];
    mst_req_o.w         = '0;
    mst_req_o.aw        = '0; // defaults
    mst_req_o.aw.id     = ar_holder_q.id;
    mst_req_o.aw.addr   = ar_holder_q.addr;
    mst_req_o.aw.len    = AXLEN;
    mst_req_o.aw.size   = AXSIZE;
    mst_req_o.aw.burst  = axi_pkg::BURST_WRAP;
    mst_req_o.aw.domain = 2'b00;
    mst_req_o.aw.snoop  = ace_pkg::WriteBack;

    slv_resp_o.r.id = ar_holder_q.id

    case(fsm_state_q)
        // Forward AW channel into a snoop request on the
        // AC channel
        SNOOP_REQ: begin
            ignore_cd_d = 1'b0;
            snoop_req_o.ac_valid = slv_req_i.ar_valid;
            slv_resp_o.ar_ready = snoop_resp_i.ac_ready;
            if (ac_handshake) begin
                fsm_state_d = SNOOP_RESP;
                load_ar_holder = 1'b1;
            end
        end
        // Receive snoop response and either write CD data or
        // move to writing to main memory
        SNOOP_RESP: begin
            snoop_req_o.cr_ready = 1'b1;
            if (snoop_resp_i.cr_valid) begin
                rresp_d[3:2] = '0;
                if (snoop_resp_i.cr_resp.DataTransfer) begin
                    if (!snoop_resp_i.cr_resp.Error) begin
                        if (snoop_resp_i.cr_resp.PassDirty) begin
                            if (snoop_info_holder_q.accepts_dirty) begin
                                rresp_d.PassDirty = 1'b1;
                                fsm_state_d = READ_CD;
                            end else begin
                                fsm_state_d = WRITE_CD;
                            end
                        end else begin
                            aw_valid_d = 1'b1;
                        end
                    end else begin
                        ignore_cd_d = 1'b1;
                    end
                end
            end
        end
        // Read CD data
        READ_CD: begin
        end
        // Write CD data back to memory
        WRITE_CD: begin
            if (!cd_last_q && !ignore_cd_q) begin
                mst_req_o.w_valid = snoop_resp_i.cd_valid;
            end
            mst_req_o.w.data     = snoop_resp_i.cd.data;
            mst_req_o.w.strb     = '1;
            mst_req_o.w.last     = snoop_resp_i.cd.last;
            mst_req_o.b_ready    = 1'b1;
            snoop_req_o.cd_ready = mst_resp_i.w_ready || ignore_cd_q;
            slv_resp_o.b         = mst_resp_i.b;
            if (cd_handshake && snoop_resp_i.cd.last) begin
                cd_last_d = 1'b1;
            end
            if (mst_resp_i.aw_ready) begin
                aw_valid_d = 1'b0;
            end
            // TODO: monitor B handshakes outside the FSM
            if (b_handshake || (cd_last_q && ignore_cd_q)) begin
                aw_valid_d  = 1'b1;
                fsm_state_d = WRITE_W;
            end
            slv_resp_o.r.data  = fifo_data_out;
            slv_resp_o.resp = {rresp_q[3:2], 2'b0};
            slv_resp_o.last = '0;
            slv_resp_o.r_valid = !fifo_empty;
        end
        // Read data from memory
        READ_R: begin
        end
    endcase
end

assign fifo_data_in = snoop_resp_i.cd.data;
assign fifo_push    = cd_handshake;

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