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

module ccu_exclusive_monitor
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg = '{default: '0},

    parameter type ccu_ar_req_t = logic,
    parameter type ccu_ace_r_t  = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [ccuCfg.u.numSubordinates-1:0] dealloc_i,
    output logic [ccuCfg.u.numSubordinates-1:0] lock_o,
    output logic [ccuCfg.u.numSubordinates-1:0]
                 [ccuCfg.u.axiSubordinateIdWidth-1:0] entry_id_o,

    input  ccu_ar_req_t ar_req_i,
    input  logic        ar_valid_i,
    output logic        ar_ready_o,

    output ccu_ar_req_t ar_req_o,
    output logic        ar_valid_o,
    input  logic        ar_ready_i,

    //  Locally-generated SC fail responses
    output ccu_ace_r_t  r_o,
    output logic [ccuCfg.transactionIndexWidth-1:0] r_tid_o,
    output logic        r_valid_o,
    input  logic        r_ready_i
);

typedef struct packed {
    logic [ccuCfg.u.axiSubordinateIdWidth-1:0] id;
} exclusive_monitor_entry_t;

typedef struct packed {
    logic [ccuCfg.axiCcuIdWidth-1:0]          id;
    logic [ccuCfg.u.axiUserWidth-1:0]         user;
    logic [ccuCfg.transactionIndexWidth-1:0]  tid;
} r_register_entry_t;

exclusive_monitor_entry_t [ccuCfg.u.numSubordinates-1:0] entry_q, entry_d;
logic [ccuCfg.u.numSubordinates-1:0] valid_q, valid_d;
logic [ccuCfg.u.numSubordinates-1:0] lock_q,  lock_d;

logic [ccuCfg.subordinateIndexWidth-1:0] ar_sub_idx;
assign ar_sub_idx = ar_req_i.ar.id[ccuCfg.axiCcuIdWidth-1-:ccuCfg.subordinateIndexWidth];

logic is_exclusive_load;
logic is_exclusive_store;
logic is_exclusive_sequence;
logic exclusive_store_will_fail;

assign is_exclusive_load  = ar_req_i.flags.is_exclusive_load;
assign is_exclusive_store = ar_req_i.flags.is_exclusive_store;

assign is_exclusive_sequence     = is_exclusive_load || is_exclusive_store;
assign exclusive_store_will_fail = is_exclusive_store && !valid_q[ar_sub_idx];

logic ar_handshake;
assign ar_handshake = ar_valid_i && ar_ready_o;

logic exclusive_store_pass;
assign exclusive_store_pass = ar_handshake && is_exclusive_store && valid_q[ar_sub_idx];

//  Defer registration while another manager holds the lock (C9.3.1)
logic registration_blocked;
assign registration_blocked = |lock_q && !lock_q[ar_sub_idx];

logic reservation_set;
assign reservation_set = ar_handshake && is_exclusive_sequence && !registration_blocked;

always_comb begin : lock_comb
    lock_d = lock_q;

    for (int s = 0; s < ccuCfg.u.numSubordinates; s++) begin
        if (dealloc_i[s]) begin
            lock_d[s] = 1'b0;
        end else if (exclusive_store_pass &&
                     ccuCfg.subordinateIndexWidth'(s) == ar_sub_idx) begin
            lock_d[s] = 1'b1;
        end
    end
end

always_comb begin : entry_comb
    entry_d = entry_q;
    valid_d = valid_q;

    for (int s = 0; s < ccuCfg.u.numSubordinates; s++) begin
        if (exclusive_store_pass &&
            ccuCfg.subordinateIndexWidth'(s) != ar_sub_idx) begin
            valid_d[s] = 1'b0;
        end else if (reservation_set &&
                     ccuCfg.subordinateIndexWidth'(s) == ar_sub_idx) begin
            valid_d[s] = 1'b1;
            entry_d[s].id = ar_req_i.ar.id[ccuCfg.u.axiSubordinateIdWidth-1:0];
        end
    end
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        entry_q <= '0;
        valid_q <= '0;
        lock_q  <= '0;
    end else begin
        entry_q <= entry_d;
        valid_q <= valid_d;
        lock_q  <= lock_d;
    end
end

assign lock_o = lock_q;

for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_entry_id
    assign entry_id_o[s] = entry_q[s].id;
end

logic r_register_valid, r_register_ready;

stream_demux #(
    .N_OUP (2)
) u_ar_demux (
    .inp_valid_i (ar_valid_i),
    .inp_ready_o (ar_ready_o),
    .oup_sel_i   (exclusive_store_will_fail),
    .oup_valid_o ({r_register_valid, ar_valid_o}),
    .oup_ready_i ({r_register_ready, ar_ready_i})
);

`ACE_ASSIGN_AR_STRUCT(ar_req_o.ar, ar_req_i.ar)
assign ar_req_o.flags   = ar_req_i.flags;
assign ar_req_o.tid     = ar_req_i.tid;
assign ar_req_o.present = ar_req_i.present;

r_register_entry_t r_register_wdata, r_register_rdata;

assign r_register_wdata = '{
    id:   ar_req_i.ar.id,
    user: ar_req_i.ar.user,
    tid:  ar_req_i.tid
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
    .valid_o    (r_valid_o),
    .ready_i    (r_ready_i),
    .data_o     (r_register_rdata)
);

assign r_o = '{
    id:   r_register_rdata.id,
    data: '0,
    resp: {2'b00, axi_pkg::RESP_OKAY},
    last: 1'b1,
    user: r_register_rdata.user
};

assign r_tid_o = r_register_rdata.tid;

//  Assertions
//  {{{
// pragma translate_off
`ifndef VERILATOR
//  at most one manager holds the lock
assert property (@(posedge clk_i) disable iff (!rst_ni)
    $onehot0(lock_q))
    else $error("multiple exclusive locks held");

//  a dealloc must target a held lock
assert property (@(posedge clk_i) disable iff (!rst_ni)
    (dealloc_i & ~lock_q) == '0)
    else $error("dealloc without a held lock");
`endif
// pragma translate_on
//  }}}
endmodule
