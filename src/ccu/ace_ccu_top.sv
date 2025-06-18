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
`include "axi/typedef.svh"
`include "ace/assign.svh"
`include "ace/typedef.svh"
`include "ace/convert.svh"
`include "ace/domain.svh"

module ace_ccu_top
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg        = '{default: '0},
    parameter type          domain_rule_t = logic,
    parameter type          slv_ar_t      = logic,
    parameter type          slv_aw_t      = logic,
    parameter type          w_t           = logic,
    parameter type          slv_b_t       = logic,
    parameter type          slv_r_t       = logic,
    parameter type          slv_req_t     = logic,
    parameter type          slv_resp_t    = logic,
    parameter type          mst_ar_t      = logic,
    parameter type          mst_aw_t      = logic,
    parameter type          mst_b_t       = logic,
    parameter type          mst_r_t       = logic,
    parameter type          mst_req_t     = logic,
    parameter type          mst_resp_t    = logic,
    parameter type          snoop_ac_t    = logic,
    parameter type          snoop_cr_t    = logic,
    parameter type          snoop_cd_t    = logic,
    parameter type          snoop_req_t   = logic,
    parameter type          snoop_resp_t  = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_req_i,
    output slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_resp_o,

    input domain_rule_t [CcuCfg.u.SlvPorts-1:0] domain_rule_i,

    output snoop_req_t  [CcuCfg.u.SlvPorts-1:0] snoop_req_o,
    input  snoop_resp_t [CcuCfg.u.SlvPorts-1:0] snoop_resp_i,

    output mst_req_t  mst_req_o,
    input  mst_resp_t mst_resp_i
);

    //  Typdefs
    //  {{{

    // AXI/ACE types
    typedef logic [CcuCfg.u.AxiSlvIdWidth-1:0] slv_id_t;
    typedef logic [CcuCfg.AxiCcuIdWidth-1:0] ccu_id_t;
    typedef logic [CcuCfg.AxiMstIdWidth-1:0] mst_id_t;
    typedef logic [CcuCfg.u.AxiAddrWidth-1:0] addr_t;
    typedef logic [CcuCfg.u.AxiDataWidth-1:0] data_t;
    typedef logic [CcuCfg.AxiStrbWidth-1:0] strb_t;
    typedef logic [CcuCfg.u.AxiUserWidth-1:0] user_t;

    // Intermediate ACE and AXI channel types
    `ACE_TYPEDEF_AW_CHAN_T(ccu_ace_aw_t, addr_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(ccu_ace_b_t, ccu_id_t, user_t)
    `ACE_TYPEDEF_AR_CHAN_T(ccu_ace_ar_t, addr_t, ccu_id_t, user_t)
    `ACE_TYPEDEF_R_CHAN_T(ccu_ace_r_t, data_t, ccu_id_t, user_t)
    `ACE_TYPEDEF_REQ_T(ccu_ace_req_t, ccu_ace_aw_t, w_t, ccu_ace_ar_t)
    `ACE_TYPEDEF_RESP_T(ccu_ace_resp_t, ccu_ace_b_t, ccu_ace_r_t)

    `AXI_TYPEDEF_AW_CHAN_T(ccu_axi_aw_t, addr_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(ccu_axi_b_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(ccu_axi_ar_t, addr_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(ccu_axi_r_t, data_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_REQ_T(ccu_axi_req_t, ccu_axi_aw_t, w_t, ccu_axi_ar_t)
    `AXI_TYPEDEF_RESP_T(ccu_axi_resp_t, ccu_axi_b_t, ccu_axi_r_t)

    // Transaction ID type
    typedef logic [CcuCfg.TransactionIdxWidth-1:0] tid_t;
    typedef logic [CcuCfg.u.SlvPorts-1:0] slv_bv_t;
    typedef logic [CcuCfg.SlvPortIdxWidth-1:0] slv_idx_t;
    typedef logic [CcuCfg.u.NLineWidth-1:0] nline_t;

    // Internal AW/AR request unified representation
    typedef struct packed {
        ccu_id_t          id;
        addr_t            addr;
        axi_pkg::len_t    len;
        axi_pkg::size_t   size;
        axi_pkg::burst_t  burst;
        logic             lock;
        axi_pkg::cache_t  cache;
        axi_pkg::prot_t   prot;
        axi_pkg::qos_t    qos;
        axi_pkg::region_t region;
        axi_pkg::atop_t   atop;
        user_t            user;
    } ccu_ax_t;
    //  }}}

    //  Internal signals
    //  {{{
    ccu_ace_req_t                          ccu_nonshareable_req;
    ccu_ace_resp_t                         ccu_nonshareable_resp;
    ccu_ace_req_t                          ccu_shareable_req;
    ccu_ace_resp_t                         ccu_shareable_resp;
    slv_bv_t                               ccu_shareable_rack;
    slv_bv_t                               ccu_shareable_wack;

    ccu_ace_ar_t                           replay_ar;
    logic                                  replay_ar_valid;
    logic                                  replay_ar_ready;

    snoop_ac_t                             ac;
    slv_bv_t                               ac_bv;
    logic                                  ac_valid;
    logic                                  ac_ready;
    snoop_cr_t                             cr;
    slv_bv_t                               cr_bv;
    logic                                  cr_valid;
    logic                                  cr_ready;
    slv_bv_t                               snoop_ac_valid;
    slv_bv_t                               snoop_ac_ready;
    snoop_ac_t     [CcuCfg.u.SlvPorts-1:0] snoop_ac;
    slv_bv_t                               snoop_cr_valid;
    slv_bv_t                               snoop_cr_ready;
    snoop_cr_t     [CcuCfg.u.SlvPorts-1:0] snoop_cr;
    slv_bv_t                               snoop_cd_valid;
    slv_bv_t                               snoop_cd_ready;
    snoop_cd_t     [CcuCfg.u.SlvPorts-1:0] snoop_cd;

    logic                                  replay_full;
    logic                                  replay_check;
    logic                                  replay_hit;
    logic                                  replay_alloc;

    logic                                  tracker_full;
    logic                                  tracker_check;
    logic                                  tracker_check_hit;
    logic                                  tracker_alloc;
    logic                                  tracker_alloc_b;
    logic                                  tracker_alloc_r;
    nline_t                                tracker_alloc_nline;
    ccu_id_t                               tracker_alloc_id;
    tid_t                                  tracker_alloc_tid;
    logic                                  tracker_dealloc_r_resp;
    logic                                  tracker_dealloc_b_resp;
    logic                                  tracker_dealloc_check_b_resp;
    ccu_id_t                               tracker_dealloc_r_resp_id;
    ccu_id_t                               tracker_dealloc_b_resp_id;
    logic                                  tracker_dealloc_b_resp_wb;
    logic                                  tracker_updt_wb;
    tid_t                                  tracker_updt_wb_tid;

    ccu_ax_t                               pipe_ax;
    logic                                  pipe_ax_is_write;
    logic                                  pipe_r_resp_shared;
    logic                                  pipe_r_resp_dirty;
    slv_bv_t                               pipe_cd_bv;
    tid_t                                  pipe_ax_tid;
    logic                                  pipe_cd_ctrl_write;
    logic                                  pipe_cd_ctrl_read;
    logic                                  write_valid;
    logic                                  write_ready;
    logic                                  read_valid;
    logic                                  read_ready;
    logic                                  cd_ctrl_valid;
    logic                                  cd_ctrl_read;

    w_t                                    write_w;
    logic                                  write_w_valid;
    logic                                  write_w_ready;

    w_t                                    cd_w;
    logic                                  cd_w_valid;
    logic                                  cd_w_ready;
    ccu_ace_r_t                            cd_r;
    logic                                  cd_r_valid;
    logic                                  cd_r_ready;

    ccu_axi_req_t                          axi_shareable_req;
    ccu_axi_resp_t                         axi_shareable_resp;
    ccu_axi_req_t                          axi_nonshareable_req;
    ccu_axi_resp_t                         axi_nonshareable_resp;

    mst_req_t                              mst_req;
    mst_resp_t                             mst_resp;

    //  }}}

    //  Frontend
    //  {{{
    ace_ccu_frontend #(
        .CcuCfg    (CcuCfg),
        .slv_bv_t  (slv_bv_t),
        .slv_idx_t (slv_idx_t),
        .slv_aw_t  (slv_aw_t),
        .w_t       (w_t),
        .slv_b_t   (slv_b_t),
        .slv_ar_t  (slv_ar_t),
        .slv_r_t   (slv_r_t),
        .slv_req_t (slv_req_t),
        .slv_resp_t(slv_resp_t),
        .ccu_aw_t  (ccu_ace_aw_t),
        .ccu_b_t   (ccu_ace_b_t),
        .ccu_ar_t  (ccu_ace_ar_t),
        .ccu_r_t   (ccu_ace_r_t),
        .ccu_req_t (ccu_ace_req_t),
        .ccu_resp_t(ccu_ace_resp_t)
    ) u_ace_ccu_frontend (
        .clk_i,
        .rst_ni,
        .slv_req_i,
        .slv_resp_o,
        .ccu_nonshareable_req_o (ccu_nonshareable_req),
        .ccu_nonshareable_resp_i(ccu_nonshareable_resp),
        .ccu_shareable_req_o    (ccu_shareable_req),
        .ccu_shareable_resp_i   (ccu_shareable_resp),
        .ccu_shareable_rack_o   (ccu_shareable_rack),
        .ccu_shareable_wack_o   (ccu_shareable_wack)
    );
    //  }}}

    //  Snoop pipeline
    //  {{{
    ace_ccu_snoop_pipe #(
        .CcuCfg       (CcuCfg),
        .domain_rule_t(domain_rule_t),
        .ccu_ax_t     (ccu_ax_t),
        .ccu_aw_t     (ccu_ace_aw_t),
        .ccu_ar_t     (ccu_ace_ar_t),
        .ccu_id_t     (ccu_id_t),
        .ac_t         (snoop_ac_t),
        .cr_t         (snoop_cr_t),
        .slv_bv_t     (slv_bv_t),
        .slv_idx_t    (slv_idx_t),
        .tid_t        (tid_t),
        .nline_t      (nline_t)
    ) u_ace_ccu_snoop_pipe (
        .clk_i,
        .rst_ni,
        .st0_aw_i                 (ccu_shareable_req.aw),
        .st0_aw_valid_i           (ccu_shareable_req.aw_valid),
        .st0_aw_ready_o           (ccu_shareable_resp.aw_ready),
        .st0_ar_i                 (ccu_shareable_req.ar),
        .st0_ar_valid_i           (ccu_shareable_req.ar_valid),
        .st0_ar_ready_o           (ccu_shareable_resp.ar_ready),
        .st0_replay_ar_i          (replay_ar),
        .st0_replay_ar_valid_i    (replay_ar_valid),
        .st0_replay_ar_ready_o    (replay_ar_ready),
        .st0_ac_o                 (ac),
        .st0_ac_bv_o              (ac_bv),
        .st0_ac_valid_o           (ac_valid),
        .st0_ac_ready_i           (ac_ready),
        .st0_replay_full_i        (replay_full),
        .st0_replay_check_o       (replay_check),
        .st0_replay_hit_i         (replay_hit),
        .st0_replay_alloc_o       (replay_alloc),
        .st0_tracker_full_i       (tracker_full),
        .st0_tracker_check_o      (tracker_check),
        .st0_tracker_check_hit_i  (tracker_check_hit),
        .st0_tracker_alloc_o      (tracker_alloc),
        .st0_tracker_alloc_b_o    (tracker_alloc_b),
        .st0_tracker_alloc_r_o    (tracker_alloc_r),
        .st0_tracker_alloc_nline_o(tracker_alloc_nline),
        .st0_tracker_alloc_id_o   (tracker_alloc_id),
        .st0_tracker_alloc_tid_i  (tracker_alloc_tid),
        .st0_domain_rule_i        (domain_rule_i),
        .st1_cr_i                 (cr),
        .st1_cr_bv_o              (cr_bv),
        .st1_cr_valid_i           (cr_valid),
        .st1_cr_ready_o           (cr_ready),
        .st1_ax_o                 (pipe_ax),
        .st1_ax_is_write_o        (pipe_ax_is_write),
        .st1_r_resp_shared_o      (pipe_r_resp_shared),
        .st1_r_resp_dirty_o       (pipe_r_resp_dirty),
        .st1_ax_tid_o             (pipe_ax_tid),
        .st1_cd_ctrl_write_o      (pipe_cd_ctrl_write),
        .st1_cd_ctrl_read_o       (pipe_cd_ctrl_read),
        .st1_write_valid_o        (write_valid),
        .st1_write_ready_i        (write_ready),
        .st1_read_valid_o         (read_valid),
        .st1_read_ready_i         (read_ready),
        .st1_cd_ctrl_valid_o      (cd_ctrl_valid),
        .st1_cd_ctrl_ready_i      (cd_ctrl_ready),
        .evt_st0_stall_o          (),
        .evt_st1_stall_o          ()
    );

    stream_fork_dynamic #(
        .N_OUP(CcuCfg.u.SlvPorts)
    ) u_ace_ccu_ac_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (ac_valid),
        .ready_o    (ac_ready),
        .sel_i      (ac_bv),
        .sel_valid_i(1'b1),
        .sel_ready_o(),
        .valid_o    (snoop_ac_valid),
        .ready_i    (snoop_ac_ready)
    );

    assign snoop_ac = {CcuCfg.u.SlvPorts{ac}};

    stream_join_dynamic #(
        .N_INP(CcuCfg.u.SlvPorts)
    ) u_cr_join (
        .inp_valid_i(snoop_cr_valid),
        .inp_ready_o(snoop_cr_ready),
        .sel_i      (cr_bv),
        .oup_valid_o(cr_valid),
        .oup_ready_i(cr_ready)
    );

    always_comb begin : cr_merge_comb
        cr         = '0;
        pipe_cd_bv = '0;
        for (int unsigned i = 0; i < CcuCfg.u.SlvPorts; i++) begin
            if (cr_bv[i]) begin
                cr |= snoop_cr[i];
                pipe_cd_bv[i] = snoop_cr[i].DataTransfer;
            end
        end
    end
    //  }}}

    //  Shareable W buffer
    //  {{{
    stream_fifo #(
        .FALL_THROUGH(1'b0),
        .DEPTH       (CcuCfg.u.ShareableWFifoDepth),
        .T           (w_t)
    ) u_shareable_w_fifo (
        .clk_i,
        .rst_ni,
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .usage_o   (),
        .data_i    (ccu_shareable_req.w),
        .valid_i   (ccu_shareable_req.w_valid),
        .ready_o   (ccu_shareable_resp.w_ready),
        .data_o    (write_w),
        .valid_o   (write_w_valid),
        .ready_i   (write_w_ready)
    );
    //  }}}

    //  Tracker
    //  {{{
    assign tracker_dealloc_r_resp = ccu_shareable_req.r_ready && ccu_shareable_resp.r_valid && ccu_shareable_resp.r.last;
    assign tracker_dealloc_r_resp_id = ccu_shareable_resp.r.id;
    assign tracker_dealloc_check_b_resp = axi_shareable_resp.b_valid;
    assign tracker_dealloc_b_resp = ccu_shareable_req.b_ready && ccu_shareable_resp.b_valid;
    assign tracker_dealloc_b_resp_id = ccu_shareable_resp.b.id;

    ace_ccu_tracker #(
        .CcuCfg   (CcuCfg),
        .slv_bv_t (slv_bv_t),
        .slv_idx_t(slv_idx_t),
        .nline_t  (nline_t),
        .ccu_id_t (ccu_id_t),
        .tid_t    (tid_t)
    ) u_ace_ccu_tracker (
        .clk_i,
        .rst_ni,
        .full_o                (tracker_full),
        .check_i               (tracker_check),
        .check_hit_o           (tracker_check_hit),
        .alloc_i               (tracker_alloc),
        .alloc_b_i             (tracker_alloc_b),
        .alloc_r_i             (tracker_alloc_r),
        .alloc_nline_i         (tracker_alloc_nline),
        .alloc_id_i            (tracker_alloc_id),
        .alloc_tid_o           (tracker_alloc_tid),
        .dealloc_rack_i        (ccu_shareable_rack),
        .dealloc_wack_i        (ccu_shareable_wack),
        .dealloc_r_resp_i      (tracker_dealloc_r_resp),
        .dealloc_r_resp_id_i   (tracker_dealloc_r_resp_id),
        .dealloc_b_resp_i      (tracker_dealloc_b_resp),
        .dealloc_check_b_resp_i(tracker_dealloc_check_b_resp),
        .dealloc_b_resp_id_i   (tracker_dealloc_b_resp_id),
        .dealloc_b_resp_wb_o   (tracker_dealloc_b_resp_wb),
        .updt_wb_i             (tracker_updt_wb),
        .updt_wb_tid_i         (tracker_updt_wb_tid)
    );
    //  }}}


    //  Replay table
    //  {{{
    if (CcuCfg.u.ReplayEn) begin : gen_replay
        $fatal(-1, "Replay table not yet implemented.");
    end else begin : gen_no_replay
        assign replay_full     = 1'b0;
        assign replay_hit      = 1'b0;
        assign replay_ar       = '0;
        assign replay_ar_valid = 1'b0;
    end
    //  }}}

    //  Write Unit
    //  {{{
    ace_ccu_write #(
        .CcuCfg  (CcuCfg),
        .ccu_ax_t(ccu_ax_t),
        .tid_t   (tid_t),
        .ccu_aw_t(ccu_axi_aw_t),
        .w_t     (w_t),
        .ccu_b_t (ccu_axi_b_t)
    ) u_ace_ccu_write (
        .clk_i,
        .rst_ni,
        .valid_i              (write_valid),
        .ready_o              (write_ready),
        .ax_i                 (pipe_ax),
        .ax_is_write_i        (pipe_ax_is_write),
        .ax_is_writeback_i    (pipe_cd_ctrl_write),
        .ax_tid_i             (pipe_ax_tid),
        .tracker_updt_wb_o    (tracker_updt_wb),
        .tracker_updt_wb_tid_o(tracker_updt_wb_tid),
        .b_is_writeback_i     (tracker_dealloc_b_resp_wb),
        .w_i                  (write_w),
        .w_valid_i            (write_w_valid),
        .w_ready_o            (write_w_ready),
        .cd_w_i               (cd_w),
        .cd_w_valid_i         (cd_w_valid),
        .cd_w_ready_o         (cd_w_ready),
        .b_o                  (ccu_shareable_resp.b),
        .b_valid_o            (ccu_shareable_resp.b_valid),
        .b_ready_i            (ccu_shareable_req.b_ready),
        .aw_o                 (axi_shareable_req.aw),
        .aw_valid_o           (axi_shareable_req.aw_valid),
        .aw_ready_i           (axi_shareable_resp.aw_ready),
        .w_o                  (axi_shareable_req.w),
        .w_valid_o            (axi_shareable_req.w_valid),
        .w_ready_i            (axi_shareable_resp.w_ready),
        .b_i                  (axi_shareable_resp.b),
        .b_valid_i            (axi_shareable_resp.b_valid),
        .b_ready_o            (axi_shareable_req.b_ready)
    );
    //  }}}

    //  Read Unit
    //  {{{
    ace_ccu_read #(
        .CcuCfg      (CcuCfg),
        .ccu_ax_t    (ccu_ax_t),
        .tid_t       (tid_t),
        .ccu_axi_ar_t(ccu_axi_ar_t),
        .ccu_axi_r_t (ccu_axi_r_t),
        .ccu_ace_r_t (ccu_ace_r_t)
    ) u_ace_ccu_read_unit (
        .clk_i,
        .rst_ni,
        .valid_i     (read_valid),
        .ready_o     (read_ready),
        .ax_i        (pipe_ax),
        .cd_r_i      (cd_r),
        .cd_r_valid_i(cd_r_valid),
        .cd_r_ready_o(cd_r_ready),
        .r_o         (ccu_shareable_resp.r),
        .r_valid_o   (ccu_shareable_resp.r_valid),
        .r_ready_i   (ccu_shareable_req.r_ready),
        .ar_o        (axi_shareable_req.ar),
        .ar_valid_o  (axi_shareable_req.ar_valid),
        .ar_ready_i  (axi_shareable_resp.ar_ready),
        .r_i         (axi_shareable_resp.r),
        .r_valid_i   (axi_shareable_resp.r_valid),
        .r_ready_o   (axi_shareable_req.r_ready)
    );
    //  }}}


    //  CD Ctrl Unit
    //  {{{
    ace_ccu_cd_ctrl #(
        .CcuCfg  (CcuCfg),
        .ccu_ax_t(ccu_ax_t),
        .ccu_id_t(ccu_id_t),
        .user_t  (user_t),
        .cd_t    (snoop_cd_t),
        .slv_bv_t(slv_bv_t),
        .w_t     (w_t),
        .ccu_r_t (ccu_ace_r_t)
    ) u_ace_ccu_cd_ctrl (
        .clk_i,
        .rst_ni,
        .valid_i        (cd_ctrl_valid),
        .ready_o        (cd_ctrl_ready),
        .ax_i           (pipe_ax),
        .cd_ctrl_write_i(pipe_cd_ctrl_write),
        .cd_ctrl_read_i (pipe_cd_ctrl_read),
        .cd_bv_i        (pipe_cd_bv),
        .r_resp_shared_i(pipe_r_resp_shared),
        .r_resp_dirty_i (pipe_r_resp_dirty),
        .cd_i           (snoop_cd),
        .cd_valid_i     (snoop_cd_valid),
        .cd_ready_o     (snoop_cd_ready),
        .w_o            (cd_w),
        .w_valid_o      (cd_w_valid),
        .w_ready_i      (cd_w_ready),
        .r_o            (cd_r),
        .r_valid_o      (cd_r_valid),
        .r_ready_i      (cd_r_ready)
    );
    //  }}}

    //  Mst mux
    //  {{{
    `ACE_TO_AXI_ASSIGN_REQ(axi_nonshareable_req, ccu_nonshareable_req)
    `AXI_TO_ACE_ASSIGN_RESP(ccu_nonshareable_resp, axi_nonshareable_resp)

    axi_mux #(
        .SlvAxiIDWidth(CcuCfg.AxiCcuIdWidth),
        .slv_aw_chan_t(ccu_axi_aw_t),
        .mst_aw_chan_t(mst_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (ccu_axi_b_t),
        .mst_b_chan_t (mst_b_t),
        .slv_ar_chan_t(ccu_axi_ar_t),
        .mst_ar_chan_t(mst_ar_t),
        .slv_r_chan_t (ccu_axi_r_t),
        .mst_r_chan_t (mst_r_t),
        .slv_req_t    (ccu_axi_req_t),
        .slv_resp_t   (ccu_axi_resp_t),
        .mst_req_t    (mst_req_t),
        .mst_resp_t   (mst_resp_t),
        .NoSlvPorts   (2),
        .MaxWTrans    (32'd8),
        .FallThrough  (1'b1),
        .SpillAw      (1'b0),
        .SpillW       (1'b0),
        .SpillB       (1'b0),
        .SpillAr      (1'b0),
        .SpillR       (1'b0)
    ) u_axi_mst_mux (
        .clk_i,
        .rst_ni,
        .test_i     (1'b0),
        .slv_reqs_i ({axi_nonshareable_req, axi_shareable_req}),
        .slv_resps_o({axi_nonshareable_resp, axi_shareable_resp}),
        .mst_req_o  (mst_req),
        .mst_resp_i (mst_resp)
    );
    //  }}}

    //  ACE/AXI cuts
    //  {{{
    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_snoop_cut

        snoop_req_t  snoop_req;
        snoop_resp_t snoop_resp;

        assign snoop_req.ac_valid = snoop_ac_valid[i];
        assign snoop_ac_ready[i]  = snoop_resp.ac_ready;
        assign snoop_req.ac       = snoop_ac[i];

        assign snoop_cr_valid[i]  = snoop_resp.cr_valid;
        assign snoop_req.cr_ready = snoop_cr_ready[i];
        assign snoop_cr[i]        = snoop_resp.cr_resp;

        assign snoop_cd_valid[i]  = snoop_resp.cd_valid;
        assign snoop_req.cd_ready = snoop_cd_ready[i];
        assign snoop_cd[i]        = snoop_resp.cd;

        ace_snoop_cut #(
            .BypassAc    (!CcuCfg.u.CutSnoopReq),
            .BypassCr    (!CcuCfg.u.CutSnoopResp),
            .BypassCd    (!CcuCfg.u.CutSnoopResp),
            .ac_chan_t   (snoop_ac_t),
            .cd_chan_t   (snoop_cd_t),
            .cr_chan_t   (snoop_cr_t),
            .snoop_req_t (snoop_req_t),
            .snoop_resp_t(snoop_resp_t)
        ) u_snoop_cut (
            .clk_i,
            .rst_ni,
            .slv_req_i (snoop_req),
            .slv_resp_o(snoop_resp),
            .mst_req_o (snoop_req_o[i]),
            .mst_resp_i(snoop_resp_i[i])
        );
    end

    axi_cut #(
        .BypassAw  (!CcuCfg.u.CutMstReq),
        .BypassW   (!CcuCfg.u.CutMstReq),
        .BypassB   (!CcuCfg.u.CutMstResp),
        .BypassAr  (!CcuCfg.u.CutMstReq),
        .BypassR   (!CcuCfg.u.CutMstResp),
        .aw_chan_t (mst_aw_t),
        .w_chan_t  (w_t),
        .b_chan_t  (mst_b_t),
        .ar_chan_t (mst_ar_t),
        .r_chan_t  (mst_r_t),
        .axi_req_t (mst_req_t),
        .axi_resp_t(mst_resp_t)
    ) u_mst_cut (
        .clk_i,
        .rst_ni,
        .slv_req_i (mst_req),
        .slv_resp_o(mst_resp),
        .mst_req_o (mst_req_o),
        .mst_resp_i(mst_resp_i)
    );
    //  }}}

endmodule

module ace_ccu_top_intf
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter  ace_ccu_cfg_t CCU_CFG       = '{default: '0},
    localparam type          domain_bv_t   = `DOMAIN_BV_T(CCU_CFG.u.SlvPorts),
    localparam type          domain_rule_t = `DOMAIN_RULE_T(domain_bv_t)
) (
    input logic                                    clk_i,
    input logic                                    rst_ni,
    input domain_rule_t   [CCU_CFG.u.SlvPorts-1:0] domain_rule_i,
          ACE_BUS.Slave                            slv          [CCU_CFG.u.SlvPorts],
          SNOOP_BUS.Slave                          snoop        [CCU_CFG.u.SlvPorts],
          AXI_BUS.Master                           mst
);

    typedef logic [CCU_CFG.u.AxiSlvIdWidth-1:0] slv_id_t;
    typedef logic [CCU_CFG.AxiMstIdWidth-1:0] mst_id_t;
    typedef logic [CCU_CFG.u.AxiAddrWidth-1:0] addr_t;
    typedef logic [CCU_CFG.u.AxiDataWidth-1:0] data_t;
    typedef logic [CCU_CFG.u.AxiDataWidth/8-1:0] strb_t;
    typedef logic [CCU_CFG.u.AxiUserWidth-1:0] user_t;

    `ACE_TYPEDEF_AW_CHAN_T(slv_aw_t, addr_t, slv_id_t, user_t)
    `AXI_TYPEDEF_W_CHAN_T(w_t, data_t, strb_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(slv_b_t, slv_id_t, user_t)
    `ACE_TYPEDEF_AR_CHAN_T(slv_ar_t, addr_t, slv_id_t, user_t)
    `ACE_TYPEDEF_R_CHAN_T(slv_r_t, data_t, slv_id_t, user_t)
    `ACE_TYPEDEF_REQ_T(slv_req_t, slv_aw_t, w_t, slv_ar_t)
    `ACE_TYPEDEF_RESP_T(slv_resp_t, slv_b_t, slv_r_t)

    `AXI_TYPEDEF_AW_CHAN_T(mst_aw_t, addr_t, mst_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(mst_b_t, mst_id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(mst_ar_t, addr_t, mst_id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(mst_r_t, data_t, mst_id_t, user_t)
    `AXI_TYPEDEF_REQ_T(mst_req_t, mst_aw_t, w_t, mst_ar_t)
    `AXI_TYPEDEF_RESP_T(mst_resp_t, mst_b_t, mst_r_t)

    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
    `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
    `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)

    slv_req_t    [CCU_CFG.u.SlvPorts-1:0] slv_req;
    slv_resp_t   [CCU_CFG.u.SlvPorts-1:0] slv_resp;

    mst_req_t                             mst_req;
    mst_resp_t                            mst_resp;

    snoop_req_t  [CCU_CFG.u.SlvPorts-1:0] snoop_req;
    snoop_resp_t [CCU_CFG.u.SlvPorts-1:0] snoop_resp;

    for (genvar i = 0; i < CCU_CFG.u.SlvPorts; i++) begin : gen_bus_assignments
        `ACE_ASSIGN_TO_REQ(slv_req[i], slv[i])
        `ACE_ASSIGN_FROM_RESP(slv[i], slv_resp[i])
        `SNOOP_ASSIGN_FROM_REQ(snoop[i], snoop_req[i])
        `SNOOP_ASSIGN_TO_RESP(snoop_resp[i], snoop[i])
    end

    `AXI_ASSIGN_FROM_REQ(mst, mst_req)
    `AXI_ASSIGN_TO_RESP(mst_resp, mst)

    ace_ccu_top #(
        .CcuCfg       (CCU_CFG),
        .domain_rule_t(domain_rule_t),
        .slv_ar_t     (slv_ar_t),
        .slv_aw_t     (slv_aw_t),
        .w_t          (w_t),
        .slv_b_t      (slv_b_t),
        .slv_r_t      (slv_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_ar_t     (mst_ar_t),
        .mst_aw_t     (mst_aw_t),
        .mst_b_t      (mst_b_t),
        .mst_r_t      (mst_r_t),
        .mst_req_t    (mst_req_t),
        .mst_resp_t   (mst_resp_t),
        .snoop_ac_t   (snoop_ac_t),
        .snoop_cr_t   (snoop_cr_t),
        .snoop_cd_t   (snoop_cd_t),
        .snoop_req_t  (snoop_req_t),
        .snoop_resp_t (snoop_resp_t)
    ) u_ace_ccu (
        .clk_i,
        .rst_ni,
        .slv_req_i    (slv_req),
        .slv_resp_o   (slv_resp),
        .domain_rule_i(domain_rule_i),
        .snoop_req_o  (snoop_req),
        .snoop_resp_i (snoop_resp),
        .mst_req_o    (mst_req),
        .mst_resp_i   (mst_resp)
    );

endmodule
