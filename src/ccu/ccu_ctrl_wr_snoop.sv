`include "axi/assign.svh"
import ace_pkg::*;

// FSM to control write snoop transactions
// This module assumes that snooping happens
// Non-snooping transactions should be handled outside
module ccu_ctrl_wr_snoop #(
    /// Request channel type towards cached master
    parameter type slv_req_t          = logic,
    /// Response channel type towards cached master
    parameter type slv_resp_t         = logic,
    /// Request channel type towards memory
    parameter type mst_req_t          = logic,
    /// Response channel type towards memory
    parameter type mst_resp_t         = logic,
    /// AW channel type towards cached master
    parameter type slv_aw_chan_t      = logic,
    /// Snoop request type
    parameter type mst_snoop_req_t    = logic,
    /// Snoop response type
    parameter type mst_snoop_resp_t   = logic,
    /// Domain masks set for each master
    parameter type domain_set_t       = logic,
    /// Domain mask type
    parameter type domain_mask_t      = logic,
    /// Fixed value for AXLEN for write back
    parameter int unsigned AXLEN      = 0,
    /// Fixed value for AXSIZE for write back
    parameter int unsigned AXSIZE     = 0,
    /// Depth of FIFO that stores AW requests
    parameter int unsigned FIFO_DEPTH = 2
) (
    /// Clock
    input                               clk_i,
    /// Reset
    input                               rst_ni,
    /// Request channel towards cached master
    input  slv_req_t                    slv_req_i,
    /// Decoded snoop transaction
    /// Assumed to be valid when slv_req_i is valid
    input  acsnoop_t                    snoop_trs_i,
    /// Response channel towards cached master
    output slv_resp_t                   slv_resp_o,
    /// Request channel towards memory
    output mst_req_t                    mst_req_o,
    /// Response channel towards memory
    input  mst_resp_t                   mst_resp_i,
    /// Response channel towards snoop crossbar
    input  mst_snoop_resp_t             snoop_resp_i,
    /// Request channel towards snoop crossbar
    output mst_snoop_req_t              snoop_req_o,
    /// Domain masks set for the current AW initiator
    input  domain_set_t                 domain_set_i,
    /// Ax mask to be used for the snoop request
    output domain_mask_t                domain_mask_o
);

// Data structure to store AW request and decoded snoop transaction
typedef struct packed {
    slv_aw_chan_t aw;
    acsnoop_t snoop_trs;
} slv_req_s;

// FSM states
typedef enum logic [1:0] { SNOOP_RESP, WRITE_CD, WRITE_W } wr_fsm_t;

logic cd_last_d, cd_last_q;
logic aw_valid_d, aw_valid_q;
logic b_done_d, b_done_q;
logic r_last_d, r_last_q;
logic recv_r, finish;
logic ac_handshake, cd_handshake, w_slv_handshake, r_slv_handshake;
logic r_last;
acsnoop_t snoop_trs_holder_d, snoop_trs_holder_q;
logic w_last_d, w_last_q;
logic ignore_cd_d, ignore_cd_q;
slv_req_s slv_req, slv_req_holder;
logic slv_req_fifo_not_full;
logic slv_req_fifo_valid;
logic pop_slv_req_fifo;
logic write_back_source; // 0 - CD, 1 - Cache
wr_fsm_t fsm_state_d, fsm_state_q;


assign slv_req.aw        = slv_req_i.aw;
assign slv_req.snoop_trs = snoop_trs_i;
assign ac_handshake      = snoop_req_o.ac_valid  && snoop_resp_i.ac_ready;
assign cd_handshake      = snoop_resp_i.cd_valid && snoop_req_o.cd_ready;
assign b_handshake       = mst_req_o.b_ready && mst_resp_i.b_valid;
assign r_slv_handshake   = slv_resp_o.r_valid && slv_req_i.r_ready;
assign r_last            = r_slv_handshake && slv_resp_o.r.last;
assign w_slv_handshake   = slv_req_i.w_valid && slv_resp_o.w_ready;
assign recv_r            = slv_req_holder.aw.atop[5];



always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        fsm_state_q <= SNOOP_RESP;
        aw_valid_q  <= 1'b0;
        w_last_q    <= 1'b0;
        cd_last_q   <= 1'b0;
        ignore_cd_q <= 1'b0;
        b_done_q    <= 1'b0;
        r_last_q    <= 1'b0;
    end else begin
        fsm_state_q <= fsm_state_d;
        aw_valid_q  <= aw_valid_d;
        w_last_q    <= w_last_d;
        cd_last_q   <= cd_last_d;
        ignore_cd_q <= ignore_cd_d;
        b_done_q    <= b_done_d;
        r_last_q    <= r_last_d;
    end
end

// AC request
always_comb begin
    snoop_req_o.ac_valid = slv_req_i.aw_valid && slv_req_fifo_not_full;
    snoop_req_o.ac.addr  = slv_req.aw.addr;
    snoop_req_o.ac.snoop = slv_req.snoop_trs;
    snoop_req_o.ac.prot  = slv_req.aw.prot;
    slv_resp_o.aw_ready  = snoop_resp_i.ac_ready && slv_req_fifo_not_full;
end

// Read channel signals not used
always_comb begin
    slv_resp_o.ar_ready = 1'b0;
    mst_req_o.ar        = '0;
    mst_req_o.ar_valid  = 1'b0;
end

// Write channel
always_comb begin
    slv_resp_o.b       = mst_resp_i.b;
    `AXI_SET_AW_STRUCT(mst_req_o.aw, slv_req_holder.aw)
    mst_req_o.aw_valid = aw_valid_q;
    if (write_back_source) begin
        mst_req_o.w.data = slv_req_i.w.data;
        mst_req_o.w.strb = slv_req_i.w.strb;
        mst_req_o.w.last = slv_req_i.w.last;
        mst_req_o.w.user = slv_req_i.w.user;
    end else begin
        mst_req_o.aw.burst = axi_pkg::BURST_WRAP;
        mst_req_o.aw.len   = AXLEN;
        mst_req_o.aw.size  = AXSIZE;
        mst_req_o.w.data   = snoop_resp_i.cd.data;
        mst_req_o.w.strb   = '1;
        mst_req_o.w.last   = snoop_resp_i.cd.last;
        mst_req_o.w.user   = '0;
    end
