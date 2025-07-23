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

module ace_ccu_cd_ctrl
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg      = '{default: '0},
    parameter type          midend_ax_t = logic,
    parameter type          midend_id_t = logic,
    parameter type          user_t      = logic,
    parameter type          cd_t        = logic,
    parameter type          slv_bv_t    = logic,
    parameter type          w_t         = logic,
    parameter type          midend_r_t  = logic
) (

    input logic clk_i,
    input logic rst_ni,

    // Ctrl
    input  logic       valid_i,
    output logic       ready_o,
    input  midend_ax_t ax_i,
    input  logic       cd_ctrl_write_i,
    input  logic       cd_ctrl_read_i,
    input  slv_bv_t    cd_bv_i,
    input  logic       r_resp_shared_i,
    input  logic       r_resp_dirty_i,

    // CD snoop channel
    input  cd_t  [CcuCfg.u.SlvPorts-1:0] cd_i,
    input  logic [CcuCfg.u.SlvPorts-1:0] cd_valid_i,
    output logic [CcuCfg.u.SlvPorts-1:0] cd_ready_o,

    // Mst interface
    output w_t   w_o,
    output logic w_valid_o,
    input  logic w_ready_i,

    // Slv interface
    output midend_r_t r_o,
    output logic      r_valid_o,
    input  logic      r_ready_i
);
    //  Typedefs
    //  {{{
    typedef logic [CcuCfg.CachelineAxiTransfersIdxWidth-1:0] cl_axi_trans_idx_t;

    typedef struct packed {
        midend_id_t        id;
        logic              cd_ctrl_write;
        logic              cd_ctrl_read;
        cl_axi_trans_idx_t r_cd_start_trans;
        logic              r_resp_shared;
        logic              r_resp_dirty;
        user_t             r_user;
        slv_bv_t           cd_bv;
        axi_pkg::len_t     r_len;
    } cd_ctrl_sync_reg_t;
    //  }}}

    //  Internal signals
    //  {{{
    cl_axi_trans_idx_t r_cd_start_trans;
    cd_ctrl_sync_reg_t cd_ctrl_sync_wdata;
    cd_ctrl_sync_reg_t cd_ctrl_sync_rdata;
    logic              cd_ctrl_sync_valid;
    logic              cd_ctrl_sync_ready;
    logic              cd_valid;
    logic              cd_ready;
    cd_t               cd;
    logic              r_drop;
    logic              r_done_q;
    logic              r_done_d;
    logic              cd_trans_cnt_clr;
    logic              cd_trans_cnt_en;
    cl_axi_trans_idx_t cd_trans_cnt;
    logic              r_len_cnt_clr;
    logic              r_len_cnt_en;
    axi_pkg::len_t     r_len_cnt;
    rresp_t            r_resp;
    //  }}}

    //  Input handshake decoupling
    //  {{{
    if (CcuCfg.CachelineAxiTransfers == 1) begin : gen_axi_start_trans_eqsize
        assign r_cd_start_trans = '0;
    end else begin : gen_axi_start_trans_diffsize
        assign r_cd_start_trans =
           ax_i.addr[CcuCfg.CachelineBytesIdxWidth-1:CcuCfg.AxiDataBytesIdxWidth];
    end

    assign cd_ctrl_sync_wdata = '{
            id: ax_i.id,
            cd_ctrl_write: cd_ctrl_write_i,
            cd_ctrl_read: cd_ctrl_read_i,
            cd_bv: cd_bv_i,
            r_cd_start_trans: r_cd_start_trans,
            r_resp_shared: r_resp_shared_i,
            r_resp_dirty: r_resp_dirty_i,
            r_user: ax_i.user,
            r_len: ax_i.len
        };

    fall_through_register #(
        .T(cd_ctrl_sync_reg_t)
    ) u_cd_ctrl_sync_reg (
        .clk_i,
        .rst_ni,
        .clr_i     (1'b0),
        .testmode_i(1'b0),
        .data_i    (cd_ctrl_sync_wdata),
        .valid_i   (valid_i),
        .ready_o   (ready_o),
        .data_o    (cd_ctrl_sync_rdata),
        .valid_o   (cd_ctrl_sync_valid),
        .ready_i   (cd_ctrl_sync_ready)
    );
    // }}}

    //  CD responses arbiter
    //  {{{
    ace_ccu_cd_arbiter #(
        .CcuCfg(CcuCfg),
        .cd_t  (cd_t)
    ) u_cd_merge (
        .clk_i,
        .rst_ni,
        .cd_valid_i    (cd_valid_i),
        .cd_ready_o    (cd_ready_o),
        .cd_i          (cd_i),
        .cd_sel_valid_i(cd_ctrl_sync_valid),
        .cd_sel_ready_o(cd_ctrl_sync_ready),
        .cd_sel_bv_i   (cd_ctrl_sync_rdata.cd_bv),
        .cd_valid_o    (cd_valid),
        .cd_ready_i    (cd_ready),
        .cd_o          (cd)
    );
    //  }}}

    //  CD forking
    //  {{{
    assign cd_sel_write = cd_ctrl_sync_rdata.cd_ctrl_write;

    assign cd_sel_read = cd_ctrl_sync_rdata.cd_ctrl_read && ~|{
        // Drop the first transfers if not needed
        r_drop,
        // Drop remaining transfers due to reduced transfer len
        r_done_q};

    stream_fork_dynamic #(
        .N_OUP(2)
    ) u_cd_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (cd_valid),
        .ready_o    (cd_ready),
        .sel_i      ({cd_sel_write, cd_sel_read}),
        .sel_valid_i('1),
        .sel_ready_o(),
        .valid_o    ({w_valid_o, r_valid_o}),
        .ready_i    ({w_ready_i, r_ready_i})
    );
    //  }}}

    //  R channel
    //  {{{
    counter #(
        .WIDTH(CcuCfg.CachelineAxiTransfersIdxWidth)
    ) u_cd_trans_counter (
        .clk_i,
        .rst_ni,
        .clear_i   (cd_trans_cnt_clr),
        .en_i      (cd_trans_cnt_en),
        .load_i    (1'b0),
        .down_i    (1'b0),
        .d_i       ('0),
        .q_o       (cd_trans_cnt),
        .overflow_o()
    );

    counter #(
        .WIDTH($bits(axi_pkg::len_t))
    ) u_r_len_counter (
        .clk_i,
        .rst_ni,
        .clear_i   (r_len_cnt_clr),
        .en_i      (r_len_cnt_en),
        .load_i    ('0),
        .down_i    ('0),
        .d_i       ('0),
        .q_o       (r_len_cnt),
        .overflow_o()
    );

    assign r_drop           = cd_trans_cnt != cd_ctrl_sync_rdata.r_cd_start_trans;
    assign cd_trans_cnt_en  = cd_valid && cd_ready && r_drop;
    assign cd_trans_cnt_clr = cd_valid && cd_ready && cd.last;

    assign r_last           = r_len_cnt == cd_ctrl_sync_rdata.r_len;
    assign r_len_cnt_en     = r_valid_o && r_ready_i;
    assign r_len_cnt_clr    = cd_valid && cd_ready && cd.last;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) r_done_q <= 1'b0;
        else r_done_q <= r_done_d;
    end

    assign r_done_d = !r_len_cnt_clr && ((r_last && r_len_cnt_en) || r_done_q);

    always_comb begin : rresp_comb
        r_resp                 = '0;
        r_resp[RESP_IS_DIRTY]  = cd_ctrl_sync_rdata.r_resp_dirty;
        r_resp[RESP_IS_SHARED] = cd_ctrl_sync_rdata.r_resp_shared;
    end

    assign r_o = '{
            id: cd_ctrl_sync_rdata.id,
            data: cd.data,
            resp: r_resp,
            last: r_last,
            user: cd_ctrl_sync_rdata.r_user
        };
    //  }}}

    //  W channel
    //  {{{
    assign w_o = '{data: cd.data, strb: '1, last: cd.last, user: '0};
    //  }}}

    //  Assertions
    //  {{{

    // If r_done_q is high, r_valid_o should never be raised
    assert property (@(posedge clk_i) disable iff (!rst_ni) r_done_q |-> !r_valid_o);
    // If r_drop is true, r_valid_o should never be raised
    assert property (@(posedge clk_i) disable iff (!rst_ni) r_drop |-> !r_valid_o);
    // If r_last is true, r_o.last should be raised
    assert property (@(posedge clk_i) disable iff (!rst_ni) r_last |-> r_o.last);
    // r_o.last can only be high if r_last is high
    assert property (@(posedge clk_i) disable iff (!rst_ni) r_valid_o && r_o.last |-> r_last);
    // r_valid_o should not be raised if not in read mode
    assert property (@(posedge clk_i) disable iff (!rst_ni) !cd_ctrl_sync_rdata.cd_ctrl_read |-> !r_valid_o);
    // r_valid_o should not be raised if cd_sel_read is not asserted
    assert property (@(posedge clk_i) disable iff (!rst_ni) !cd_sel_read |-> !r_valid_o);
    // w_valid_o should not be raised if cd_sel_write is not asserted
    assert property (@(posedge clk_i) disable iff (!rst_ni) !cd_sel_write |-> !w_valid_o);

    //  }}}

endmodule
