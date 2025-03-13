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

module ace_ccu_snoop_resp #(
    parameter int unsigned NumOup = 1,           // Number of outputs
    parameter type cr_chan_t      = logic,       // Type for Control Response channel
    parameter type cd_chan_t      = logic,       // Type for Data Response channel
    parameter type ctrl_t         = logic        // Ctrl data type
) (
    input  logic clk_i,                              // Clock input
    input  logic rst_ni,                             // Active-low reset

    // Control Response (CR) inputs and outputs per output
    input  logic     [NumOup-1:0] cr_valids_i,       // CR valid signals from outputs
    output logic     [NumOup-1:0] cr_readies_o,      // CR ready signals to outputs
    input  cr_chan_t [NumOup-1:0] cr_chans_i,        // CR data from outputs

    // Data Response (CD) inputs and outputs per output
    input  logic     [NumOup-1:0] cd_valids_i,       // CD valid signals from outputs
    output logic     [NumOup-1:0] cd_readies_o,      // CD ready signals to outputs
    input  cd_chan_t [NumOup-1:0] cd_chans_i,        // CD data from outputs

    // Control flow
    input  ctrl_t    ctrl_i,                         // Control signals
    input  logic     ctrl_valid_i,                   // Control valid signal
    output logic     ctrl_ready_o,                   // Control ready signal

    // Combined CR and CD outputs
    output logic     cr_valid_o,                     // Combined CR valid output
    input  logic     cr_ready_i,                     // Combined CR ready input
    output cr_chan_t cr_chan_o,                      // Combined CR data output
    output ctrl_t    cr_ctrl_o,                      // Combined CR ctrl output
    output logic     cd_valid_o,                     // Combined CD valid output
    input  logic     cd_ready_i,                     // Combined CD ready input
    output cd_chan_t cd_chan_o,                      // Combined CD data output
    output ctrl_t    cd_ctrl_o                       // Combined CD ctrl output
);

    // Index type based on the number of outputs
    typedef logic [$clog2(NumOup)-1:0] oup_idx_t;

    logic cr_sel_valid, cr_sel_ready;
    logic cd_sel_valid, cd_sel_ready;
    logic [NumOup-1:0] cd_sel_valids, cd_sel_readies;

    logic [NumOup-1:0] cr_valids, cr_readies;
    logic [NumOup-1:0] cd_valids, cd_readies;
    logic [NumOup-1:0] to_cd_mux_valids, from_cd_mux_readies;

    logic [NumOup-1:0] fr_one_hot;
    oup_idx_t fr_d, fr_q;
    logic fr_lock_d, fr_lock_q;
    oup_idx_t lowest_index_responder;
    logic set_fr, clear_fr;

    assign cr_ctrl_o = ctrl_i;

    for (genvar j = 0; j < NumOup; j++) begin : gen_chan

        logic cr_data_transfer;
        logic cd_last;

        logic dt_valid, dt_ready;

        logic to_dt_filter_valid, from_dt_filter_ready;
        logic to_cd_join_valid, from_cd_join_ready;

        logic cd_sel_lock_valid, cd_sel_lock_ready;

        assign cr_data_transfer = cr_chans_i[j].DataTransfer;
        assign cd_last = cd_chans_i[j].last;

        stream_fork #(
            .N_OUP (2)
        ) i_cr_fork (
            .clk_i       (clk_i),
            .rst_ni      (rst_ni),
            .valid_i     (cr_valids_i[j]),
            .ready_o     (cr_readies_o[j]),
            .valid_o     ({cr_valids[j], dt_valid}),
            .ready_i     ({cr_readies[j], dt_ready})
        );

        stream_join #(
            .N_INP (2)
        ) i_cd_ctrl_handshake (
            .inp_valid_i ({cd_sel_valids[j], dt_valid}),
            .inp_ready_o ({cd_sel_readies[j], dt_ready}),
            .oup_valid_o (to_dt_filter_valid),
            .oup_ready_i (from_dt_filter_ready)
        );

        stream_filter i_dt_filter (
            .valid_i (to_dt_filter_valid),
            .ready_o (from_dt_filter_ready),
            .drop_i  (!cr_data_transfer),
            .valid_o (to_cd_join_valid),
            .ready_i (from_cd_join_ready && cd_last)
        );

        stream_join #(
            .N_INP (2)
        ) i_cd_handshake (
            .inp_valid_i ({to_cd_join_valid, cd_valids_i[j]}),
            .inp_ready_o ({from_cd_join_ready, cd_readies_o[j]}),
            .oup_valid_o (cd_valids[j]),
            .oup_ready_i (cd_readies[j])
        );

        stream_filter i_fr_filter (
            .valid_i (cd_valids[j]),
            .ready_o (cd_readies[j]),
            .drop_i  (!fr_one_hot[j]),
            .valid_o (to_cd_mux_valids[j]),
            .ready_i (from_cd_mux_readies[j])
        );

    end

    stream_join_dynamic #(
        .N_INP (NumOup+1)
    ) i_cr_handshake (
        .inp_valid_i ({cr_sel_valid, cr_valids}),
        .inp_ready_o ({cr_sel_ready, cr_readies}),
        .sel_i       ({1'b1, cr_ctrl_o.sel}),
        .oup_valid_o (cr_valid_o),
        .oup_ready_i (cr_ready_i)
    );

    // Combine CR channels from all outputs
    always_comb begin
        cr_chan_o = '0;
        for (int unsigned i = 0; i < NumOup; i++) begin
            if (cr_ctrl_o.sel[i]) begin
                cr_chan_o.WasUnique    |= cr_chans_i[i].WasUnique;
                cr_chan_o.IsShared     |= cr_chans_i[i].IsShared;
                cr_chan_o.PassDirty    |= cr_chans_i[i].PassDirty;
                cr_chan_o.Error        |= cr_chans_i[i].Error;
                cr_chan_o.DataTransfer |= cr_chans_i[i].DataTransfer;
            end
        end
    end

    stream_fork #(
        .N_OUP (2)
    ) i_sel_fork (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .valid_i     (ctrl_valid_i),
        .ready_o     (ctrl_ready_o),
        .valid_o     ({cr_sel_valid, cd_sel_lock_valid}),
        .ready_i     ({cr_sel_ready, cd_sel_lock_ready})
    );

    ace_ccu_lock_reg #(
        .dtype (ctrl_t)
    ) i_cd_sel_lock (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .valid_i    (cd_sel_lock_valid),
        .ready_o    (cd_sel_lock_ready),
        .data_i     (cr_ctrl_o),
        .valid_o    (cd_sel_valid),
        .ready_i    (cd_sel_ready),
        .data_o     (cd_ctrl_o)
    );

    stream_fork_dynamic #(
        .N_OUP (NumOup)
    ) i_cd_sel_fork (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .valid_i     (cd_sel_valid),
        .ready_o     (cd_sel_ready),
        .sel_i       (cd_ctrl_o.sel),
        .sel_valid_i (cd_sel_valid),
        .sel_ready_o (),
        .valid_o     (cd_sel_valids),
        .ready_i     (cd_sel_readies)
    );

    // Find the lowest index responder
    always_comb begin
        lowest_index_responder = '0;
        set_fr = 1'b0;
        for (int unsigned i = 0; i < NumOup; i++) begin
            if (cd_valids[i]) begin
                lowest_index_responder = oup_idx_t'(i);
                set_fr = 1'b1;
                break;
            end
        end
    end

    assign clear_fr = cd_sel_valid && cd_sel_ready;

    always_comb begin
        fr_d      = fr_q;
        fr_lock_d = fr_lock_q;

        if (fr_lock_q) begin
            if (clear_fr) begin
                fr_lock_d = 1'b0;
            end
        end else if (set_fr) begin
            fr_lock_d = 1'b1;
            fr_d      = lowest_index_responder;
        end
    end

    always_comb begin
        fr_one_hot = '0;
        fr_one_hot[fr_d] = 1'b1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fr_q      <= '0;
            fr_lock_q <= 1'b0;
        end else begin
            fr_q      <= fr_d;
            fr_lock_q <= fr_lock_d;
        end
    end

    stream_mux #(
        .DATA_T (cd_chan_t),
        .N_INP  (NumOup)
    ) i_cd_mux (
        .inp_data_i   (cd_chans_i),
        .inp_valid_i  (to_cd_mux_valids),
        .inp_ready_o  (from_cd_mux_readies),
        .inp_sel_i    (fr_d),
        .oup_data_o   (cd_chan_o),
        .oup_valid_o  (cd_valid_o),
        .oup_ready_i  (cd_ready_i)
    );

endmodule
