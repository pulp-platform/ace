import ace_pkg::*;
import ccu_ctrl_pkg::*;

// FSM to control read snoop transactions
// This module assumes that snooping happens
// Non-snooping transactions should be handled outside
module ccu_ctrl_r_snoop #(
    /// Request channel type towards cached master
    parameter type slv_req_t         = logic,
    /// Response channel type towards cached master
    parameter type slv_resp_t        = logic,
    /// Request channel type towards memory
    parameter type mst_req_t         = logic,
    /// Response channel type towards memory
    parameter type mst_resp_t        = logic,
    // /// AW channel type towards cached master
    parameter type slv_ar_chan_t     = logic,
    /// Snoop request type
    parameter type mst_snoop_req_t   = logic,
    /// Snoop response type
    parameter type mst_snoop_resp_t  = logic,
    /// Domain masks set for each master
    parameter type domain_set_t      = logic,
    /// Domain mask type
    parameter type domain_mask_t     = logic,
    /// Fixed value for AXLEN for write back
    parameter int unsigned AXLEN = 0,
    /// Fixed value for AXSIZE for write back
    parameter int unsigned AXSIZE = 0
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
    output mst_snoop_req_t              snoop_req_o,
    /// Domain masks set for the current AR initiator
    input  domain_set_t                 domain_set_i,
    /// Ax mask to be used for the snoop request
    output domain_mask_t                domain_mask_o
);

logic load_ar_holder;
snoop_info_t snoop_info_holder_q;
slv_ar_chan_t ar_holder_q;
logic cd_last_d, cd_last_q;
logic aw_valid_d, aw_valid_q, ar_valid_d, ar_valid_q;
logic ac_handshake, cd_handshake, b_handshake, r_handshake;
rresp_t rresp_d, rresp_q;
logic [4:0] arlen_counter;
logic arlen_counter_en, arlen_counting, arlen_counter_clear;
logic cd_ready;
logic [1:0] cd_mask_d, cd_mask_q;
logic [1:0] cd_fork_valid, cd_fork_ready;
logic cd_mask_valid;
logic r_last;
logic r_last_q, r_last_d;
logic write_back, resp_shared, resp_dirty;

assign ac_handshake       = snoop_req_o.ac_valid  && snoop_resp_i.ac_ready;
assign r_handshake        = slv_resp_o.r_valid && slv_req_i.r_ready;
assign cd_handshake       = snoop_req_o.cd_ready && snoop_resp_i.cd_valid;
assign b_handshake        = mst_req_o.b_ready && mst_resp_i.b_valid;
assign r_last             = (arlen_counter == ar_holder_q.len);
assign mst_req_o.aw_valid = aw_valid_q;
assign mst_req_o.ar       = ar_holder_q;
assign mst_req_o.ar_valid = ar_valid_q;

localparam unsigned MST_R_IDX = 0; // R channel of Initiating master
localparam unsigned MEM_W_IDX = 1; // W channel of Memory
typedef enum logic [2:0] { SNOOP_REQ, SNOOP_RESP, READ_CD, WRITE_CD, READ_R, IGNORE_CD } r_fsm_t;
r_fsm_t fsm_state_d, fsm_state_q;

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        arlen_counter <= '0;
    end else if (arlen_counter_clear) begin
        arlen_counter <= '0;
    end else if (arlen_counter_en) begin
        arlen_counter <= arlen_counter + 1'b1;
    end
end

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        fsm_state_q  <= SNOOP_REQ;
        rresp_q[3:2] <= '0;
        cd_mask_q    <= '0;
        aw_valid_q   <= '0;
        ar_valid_q   <= '0;
        cd_last_q    <= '0;
        r_last_q     <= '0;
    end else begin
        fsm_state_q  <= fsm_state_d;
        rresp_q[3:2] <= rresp_d[3:2];
        cd_mask_q    <= cd_mask_d;
        aw_valid_q   <= aw_valid_d;
        ar_valid_q   <= ar_valid_d;
        cd_last_q    <= cd_last_d;
        r_last_q     <= r_last_d;
    end
end

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        ar_holder_q         <= '0;
        snoop_info_holder_q <= '0;
    end else begin
        if (load_ar_holder) begin
            ar_holder_q         <= slv_req_i.ar;
            snoop_info_holder_q <= snoop_info_i;
        end
    end
