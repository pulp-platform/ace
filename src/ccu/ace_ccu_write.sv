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
    parameter ace_ccu_cfg_t CcuCfg   = '{default: '0},
    parameter type          ccu_ax_t = logic,
    parameter type          tid_t    = logic,
    parameter type          ccu_aw_t = logic,
    parameter type          w_t      = logic,
    parameter type          ccu_b_t  = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // Ctrl
    input  logic    valid_i,
    output logic    ready_o,
    input  ccu_ax_t ax_i,
    input  logic    ax_is_write_i,
    input  logic    ax_is_writeback_i,
    input  tid_t    ax_tid_i,

    output logic tracker_updt_wb_o,
    output tid_t tracker_updt_wb_tid_o,
    input  logic b_is_writeback_i,

    // Slv interface
    input  w_t      w_i,
    input  logic    w_valid_i,
    output logic    w_ready_o,
    input  w_t      cd_w_i,
    input  logic    cd_w_valid_i,
    output logic    cd_w_ready_o,
    output ccu_b_t  b_o,
    output logic    b_valid_o,
    input  logic    b_ready_i,
    // Mst interface
    output ccu_aw_t aw_o,
    output logic    aw_valid_o,
    input  logic    aw_ready_i,
    output w_t      w_o,
    output logic    w_valid_o,
    input  logic    w_ready_i,
    input  ccu_b_t  b_i,
    input  logic    b_valid_i,
    output logic    b_ready_o
);
    //  Typedefs
    //  {{{
    typedef struct packed {
        ccu_ax_t ax;
        logic    ax_is_write;
        logic    ax_is_writeback;
        tid_t    ax_tid;
    } aw_sync_reg_t;
    //  }}}

    //  Internal signals
    //  {{{
    aw_sync_reg_t aw_sync_wdata;
    aw_sync_reg_t aw_sync_rdata;
    logic         aw_sync_valid;
    logic         aw_sync_ready;
    logic         aw_sync_gate;
    logic         aw_is_writeback;
    logic         aw_writeback_done_d;
    logic         aw_writeback_done_q;

    logic         w_ctrl_fifo_valid_in;
    logic         w_ctrl_fifo_ready_in;
    logic         w_ctrl_fifo_valid_out;
    logic         w_ctrl_fifo_ready_out;
    logic         w_mux_valid_out;
    logic         w_mux_ready_out;
    logic         w_is_write_back;
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
        .ready_i   (aw_sync_ready && !aw_sync_gate),
        .data_o    (aw_sync_rdata)
    );

    assign tracker_updt_wb_tid_o = aw_sync_rdata.ax_tid;

    always_comb begin : aw_writeback_fsm_comb
        aw_writeback_done_d = aw_writeback_done_q;
        aw_is_writeback     = 1'b0;
        aw_sync_gate        = 1'b0;

        tracker_updt_wb_o   = 1'b0;

        if (!aw_writeback_done_q) begin
            if (aw_sync_rdata.ax_is_writeback) begin
                // A writeback is pending
                aw_is_writeback = 1'b1;
                if (aw_sync_valid && aw_sync_ready) begin
                    // The writeback request is done
                    tracker_updt_wb_o = 1'b1;
                    if (aw_sync_rdata.ax_is_write) begin
                        // A write is also pending
                        aw_writeback_done_d = 1'b1;
                        aw_sync_gate        = 1'b1;
                    end
                end
            end
        end else begin
            // Send the pending write after the writeback
            if (aw_sync_valid && aw_sync_ready) begin
                aw_writeback_done_d = 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_writeback_done_q <= 1'b0;
        end else begin
            aw_writeback_done_q <= aw_writeback_done_d;
        end
    end

    always_comb begin : aw_mux_comb
        aw_o = '0;

        `AXI_SET_AW_STRUCT(aw_o, aw_sync_rdata.ax)

        if (aw_is_writeback) begin
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
        .valid_i(aw_sync_valid),
        .ready_o(aw_sync_ready),
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
        .drop_i (b_is_writeback_i),
        .valid_o(b_valid_o),
        .ready_i(b_ready_i)
    );

    `AXI_ASSIGN_B_STRUCT(b_o, b_i)
    //  }}}

endmodule
