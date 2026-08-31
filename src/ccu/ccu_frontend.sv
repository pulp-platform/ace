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
//
// Authors:
// - Riccardo Tedeschi <riccardo.tedeschi6@unibo.it>

`include "ace/assign.svh"

module ccu_frontend
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg = '{default: '0},

    parameter type ccu_ace_manager_ar_t   = logic,
    parameter type ccu_ace_manager_aw_t   = logic,
    parameter type ccu_w_t                = logic,
    parameter type ccu_ace_manager_r_t    = logic,
    parameter type ccu_ace_manager_b_t    = logic,
    parameter type ccu_ace_manager_req_t  = logic,
    parameter type ccu_ace_manager_resp_t = logic,

    parameter type ccu_ace_subordinate_ar_t   = logic,
    parameter type ccu_ace_subordinate_aw_t   = logic,
    parameter type ccu_ace_subordinate_r_t    = logic,
    parameter type ccu_ace_subordinate_b_t    = logic,
    parameter type ccu_ace_subordinate_req_t  = logic,
    parameter type ccu_ace_subordinate_resp_t = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  ccu_ace_subordinate_req_t  [ccuCfg.u.numSubordinates-1:0]      subordinate_req_i,
    output ccu_ace_subordinate_resp_t [ccuCfg.u.numSubordinates-1:0]      subordinate_resp_o,
    input  logic                      [ccuCfg.u.numSubordinates-1:0]      subordinate_rack_i,
    input  logic                      [ccuCfg.u.numSubordinates-1:0]      subordinate_wack_i,

    output  ccu_ace_manager_req_t                                         manager_req_o,
    input   ccu_ace_manager_resp_t                                        manager_resp_i,
    //  Locally-generated SC fail response marker, aligned with manager R
    input   logic                                                         manager_r_sc_fail_i,
    //  Scoreboard index of the transaction owning the manager R
    input   logic [ccuCfg.transactionIndexWidth-1:0]                      manager_r_tid_i,

    //  Exclusive monitor state and dealloc (monitor lives downstream)
    input  logic [ccuCfg.u.numSubordinates-1:0]                           exclusive_lock_i,
    input  logic [ccuCfg.u.numSubordinates-1:0]
                 [ccuCfg.u.axiSubordinateIdWidth-1:0]                     exclusive_entry_id_i,
    output logic [ccuCfg.u.numSubordinates-1:0]                           exclusive_dealloc_o,

    //  Transactions whose RACK arrived this cycle; several may retire together
    output logic [ccuCfg.u.numShareableTransactions-1:0]                   rack_free_o,

    output logic                                                          pos_aw_valid_o,
    output logic [ccuCfg.addressCheckWidth-1:0]                           pos_aw_slice_o,
    input  logic                                                          pos_aw_full_i
);

    typedef struct packed {
        logic [ccuCfg.transactionIndexWidth-1:0] tid;
        logic                                    exclusive;
    } rack_fifo_entry_t;

    typedef struct packed {
        ccu_ace_manager_r_t                      r;
        logic                                    sc_fail;
        logic [ccuCfg.transactionIndexWidth-1:0] tid;
    } r_spill_entry_t;

    logic [ccuCfg.u.numSubordinates-1:0]
          [ccuCfg.u.numShareableTransactions-1:0] rack_free;

    ccu_ace_subordinate_req_t  [ccuCfg.u.numSubordinates-1:0] subordinate_req;
    ccu_ace_subordinate_resp_t [ccuCfg.u.numSubordinates-1:0] subordinate_resp;

    ccu_ace_manager_req_t  arbiter_req;
    ccu_ace_manager_resp_t arbiter_resp;

    r_spill_entry_t      r_spill_in;
    r_spill_entry_t      r_spill_out;
    logic                r_spill_valid_out;
    logic                r_spill_ready_out;

    //  Per-subordinate logic
    //  {{{
    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_subordinate

        logic             rack_fifo_full;
        logic             rack_fifo_empty;
        rack_fifo_entry_t rack_fifo_wdata;
        rack_fifo_entry_t rack_fifo_rdata;
        logic             rack_fifo_push;
        logic             rack_fifo_pop;

        logic             r_id_hit;

        `ACE_ASSIGN_AR_STRUCT(subordinate_req[s].ar, subordinate_req_i[s].ar)
        assign subordinate_req[s].ar_valid    = subordinate_req_i[s].ar_valid;
        assign subordinate_resp_o[s].ar_ready = subordinate_resp[s].ar_ready;

        `ACE_ASSIGN_R_STRUCT(subordinate_resp_o[s].r, subordinate_resp[s].r)
        assign subordinate_resp_o[s].r_valid = subordinate_resp[s].r_valid && !rack_fifo_full;
        assign subordinate_req[s].r_ready    = subordinate_req_i[s].r_ready && !rack_fifo_full;

        `ACE_ASSIGN_AW_STRUCT(subordinate_req[s].aw, subordinate_req_i[s].aw)
        assign subordinate_req[s].aw_valid    = subordinate_req_i[s].aw_valid;
        assign subordinate_resp_o[s].aw_ready = subordinate_resp[s].aw_ready;

        `AXI_ASSIGN_W_STRUCT(subordinate_req[s].w, subordinate_req_i[s].w)
        assign subordinate_req[s].w_valid    = subordinate_req_i[s].w_valid;
        assign subordinate_resp_o[s].w_ready = subordinate_resp[s].w_ready;

        `AXI_ASSIGN_B_STRUCT(subordinate_resp_o[s].b, subordinate_resp[s].b)
        assign subordinate_resp_o[s].b_valid = subordinate_resp[s].b_valid;
        assign subordinate_req[s].b_ready    = subordinate_req_i[s].b_ready;

        //  The xACK signal is used to extend the lifetime of
        //  a transaction beyond the last R handshake.
        //  Since ACE uses xACK signals to trigger many events
        //  and xACK signals enforce FIFO ordering, a plain FIFO
        //  can be used to push and pop relevant metadata between
        //  a channel response and the associated xACK
        assign rack_fifo_push =
            subordinate_resp_o[s].r_valid && subordinate_req_i[s].r_ready && subordinate_resp_o[s].r.last;

        //  RACK-related metadata are used to:
        //  - retire the AR dispatch entry (by id)
        //  - clear the corresponding exclusive monitor entry
        //  SC failure responses are locally generated, their RACK still
        //  retires the dispatch entry but must not clear the monitor
        assign r_id_hit = exclusive_entry_id_i[s] == subordinate_resp_o[s].r.id;

        assign rack_fifo_wdata = '{
            tid:       r_spill_out.tid,
            exclusive: r_id_hit && exclusive_lock_i[s] && !r_spill_out.sc_fail
        };

        assign rack_fifo_pop = subordinate_rack_i[s];

        fifo_v3 #(
            .FALL_THROUGH (1'b0),
            .DEPTH        (2),
            .dtype        (rack_fifo_entry_t)
        ) u_rack_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .usage_o    (),
            .empty_o    (rack_fifo_empty),
            .full_o     (rack_fifo_full),
            .data_i     (rack_fifo_wdata),
            .push_i     (rack_fifo_push),
            .data_o     (rack_fifo_rdata),
            .pop_i      (rack_fifo_pop)
        );

        assign rack_free[s] = subordinate_rack_i[s] ?
            (ccuCfg.u.numShareableTransactions'(1) << rack_fifo_rdata.tid) : '0;
        assign exclusive_dealloc_o[s] = subordinate_rack_i[s] && rack_fifo_rdata.exclusive;

        // pragma translate_off
        `ifndef VERILATOR
        //  a RACK must match an outstanding R
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            subordinate_rack_i[s] |-> !rack_fifo_empty)
            else $error("RACK without an outstanding R");
        `endif
        // pragma translate_on
    end

    always_comb begin : rack_free_comb
        rack_free_o = '0;
        for (int unsigned s = 0; s < ccuCfg.u.numSubordinates; s++)
            rack_free_o |= rack_free[s];
    end

    // pragma translate_off
    `ifndef VERILATOR
    //  a transaction belongs to one subordinate, so no two RACKs may retire it
    for (genvar a = 0; a < ccuCfg.u.numSubordinates; a++) begin : gen_rack_disjoint_assert
        for (genvar b = a + 1; b < ccuCfg.u.numSubordinates; b++) begin : gen_pair
            assert property (@(posedge clk_i) disable iff (!rst_ni)
                (rack_free[a] & rack_free[b]) == '0)
                else $error("two RACKs retire the same transaction");
        end
    end
    `endif
    // pragma translate_on
    //  }}}

    //  Point of Serialization (PoS)
    //  {{{
    ccu_frontend_arbiter #(
        .numSubordinates      (ccuCfg.u.numSubordinates),
        .aceSubordinateIdWidth(ccuCfg.u.axiSubordinateIdWidth),
        .maxWTrans            (ccuCfg.u.numWriteTransactions),
        .fallThrough          (1'b1),

        .ccu_ace_manager_ar_t  (ccu_ace_manager_ar_t),
        .ccu_ace_manager_aw_t  (ccu_ace_manager_aw_t),
        .ccu_w_t               (ccu_w_t),
        .ccu_ace_manager_r_t   (ccu_ace_manager_r_t),
        .ccu_ace_manager_b_t   (ccu_ace_manager_b_t),
        .ccu_ace_manager_req_t (ccu_ace_manager_req_t),
        .ccu_ace_manager_resp_t(ccu_ace_manager_resp_t),

        .ccu_ace_subordinate_ar_t  (ccu_ace_subordinate_ar_t),
        .ccu_ace_subordinate_aw_t  (ccu_ace_subordinate_aw_t),
        .ccu_ace_subordinate_r_t   (ccu_ace_subordinate_r_t),
        .ccu_ace_subordinate_b_t   (ccu_ace_subordinate_b_t),
        .ccu_ace_subordinate_req_t (ccu_ace_subordinate_req_t),
        .ccu_ace_subordinate_resp_t(ccu_ace_subordinate_resp_t)
    ) u_subordinate_arbiter (
        .clk_i,
        .rst_ni,
        .subordinate_req_i  (subordinate_req),
        .subordinate_resp_o (subordinate_resp),
        .manager_req_o      (arbiter_req),
        .manager_resp_i     (arbiter_resp)
     );
    // }}}

    //  Per-channel spill registers
    //  {{{
    spill_register #(
        .T      (ccu_ace_manager_ar_t),
        .Bypass (!ccuCfg.u.frontendPipeAr)
    ) u_ar_spill (
        .clk_i,
        .rst_ni,
        .valid_i (arbiter_req.ar_valid),
        .ready_o (arbiter_resp.ar_ready),
        .data_i  (arbiter_req.ar),
        .valid_o (manager_req_o.ar_valid),
        .ready_i (manager_resp_i.ar_ready),
        .data_o  (manager_req_o.ar)
    );

    logic aw_spill_valid;
    logic aw_spill_ready;

    //  Stall PoS write acceptance while the engine pending filter is at the bound
    assign aw_spill_valid        = arbiter_req.aw_valid && !pos_aw_full_i;
    assign arbiter_resp.aw_ready = aw_spill_ready      && !pos_aw_full_i;

    assign pos_aw_valid_o = arbiter_req.aw_valid && arbiter_resp.aw_ready;
    assign pos_aw_slice_o = arbiter_req.aw.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];

    spill_register #(
        .T      (ccu_ace_manager_aw_t),
        .Bypass (!ccuCfg.u.frontendPipeAw)
    ) u_aw_spill (
        .clk_i,
        .rst_ni,
        .valid_i (aw_spill_valid),
        .ready_o (aw_spill_ready),
        .data_i  (arbiter_req.aw),
        .valid_o (manager_req_o.aw_valid),
        .ready_i (manager_resp_i.aw_ready),
        .data_o  (manager_req_o.aw)
    );

    spill_register #(
        .T      (ccu_w_t),
        .Bypass (!ccuCfg.u.frontendPipeW)
    ) u_w_spill (
        .clk_i,
        .rst_ni,
        .valid_i (arbiter_req.w_valid),
        .ready_o (arbiter_resp.w_ready),
        .data_i  (arbiter_req.w),
        .valid_o (manager_req_o.w_valid),
        .ready_i (manager_resp_i.w_ready),
        .data_o  (manager_req_o.w)
    );

    spill_register #(
        .T      (ccu_ace_manager_b_t),
        .Bypass (!ccuCfg.u.frontendPipeB)
    ) u_b_spill (
        .clk_i,
        .rst_ni,
        .valid_i (manager_resp_i.b_valid),
        .ready_o (manager_req_o.b_ready),
        .data_i  (manager_resp_i.b),
        .valid_o (arbiter_resp.b_valid),
        .ready_i (arbiter_req.b_ready),
        .data_o  (arbiter_resp.b)
    );

    // R channel: wrap R data + sc_fail through the spill register
    assign r_spill_in = '{
        r:       manager_resp_i.r,
        sc_fail: manager_r_sc_fail_i,
        tid:     manager_r_tid_i
    };

    spill_register #(
        .T      (r_spill_entry_t),
        .Bypass (!ccuCfg.u.frontendPipeR)
    ) u_r_spill (
        .clk_i,
        .rst_ni,
        .valid_i (manager_resp_i.r_valid),
        .ready_o (manager_req_o.r_ready),
        .data_i  (r_spill_in),
        .valid_o (r_spill_valid_out),
        .ready_i (r_spill_ready_out),
        .data_o  (r_spill_out)
    );

    `ACE_ASSIGN_R_STRUCT(arbiter_resp.r, r_spill_out.r)
    assign arbiter_resp.r_valid = r_spill_valid_out;
    assign r_spill_ready_out    = arbiter_req.r_ready;
    //  }}}

endmodule
