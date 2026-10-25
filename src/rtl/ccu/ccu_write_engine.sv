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

`include "axi/assign.svh"

module ccu_write_engine
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg       = '{default: '0},
    parameter type         ccu_axi_aw_t = logic,
    parameter type         ccu_w_t      = logic,
    parameter type         ccu_axi_b_t  = logic
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    input  logic                                aw_valid_i,
    output logic                                aw_ready_o,
    input  ccu_axi_aw_t                         aw_i,
    input  logic                                w_valid_i,
    output logic                                w_ready_o,
    input  ccu_w_t                              w_i,
    output logic                                b_valid_o,
    input  logic                                b_ready_i,
    output ccu_axi_b_t                          b_o,

    input  logic                                writeback_aw_valid_i,
    output logic                                writeback_aw_ready_o,
    input  ccu_axi_aw_t                         writeback_aw_i,
    input  logic                                writeback_w_valid_i,
    output logic                                writeback_w_ready_o,
    input  ccu_w_t                              writeback_w_i,
    //  Write-back reservation, made before the snoop pipeline releases the line
    input  logic                                wb_alloc_valid_i,
    output logic                                wb_alloc_ready_o,
    input  logic [ccuCfg.addressCheckWidth-1:0] wb_alloc_slice_i,

    output logic                                aw_valid_o,
    input  logic                                aw_ready_i,
    output ccu_axi_aw_t                         aw_o,
    output logic                                w_valid_o,
    input  logic                                w_ready_i,
    output ccu_w_t                              w_o,
    input  logic                                b_valid_i,
    output logic                                b_ready_o,
    input  ccu_axi_b_t                          b_i,

    //  PoS-accepted frontend AW (pre-spill), allocates a pending-write entry
    input  logic                                pos_aw_valid_i,
    input  logic [ccuCfg.addressCheckWidth-1:0] pos_aw_slice_i,
    //  PoS AW gate: stall acceptance while the pending filter is at the bound
    output logic                                pos_aw_full_o,

    //  Memory AR gate: stall while a same-line write is in PoS .. B
    input  logic                                mem_ar_addr_check_i,
    input  logic [ccuCfg.addressCheckWidth-1:0] mem_ar_addr_slice_i,
    output logic                                mem_ar_stall_o,

    output ccu_write_engine_events_t            events_o
);

    localparam int unsigned numFifos   = ccuCfg.numWriteFifos;
    localparam int unsigned hashWidth  = ccuCfg.u.writeHashWidth;
    localparam int unsigned hashLsb    = ccuCfg.u.addressCheckLsb;

    //  Frontend writes and writebacks share one pending pool
    localparam int unsigned numPending   = ccuCfg.u.numWriteTransactions +
                                           ccuCfg.u.numSnoopTransactions;
    localparam int unsigned pendIdxWidth = numPending > 1 ? $clog2(numPending) : 1;

    typedef struct packed {
        logic [ccuCfg.axiCcuIdWidth-1:0] id;
        logic                            is_wb;
        logic [pendIdxWidth-1:0]         sb_idx;
    } inflight_entry_t;

//  AW arbitration
//  {{{
    logic            aw_arb_valid;
    logic            aw_arb_ready;
    ccu_axi_aw_t     aw_arb;
    logic            aw_is_writeback;
    logic [hashWidth-1:0] aw_hash;
    logic            aw_grant;

    logic w_ctrl_fifo_valid_in;
    logic w_ctrl_fifo_ready_in;
    logic writeback_aw_valid;
    logic writeback_aw_ready;
    logic wb_idx_valid, wb_idx_pop;

    //  Wait for the reservation; it is popped by this request's grant, as LockIn needs
    stream_join #(
        .N_INP (2)
    ) u_wb_aw_join (
        .inp_valid_i ({writeback_aw_valid_i, wb_idx_valid}),
        .inp_ready_o ({writeback_aw_ready_o, wb_idx_pop}),
        .oup_valid_o (writeback_aw_valid),
        .oup_ready_i (writeback_aw_ready)
    );

    rr_arb_tree #(
        .NumIn     (2),
        .DataType  (ccu_axi_aw_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_aw_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   ({writeback_aw_valid, aw_valid_i}),
        .gnt_o   ({writeback_aw_ready, aw_ready_o}),
        .data_i  ({writeback_aw_i    , aw_i      }),
        .req_o   (aw_arb_valid),
        .gnt_i   (aw_arb_ready),
        .data_o  (aw_arb),
        .idx_o   (aw_is_writeback)
    );

    assign aw_hash  = aw_arb.addr[hashLsb +: hashWidth];
    assign aw_grant = aw_arb_valid && aw_arb_ready;

    //  Swap the id for the hash index so same-address writes share it
    always_comb begin : aw_id_swap_comb
        aw_o    = aw_arb;
        aw_o.id = '0;
        aw_o.id[hashWidth-1:0] = aw_hash;
    end
//  }}}

//  Pending-write scoreboard (PoS acceptance .. B), queried by the read engine
//  {{{
    logic                                pending_hit;
    logic                                wb_alloc;
    logic                                wb_idx_ready;
    logic                                wb_push;
    logic                                b_free;
    logic [ccuCfg.addressCheckWidth-1:0] aw_arb_slice;
    logic [hashWidth-1:0]                b_hash;
    inflight_entry_t                     b_entry;

    logic [1:0]                    pend_alloc_valid;
    logic [1:0][ccuCfg.addressCheckWidth-1:0] pend_alloc_slice;
    logic [1:0][pendIdxWidth-1:0]  pend_alloc_idx;
    logic [1:0]                    pend_full;
    logic [numPending-1:0]         pend_free_mask;
    logic [numPending-1:0][ccuCfg.addressCheckWidth-1:0] pend_slice;

    assign aw_arb_slice = aw_arb.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];
    assign wb_push      = aw_grant && aw_is_writeback;
    assign b_free       = b_valid_i  && b_ready_o;

    assign wb_alloc_ready_o = !pend_full[0] && wb_idx_ready;
    assign wb_alloc         = wb_alloc_valid_i && wb_alloc_ready_o;

    //  One allocation port each for PoS accepts and writeback reservations
    assign pend_alloc_valid = {pos_aw_valid_i, wb_alloc};
    assign pend_alloc_slice = {pos_aw_slice_i, wb_alloc_slice_i};
    assign pend_free_mask   = b_free ? (numPending'(1) << b_entry.sb_idx) : '0;

    assign pos_aw_full_o = pend_full[1];

    ccu_scoreboard #(
        .numEntries (numPending),
        .sliceWidth (ccuCfg.addressCheckWidth),
        .idWidth    (1),
        .numAlloc   (2),
        .numQueries (1)
    ) u_pending_scoreboard (
        .clk_i,
        .rst_ni,
        .alloc_valid_i (pend_alloc_valid),
        .alloc_slice_i (pend_alloc_slice),
        .alloc_id_i    ('0),
        .alloc_idx_o   (pend_alloc_idx),
        .full_o        (pend_full),
        .retire_mask_i (pend_free_mask),
        .free_mask_i   (pend_free_mask),
        .retired_o     (),
        .query_slice_i (mem_ar_addr_slice_i),
        .query_hit_o   (pending_hit),
        .valid_o       (),
        .slice_o       (pend_slice),
        .id_o          ()
    );

    //  Same-cycle insertions are visible to the query
    assign mem_ar_stall_o = mem_ar_addr_check_i &&
                            (pending_hit ||
                             (pos_aw_valid_i && pos_aw_slice_i == mem_ar_addr_slice_i) ||
                             (wb_alloc && wb_alloc_slice_i == mem_ar_addr_slice_i));
//  }}}

//  Writeback index queue, in reservation order
//  {{{
    logic [pendIdxWidth-1:0] wb_idx_head;

    stream_fifo #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (ccuCfg.u.numSnoopTransactions),
        .DATA_WIDTH   (pendIdxWidth)
    ) u_wb_idx_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .data_i     (pend_alloc_idx[0]),
        .valid_i    (wb_alloc_valid_i && !pend_full[0]),
        .ready_o    (wb_idx_ready),
        .data_o     (wb_idx_head),
        .valid_o    (wb_idx_valid),
        .ready_i    (wb_idx_pop)
    );
//  }}}

//  PoS index queue, in AW order
//  {{{
    logic [pendIdxWidth-1:0] pos_idx_head;
    logic                    pos_idx_full;
    logic                    pos_idx_empty;
    logic                    pos_idx_pop;

    assign pos_idx_pop = aw_grant && !aw_is_writeback;

    fifo_v3 #(
        .FALL_THROUGH (1'b1),
        .DEPTH        (ccuCfg.u.numWriteTransactions),
        .DATA_WIDTH   (pendIdxWidth)
    ) u_pos_idx_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (pos_idx_full),
        .empty_o    (pos_idx_empty),
        .usage_o    (),
        .data_i     (pend_alloc_idx[1]),
        .push_i     (pos_aw_valid_i),
        .data_o     (pos_idx_head),
        .pop_i      (pos_idx_pop)
    );
//  }}}

//  Inflight FIFOs (one per hash)
//  {{{
    logic            [numFifos-1:0] fifo_full;
    logic            [numFifos-1:0] fifo_empty;
    logic            [numFifos-1:0] fifo_push;
    logic            [numFifos-1:0] fifo_pop;
    inflight_entry_t [numFifos-1:0] fifo_rdata;
    inflight_entry_t                fifo_wdata;

    assign fifo_wdata = '{
        id:     aw_arb.id[ccuCfg.axiCcuIdWidth-1:0],
        is_wb:  aw_is_writeback,
        sb_idx: aw_is_writeback ? wb_idx_head : pos_idx_head
    };

    assign b_hash = b_i.id[hashWidth-1:0];

    for (genvar h = 0; h < numFifos; h++) begin : gen_inflight_fifo
        assign fifo_push[h] = aw_grant && aw_hash == hashWidth'(h);
        assign fifo_pop[h]  = b_valid_i  && b_ready_o  && b_hash  == hashWidth'(h);

        fifo_v3 #(
            .FALL_THROUGH (1'b0),
            .DEPTH        (ccuCfg.u.numWriteTransactions),
            .dtype        (inflight_entry_t)
        ) u_inflight_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (fifo_full[h]),
            .empty_o    (fifo_empty[h]),
            .usage_o    (),
            .data_i     (fifo_wdata),
            .push_i     (fifo_push[h]),
            .data_o     (fifo_rdata[h]),
            .pop_i      (fifo_pop[h])
        );
    end

//  }}}

//  AW fork
//  {{{
    //  Fork to the manager AW and the W-steering fifo; the grant books a hash FIFO entry
    stream_fork_dynamic #(
        .N_OUP (2)
    ) u_aw_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (aw_arb_valid),
        .ready_o     (aw_arb_ready),
        .sel_i       ('1),
        .sel_valid_i (!fifo_full[aw_hash]),
        .sel_ready_o (),
        .valid_o     ({aw_valid_o, w_ctrl_fifo_valid_in}),
        .ready_i     ({aw_ready_i, w_ctrl_fifo_ready_in})
    );
//  }}}

//  W muxing
//  {{{
    logic w_ctrl_fifo_valid_out;
    logic w_ctrl_fifo_ready_out;
    logic w_is_writeback;
    logic w_mux_valid_out;
    logic w_mux_ready_out;

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
        .data_o    (w_is_writeback),
        .valid_o   (w_ctrl_fifo_valid_out),
        .ready_i   (w_ctrl_fifo_ready_out && w_o.last)
    );

    stream_mux #(
        .DATA_T(ccu_w_t),
        .N_INP (2)
    ) u_w_mux (
        .inp_data_i ({writeback_w_i      , w_i}),
        .inp_valid_i({writeback_w_valid_i, w_valid_i}),
        .inp_ready_o({writeback_w_ready_o, w_ready_o}),
        .inp_sel_i  (w_is_writeback),
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

//  B channel: recover the original id and drop writeback responses
//  {{{
    assign b_entry = fifo_rdata[b_hash];

    stream_filter u_b_filter (
        .valid_i(b_valid_i),
        .ready_o(b_ready_o),
        .drop_i (b_entry.is_wb),
        .valid_o(b_valid_o),
        .ready_i(b_ready_i)
    );

    always_comb begin : b_comb
        `AXI_SET_B_STRUCT(b_o, b_i)
        b_o.id                           = '0;
        b_o.id[ccuCfg.axiCcuIdWidth-1:0] = b_entry.id;
    end
