import ace_pkg::*;
import ccu_ctrl_pkg::*;

module ccu_ctrl_wr_snoop #(
    /// Request channel type towards cached master
    parameter type slv_req_t         = logic,
    /// Response channel type towards cached master
    parameter type slv_resp_t        = logic,
    /// Request channel type towards memory
    parameter type mst_req_t         = logic,
    /// Response channel type towards memory
    parameter type mst_resp_t        = logic,
    /// AW channel type towards memoryy
    parameter type mst_aw_chan_t     = logic,
    /// W channel type towards memory
    parameter type mst_w_chan_t      = logic,
    /// B channel type towards memory
    parameter type mst_b_chan_t      = logic,
    /// AW channel type towards cached master
    parameter type slv_aw_chan_t     = logic,
    /// W channel type towards cached master
    parameter type slv_w_chan_t      = logic,
    /// B channel type towards cached master
    parameter type slv_b_chan_t      = logic,
    /// Snoop AC channel type
    parameter type mst_ac_t          = logic,
    /// Snoop request type
    parameter type mst_snoop_req_t   = logic,
    /// Snoop response type
    parameter type mst_snoop_resp_t  = logic
) (
    /// Clock
    input                               clk_i,
    /// Reset
    input                               rst_ni,
    /// Request channel towards cached master
    input  slv_req_t                    slv_req_i,
    /// Decoded snoop transaction
    input  acsnoop_t                    snoop_trs_i,
    /// Response channel towards cached master
    output slv_resp_t                   slv_req_o,
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
logic snoop_trs;

slv_aw_chan_t aw_holder_q;
logic load_aw_holder;
acsnoop_t snoop_trs_holder_d, snoop_trs_holder_q;
logic aw_holder_valid, aw_holder_ready, w_holder_valid, w_holder_ready;
logic ac_start;
logic ac_handshake, cd_handshake;
logic aw_valid_d, aw_valid_q;

typedef enum logic [1:0] { SNOOP_REQ, SNOOP_RESP, WRITE_CD, WRITE_W } wr_fsm_t;
wr_fsm_t fsm_state_d, fsm_state_q;

assign snoop_req_o.ac_addr  = aw_holder.addr;
assign snoop_req_o.ac_prot  = aw_holder.prot;
assign snoop_req_o.ac_snoop = snoop_trs_i;
assign snoop_req_o.ac_valid = slv_req_i.aw_valid && ac_start;

assign slv_resp_o.aw_ready  = snoop_req_i.ac_ready && ac_start;

assign snoop_req_o.ac_addr = slv_req_i.aw.addr;

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        fsm_state_q <= SNOOP_REQ;
        aw_valid_q  <= 1'b0;
    end else begin
        fsm_state_q <= fsm_state_d;
        aw_valid_q  <= aw_valid_d;
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

// Connect to memory request
always_comb begin
    mst_req_o.aw = aw_holder_q;
    mst_req_o.w  = slv_req_i.w;
    mst_req_o.b_ready = slv_req_i.b_ready;
    slv_resp_o.b = mst_resp_i.b;
    if (fsm_state_q == WRITE_CD) begin
        // Snooped data is provided wrap-bursted
        mst_req_o.aw.burst = axi_pkg::BURST_WRAP;
        mst_req_o.w_valid    = snoop_resp_i.cd_valid;
        mst_req_o.w.data     = snoop_resp_i.cd.data;
        mst_req_o.w.strb     = '1;
        mst_req_o.w.last     = snoop_resp_i.cd.last;
        mst_req_o.w.user     = '0; // What to put here?
        mst_req_o.b_ready = 1'b1;
    end
end


always_comb begin
    ac_start = 1'b0;
    aw_valid_d = aw_valid_q;
    fsm_state_d = fsm_state_q;
    snoop_req_o.ac_valid = 1'b0;
    snoop_req_o.cr_ready = 1'b0;
    snoop_req_o.cd_ready = 1'b0;
    slv_resp_o.aw_ready  = 1'b0;
    mst_req_o.w_valid    = 1'b0;
    load_aw_holder       = 1'b0;
    slv_resp_o.aw_ready  = 1'b0;

    case(fsm_state_q)
        SNOOP_REQ: begin
            snoop_req_o.ac_valid = slv_req_i.aw_valid;
            slv_resp_o.aw_ready  = snoop_resp_i.ac_ready;
            if (ac_handshake) begin
                fsm_state_d    = SNOOP_RESP;
                load_aw_holder = 1'b1;
            end
        end
        SNOOP_RESP: begin
            snoop_req_o.cr_ready = 1'b1;
            if (snoop_req_i.cr_valid) begin
                aw_valid_d = 1'b1;
                if (snoop_req_i.cr_resp.DataTransfer
                    && !snoop_req_i.cr_resp.Error) begin
                    fsm_state_d = WRITE_CD;
                end else begin
                    fsm_state_d = WRITE_W;
                end
            end
        end
        WRITE_CD: begin
            if (mst_resp_i.aw_ready) begin
                aw_valid_d = 1'b0;
            end
            snoop_req_o.cd_ready = mst_resp_i.w_ready;
            mst_req_o.w_valid    = snoop_resp_i.cd_valid;
            // TODO: monitor B handshakes outside the FSM
            if (b_handshake) begin
                aw_valid_d  = 1'b1;
                fsm_state_d = WRITE_W;
            end
        end
        WRITE_W: begin
            if (mst_resp_i.aw_ready) begin
                aw_valid_d = 1'b0;
            end
            if (b_handshake) begin
                fsm_state_d = SNOOP_REQ;
            end
        end
    endcase
end

endmodule