end

always_comb begin
    r_last_d             = r_last_q;
    arlen_counting       = 1'b0;
    fsm_state_d          = fsm_state_q;
    load_ar_holder       = 1'b0;
    rresp_d[3:2]         = rresp_q[3:2];
    cd_mask_d            = cd_mask_q;
    arlen_counter_clear  = 1'b0;
    aw_valid_d           = aw_valid_q;
    ar_valid_d           = ar_valid_q;
    cd_last_d            = cd_last_q;
    mst_req_o.w          = '0;
    mst_req_o.w_valid    = '0;
    mst_req_o.aw         = '0; // defaults
    mst_req_o.aw.id      = ar_holder_q.id;
    mst_req_o.aw.addr    = ar_holder_q.addr;
    mst_req_o.aw.len     = AXLEN;
    mst_req_o.aw.size    = AXSIZE;
    mst_req_o.aw.burst   = axi_pkg::BURST_WRAP;
    mst_req_o.aw.domain  = 2'b00;
    mst_req_o.aw.snoop   = ace_pkg::WriteBack;
    mst_req_o.r_ready    = 1'b0;
    mst_req_o.b_ready    = 1'b0;
    mst_req_o.rack       = 1'b0;
    mst_req_o.wack       = 1'b0;
    slv_resp_o.ar_ready  = 1'b0;
    slv_resp_o.aw_ready  = 1'b0;
    slv_resp_o.w_ready   = 1'b0;
    slv_resp_o.b_valid   = 1'b0;
    slv_resp_o.b         = '0;
    slv_resp_o.r_valid   = 1'b0;
    slv_resp_o.r         = '0;
    slv_resp_o.r.id      = ar_holder_q.id;
    snoop_req_o.ac       = '0;
    snoop_req_o.ac_valid = 1'b0;
    snoop_req_o.cd_ready = 1'b0;
    snoop_req_o.cr_ready = 1'b0;
    cd_fork_ready        = '0;
    cd_mask_valid        = 1'b1;
    arlen_counter_en     = 1'b0;

    case(fsm_state_q)
        // Forward AR channel into a snoop request on the
        // AC channel
        SNOOP_REQ: begin
            cd_mask_d            = '0;
            cd_last_d            = 1'b0;
            r_last_d             = 1'b0;
            arlen_counter_clear  = 1'b1;
            snoop_req_o.ac_valid = slv_req_i.ar_valid;
            snoop_req_o.ac.addr  = slv_req_i.ar.addr;
            snoop_req_o.ac.snoop = snoop_info_i.snoop_trs;
            snoop_req_o.ac.prot  = slv_req_i.ar.prot;
            slv_resp_o.ar_ready  = snoop_resp_i.ac_ready;
            if (ac_handshake) begin
                fsm_state_d = SNOOP_RESP;
                load_ar_holder = 1'b1;
            end
        end
        // Receive snoop response
        // Move to receiving CD response or reading from memory
        SNOOP_RESP: begin
            snoop_req_o.cr_ready = 1'b1;
            if (snoop_resp_i.cr_valid) begin
                rresp_d[2] = resp_dirty;
                rresp_d[3] = resp_shared;
                if (snoop_resp_i.cr_resp.DataTransfer) begin
                    if (!snoop_resp_i.cr_resp.Error) begin
                        fsm_state_d          = WRITE_CD;
                        cd_mask_d[MST_R_IDX] = 1'b1;
                        cd_mask_d[MEM_W_IDX] = write_back;
                        aw_valid_d           = write_back;
                    end else begin
                        cd_mask_d   = '1;
                        fsm_state_d = IGNORE_CD;
                    end
                end else begin
                    // No DataTransfer
                    // read from memory
                    fsm_state_d = READ_R;
                    ar_valid_d  = 1'b1;
                end
            end
        end
        // Ignore CD if data is erronous
        IGNORE_CD: begin
            cd_fork_ready = '1;
            snoop_req_o.cd_ready = cd_ready;
            if (cd_handshake && snoop_resp_i.cd.last) begin
                fsm_state_d = READ_R;
                ar_valid_d  = 1'b1;
            end
        end
        // Write CD
        // To memory and/or to initiating master
        WRITE_CD: begin
            arlen_counting    = cd_mask_q[MST_R_IDX];
            mst_req_o.w_valid = cd_fork_valid[MEM_W_IDX] && !aw_valid_q;
            mst_req_o.w.data  = snoop_resp_i.cd.data;
            mst_req_o.w.strb  = '1;
            mst_req_o.w.last  = snoop_resp_i.cd.last;

            slv_resp_o.r.data  = snoop_resp_i.cd.data;
            slv_resp_o.r.resp  = {rresp_q[3:2], 2'b0}; // something has to happen to 2 lsb when atomic
            slv_resp_o.r.last  = r_last;
            slv_resp_o.r_valid = cd_fork_valid[MST_R_IDX] && !r_last_q;
            arlen_counter_en   = r_handshake;

            cd_fork_ready[MEM_W_IDX] = mst_resp_i.w_ready && !aw_valid_q;
            cd_fork_ready[MST_R_IDX] = slv_req_i.r_ready || r_last_q;

            mst_req_o.b_ready    = cd_last_q;
            snoop_req_o.cd_ready = cd_ready;

            if (cd_handshake && snoop_resp_i.cd.last) begin
                cd_last_d = 1'b1;
            end
            if (mst_resp_i.aw_ready) begin
                aw_valid_d = 1'b0;
            end
            if (b_handshake) begin
                // If memory access, end on b handshake
                fsm_state_d = SNOOP_REQ;
            end
            if (r_handshake && r_last && !cd_mask_q[MEM_W_IDX]) begin
                r_last_d    = 1'b1;
                if (cd_handshake && snoop_resp_i.cd.last) begin
                    // Move forward only if it was the last cd sample
                    fsm_state_d = SNOOP_REQ;
                end
            end
            if (cd_handshake && snoop_resp_i.cd.last &&
                r_last_q && !cd_mask_q[MEM_W_IDX]) begin
                // Move forward after all CD data has come
                fsm_state_d = SNOOP_REQ;
            end
        end
        // Read data from memory
        READ_R: begin
            if (mst_resp_i.ar_ready) begin
                ar_valid_d = 1'b0;
            end
            slv_resp_o.r       = mst_resp_i.r;
            slv_resp_o.r_valid = mst_resp_i.r_valid;
            mst_req_o.r_ready  = slv_req_i.r_ready;
            if (r_handshake && slv_resp_o.r.last) begin
                fsm_state_d = SNOOP_REQ;
            end
        end
    endcase
end


// Determine whether write-back is needed and what the
// RRESP[3:2] bits are
always_comb begin
    write_back  = 1'b1;
    resp_shared = 1'b0;
    resp_dirty  = 1'b0;
    case ({snoop_resp_i.cr_resp.PassDirty, snoop_resp_i.cr_resp.IsShared})
        2'b00: begin
            write_back = 1'b0;
        end
        2'b01: begin
            if (snoop_info_holder_q.accepts_shared) begin
                write_back  = 1'b0;
                resp_shared = 1'b1;
            end
        end
        2'b10: begin
            if (snoop_info_holder_q.accepts_dirty) begin
                write_back = 1'b0;
                resp_dirty = 1'b1;
            end
        end
        2'b11: begin
            if (snoop_info_holder_q.accepts_dirty_shared) begin
                write_back  = 1'b0;
                resp_shared = 1'b1;
                resp_dirty  = 1'b1;
            end
        end
    endcase
end

// Fork module to achieve simultaneous write-back and
// R channel response
// index 0: R channel of initiating master
// index 1: W channel of memory
stream_fork_dynamic #(
    .N_OUP(2)
) stream_fork (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .valid_i(snoop_resp_i.cd_valid),
    .ready_o(cd_ready),
    .sel_i(cd_mask_q),
    .sel_valid_i(cd_mask_valid),
    .sel_ready_o(),
    .valid_o(cd_fork_valid),
    .ready_i(cd_fork_ready)
);

// Domain mask generation
// Note: this signal should flow along with AC
always_comb begin
    domain_mask_o = '0;
    case (slv_req_i.ar.domain)
      NonShareable:   domain_mask_o = 0;
      InnerShareable: domain_mask_o = domain_set_i.inner;
      OuterShareable: domain_mask_o = domain_set_i.outer;
      System:         domain_mask_o = ~domain_set_i.initiator;
    endcase
end


endmodule
