// Copyright (c) 2025 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`include "axi/assign.svh"

module ace_ccu_write
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg       = '{default: '0},
    parameter type          midend_ax_t  = logic,
    parameter type          tid_t        = logic,
    parameter type          backend_aw_t = logic,
    parameter type          w_t          = logic,
    parameter type          midend_b_t   = logic,
    parameter type          backend_b_t  = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // Ctrl
    input  logic        valid_i,
    output logic        ready_o,
    input  midend_ax_t  ax_i,
    input  logic        ax_is_write_i,
    input  logic        ax_is_writeback_i,
    input  tid_t        ax_tid_i,
    // Slv interface
    input  w_t          w_i,
    input  logic        w_valid_i,
    output logic        w_ready_o,
    input  w_t          cd_w_i,
    input  logic        cd_w_valid_i,
    output logic        cd_w_ready_o,
    output midend_b_t   b_o,
    output logic        b_valid_o,
    input  logic        b_ready_i,
    // Mst interface
    output backend_aw_t aw_o,
    output logic        aw_valid_o,
    input  logic        aw_ready_i,
    output w_t          w_o,
    output logic        w_valid_o,
    input  logic        w_ready_i,
    input  backend_b_t  b_i,
    input  logic        b_valid_i,
    output logic        b_ready_o
);
    //  Typedefs
    //  {{{
    typedef struct packed {
        midend_ax_t ax;
        logic       ax_is_write;
        logic       ax_is_writeback;
        tid_t       ax_tid;
    } aw_sync_reg_t;

    typedef enum {
        AW_FSM_IDLE,
        AW_FSM_WAIT_B_RESP,
        AW_FSM_PASSTHROUGH
    } aw_fsm_e;
    //  }}}

    //  Internal signals
    //  {{{
    aw_sync_reg_t aw_sync_wdata;
    aw_sync_reg_t aw_sync_rdata;
    logic         aw_sync_valid;
    logic         aw_sync_ready;
    logic         aw_fsm_valid;
    logic         aw_fsm_ready;
    logic         aw_is_writeback;
    aw_fsm_e      aw_fsm_d;
    aw_fsm_e      aw_fsm_q;

    logic         w_ctrl_fifo_valid_in;
    logic         w_ctrl_fifo_ready_in;
    logic         w_ctrl_fifo_valid_out;
    logic         w_ctrl_fifo_ready_out;
    logic         w_mux_valid_out;
    logic         w_mux_ready_out;
    logic         w_is_write_back;
    logic         b_is_write_back;
    //  }}}

    //  AW channel
    //  {{{

    // Decouple AW handling from snoop pipe
    assign aw_sync_wdata = '{
            ax: ax_i,
            ax_is_write: ax_is_write_i,
            ax_is_writeback: ax_is_writeback_i,
            ax_tid: ax_tid_i
        };

    fall_through_register #(
        .T(aw_sync_reg_t)
    ) u_aw_sync_reg (
        .clk_i,
        .rst_ni,
        .clr_i     (1'b0),
        .testmode_i(1'b0),
        .valid_i   (valid_i),
        .ready_o   (ready_o),
        .data_i    (aw_sync_wdata),
        .valid_o   (aw_sync_valid),
        .ready_i   (aw_sync_ready),
        .data_o    (aw_sync_rdata)
    );

    always_comb begin : aw_writeback_fsm_comb
        aw_fsm_d        = aw_fsm_q;

        aw_is_writeback = 1'b0;
        aw_fsm_valid    = aw_sync_valid;
        aw_sync_ready   = aw_fsm_ready;

        case (aw_fsm_q)
            AW_FSM_IDLE: begin
                if (aw_sync_rdata.ax_is_writeback) begin
                    // A writeback is pending
                    aw_is_writeback = 1'b1;
                    if (aw_fsm_valid && aw_fsm_ready) begin
                        // The writeback request is done
                        if (aw_sync_rdata.ax_is_write) begin
                            // A write is also pending
                            aw_fsm_d      = AW_FSM_WAIT_B_RESP;
                            aw_sync_ready = 1'b0;
                        end
                    end
                end
            end
            AW_FSM_WAIT_B_RESP: begin
                aw_fsm_valid  = 1'b0;
                aw_sync_ready = 1'b0;

                if (b_valid_i && b_ready_o && {1'b1, aw_sync_rdata.ax.id} == b_i.id) begin
                    // The writeback response is received
                    // The pending  write can be sent
                    aw_fsm_d = AW_FSM_PASSTHROUGH;
                end
            end
            AW_FSM_PASSTHROUGH: begin
                // Let the handshake complete
                if (aw_fsm_valid && aw_fsm_ready) begin
                    aw_fsm_d = AW_FSM_IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_fsm_q <= AW_FSM_IDLE;
        end else begin
            aw_fsm_q <= aw_fsm_d;
        end
    end

    always_comb begin : aw_mux_comb
        aw_o = '0;

        `AXI_SET_AW_STRUCT(aw_o, aw_sync_rdata.ax)

        if (aw_is_writeback) begin
            // Use the MSB ID bit to indicate a writeback
            aw_o.id[CcuCfg.AxiBackendIdWidth-1] = 1'b1;
            // Pass a full cacheline
            aw_o.addr = axi_pkg::aligned_addr(aw_sync_rdata.ax.addr, CcuCfg.CachelineBytesIdxWidth);
            aw_o.len = CcuCfg.CachelineAxiTransfers - 1;
            aw_o.size = CcuCfg.AxiDataBytesIdxWidth;
            // Burst type for write backs
            aw_o.burst = axi_pkg::BURST_WRAP;
            // The write back is not atomic
            aw_o.lock = 1'b0;
            aw_o.atop = '0;
        end
    end

    stream_fork #(
        .N_OUP(2)
    ) u_aw_fork (
        .clk_i,
        .rst_ni,
        .valid_i(aw_fsm_valid),
        .ready_o(aw_fsm_ready),
        .valid_o({aw_valid_o, w_ctrl_fifo_valid_in}),
        .ready_i({aw_ready_i, w_ctrl_fifo_ready_in})
    );
    //  }}}


    //  W channel
    //  {{{
    stream_fifo #(
        .FALL_THROUGH(1'b1),
        .DATA_WIDTH  (1),
        .DEPTH       (2)
    ) u_w_ctrl_fifo (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .usage_o   (),
        .data_i    (aw_is_writeback),
        .valid_i   (w_ctrl_fifo_valid_in),
        .ready_o   (w_ctrl_fifo_ready_in),
        .data_o    (w_is_write_back),
        .valid_o   (w_ctrl_fifo_valid_out),
        .ready_i   (w_ctrl_fifo_ready_out && w_o.last)
    );

    stream_mux #(
        .DATA_T(w_t),
        .N_INP (2)
    ) u_w_mux (
        .inp_data_i ({cd_w_i, w_i}),
        .inp_valid_i({cd_w_valid_i, w_valid_i}),
        .inp_ready_o({cd_w_ready_o, w_ready_o}),
        .inp_sel_i  (w_is_write_back),
        .oup_data_o (w_o),
        .oup_valid_o(w_mux_valid_out),
        .oup_ready_i(w_mux_ready_out)
    );

    stream_join #(
        .N_INP(2)
    ) u_w_join (
        .inp_valid_i({w_ctrl_fifo_valid_out, w_mux_valid_out}),
        .inp_ready_o({w_ctrl_fifo_ready_out, w_mux_ready_out}),
        .oup_valid_o(w_valid_o),
        .oup_ready_i(w_ready_i)
    );
    //  }}}

    //  B channel
    //  {{{
    stream_filter u_b_filter (
        .valid_i(b_valid_i),
        .ready_o(b_ready_o),
        .drop_i (b_is_write_back),
        .valid_o(b_valid_o),
        .ready_i(b_ready_i)
    );

    assign b_is_write_back = b_i.id[CcuCfg.AxiBackendIdWidth-1];

    `AXI_ASSIGN_B_STRUCT(b_o, b_i)
    //  }}}

endmodule
