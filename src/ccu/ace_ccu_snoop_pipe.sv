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

module ace_ccu_snoop_pipe
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg        = '{default: '0},
    parameter type          domain_rule_t = logic,
    parameter type          midend_aw_t   = logic,
    parameter type          midend_ar_t   = logic,
    parameter type          midend_ax_t   = logic,
    parameter type          midend_id_t   = logic,
    parameter type          ac_t          = logic,
    parameter type          cr_t          = logic,
    parameter type          slv_bv_t      = logic,
    parameter type          slv_idx_t     = logic,
    parameter type          tid_t         = logic,
    parameter type          nline_t       = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  midend_aw_t st0_aw_i,
    input  logic       st0_aw_valid_i,
    output logic       st0_aw_ready_o,

    input  midend_ar_t st0_ar_i,
    input  logic       st0_ar_valid_i,
    output logic       st0_ar_ready_o,

    input  midend_ar_t st0_replay_ar_i,
    input  logic       st0_replay_ar_valid_i,
    output logic       st0_replay_ar_ready_o,

    output ac_t     st0_ac_o,
    output slv_bv_t st0_ac_bv_o,
    output logic    st0_ac_valid_o,
    input  logic    st0_ac_ready_i,

    input  cr_t     st1_cr_i,
    output slv_bv_t st1_cr_bv_o,
    input  logic    st1_cr_valid_i,
    output logic    st1_cr_ready_o,

    input  logic st0_replay_full_i,
    output logic st0_replay_check_o,
    input  logic st0_replay_hit_i,
    output logic st0_replay_alloc_o,

    input  logic       st0_tracker_full_i,
    output logic       st0_tracker_check_o,
    input  logic       st0_tracker_check_hit_i,
    output logic       st0_tracker_alloc_o,
    output logic       st0_tracker_alloc_b_o,
    output logic       st0_tracker_alloc_r_o,
    output nline_t     st0_tracker_alloc_nline_o,
    output midend_id_t st0_tracker_alloc_id_o,
    input  tid_t       st0_tracker_alloc_tid_i,

    input domain_rule_t [CcuCfg.u.SlvPorts-1:0] st0_domain_rule_i,

    output midend_ax_t st1_ax_o,
    output logic       st1_ax_is_write_o,
    output logic       st1_r_resp_shared_o,
    output logic       st1_r_resp_dirty_o,
    output tid_t       st1_ax_tid_o,
    output logic       st1_cd_ctrl_write_o,
    output logic       st1_cd_ctrl_read_o,
    output logic       st1_write_valid_o,
    input  logic       st1_write_ready_i,
    output logic       st1_read_valid_o,
    input  logic       st1_read_ready_i,
    output logic       st1_cd_ctrl_valid_o,
    input  logic       st1_cd_ctrl_ready_i,

    output logic evt_st0_stall_o,
    output logic evt_st1_stall_o
);
    //  Typedefs
    //  {{{
    typedef struct packed {
        logic       ax_is_write;
        logic       ar_accepts_dirty;
        logic       ar_accepts_dirty_shared;
        logic       ar_accepts_shared;
        slv_bv_t    cr_bv;
        tid_t       tid;
        midend_ax_t ax;
    } st1_t;
    //  }}}

    //  Internal signals
    //  {{{
    midend_ax_t st0_ax;
    logic       st0_ax_valid;
    logic       st0_ax_ready;
    logic       st0_ax_is_write;
    acsnoop_t   st0_ax_acsnoop;
    axdomain_t  st0_ax_domain;
    logic       st0_ar_accepts_dirty;
    logic       st0_ar_accepts_dirty_shared;
    logic       st0_ar_accepts_shared;
    logic       st0_pipe_valid;
    logic       st0_pipe_ready;
    logic       st0_hazard;
    logic       st0_replay;
    slv_idx_t   st0_slv_idx;
    st1_t       st0_pipe;

    logic       st1_pipe_valid;
    logic       st1_pipe_ready;
    st1_t       st1;
    logic       st1_valid;
    logic       st1_ready;
    logic       st1_r_resp_shared;
    logic       st1_r_resp_dirty;
    logic       st1_aw_sel;
    logic       st1_ar_sel;
    logic       st1_cd_sel;
    logic       st1_cd_write;
    logic       st1_cd_read;
    // }}}

    //  AX arbiter
    //  {{{
    ace_ccu_ax_arbiter #(
        .CcuCfg     (CcuCfg),
        .midend_aw_t(midend_aw_t),
        .midend_ar_t(midend_ar_t),
        .midend_ax_t(midend_ax_t)
    ) u_st0_ax_arbiter (
        .clk_i,
        .rst_ni,
        .replay_full_i            (st0_replay_full_i),
        .aw_i                     (st0_aw_i),
        .aw_valid_i               (st0_aw_valid_i),
        .aw_ready_o               (st0_aw_ready_o),
        .ar_i                     (st0_ar_i),
        .ar_valid_i               (st0_ar_valid_i),
        .ar_ready_o               (st0_ar_ready_o),
        .replay_ar_i              (st0_replay_ar_i),
        .replay_ar_valid_i        (st0_replay_ar_valid_i),
        .replay_ar_ready_o        (st0_replay_ar_ready_o),
        .ax_o                     (st0_ax),
        .ax_valid_o               (st0_ax_valid),
        .ax_ready_i               (st0_ax_ready),
        .ax_is_write_o            (st0_ax_is_write),
        .ax_is_replay_o           (st0_ax_is_replay),
        .ax_acsnoop_o             (st0_ax_acsnoop),
        .ar_accepts_dirty_o       (st0_ar_accepts_dirty),
        .ar_accepts_dirty_shared_o(st0_ar_accepts_dirty_shared),
        .ar_accepts_shared_o      (st0_ar_accepts_shared),
        .ax_domain_o              (st0_ax_domain)
    );
    //  }}}

    //  Stage 0
    //  {{{
    always_comb begin : hazard_comb
        st0_hazard          = 1'b1;
        st0_replay          = 1'b0;

        st0_tracker_check_o = 1'b0;
        st0_replay_check_o  = 1'b0;

        if (!st0_tracker_full_i && st0_pipe_ready) begin
            // Check if there is any conflict on nline or ID (tracker)
            st0_tracker_check_o = 1'b1;
            if (st0_ax_is_write) begin
                // The AX originates from AW
                if (st0_tracker_check_hit_i) begin
                    // Writes are not replayable
                    // nline conflict cause head of line stalling
                    // Resolution of conflicts happens by draining
                    // the downstream buffers
                end else begin
                    // The write is clear to go
                    st0_hazard = 1'b0;
                end
            end else begin
                // The AX originates from AR
                // Check also if there is any conflict on ID (replay)
                st0_replay_check_o = !st0_ax_is_replay;
                if (!st0_tracker_check_hit_i && !st0_replay_hit_i) begin
                    // No conflict is detected
                    st0_hazard = 1'b0;
                end else if (CcuCfg.u.ReplayEn) begin
                    // Reads are replayable
                    // ID or nline conflict is avoided by putting the request on hold
                    st0_replay = 1'b1;
                end
            end
        end
    end

    // Handshaking logic
    assign st0_ac_valid_o = st0_hazard ? 1'b0 : st0_ax_valid;
    assign st0_ax_ready = st0_hazard ? st0_replay : st0_ac_ready_i;
    // Allocations
    assign st0_tracker_alloc_o = st0_ax_valid && st0_ax_ready && !st0_replay;
    assign st0_tracker_alloc_b_o = st0_ax_is_write;
    assign st0_tracker_alloc_r_o = !st0_ax_is_write || st0_ax.atop[axi_pkg::ATOP_R_RESP];
    assign st0_tracker_alloc_nline_o = st0_ax.addr[CcuCfg.CachelineBytesIdxWidth+:CcuCfg.u.NLineWidth];
    assign st0_tracker_alloc_id_o = st0_ax.id;
    assign st0_replay_alloc_o = st0_ax_valid && st0_ax_ready && st0_replay;

    assign st0_pipe_valid = st0_ac_valid_o && st0_ac_ready_i;

    assign st0_slv_idx = st0_ax.id[CcuCfg.AxiMidendIdWidth-1 : CcuCfg.u.AxiSlvIdWidth];

    always_comb begin : ac_bv_comb
        unique case (st0_ax_domain)
            InnerShareable: st0_ac_bv_o = st0_domain_rule_i[st0_slv_idx].inner;
            OuterShareable: st0_ac_bv_o = st0_domain_rule_i[st0_slv_idx].outer;
            System:         st0_ac_bv_o = ~st0_domain_rule_i[st0_slv_idx].initiator;
            default:        st0_ac_bv_o = '0;
        endcase
    end

    assign st0_ac_o = '{
            addr: axi_pkg::aligned_addr(st0_ax.addr, CcuCfg.CachelineBytesIdxWidth),
            snoop: st0_ax_acsnoop,
            prot: '0
        };

    assign st0_pipe = '{
            ax_is_write: st0_ax_is_write,
            ar_accepts_dirty: st0_ar_accepts_dirty,
            ar_accepts_dirty_shared: st0_ar_accepts_dirty_shared,
            ar_accepts_shared: st0_ar_accepts_shared,
            cr_bv: st0_ac_bv_o,
            tid: st0_tracker_alloc_tid_i,
            ax: st0_ax
        };
    // }}}

    //  Stage 1
    //  {{{
    spill_register #(
        .T     (st1_t),
        .Bypass(1'b0)
    ) u_st1_pipe_reg (
        .clk_i,
        .rst_ni,
        .valid_i(st0_pipe_valid),
        .ready_o(st0_pipe_ready),
        .data_i (st0_pipe),
        .valid_o(st1_valid),
        .ready_i(st1_ready),
        .data_o (st1)
    );

    stream_join #(
        .N_INP(2)
    ) u_st1_join (
        .inp_valid_i({st1_valid, st1_cr_valid_i}),
        .inp_ready_o({st1_ready, st1_cr_ready_o}),
        .oup_valid_o(st1_pipe_valid),
        .oup_ready_i(st1_pipe_ready)
    );

    assign st1_cr_bv_o       = st1.cr_bv;

    assign st1_r_resp_shared = st1_cr_i.IsShared;
    assign st1_r_resp_dirty  = st1_cr_i.PassDirty && st1.ar_accepts_dirty;

    always_comb begin
        st1_aw_sel   = 1'b0;
        st1_ar_sel   = 1'b0;
        st1_cd_sel   = 1'b0;

        st1_cd_write = 1'b0;
        st1_cd_read  = 1'b0;

        if (st1.ax_is_write) begin
            // The transactions is a shareable write
            st1_aw_sel = 1'b1;
            if (st1_cr_i.DataTransfer) begin
                // A writeback is expected
                st1_cd_sel   = 1'b1;
                // If dirty data is passed, do a writeback
                // otherwise CD data will be dropped
                st1_cd_write = st1_cr_i.PassDirty;
            end
        end else begin
            // The transactions is a shareable read
            if (st1_cr_i.DataTransfer) begin
                // A cacheline is expected on CD
                st1_cd_sel  = 1'b1;
                st1_cd_read = 1'b1;
                if (st1_cr_i.PassDirty && !st1.ar_accepts_dirty) begin
                    // The cacheline is dirty but the initiator cannot accept it
                    st1_aw_sel   = 1'b1;
                    st1_cd_write = 1'b1;
                end
            end else begin
                // The cacheline must be obtained from memory
                st1_ar_sel = 1'b1;
            end
        end
    end

    stream_fork_dynamic #(
        .N_OUP(3)
    ) u_st1_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (st1_pipe_valid),
        .ready_o    (st1_pipe_ready),
        .sel_i      ({st1_aw_sel, st1_ar_sel, st1_cd_sel}),
        .sel_valid_i('1),
        .sel_ready_o(),
        .valid_o    ({st1_write_valid_o, st1_read_valid_o, st1_cd_ctrl_valid_o}),
        .ready_i    ({st1_write_ready_i, st1_read_ready_i, st1_cd_ctrl_ready_i})
    );
    //  }}}

    //  Pipe outputs
    //  {{{
    assign st1_ax_o            = st1.ax;
    assign st1_ax_is_write_o   = st1.ax_is_write;
    assign st1_r_resp_shared_o = st1_r_resp_shared;
    assign st1_r_resp_dirty_o  = st1_r_resp_dirty;
    assign st1_cd_ctrl_write_o = st1_cd_write;
    assign st1_cd_ctrl_read_o  = st1_cd_read;
    assign st1_ax_tid_o        = st1.tid;
    //  }}}

    //  Performance events
    //  {{{
    assign evt_st0_stall_o     = st0_ax_valid && !st0_ax_ready;
    assign evt_st1_stall_o     = st1_pipe_valid && !st1_pipe_ready;
    //  }}}

endmodule
