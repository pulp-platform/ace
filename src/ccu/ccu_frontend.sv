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
    //  Subset of those whose read errored, so no line was cached
    output logic [ccuCfg.u.numShareableTransactions-1:0]                   rack_error_o,

    output logic                                                          pos_aw_valid_o,
    output logic [ccuCfg.addressCheckWidth-1:0]                           pos_aw_slice_o,
    input  logic                                                          pos_aw_full_i,
    //  Snoop filter de-allocation from the write channel
    output logic [ccuCfg.u.numSubordinates-1:0]                           sf_aw_remove_valid_o,
    input  logic [ccuCfg.u.numSubordinates-1:0]                           sf_aw_remove_ready_i,
    output logic [ccuCfg.u.numSubordinates-1:0]
                 [ccuCfg.u.axiAddressWidth-1:0]                           sf_aw_remove_addr_o
);

    typedef struct packed {
        logic [ccuCfg.transactionIndexWidth-1:0] tid;
        logic                                    exclusive;
        logic                                    error;
    } rack_fifo_entry_t;

    typedef struct packed {
        ccu_ace_manager_r_t                      r;
        logic                                    sc_fail;
        logic [ccuCfg.transactionIndexWidth-1:0] tid;
    } r_spill_entry_t;

    logic [ccuCfg.u.numSubordinates-1:0]
          [ccuCfg.u.numShareableTransactions-1:0] rack_free;
    logic [ccuCfg.u.numSubordinates-1:0]
          [ccuCfg.u.numShareableTransactions-1:0] rack_error;

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
        logic             r_beat;
        logic             r_error;
        logic             r_error_q;

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
        assign r_beat = subordinate_resp_o[s].r_valid && subordinate_req_i[s].r_ready;

        assign rack_fifo_push = r_beat && subordinate_resp_o[s].r.last;

        //  Any beat may carry the error, and AXI4 forbids read interleaving
        assign r_error = r_error_q | subordinate_resp_o[s].r.resp[1];

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni)     r_error_q <= 1'b0;
            else if (r_beat) r_error_q <= subordinate_resp_o[s].r.last ? 1'b0 : r_error;
        end

        //  RACK-related metadata are used to:
        //  - retire the AR dispatch entry (by id)
        //  - clear the corresponding exclusive monitor entry
        //  SC failure responses are locally generated, their RACK still
        //  retires the dispatch entry but must not clear the monitor
        assign r_id_hit = exclusive_entry_id_i[s] == subordinate_resp_o[s].r.id;

        assign rack_fifo_wdata = '{
            tid:       r_spill_out.tid,
            exclusive: r_id_hit && exclusive_lock_i[s] && !r_spill_out.sc_fail,
            error:     r_error
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
        assign rack_error[s] = rack_fifo_rdata.error ? rack_free[s] : '0;
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
        rack_free_o  = '0;
        rack_error_o = '0;
        for (int unsigned s = 0; s < ccuCfg.u.numSubordinates; s++) begin
            rack_free_o  |= rack_free[s];
            rack_error_o |= rack_error[s];
        end
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

    //  Write-channel de-allocation, taken downstream of arbitration so the
    //  subordinate index comes from the id the arbiter already prefixed
    localparam int unsigned subIdxW = ccuCfg.subordinateIndexWidth;
    localparam int unsigned subIdW  = ccuCfg.u.axiSubordinateIdWidth;

    logic [subIdxW-1:0]  aw_sub_idx;
    logic                aw_is_evict, aw_deallocates;
    logic                write_aw_valid, write_aw_ready;
    logic                evict_aw_valid, evict_aw_ready;
    logic                aw_remove_valid, aw_remove_ready;
    logic                evict_b_valid,   evict_b_gnt;
    ccu_ace_manager_b_t  evict_b, evict_b_q;
    logic                mem_b_valid, mem_b_ready;
    ccu_ace_manager_b_t  mem_b;

    assign aw_sub_idx  = arbiter_req.aw.id[subIdW +: subIdxW];
    assign aw_is_evict = ace_is_evict(arbiter_req.aw.bar[0], arbiter_req.aw.domain,
                                      arbiter_req.aw.snoop);
    //  Non-shareable lines are never tracked (C3-13), and WriteBack and
    //  WriteEvict are legal in that domain, so they are excluded here
    assign aw_deallocates =
        arbiter_req.aw.domain inside {InnerShareable, OuterShareable} &&
       (ace_is_write_back (arbiter_req.aw.bar[0], arbiter_req.aw.domain, arbiter_req.aw.snoop) ||
        ace_is_write_evict(arbiter_req.aw.bar[0], arbiter_req.aw.domain, arbiter_req.aw.snoop));

    //  An Evict carries no data and updates no memory (C4.9.1): the removal is
    //  its only destination, so the AW retires on it and the response it makes
    //  leaves a cycle later, never ahead of the request
    stream_demux #(
        .N_OUP (2)
    ) u_aw_evict_demux (
        .inp_valid_i (arbiter_req.aw_valid),
        .inp_ready_o (arbiter_resp.aw_ready),
        .oup_sel_i   (aw_is_evict),
        .oup_valid_o ({evict_aw_valid, write_aw_valid}),
        .oup_ready_i ({evict_aw_ready, write_aw_ready})
    );

    logic aw_spill_valid;
    logic aw_spill_ready;
    logic write_pos_valid, write_pos_ready;
    logic wb_remove_valid;

    //  A writeback carries data, so it de-allocates alongside the write
    stream_fork_dynamic #(
        .N_OUP (2)
    ) u_aw_remove_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (write_aw_valid),
        .ready_o     (write_aw_ready),
        .sel_i       ({aw_deallocates, 1'b1}),
        .sel_valid_i (1'b1),
        .sel_ready_o (),
        .valid_o     ({wb_remove_valid, write_pos_valid}),
        .ready_i     ({aw_remove_ready, write_pos_ready})
    );

    //  One AW sits at the demux at a time, so the two legs never overlap
    assign aw_remove_valid = wb_remove_valid || evict_aw_valid;
    assign aw_remove_ready = sf_aw_remove_ready_i[aw_sub_idx];
    assign evict_aw_ready  = aw_remove_ready && !evict_b_valid;

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_aw_remove
        assign sf_aw_remove_valid_o[s] = aw_remove_valid && aw_sub_idx == subIdxW'(s);
        assign sf_aw_remove_addr_o[s]  = arbiter_req.aw.addr;
    end

    always_comb begin : evict_b_comb
        evict_b      = '0;
        evict_b.id   = arbiter_req.aw.id;
        evict_b.resp = axi_pkg::RESP_OKAY;
        evict_b.user = arbiter_req.aw.user;
    end

    //  Made from the handshake that retires the AW, so it cannot overtake it
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            evict_b_valid <= 1'b0;
            evict_b_q     <= '0;
        end else if (evict_aw_valid && evict_aw_ready) begin
            evict_b_valid <= 1'b1;
            evict_b_q     <= evict_b;
        end else if (evict_b_gnt) begin
            evict_b_valid <= 1'b0;
        end
    end

    //  Stall PoS write acceptance while the engine pending filter is at the bound
    assign aw_spill_valid  = write_pos_valid && !pos_aw_full_i;
    assign write_pos_ready = aw_spill_ready  && !pos_aw_full_i;

    assign pos_aw_valid_o = write_pos_valid && write_pos_ready;
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
        .valid_o (mem_b_valid),
        .ready_i (mem_b_ready),
        .data_o  (mem_b)
    );

    //  An Evict response carries the id the arbiter prefixed, so it demuxes
    //  back to its subordinate like any other
    rr_arb_tree #(
        .NumIn     (2),
        .DataType  (ccu_ace_manager_b_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_b_merge (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   ({evict_b_valid, mem_b_valid}),
        .gnt_o   ({evict_b_gnt,   mem_b_ready}),
        .data_i  ({evict_b_q,     mem_b}),
        .req_o   (arbiter_resp.b_valid),
        .gnt_i   (arbiter_req.b_ready),
        .data_o  (arbiter_resp.b),
        .idx_o   ()
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
