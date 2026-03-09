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

    ccu_ace_subordinate_req_t  [ccuCfg.u.numSubordinates-1:0] subordinate_req;
    ccu_ace_subordinate_resp_t [ccuCfg.u.numSubordinates-1:0] subordinate_resp;

    ccu_ace_subordinate_ar_t [ccuCfg.u.numSubordinates-1:0] subordinate_ar;
    logic                    [ccuCfg.u.numSubordinates-1:0] subordinate_ar_valid;
    logic                    [ccuCfg.u.numSubordinates-1:0] subordinate_ar_ready;
    ccu_ace_subordinate_r_t  [ccuCfg.u.numSubordinates-1:0] subordinate_r;
    logic                    [ccuCfg.u.numSubordinates-1:0] subordinate_r_valid;
    logic                    [ccuCfg.u.numSubordinates-1:0] subordinate_r_ready;

    ccu_ace_subordinate_ar_t [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_ar;
    logic                    [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_ar_valid;
    logic                    [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_ar_ready;
    ccu_ace_subordinate_r_t  [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_r;
    logic                    [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_r_valid;
    logic                    [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_r_ready;


    logic [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_id_hit;
    logic [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_dealloc;
    logic [ccuCfg.u.numSubordinates-1:0] exclusive_monitor_sc_fail;

    //  Per-subordinate logic
    //  {{{
    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_subordinate_monitor

        logic             rack_fifo_full;
        rack_fifo_entry_t rack_fifo_wdata;
        rack_fifo_entry_t rack_fifo_rdata;
        logic             rack_fifo_push;
        logic             rack_fifo_pop;

        always_comb begin : ar_comb
            //  Input request --> exclusive monitor
            `ACE_SET_AR_STRUCT(subordinate_ar[s], subordinate_req_i[s].ar)
            subordinate_ar_valid[s] = subordinate_req_i[s].ar_valid;
            subordinate_resp_o[s].ar_ready = subordinate_ar_ready[s];

            //  Exclusive monitor --> mux
            `ACE_SET_AR_STRUCT(subordinate_req[s].ar, exclusive_monitor_ar[s])
            subordinate_req[s].ar_valid = exclusive_monitor_ar_valid[s];
            exclusive_monitor_ar_ready[s] = subordinate_resp[s].ar_ready;
        end

        always_comb begin : r_comb
            //  Input request <-- exclusive monitor
            `ACE_SET_R_STRUCT(subordinate_resp_o[s].r, subordinate_r[s])
            subordinate_resp_o[s].r_valid = subordinate_r_valid[s];
            subordinate_r_ready[s] = subordinate_req_i[s].r_ready;

            //  Exclusive monitor <-- mux
            `ACE_SET_R_STRUCT(exclusive_monitor_r[s], subordinate_resp[s].r)
            exclusive_monitor_r_valid[s] = subordinate_resp[s].r_valid;
            subordinate_req[s].r_ready = exclusive_monitor_r_ready[s];

            //  Stall R responses once the RACK fifo is full
            if (rack_fifo_full) begin
                exclusive_monitor_r_valid[s] = 1'b0;
                subordinate_req[s].r_ready = 1'b0;
            end
        end

        always_comb begin : aw_comb
            //  Input request --> mux
            `ACE_SET_AW_STRUCT(subordinate_req[s].aw, subordinate_req_i[s].aw)
            subordinate_req[s].aw_valid = subordinate_req_i[s].aw_valid;
            subordinate_resp_o[s].aw_ready = subordinate_resp[s].aw_ready;
        end

        always_comb begin : w_comb
            //  Input request --> mux
            `AXI_SET_W_STRUCT(subordinate_req[s].w, subordinate_req_i[s].w)
            subordinate_req[s].w_valid = subordinate_req_i[s].w_valid;
            subordinate_resp_o[s].w_ready = subordinate_resp[s].w_ready;
        end

        always_comb begin : b_comb
            //  Input request <-- mux
            `AXI_SET_B_STRUCT(subordinate_resp_o[s].b, subordinate_resp[s].b)
            subordinate_resp_o[s].b_valid = subordinate_resp[s].b_valid;
            subordinate_req[s].b_ready = subordinate_req_i[s].b_ready;
        end


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
        assign rack_fifo_wdata = '{
            tid:       scoreboard_dealloc_entry_i,
            dealloc:   scoreboard_dealloc_hit_i    && !exclusive_monitor_sc_fail[s],
            exclusive: exclusive_monitor_id_hit[s] && !exclusive_monitor_sc_fail[s]
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

    // ACE exclusive monitor as prescribed in the specs
    ccu_exclusive_monitor #(
        .ccuCfg       (ccuCfg),
        .ccu_ace_ar_t (ccu_ace_subordinate_ar_t),
        .ccu_ace_r_t  (ccu_ace_subordinate_r_t)
    ) u_ccu_exclusive_monitor (
        .clk_i,
        .rst_ni,
        .dealloc_i  (exclusive_monitor_dealloc),
        .sc_fail_o  (exclusive_monitor_sc_fail),
        .r_id_hit_o (exclusive_monitor_id_hit),
        .ar_i       (subordinate_ar),
        .ar_valid_i (subordinate_ar_valid),
        .ar_ready_o (subordinate_ar_ready),
        .r_o        (subordinate_r),
        .r_valid_o  (subordinate_r_valid),
        .r_ready_i  (subordinate_r_ready),
        .ar_o       (exclusive_monitor_ar),
        .ar_valid_o (exclusive_monitor_ar_valid),
        .ar_ready_i (exclusive_monitor_ar_ready),
        .r_i        (exclusive_monitor_r),
        .r_valid_i  (exclusive_monitor_r_valid),
        .r_ready_o  (exclusive_monitor_r_ready)
    );
    //  }}}

    //  Point of Serialization (PoS)
    //  {{{
    axi_mux #(
        .SlvAxiIDWidth (ccuCfg.u.axiSubordinateIdWidth),
        .slv_aw_chan_t (ccu_ace_subordinate_aw_t),
        .mst_aw_chan_t (ccu_ace_manager_aw_t),
        .w_chan_t      (ccu_w_t),
        .slv_b_chan_t  (ccu_ace_subordinate_b_t),
        .mst_b_chan_t  (ccu_ace_manager_b_t),
        .slv_ar_chan_t (ccu_ace_subordinate_ar_t),
        .mst_ar_chan_t (ccu_ace_manager_ar_t),
        .slv_r_chan_t  (ccu_ace_subordinate_r_t),
        .mst_r_chan_t  (ccu_ace_manager_r_t),
        .slv_req_t     (ccu_ace_subordinate_req_t),
        .slv_resp_t    (ccu_ace_subordinate_resp_t),
        .mst_req_t     (ccu_ace_manager_req_t),
        .mst_resp_t    (ccu_ace_manager_resp_t),
        .NoSlvPorts    (ccuCfg.u.numSubordinates),
        .MaxWTrans     (ccuCfg.u.numWriteTransactions),
        .FallThrough   (1'b1),
        .SpillAw       (1'b0),
        .SpillW        (1'b0),
        .SpillB        (1'b0),
        .SpillAr       (1'b0),
        .SpillR        (1'b0)
    ) u_subordinate_mux (
        .clk_i,
        .rst_ni,
        .test_i      (1'b0),
        .slv_reqs_i  (subordinate_req),
        .slv_resps_o (subordinate_resp),
        .mst_req_o   (manager_req_o),
        .mst_resp_i  (manager_resp_i)
    );
    // }}}

    //  Scoreboard dealloc check
    //  {{{
        assign scoreboard_dealloc_check_o =
            manager_resp_i.r_valid && manager_req_o.r_ready && manager_resp_i.r.last;
        assign scoreboard_dealloc_id_o    = manager_resp_i.r.id;
    //  }}}
endmodule