//  }}}

//  Performance events
//  {{{
    ccu_write_engine_events_t events_d;

    always_comb begin : events_comb
        events_d = '0;

        events_d.aw_issued    = aw_valid_o && aw_ready_i;
        events_d.aw_writeback = wb_push;

        //  Why an AW is not issued: the pending pool, the hash FIFO, memory
        events_d.wb_alloc_stall_full = wb_alloc_valid_i && pend_full[0];
        events_d.aw_stall_hash_full  = aw_arb_valid && fifo_full[aw_hash];
        events_d.aw_stall_mem        = aw_valid_o && !aw_ready_i;

        events_d.w_stall_mem = w_valid_o && !w_ready_i;
        //  An AW is through but its data has not arrived
        events_d.w_starve    = w_ctrl_fifo_valid_out && !w_mux_valid_out;

        //  A memory read held off by a same-line write in PoS .. B (C6.5.1)
        events_d.mem_ar_stall = mem_ar_stall_o;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) events_o <= '0;
        else         events_o <= events_d;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    //  an allocation is gated by its own full, so neither port may overrun
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        pos_aw_valid_i |-> !pend_full[1])
        else $error("PoS AW accepted with no pending entry");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wb_alloc |-> !pend_full[0])
        else $error("writeback reserved with no pending entry");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wb_push |-> wb_idx_valid)
        else $error("writeback issued without a reservation");

    //  the memory AW never runs past its own grant, so the head is still its reservation
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        writeback_aw_valid_i && !writeback_aw_valid |-> !aw_arb_valid || !aw_is_writeback)
        else $error("writeback forwarded while waiting for its reservation");

    //  a pending entry holds the line of the write that allocated it
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wb_alloc |=> pend_slice[$past(pend_alloc_idx[0])] == $past(wb_alloc_slice_i))
        else $error("writeback pending entry holds the wrong line");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        wb_push |-> pend_slice[wb_idx_head] == aw_arb_slice)
        else $error("writeback issued under another line's reservation");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        pos_aw_valid_i |=> pend_slice[$past(pend_alloc_idx[1])] == $past(pos_aw_slice_i))
        else $error("PoS pending entry holds the wrong line");

    //  the index queue mirrors the PoS accepts, so it never drops or starves
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        pos_aw_valid_i |-> !pos_idx_full)
        else $error("PoS index queue overflow");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        pos_idx_pop |-> !pos_idx_empty)
        else $error("frontend AW with no PoS index");

    //  a memory B must match a tracked write
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        b_valid_i |-> !fifo_empty[b_hash])
        else $error("B response without a tracked write");

    //  the B channel is stable while stalled
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        b_valid_o && !b_ready_i |=> b_valid_o && $stable(b_o))
        else $error("B channel unstable while stalled");

    //  W carries no id: each memory W burst must match the AW it was steered for
    axi_pkg::len_t chk_len [$];
    axi_pkg::len_t chk_beat;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            chk_len.delete();
            chk_beat = '0;
        end else begin
            if (w_ctrl_fifo_valid_in && w_ctrl_fifo_ready_in) chk_len.push_back(aw_arb.len);
            if (w_valid_o && w_ready_i) begin
                assert (chk_len.size() != 0) else $error("memory W with no AW");
                if (chk_len.size() != 0) begin
                    assert (w_o.last == (chk_beat == chk_len[0]))
                        else $error("memory W burst (%s): last on beat %0d, AW len %0d",
                                    w_is_writeback ? "writeback" : "frontend", chk_beat, chk_len[0]);
                    if (w_o.last) void'(chk_len.pop_front());
                end
                chk_beat = w_o.last ? '0 : chk_beat + 1;
            end
        end
    end
    `endif
    // pragma translate_on
//  }}}
endmodule
