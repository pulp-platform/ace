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
`include "ace/assign.svh"

module ccu_exclusive_monitor
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg = '{default: '0},

    parameter type ccu_ace_ar_t   = logic,
    parameter type ccu_ace_r_t    = logic
) (
    input logic  clk_i,
    input logic  rst_ni,

    input  logic        [ccuCfg.u.numSubordinates-1:0] dealloc_i,
    output logic        [ccuCfg.u.numSubordinates-1:0] sc_fail_o,

    output logic        [ccuCfg.u.numSubordinates-1:0] r_id_hit_o,

    input  ccu_ace_ar_t [ccuCfg.u.numSubordinates-1:0] ar_i,
    input  logic        [ccuCfg.u.numSubordinates-1:0] ar_valid_i,
    output logic        [ccuCfg.u.numSubordinates-1:0] ar_ready_o,
    output  ccu_ace_r_t [ccuCfg.u.numSubordinates-1:0] r_o,
    output  logic       [ccuCfg.u.numSubordinates-1:0] r_valid_o,
    input   logic       [ccuCfg.u.numSubordinates-1:0] r_ready_i,

    output ccu_ace_ar_t [ccuCfg.u.numSubordinates-1:0] ar_o,
    output logic        [ccuCfg.u.numSubordinates-1:0] ar_valid_o,
    input  logic        [ccuCfg.u.numSubordinates-1:0] ar_ready_i,
    input  ccu_ace_r_t  [ccuCfg.u.numSubordinates-1:0] r_i,
    input  logic        [ccuCfg.u.numSubordinates-1:0] r_valid_i,
    output logic        [ccuCfg.u.numSubordinates-1:0] r_ready_o
);

typedef struct packed {
    logic [ccuCfg.u.axiSubordinateIdWidth-1:0] id;
} exclusive_monitor_entry_t;

typedef struct packed {
    logic [ccuCfg.u.axiSubordinateIdWidth-1:0] id;
    logic [ccuCfg.u.axiUserWidth-1:0]          user;
} r_register_entry_t;

exclusive_monitor_entry_t [ccuCfg.u.numSubordinates-1:0] entry_q;
exclusive_monitor_entry_t [ccuCfg.u.numSubordinates-1:0] entry_d;
logic                     [ccuCfg.u.numSubordinates-1:0] valid_q;
logic                     [ccuCfg.u.numSubordinates-1:0] valid_d;
logic                     [ccuCfg.u.numSubordinates-1:0] lock_q;
logic                     [ccuCfg.u.numSubordinates-1:0] lock_d;

logic                     [ccuCfg.u.numSubordinates-1:0] exclusive_store_pass;

for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_entry
    logic is_exclusive_sequence;
    logic is_exclusive_load;
    logic is_exclusive_store;
    logic reservation_set;
    logic reservation_reset;
    logic exclusive_store_will_fail;

    r_register_entry_t r_register_wdata;
    r_register_entry_t r_register_rdata;
    logic              r_register_valid;
    logic              r_register_ready;
    logic              r_ack_valid;
    logic              r_ack_ready;
    ccu_ace_r_t        r_ack;

    logic              ar_valid;
    logic              ar_ready;

    assign r_id_hit_o[s] = entry_q[s].id == r_o[s].id;

    assign is_exclusive_load = ar_i[s].lock && (
        ace_is_read_clean (
            ar_i[s].bar,
            ar_i[s].domain,
            ar_i[s].snoop
        ) ||
        ace_is_read_shared(
            ar_i[s].bar,
            ar_i[s].domain,
            ar_i[s].snoop
        ));

    assign is_exclusive_store = ar_i[s].lock &&
        ace_is_clean_unique(
            ar_i[s].bar,
            ar_i[s].domain,
            ar_i[s].snoop
        );

    assign is_exclusive_sequence = is_exclusive_store || is_exclusive_load;

    assign reservation_set = ar_valid_i[s] && ar_ready_o[s] && is_exclusive_sequence;
    assign reservation_reset = |exclusive_store_pass && !exclusive_store_pass[s];
    assign exclusive_store_pass[s] = ar_valid_i[s] && ar_ready_o[s] && is_exclusive_store && valid_q[s];
    assign exclusive_store_will_fail = !valid_q[s] && is_exclusive_store;

    always_comb begin
        entry_d[s] = entry_q[s];
        valid_d[s] = valid_q[s];
        lock_d [s] = lock_q [s];

        if (dealloc_i[s]) begin
            lock_d[s] = 1'b0;
        end else if (exclusive_store_pass[s]) begin
            lock_d[s] = 1'b1;
        end else if (reservation_reset) begin
            valid_d[s] = 1'b0;
        end else if (reservation_set) begin
            valid_d[s] = 1'b1;
            entry_d[s].id = ar_i[s].id;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            entry_q[s] <= '0;
            valid_q[s] <= 1'b0;
            lock_q [s] <= 1'b0;
        end else begin
            entry_q[s] <= entry_d[s];
            valid_q[s] <= valid_d[s];
            lock_q [s] <= lock_d [s];
        end
    end

    assign ar_valid      = ar_valid_i[s] &&
                         !(is_exclusive_sequence && |lock_q && !lock_q[s]);
    assign ar_ready_o[s] = ar_ready &&
                         !(is_exclusive_sequence && |lock_q && !lock_q[s]);

    stream_demux #(
        .N_OUP (2)
    ) u_ar_demux (
        .inp_valid_i (ar_valid),
        .inp_ready_o (ar_ready),
        .oup_sel_i   (exclusive_store_will_fail),
        .oup_valid_o ({r_register_valid, ar_valid_o[s]}),
        .oup_ready_i ({r_register_ready, ar_ready_i[s]})
    );

    `ACE_ASSIGN_AR_STRUCT(ar_o[s], ar_i[s])

    assign r_register_wdata = '{
        id:   ar_i[s].id,
        user: ar_i[s].user
    };

    stream_register #(
        .T (r_register_entry_t)
    ) u_r_register (
        .clk_i,
        .rst_ni,
        .clr_i      (1'b0),
        .testmode_i (1'b0),
        .valid_i    (r_register_valid),
        .ready_o    (r_register_ready),
        .data_i     (r_register_wdata),
        .valid_o    (r_ack_valid),
        .ready_i    (r_ack_ready),
        .data_o     (r_register_rdata)
    );

    assign r_ack = '{
        id:   r_register_rdata.id,
        data: r_i[s].data, // Don't care
        resp: {2'b00, axi_pkg::RESP_OKAY},
        last: 1'b1,
        user: r_register_rdata.user
    };

    logic [1:0] r_arbiter_valid;
    logic [1:0] r_arbiter_ready;
    logic [1:0] mask_d;
    logic [1:0] mask_q;

    assign r_arbiter_valid = {r_ack_valid, r_valid_i[s]} & ~mask_q;
    assign {r_ack_ready, r_ready_o[s]} = r_arbiter_ready & ~mask_q;

    always_comb begin : mask_comb
        mask_d = mask_q;
        if (r_valid_o[s] && r_ready_i[s] && r_o[s].last)
            mask_d = '0;
        else if (r_valid_o[s] && r_ready_i[s])
            mask_d = ~(r_arbiter_valid & r_arbiter_ready);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) mask_q <= '0;
        else         mask_q <= mask_d;
    end

    rr_arb_tree #(
        .NumIn     (2),
        .DataType  (ccu_ace_r_t),
        .ExtPrio   (1'b0),
        .AxiVldRdy (1'b1),
        .LockIn    (1'b1),
        .FairArb   (1'b1)
    ) u_r_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i (1'b0),
        .rr_i    ('0),
        .req_i   (r_arbiter_valid),
        .gnt_o   (r_arbiter_ready),
        .data_i  ({r_ack, r_i[s]}),
        .req_o   (r_valid_o[s]),
        .gnt_i   (r_ready_i[s]),
        .data_o  (r_o[s]),
        .idx_o   (sc_fail_o[s])
    );
end

endmodule