end

always_comb begin
    aw_valid_d           = aw_valid_q;
    fsm_state_d          = fsm_state_q;
    w_last_d             = w_last_q;
    cd_last_d            = cd_last_q;
    ignore_cd_d          = ignore_cd_q;
    b_done_d             = b_done_q;
    r_last_d             = r_last_q;
    pop_slv_req_fifo     = 1'b0;
    write_back_source    = 1'b0;
    snoop_req_o.cr_ready = 1'b0;
    snoop_req_o.cd_ready = 1'b0;
    slv_resp_o.w_ready   = 1'b0;
    slv_resp_o.b_valid   = 1'b0;
    mst_req_o.w_valid    = 1'b0;
    mst_req_o.b_ready    = 1'b0;
    slv_resp_o.r_valid   = 1'b0;
    slv_resp_o.r         = '0;
    mst_req_o.r_ready    = 1'b0;
    finish               = 1'b0;

    case(fsm_state_q)
        // Receive snoop response and either write CD data or
        // move to writing to main memory
        SNOOP_RESP: begin
            b_done_d             = 1'b0;
            r_last_d             = 1'b0;
            w_last_d             = 1'b0;
            cd_last_d            = 1'b0;
            ignore_cd_d          = 1'b0;
            snoop_req_o.cr_ready = slv_req_fifo_valid;
            if (snoop_resp_i.cr_valid) begin
                if (snoop_resp_i.cr_resp.DataTransfer) begin
                    // If received data is erronous or clean,
                    // we receive CD but do not write it
                    if (snoop_resp_i.cr_resp.Error ||
                        !snoop_resp_i.cr_resp.PassDirty) begin
                        ignore_cd_d = 1'b1;
                    end else begin
                        aw_valid_d = 1'b1;
                    end
                    fsm_state_d = WRITE_CD;
                end else begin
                    aw_valid_d  = 1'b1;
                    fsm_state_d = WRITE_W;
                end
            end
        end
        // Write CD data back to memory
        WRITE_CD: begin
            if (!cd_last_q && !ignore_cd_q) begin
                mst_req_o.w_valid = snoop_resp_i.cd_valid;
            end
            mst_req_o.b_ready    = cd_last_q;
            snoop_req_o.cd_ready = mst_resp_i.w_ready || ignore_cd_q;
            if (cd_handshake && snoop_resp_i.cd.last) begin
                cd_last_d = 1'b1;
            end
            if (mst_resp_i.aw_ready) begin
                aw_valid_d = 1'b0;
            end
            if (b_handshake || (cd_last_q && ignore_cd_q)) begin
                aw_valid_d  = 1'b1;
                fsm_state_d = WRITE_W;
            end
        end
        // Write data to memory
        WRITE_W: begin
            write_back_source = 1'b1;
            r_last_d = r_last_q || r_last;
            b_done_d = b_done_q || b_handshake;
            if (!w_last_q) begin
                mst_req_o.w_valid  = slv_req_i.w_valid;
                slv_resp_o.w_ready = mst_resp_i.w_ready;
            end
            if (w_slv_handshake && slv_req_i.w.last) begin
                w_last_d = 1'b1;
            end
            mst_req_o.b_ready  = slv_req_i.b_ready;
            slv_resp_o.b_valid = mst_resp_i.b_valid;
            if (recv_r) begin
                mst_req_o.r_ready  = slv_req_i.r_ready;
                slv_resp_o.r_valid = mst_resp_i.r_valid;
                `AXI_SET_R_STRUCT(slv_resp_o.r, mst_resp_i.r)
            end
            if (mst_resp_i.aw_ready) begin
                aw_valid_d = 1'b0;
            end
            if (b_handshake || b_done_q) begin
                if (recv_r) begin
                    if (r_last || r_last_q) begin
                        finish = 1'b1;
                    end
                end else begin
                    finish = 1'b1;
                end
            end
            if (finish) begin
                fsm_state_d      = SNOOP_RESP;
                pop_slv_req_fifo = 1'b1;
            end
        end
        default: begin
            fsm_state_d = SNOOP_RESP;
        end
    endcase
end

// Domain mask generation
// Note: this signal should flow along with AC
always_comb begin
    domain_mask_o = '0;
    case (slv_req_i.aw.domain)
      NonShareable:   domain_mask_o = 0;
      InnerShareable: domain_mask_o = domain_set_i.inner;
      OuterShareable: domain_mask_o = domain_set_i.outer;
      System:         domain_mask_o = ~domain_set_i.initiator;
    endcase
end

// FIFO for storing AW requests
stream_fifo_optimal_wrap #(
    .Depth  (FIFO_DEPTH),
    .type_t (slv_req_s)
) i_slv_req_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .usage_o    (),
    .valid_i    (ac_handshake),
    .ready_o    (slv_req_fifo_not_full),
    .data_i     (slv_req),
    .valid_o    (slv_req_fifo_valid),
    .ready_i    (pop_slv_req_fifo),
    .data_o     (slv_req_holder)
);

endmodule
