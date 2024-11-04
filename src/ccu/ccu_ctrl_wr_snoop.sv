import ace_pkg::*;
import ccu_ctrl_pkg::*;

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
    // /// AW channel type towards cached master
    parameter type slv_aw_chan_t      = logic,
    /// Snoop request type
    parameter type mst_snoop_req_t    = logic,
    /// Snoop response type
    parameter type mst_snoop_resp_t   = logic,
    /// Domain masks set for each master
    parameter type domain_set_t       = logic,
    /// Domain mask type
    parameter type domain_mask_t      = logic
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

logic illegal_trs;
logic snoop_trs;

slv_aw_chan_t aw_holder_q;
logic load_aw_holder;
acsnoop_t snoop_trs_holder_d, snoop_trs_holder_q;
logic aw_holder_valid, aw_holder_ready, w_holder_valid, w_holder_ready;
logic ac_start;
logic ac_handshake, cd_handshake, w_slv_handshake;
logic aw_valid_d, aw_valid_q;
logic w_last_d, w_last_q;
logic cd_last_d, cd_last_q;
logic ignore_cd_d, ignore_cd_q;

typedef enum logic [1:0] { SNOOP_REQ, SNOOP_RESP, WRITE_CD, WRITE_W } wr_fsm_t;
wr_fsm_t fsm_state_d, fsm_state_q;

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        fsm_state_q <= SNOOP_REQ;
        aw_valid_q  <= 1'b0;
        w_last_q    <= 1'b0;
        cd_last_q   <= 1'b0;
        ignore_cd_q <= 1'b0;
    end else begin
        fsm_state_q <= fsm_state_d;
        aw_valid_q  <= aw_valid_d;
        w_last_q    <= w_last_d;
        cd_last_q   <= cd_last_d;
        ignore_cd_q <= ignore_cd_d;
    end
end

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        aw_holder_q        <= '0;
        snoop_trs_holder_q <= '0;
    end else begin
        if (load_aw_holder) begin
            aw_holder_q        <= slv_req_i.aw;
            snoop_trs_holder_q <= snoop_trs_i;
        end
    end
end

assign cd_handshake = snoop_resp_i.cd_valid && snoop_req_o.cd_ready;
assign ac_handshake = snoop_req_o.ac_valid  && snoop_resp_i.ac_ready;
assign b_handshake = mst_req_o.b_ready && mst_resp_i.b_valid;
assign w_slv_handshake = slv_req_i.w_valid && slv_resp_o.w_ready;

assign snoop_req_o.ac.addr = slv_req_i.aw.addr;
assign snoop_req_o.ac.snoop = snoop_trs_i;
assign snoop_req_o.ac.prot = slv_req_i.aw.prot;

assign mst_req_o.aw_valid = aw_valid_q;

always_comb begin
    ac_start             = 1'b0;
    aw_valid_d           = aw_valid_q;
    fsm_state_d          = fsm_state_q;
    w_last_d             = w_last_q;
    cd_last_d            = cd_last_q;
    ignore_cd_d          = ignore_cd_q;
    load_aw_holder       = 1'b0;
    snoop_req_o.ac_valid = 1'b0;
    snoop_req_o.cr_ready = 1'b0;
    snoop_req_o.cd_ready = 1'b0;
    slv_resp_o.aw_ready  = 1'b0;
    slv_resp_o.ar_ready  = 1'b0;
    slv_resp_o.w_ready   = 1'b0;
    slv_resp_o.r_valid   = 1'b0;
    slv_resp_o.r         = '0;
    slv_resp_o.b_valid   = 1'b0;
    slv_resp_o.b         = '0;
    mst_req_o.aw         = aw_holder_q;
    mst_req_o.w          = '0;
    mst_req_o.w_valid    = 1'b0;
    mst_req_o.b_ready    = 1'b0;
    mst_req_o.ar         = '0;
    mst_req_o.ar_valid   = 1'b0;
    mst_req_o.r_ready    = 1'b0;
    mst_req_o.rack       = 1'b0;
    mst_req_o.wack       = 1'b0;

    case(fsm_state_q)
        // Forward AW channel into a snoop request on the
        // AC channel
        SNOOP_REQ: begin
            w_last_d = 1'b0;
            cd_last_d = 1'b0;
            ignore_cd_d = 1'b0;
            snoop_req_o.ac_valid = slv_req_i.aw_valid;
            slv_resp_o.aw_ready  = snoop_resp_i.ac_ready;
            if (ac_handshake) begin
                fsm_state_d    = SNOOP_RESP;
                load_aw_holder = 1'b1;
            end
        end
        // Receive snoop response and either write CD data or
        // move to writing to main memory
        SNOOP_RESP: begin
            snoop_req_o.cr_ready = 1'b1;
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
                    aw_valid_d = 1'b1;
                    fsm_state_d = WRITE_W;
                end
            end
        end
        // Write CD data back to memory
        WRITE_CD: begin
            // Snooped data is provided wrap-bursted
            mst_req_o.aw.burst   = axi_pkg::BURST_WRAP;
            if (!cd_last_q && !ignore_cd_q) begin
                mst_req_o.w_valid = snoop_resp_i.cd_valid;
            end
            mst_req_o.w.data     = snoop_resp_i.cd.data;
            mst_req_o.w.strb     = '1;
            mst_req_o.w.last     = snoop_resp_i.cd.last;
            mst_req_o.w.user     = '0; // What to put here?
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
        end
        // Write data to memory
        WRITE_W: begin
            if (!w_last_q) begin
                mst_req_o.w_valid  = slv_req_i.w_valid;
                slv_resp_o.w_ready = mst_resp_i.w_ready;
            end
            if (w_slv_handshake && slv_req_i.w.last) begin
                w_last_d = 1'b1;
            end
            mst_req_o.w        = slv_req_i.w;
            mst_req_o.b_ready  = slv_req_i.b_ready;
            slv_resp_o.b_valid = mst_resp_i.b_valid;
            slv_resp_o.b       = mst_resp_i.b;
            if (mst_resp_i.aw_ready) begin
                aw_valid_d = 1'b0;
            end
            if (b_handshake) begin
                fsm_state_d = SNOOP_REQ;
            end
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

endmodule
