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

    output logic                                aw_valid_o,
    input  logic                                aw_ready_i,
    output ccu_axi_aw_t                         aw_o,
    output logic                                w_valid_o,
    input  logic                                w_ready_i,
    output ccu_w_t                              w_o,
    input  logic                                b_valid_i,
    output logic                                b_ready_o,
    input  ccu_axi_b_t                          b_i,

    //  WACK of master writes, retires the address from the hazard check
    input  logic [ccuCfg.u.numSubordinates-1:0] wack_i,

    //  Address hazard check: a read collides while a write to the same line
    //  is inflight towards memory (issued .. B) or awaiting its WACK (B .. WACK)
    input  logic                                read_engine_addr_check_i,
    output logic                                read_engine_addr_hit_o,
    input  logic [ccuCfg.addressCheckWidth-1:0] read_engine_addr_slice_i
);

    localparam int unsigned numFifos   = ccuCfg.numWriteFifos;
    localparam int unsigned hashWidth  = ccuCfg.u.writeHashWidth;
    localparam int unsigned hashLsb    = ccuCfg.u.addressCheckLsb;

    typedef struct packed {
        logic [ccuCfg.addressCheckWidth-1:0] addr;
        logic [ccuCfg.axiCcuIdWidth-1:0]     id;
        logic                                is_wb;
    } inflight_entry_t;

//  AW arbitration
//  {{{
    logic            aw_arb_valid;
    logic            aw_arb_ready;
    ccu_axi_aw_t     aw_arb;
    logic            aw_is_writeback;
    logic [hashWidth-1:0] aw_hash;

    logic w_ctrl_fifo_valid_in;
    logic w_ctrl_fifo_ready_in;

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
        .req_i   ({writeback_aw_valid_i, aw_valid_i}),
        .gnt_o   ({writeback_aw_ready_o, aw_ready_o}),
        .data_i  ({writeback_aw_i      , aw_i      }),
        .req_o   (aw_arb_valid),
        .gnt_i   (aw_arb_ready),
        .data_o  (aw_arb),
        .idx_o   (aw_is_writeback)
    );

    assign aw_hash = aw_arb.addr[hashLsb +: hashWidth];

    //  Swap the id for the hash index so same-address writes share it
    always_comb begin : aw_id_swap_comb
        aw_o    = aw_arb;
        aw_o.id = '0;
        aw_o.id[hashWidth-1:0] = aw_hash;
    end
//  }}}

//  Inflight FIFOs (one per hash)
//  {{{
    logic            [numFifos-1:0] fifo_full;
    logic            [numFifos-1:0] fifo_push;
    logic            [numFifos-1:0] fifo_pop;
    inflight_entry_t [numFifos-1:0] fifo_rdata;
    logic            [numFifos-1:0] fifo_exists;
    inflight_entry_t                fifo_wdata;
    inflight_entry_t                exists_mask;

    logic [hashWidth-1:0] b_hash;
    logic [hashWidth-1:0] check_hash;
    inflight_entry_t      b_entry;

    assign fifo_wdata = '{
        addr:  aw_arb.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb],
        id:    aw_arb.id[ccuCfg.axiCcuIdWidth-1:0],
        is_wb: aw_is_writeback
    };

    always_comb begin : exists_mask_comb
        exists_mask       = '0;
        exists_mask.addr  = '1;
    end

    assign b_hash     = b_i.id[hashWidth-1:0];
    assign check_hash = read_engine_addr_slice_i[hashWidth-1:0];

    for (genvar h = 0; h < numFifos; h++) begin : gen_inflight_fifo
        inflight_entry_t exists_data;
        assign exists_data = '{addr: read_engine_addr_slice_i, id: '0, is_wb: 1'b0};

        assign fifo_push[h] = aw_valid_o && aw_ready_i && aw_hash == hashWidth'(h);
        assign fifo_pop[h]  = b_valid_i  && b_ready_o  && b_hash  == hashWidth'(h);

        ccu_fifo #(
            .numEntries (ccuCfg.u.numWriteTransactions),
            .data_t     (inflight_entry_t)
        ) u_inflight_fifo (
            .clk_i,
            .rst_ni,
            .flush_i       (1'b0),
            .full_o        (fifo_full[h]),
            .empty_o       (),
            .usage_o       (),
            .data_i        (fifo_wdata),
            .push_i        (fifo_push[h]),
            .data_o        (fifo_rdata[h]),
            .pop_i         (fifo_pop[h]),
            .exists_data_i (exists_data),
            .exists_mask_i (exists_mask),
            .exists_o      (fifo_exists[h])
        );
    end

//  }}}

//  WACK address tracking (B .. WACK, master writes only)
//  {{{
    //  A master write leaves the hash FIFO at its B, but the ACE snoop
    //  ordering rule (IHI0022E C6.2) forbids snooping the line until its
    //  WACK. Each master write's address is therefore parked, per
    //  subordinate, from the B forwarded to the master until its WACK.
    logic [ccuCfg.addressCheckWidth-1:0] b_addr_slice;
    logic [ccuCfg.subordinateIndexWidth-1:0] b_sub_index;
    logic [ccuCfg.u.numSubordinates-1:0] wack_fifo_exists;

    assign b_addr_slice = b_entry.addr;
    assign b_sub_index  = b_entry.id[ccuCfg.axiCcuIdWidth-1 -: ccuCfg.subordinateIndexWidth];

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_wack_fifo
        logic push;
        assign push = b_valid_o && b_ready_i && b_sub_index == ccuCfg.subordinateIndexWidth'(s);

        ccu_fifo #(
            .numEntries (ccuCfg.u.numWriteTransactions),
            .data_t     (logic [ccuCfg.addressCheckWidth-1:0])
        ) u_wack_fifo (
            .clk_i,
            .rst_ni,
            .flush_i       (1'b0),
            .full_o        (),
            .empty_o       (),
            .usage_o       (),
            .data_i        (b_addr_slice),
            .push_i        (push),
            .data_o        (),
            .pop_i         (wack_i[s]),
            .exists_data_i (read_engine_addr_slice_i),
            .exists_mask_i ('1),
            .exists_o      (wack_fifo_exists[s])
        );
    end

    //  A read hazards a write inflight to memory or awaiting its WACK
    assign read_engine_addr_hit_o = read_engine_addr_check_i &&
                                    (fifo_exists[check_hash] || |wack_fifo_exists);
//  }}}

//  AW fork
//  {{{
    //  Fork the arbitrated AW into the manager AW and the W-steering fifo.
    //  Stall on a full hash FIFO so the inflight bookkeeping never overflows.
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
endmodule
