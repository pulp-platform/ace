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

`include "ace/assign.svh"
`include "ace/convert.svh"

// FSM to control read snoop transactions
// This module assumes that snooping happens
// Non-snooping transactions should be handled outside
module ccu_ctrl_r_snoop import ace_pkg::*; #(
    /// Request channel type towards cached master
    parameter type slv_req_t          = logic,
    /// Response channel type towards cached master
    parameter type slv_resp_t         = logic,
    /// Request channel type towards memory
    parameter type mst_req_t          = logic,
    /// Response channel type towards memory
    parameter type mst_resp_t         = logic,
    /// AR channel type towards cached master
    parameter type slv_ar_chan_t      = logic,
    /// R channel type towards cached master
    parameter type slv_r_chan_t       = logic,
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
    /// Cacheline offset bits
    parameter int unsigned BLOCK_OFFSET = 0,
    /// Fixed value to align CD writeback addresses,
    parameter int unsigned ALIGN_SIZE = 0,
    /// Depth of FIFO that stores AR requests
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

    parameter int unsigned ARUSER_WIDTH    = $bits(slv_req_i.ar.user);
    parameter int unsigned ARID_WIDTH      = $bits(slv_req_i.ar.id);
    parameter int unsigned ARLEN_CNT_WIDTH = 5;
    parameter int unsigned RDROP_CNT_WIDTH = $clog2(AXLEN)+1;

    typedef struct packed {
        slv_ar_chan_t ar;
        snoop_info_t  snoop_info;
    } slv_trs_t;

    typedef struct packed {
        logic [ARLEN_CNT_WIDTH-1:0] arlen;
        logic [RDROP_CNT_WIDTH-1:0] rdrop;
        logic [1:0]                 crresp;
        logic [ARUSER_WIDTH-1:0]    aruser;
        logic [ARID_WIDTH-1:0]      arid;
        logic                       write_back;
    } wb_trs_t;

    logic wb_lock_d, wb_lock_q;

    logic slv_ar_valid, slv_ar_ready;
    logic slv_r_valid, slv_r_ready;

    logic wb_r_valid, wb_r_ready;

    logic ac_valid, ac_ready;
    logic cr_valid, cr_ready;
    logic cd_valid, cd_ready;

    logic [3:0] cr_sel;

    logic cd_last;
    logic cd_sel_valid, cd_sel_ready;
    logic [1:0] cd_sel;

    logic                   rdrop_cnt_en, rdrop_cnt_clr;
    logic [$clog2(AXLEN):0] rdrop_cnt_q;
    logic                   rdrop;
    logic                   arlen_cnt_en, arlen_cnt_clr;
    logic [4:0]             arlen_cnt_q;
    logic                   rlast;
    logic                   rdone_q, rdone_d;

    logic mst_aw_valid, mst_aw_ready;
    logic mst_w_valid, mst_w_ready;
    logic mst_ar_valid, mst_ar_ready;
    logic mst_r_valid, mst_r_ready;

    slv_r_chan_t slv_r, mst_r, wb_r;

    logic cd_handshake;
    logic wb_r_handshake;
    logic write_back, resp_shared, resp_dirty;

    slv_trs_t slv_trs_fifo_in, slv_trs_fifo_out;
    logic     slv_trs_fifo_ready_in, slv_trs_fifo_valid_in;
    logic     slv_trs_fifo_ready_out, slv_trs_fifo_valid_out;

    wb_trs_t wb_trs_fifo_in, wb_trs_fifo_out;
    logic    wb_trs_fifo_ready_in, wb_trs_fifo_valid_in;
    logic    wb_trs_fifo_ready_out, wb_trs_fifo_valid_out;

    logic r_sel_fifo_in, r_sel_fifo_out;
    logic r_sel_fifo_valid_in, r_sel_fifo_ready_in;
    logic r_sel_fifo_valid_out, r_sel_fifo_ready_out;

    assign cd_handshake = cd_valid && cd_ready;

    stream_fork #(
        .N_OUP (2)
    ) i_ar_fork (
        .clk_i,
        .rst_ni,
        .valid_i (slv_ar_valid),
        .ready_o (slv_ar_ready),
        .valid_o ({slv_trs_fifo_valid_in, ac_valid}),
        .ready_i ({slv_trs_fifo_ready_in, ac_ready})
    );

    assign slv_trs_fifo_in.ar         = slv_req_i.ar;
    assign slv_trs_fifo_in.snoop_info = snoop_info_i;

    stream_fifo_optimal_wrap #(
        .Depth  (FIFO_DEPTH),
        .type_t (slv_trs_t)
    ) i_slv_trs_fifo (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .valid_i    (slv_trs_fifo_valid_in),
        .ready_o    (slv_trs_fifo_ready_in),
        .data_i     (slv_trs_fifo_in),
        .valid_o    (slv_trs_fifo_valid_out),
        .ready_i    (slv_trs_fifo_ready_out),
        .data_o     (slv_trs_fifo_out)
    );

    assign resp_shared = snoop_resp_i.cr_resp.IsShared;
    assign resp_dirty  = slv_trs_fifo_out.snoop_info.accepts_dirty && snoop_resp_i.cr_resp.PassDirty;
    assign write_back  = !slv_trs_fifo_out.snoop_info.accepts_dirty && snoop_resp_i.cr_resp.PassDirty;
    assign cr_sel      = snoop_resp_i.cr_resp.DataTransfer ? {1'b0, write_back, 2'b11} : 4'b1001;

    stream_fork_dynamic #(
        .N_OUP (4)
    ) i_cr_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (slv_trs_fifo_valid_out),
        .ready_o     (slv_trs_fifo_ready_out),
        .sel_i       (cr_sel),
        .sel_valid_i (cr_valid),
        .sel_ready_o (cr_ready),
        .valid_o     ({mst_ar_valid, mst_aw_valid, wb_trs_fifo_valid_in, r_sel_fifo_valid_in}),
        .ready_i     ({mst_ar_ready, mst_aw_ready, wb_trs_fifo_ready_in, r_sel_fifo_ready_in})
    );

    assign r_sel_fifo_in = snoop_resp_i.cr_resp.DataTransfer;

    assign wb_trs_fifo_in.arid       = slv_trs_fifo_out.ar.id;
    assign wb_trs_fifo_in.arlen      = slv_trs_fifo_out.ar.len;
    assign wb_trs_fifo_in.rdrop      = slv_trs_fifo_out.ar.addr[BLOCK_OFFSET-1:AXSIZE];
    assign wb_trs_fifo_in.crresp     = {resp_shared, resp_dirty};
    assign wb_trs_fifo_in.aruser     = slv_trs_fifo_out.ar.user;
    assign wb_trs_fifo_in.write_back = write_back;

    stream_fifo #(
        .FALL_THROUGH (1'b1),
        .DEPTH        (2),
        .T            (wb_trs_t)
    ) i_wb_trs_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .data_i     (wb_trs_fifo_in),
        .valid_i    (wb_trs_fifo_valid_in),
        .ready_o    (wb_trs_fifo_ready_in),
        .data_o     (wb_trs_fifo_out),
        .valid_o    (wb_trs_fifo_valid_out),
        .ready_i    (wb_trs_fifo_ready_out)
    );

    assign cd_last = snoop_resp_i.cd.last;

    always_comb begin
        wb_lock_d             = wb_lock_q;
        cd_sel_valid          = 1'b0;
        wb_trs_fifo_ready_out = 1'b0;

        arlen_cnt_clr = 1'b0;
        rdrop_cnt_clr = 1'b0;

        if (!wb_lock_q) begin
            if (wb_trs_fifo_valid_out) begin
                cd_sel_valid = 1'b1;
                if (cd_sel_ready && cd_last) begin
                    wb_trs_fifo_ready_out = 1'b1;
                    arlen_cnt_clr = 1'b1;
                    rdrop_cnt_clr = 1'b1;
                end else begin
                    wb_lock_d = 1'b1;
                end
            end
        end else begin
            cd_sel_valid = 1'b1;
            if (cd_sel_ready && cd_last) begin
                wb_trs_fifo_ready_out = 1'b1;
                wb_lock_d = 1'b0;
                arlen_cnt_clr = 1'b1;
                rdrop_cnt_clr = 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            wb_lock_q <= 1'b0;
        else
            wb_lock_q <= wb_lock_d;
    end

    assign rdrop        = rdrop_cnt_q != wb_trs_fifo_out.rdrop;
    assign rdrop_cnt_en = rdrop && cd_handshake;

    counter #(
        .WIDTH (RDROP_CNT_WIDTH)
    ) i_rdrop_cnt (
        .clk_i,
        .rst_ni,
        .clear_i    (rdrop_cnt_clr),
        .en_i       (rdrop_cnt_en),
        .load_i     ('0),
        .down_i     ('0),
        .d_i        ('0),
        .q_o        (rdrop_cnt_q),
        .overflow_o ()
    );

    assign wb_r_handshake = wb_r_valid && wb_r_ready;
    assign rlast          = arlen_cnt_q == wb_trs_fifo_out.arlen;
    assign arlen_cnt_en   = wb_r_handshake;

    counter #(
        .WIDTH (ARLEN_CNT_WIDTH)
    ) i_arlen_cnt (
        .clk_i,
        .rst_ni,
        .clear_i    (arlen_cnt_clr),
        .en_i       (arlen_cnt_en),
        .load_i     ('0),
        .down_i     ('0),
        .d_i        ('0),
        .q_o        (arlen_cnt_q),
        .overflow_o ()
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            rdone_q <= 1'b0;
        else
            rdone_q <= rdone_d;
    end

    assign rdone_d = !arlen_cnt_clr &&
                     ((rlast && wb_r_handshake) || rdone_q);

    assign cd_sel = {wb_trs_fifo_out.write_back, !rdrop && !rdone_q};

    stream_fork_dynamic #(
        .N_OUP (2)
    ) i_cd_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (cd_valid),
        .ready_o     (cd_ready),
        .sel_i       (cd_sel),
        .sel_valid_i (cd_sel_valid),
        .sel_ready_o (cd_sel_ready),
        .valid_o     ({mst_w_valid, wb_r_valid}),
        .ready_i     ({mst_w_ready, wb_r_ready})
    );

    always_comb begin
        wb_r       = '0;
        wb_r.id    = wb_trs_fifo_out.arid;
        wb_r.data  = snoop_resp_i.cd.data;
        wb_r.resp  = {wb_trs_fifo_out.crresp, 2'b0}; // something has to happen to 2 lsb when atomic
        wb_r.last  = rlast;
    end

    // TODO: evaluate this solution
    // Potential issue: transactions with the same ID could be reordered
    // stream_arbiter #(
    //     .DATA_T (slv_r_chan_t),
    //     .N_INP  (2)
    // ) i_slv_r_arb (
    //     .clk_i,
    //     .rst_ni,
    //     .inp_data_i  ({wb_r, mst_r}),
    //     .inp_valid_i ({wb_r_valid, mst_r_valid}),
    //     .inp_ready_o ({wb_r_ready, mst_r_ready}),
    //     .oup_data_o  (slv_r),
    //     .oup_valid_o (slv_r_valid),
    //     .oup_ready_i (slv_r_ready)
    // );

    stream_fifo #(
        .FALL_THROUGH (1'b1),
        .DEPTH        (FIFO_DEPTH),
        .T            (logic)
    ) i_r_sel_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .data_i     (r_sel_fifo_in),
        .valid_i    (r_sel_fifo_valid_in),
        .ready_o    (r_sel_fifo_ready_in),
        .data_o     (r_sel_fifo_out),
        .valid_o    (r_sel_fifo_valid_out),
        .ready_i    (r_sel_fifo_ready_out && slv_r.last)
    );

    stream_mux #(
        .DATA_T    (slv_r_chan_t),
        .N_INP     (2)
    ) i_slv_r_mux (
        .inp_data_i  ({wb_r, mst_r}),
        .inp_valid_i ({wb_r_valid, mst_r_valid}),
        .inp_ready_o ({wb_r_ready, mst_r_ready}),
        .inp_sel_i   (r_sel_fifo_out),
        .oup_data_o  (slv_r),
        .oup_valid_o (slv_r_mux_valid_out),
        .oup_ready_i (slv_r_mux_ready_out)
    );

    stream_join #(
        .N_INP (2)
    ) i_slv_r_join (
        .inp_valid_i ({slv_r_mux_valid_out, r_sel_fifo_valid_out}),
        .inp_ready_o ({slv_r_mux_ready_out, r_sel_fifo_ready_out}),
        .oup_valid_o (slv_r_valid),
        .oup_ready_i (slv_r_ready)
    );

    //////////////
    // Channels //
    //////////////

    /* SLV INTF */

    // AR
    assign slv_resp_o.ar_ready = slv_ar_ready;
    assign slv_ar_valid        = slv_req_i.ar_valid;
    // R
    assign slv_resp_o.r_valid = slv_r_valid;
    assign slv_r_ready        = slv_req_i.r_ready;
    assign slv_resp_o.r       = slv_r;
    // AW
    assign slv_resp_o.aw_ready = 1'b0;
    // W
    assign slv_resp_o.w_ready = 1'b0;
    // B
    assign slv_resp_o.b_valid = 1'b0;
    assign slv_resp_o.b       = '0;

    /* SNP INTF */

    // AC
    assign snoop_req_o.ac_valid = ac_valid;
    assign ac_ready             = snoop_resp_i.ac_ready;
    assign snoop_req_o.ac.addr  = slv_trs_fifo_in.ar.addr;
    assign snoop_req_o.ac.snoop = slv_trs_fifo_in.snoop_info.snoop_trs;
    assign snoop_req_o.ac.prot  = slv_trs_fifo_in.ar.prot;

    // CR
    assign snoop_req_o.cr_ready = cr_ready;
    assign cr_valid             = snoop_resp_i.cr_valid;

    // CD
    assign snoop_req_o.cd_ready = cd_ready;
    assign cd_valid             = snoop_resp_i.cd_valid;

    /* MST INTF */

    // AR
    assign mst_req_o.ar_valid = mst_ar_valid;
    assign mst_ar_ready       = mst_resp_i.ar_ready;
    `AXI_ASSIGN_AR_STRUCT(mst_req_o.ar, slv_trs_fifo_out.ar)

    // R
    assign mst_req_o.r_ready = mst_r_ready;
    assign mst_r_valid       = mst_resp_i.r_valid;
    `AXI_TO_ACE_ASSIGN_R_STRUCT(mst_r, mst_resp_i.r)

    // AW
    assign mst_req_o.aw_valid  = mst_aw_valid;
    assign mst_aw_ready        = mst_resp_i.aw_ready;
    assign mst_req_o.aw.id     = slv_trs_fifo_out.ar.id;
    assign mst_req_o.aw.addr   = axi_pkg::aligned_addr(slv_trs_fifo_out.ar.addr, ALIGN_SIZE);
    assign mst_req_o.aw.len    = AXLEN;
    assign mst_req_o.aw.size   = AXSIZE;
    assign mst_req_o.aw.burst  = axi_pkg::BURST_WRAP;
    assign mst_req_o.aw.lock   = 1'b0;
    assign mst_req_o.aw.cache  = axi_pkg::CACHE_MODIFIABLE;
    assign mst_req_o.aw.prot   = slv_trs_fifo_out.ar.prot;
    assign mst_req_o.aw.qos    = slv_trs_fifo_out.ar.qos;
    assign mst_req_o.aw.region = slv_trs_fifo_out.ar.region;
    assign mst_req_o.aw.atop   = '0;
    assign mst_req_o.aw.user   = slv_trs_fifo_out.ar.user;

    // W
    assign mst_req_o.w_valid = mst_w_valid;
    assign mst_w_ready       = mst_resp_i.w_ready;
    assign mst_req_o.w.data  = snoop_resp_i.cd.data;
    assign mst_req_o.w.strb  = '1;
    assign mst_req_o.w.last  = snoop_resp_i.cd.last;
    assign mst_req_o.w.user  = wb_trs_fifo_out.aruser;

    // B
    assign mst_req_o.b_ready = 1'b1;

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
