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
    parameter type ccu_ace_subordinate_resp_t = logic,

    localparam int unsigned scoreboardEntryIndexWidth = ccuCfg.transactionIndexWidth

) (
    input  logic clk_i,
    input  logic rst_ni,

    input  ccu_ace_subordinate_req_t  [ccuCfg.u.numSubordinates-1:0]                  subordinate_req_i,
    output ccu_ace_subordinate_resp_t [ccuCfg.u.numSubordinates-1:0]                  subordinate_resp_o,
    input  logic                      [ccuCfg.u.numSubordinates-1:0]                  subordinate_rack_i,
    input  logic                      [ccuCfg.u.numSubordinates-1:0]                  subordinate_wack_i,

    output  ccu_ace_manager_req_t                                                     manager_req_o,
    input   ccu_ace_manager_resp_t                                                    manager_resp_i,

    output logic                                                                      scoreboard_dealloc_check_o,
    output logic [ccuCfg.axiCcuIdWidth-1:0]                                           scoreboard_dealloc_id_o,
    input  logic                                                                      scoreboard_dealloc_hit_i,
    input  logic [scoreboardEntryIndexWidth-1:0]                                      scoreboard_dealloc_entry_i,
    output logic [ccuCfg.u.numSubordinates-1:0]                                       scoreboard_dealloc_o,
    output logic [ccuCfg.u.numSubordinates-1:0][scoreboardEntryIndexWidth-1:0]        scoreboard_dealloc_entry_o
);

    typedef struct packed {
        logic [ccuCfg.transactionIndexWidth-1:0]   tid;
        logic                                      dealloc;
        logic                                      exclusive;
    } rack_fifo_entry_t;

    typedef struct packed {
        ccu_ace_manager_r_t r;
        logic               sc_fail;
    } r_spill_entry_t;

    ccu_ace_subordinate_req_t  [ccuCfg.u.numSubordinates-1:0] subordinate_req;
    ccu_ace_subordinate_resp_t [ccuCfg.u.numSubordinates-1:0] subordinate_resp;

    ccu_ace_manager_req_t  arbiter_req;
    ccu_ace_manager_resp_t arbiter_resp;

    logic [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_lock;
    logic [ccuCfg.u.numSubordinates-1:0][ccuCfg.u.axiSubordinateIdWidth-1:0] exclusive_monitor_entry_id;
    logic exclusive_monitor_sc_fail;
    logic [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_dealloc;

    // Exclusive monitor AR/R (post AR-spill, pre manager)
    ccu_ace_manager_ar_t exclusive_monitor_ar_in;
    logic                exclusive_monitor_ar_valid_in;
    logic                exclusive_monitor_ar_ready_in;

    // Exclusive monitor R output (pre R-spill)
    ccu_ace_manager_r_t  exclusive_monitor_r;
    logic                exclusive_monitor_r_valid;
    logic                exclusive_monitor_r_ready;

    r_spill_entry_t      r_spill_in;
    r_spill_entry_t      r_spill_out;
    logic                r_spill_valid_out;
    logic                r_spill_ready_out;

    //  Per-subordinate logic
    //  {{{
    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_subordinate

        logic is_exclusive_sequence;
        logic lock_stall;

        logic             rack_fifo_full;
        rack_fifo_entry_t rack_fifo_wdata;
        rack_fifo_entry_t rack_fifo_rdata;
        logic             rack_fifo_push;
        logic             rack_fifo_pop;

        logic             r_id_hit;

        assign is_exclusive_sequence =
            ace_ar_is_exclusive_load (
                subordinate_req_i[s].ar.bar[0],
                subordinate_req_i[s].ar.domain,
                subordinate_req_i[s].ar.snoop,
                subordinate_req_i[s].ar.lock
            ) ||
            ace_ar_is_exclusive_store(
                subordinate_req_i[s].ar.bar[0],
                subordinate_req_i[s].ar.domain,
                subordinate_req_i[s].ar.snoop,
                subordinate_req_i[s].ar.lock
            );

        assign lock_stall = is_exclusive_sequence &&
                            |exclusive_monitor_lock && !exclusive_monitor_lock[s];

        `ACE_ASSIGN_AR_STRUCT(subordinate_req[s].ar, subordinate_req_i[s].ar)
        assign subordinate_req[s].ar_valid    = subordinate_req_i[s].ar_valid && !lock_stall;
        assign subordinate_resp_o[s].ar_ready = subordinate_resp[s].ar_ready  && !lock_stall;

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
        //  - clear the corresponding scoreboard entry
        //  - clear the corresponding exclusive monitor entry
        //  SC failure responses are locally generated, thus no entry should be cleared
        //  once the RACK arrives
        assign r_id_hit = exclusive_monitor_entry_id[s] == subordinate_resp_o[s].r.id;

        assign rack_fifo_wdata = '{
            tid:       scoreboard_dealloc_entry_i,
            dealloc:   scoreboard_dealloc_hit_i              && !r_spill_out.sc_fail,
            exclusive: r_id_hit && exclusive_monitor_lock[s] && !r_spill_out.sc_fail
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
            .empty_o    (),
            .full_o     (rack_fifo_full),
            .data_i     (rack_fifo_wdata),
            .push_i     (rack_fifo_push),
            .data_o     (rack_fifo_rdata),
            .pop_i      (rack_fifo_pop)
        );

        assign scoreboard_dealloc_o[s]       = subordinate_rack_i[s] && rack_fifo_rdata.dealloc;
        assign scoreboard_dealloc_entry_o[s] = rack_fifo_rdata.tid;
        assign exclusive_monitor_dealloc[s]  = subordinate_rack_i[s] && rack_fifo_rdata.exclusive;
    end
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
        .valid_o (exclusive_monitor_ar_valid_in),
        .ready_i (exclusive_monitor_ar_ready_in),
        .data_o  (exclusive_monitor_ar_in)
    );

    spill_register #(
        .T      (ccu_ace_manager_aw_t),
        .Bypass (!ccuCfg.u.frontendPipeAw)
    ) u_aw_spill (
        .clk_i,
        .rst_ni,
        .valid_i (arbiter_req.aw_valid),
        .ready_o (arbiter_resp.aw_ready),
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
        r:       exclusive_monitor_r,
        sc_fail: exclusive_monitor_sc_fail
    };

    spill_register #(
        .T      (r_spill_entry_t),
        .Bypass (!ccuCfg.u.frontendPipeR)
    ) u_r_spill (
        .clk_i,
        .rst_ni,
        .valid_i (exclusive_monitor_r_valid),
        .ready_o (exclusive_monitor_r_ready),
        .data_i  (r_spill_in),
        .valid_o (r_spill_valid_out),
        .ready_i (r_spill_ready_out),
        .data_o  (r_spill_out)
    );

    `ACE_ASSIGN_R_STRUCT(arbiter_resp.r, r_spill_out.r)
    assign arbiter_resp.r_valid = r_spill_valid_out;
    assign r_spill_ready_out    = arbiter_req.r_ready;
    //  }}}

    // ACE exclusive monitor
    //  {{{
    ccu_exclusive_monitor #(
        .ccuCfg       (ccuCfg),
        .ccu_ace_ar_t (ccu_ace_manager_ar_t),
        .ccu_ace_r_t  (ccu_ace_manager_r_t)
    ) u_ccu_exclusive_monitor (
        .clk_i,
        .rst_ni,
        .dealloc_i  (exclusive_monitor_dealloc),
        .lock_o     (exclusive_monitor_lock),
        .entry_id_o (exclusive_monitor_entry_id),
        .sc_fail_o  (exclusive_monitor_sc_fail),
        .ar_i       (exclusive_monitor_ar_in),
        .ar_valid_i (exclusive_monitor_ar_valid_in),
        .ar_ready_o (exclusive_monitor_ar_ready_in),
        .ar_o       (manager_req_o.ar),
        .ar_valid_o (manager_req_o.ar_valid),
        .ar_ready_i (manager_resp_i.ar_ready),
        .r_i        (manager_resp_i.r),
        .r_valid_i  (manager_resp_i.r_valid),
        .r_ready_o  (manager_req_o.r_ready),
        .r_o        (exclusive_monitor_r),
        .r_valid_o  (exclusive_monitor_r_valid),
        .r_ready_i  (exclusive_monitor_r_ready)
    );
    //  }}}

    //  Scoreboard dealloc check on post-spill R (aligned with per-sub R demux)
    //  {{{
        assign scoreboard_dealloc_check_o =
            r_spill_valid_out && r_spill_ready_out && r_spill_out.r.last;
        assign scoreboard_dealloc_id_o    = r_spill_out.r.id;
    //  }}}
endmodule
