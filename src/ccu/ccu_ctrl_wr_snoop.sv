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

slv_aw_chan_t aw_holder, w_holder;
acsnoop_t snoop_trs_holder;
logic aw_holder_valid, aw_holder_ready, w_holder_valid, w_holder_ready;
logic ac_start;

typedef enum logic [1:0] { SNOOP_REQ, SNOOP_RESP, WRITE_CD, WRITE_W } wr_fsm_t;
wr_fsm_t fsm_state_d, fsm_state_q;

// Store AW data
spill_register #(
    .T       (slv_aw_chan_t),
    .Bypass  (1'b1)
) aw_spill_register (
    .clk_i,
    .rst_ni,
    .valid_i (slv_req_o.aw_valid),
    .ready_o (slv_resp_o.aw_ready),
    .data_i  (slv_req_i.aw),
    .valid_o (aw_holder_valid),
    .ready_i (aw_holder_ready),
    .data_o  (aw_holder)
);

// Store W data
spill_register #(
    .T       (slv_w_chan_t),
    .Bypass  (1'b1)
) w_spill_register (
    .clk_i,
    .rst_ni,
    .valid_i (slv_req_o.w_valid),
    .ready_o (slv_resp_o.w_ready),
    .data_i  (slv_req_i.w),
    .valid_o (w_holder_valid),
    .ready_i (w_holder_ready),
    .data_o  (w_holder)
);

// Store decoded snoop transaction
spill_register #(
    .T       (acsnoop_t),
    .Bypass  (1'b1)
) snoop_trs_spill_register (
    .clk_i,
    .rst_ni,
    .valid_i (slv_req_o.aw_valid),
    .ready_o (slv_resp_o.aw_ready),
    .data_i  (snoop_trs_i),
    .valid_o (aw_holder_valid),
    .ready_i (aw_holder_ready),
    .data_o  (snoop_trs_holder)
);

assign snoop_req_o.ac_addr  = aw_holder.addr;
assign snoop_req_o.ac_prot  = aw_holder.prot;
assign snoop_req_o.ac_snoop = snoop_trs_holder;
assign snoop_req_o.ac_valid = aw_holder_valid && ac_start;
assign aw_holder_ready = snoop_req_i.ac_ready && ac_start;

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        fsm_state_q <= SNOOP_REQ;
    end else begin
        fsm_state_q <= fsm_state_d;
    end
end


always_comb begin
    ac_start = 1'b0;
    fsm_state_d = SNOOP_REQ;
    snoop_req_o.cr_ready = 1'b0;
    snoop_req_o.cd_ready = 1'b0;
    case(fsm_state_q)
        SNOOP_REQ: begin
            ac_start = 1'b1;
            fsm_state_d = snoop_req_i.ac_ready ? SNOOP_RESP : SNOOP_REQ;
        end
        SNOOP_RESP: begin
            snoop_req_o.cr_ready = 1'b1;
            if (snoop_req_i.cr_valid) begin
                if (snoop_req_i.cr_resp.DataTransfer) begin
                    fsm_state_d = WRITE_CD;
                end else begin
                    fsm_state_d = WRITE_W;
                end
            end
        end
        WRITE_CD: begin
            snoop_req_o.cd_ready = 1'b1;
            
        end
        WRITE_W: begin
            snoop_req_o.cd_ready = 1'b1;
        end
    endcase
end

endmodule