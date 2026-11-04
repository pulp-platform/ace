// Copyright (c) 2026 ETH Zurich, University of Bologna
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

//! Port adapter
//
//  One per manager: its read, write and snoop sides.
module ccu_port_adapter
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg       = '{default: '0},
    parameter  type         sub_req_t    = logic,
    parameter  type         sub_resp_t   = logic,
    parameter  type         sub_r_t      = logic,
    parameter  type         sub_b_t      = logic,
    parameter  type         snoop_req_t  = logic,
    parameter  type         snoop_resp_t = logic,
    parameter  type         snoop_cd_t   = logic,
    parameter  type         ar_hdr_t     = logic,
    parameter  type         aw_hdr_t     = logic,
    parameter  type         w_beat_t     = logic,
    parameter  type         ac_req_t     = logic,
    parameter  type         cr_ret_t     = logic,
    parameter  type         route_t      = logic,
    parameter  type         r_info_t     = logic,
    parameter  type         rb_mem_t     = logic,
    parameter  type         rb_cd_t      = logic,
    parameter  type         cd_r_t       = logic,
    parameter  type         cd_w_t       = logic,
    parameter  type         b_ret_t      = logic,
    localparam int unsigned numTids      = ccuCfg.numTids,
    localparam int unsigned tidW         = ccuCfg.tidWidth,
    localparam int unsigned rSlotW       = ccuCfg.rSlotWidth,
    localparam int unsigned numBSlots    = ccuCfg.numBSlots,
    localparam int unsigned bSlotW       = ccuCfg.bSlotWidth,
    localparam int unsigned lineW        = ccuCfg.numLineWidth,
    localparam int unsigned offW         = ccuCfg.cachelineByteIndexWidth,
    localparam int unsigned subIdW       = ccuCfg.u.axiSubordinateIdWidth,
    localparam int unsigned subIdxW      = ccuCfg.subordinateIndexWidth
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    //  Which port this is
    input  logic [subIdxW-1:0]         port_i,

    //  The manager
    input  sub_req_t                   req_i,
    output sub_resp_t                  resp_o,
    input  logic                       rack_i,
    input  logic                       wack_i,
    output snoop_req_t                 snoop_req_o,
    input  snoop_resp_t                snoop_resp_i,

    //  Snoop-dependent reads; the table binds a tid to the R slot later
    output ar_hdr_t                    ar_hdr_o,
    output logic                       ar_valid_o,
    input  logic                       ar_ready_i,
    input  logic                       bind_valid_i,
    input  logic [rSlotW-1:0]          bind_rslot_i,
    input  logic [tidW-1:0]            bind_tid_i,

    //  Non-blocking writes, named by their port-local B slot; W follows tagged with it
    output aw_hdr_t                    aw_hdr_o,
    output logic                       aw_valid_o,
    input  logic                       aw_ready_i,
    //  The line leaves this manager's cache
    output logic                       remove_valid_o,
    output logic [lineW-1:0]           remove_line_o,
    input  logic                       remove_ready_i,
    output w_beat_t                    w_o,
    output logic                       w_valid_o,
    input  logic                       w_ready_i,

    //  Snoops, tagged with the tid they answer
    input  ac_req_t                    ac_i,
    input  logic                       ac_valid_i,
    output logic                       ac_ready_o,
    output cr_ret_t                    cr_o,
    output logic                       cr_valid_o,
    //  Routing of a resolved tid's CD, to every port
    input  logic                       route_valid_i,
    input  route_t                     route_i,
    output cd_r_t                      cd_r_o,
    output logic                       cd_r_valid_o,
    input  logic                       cd_r_ready_i,
    output cd_w_t                      cd_w_o,
    output logic                       cd_w_valid_o,
    input  logic                       cd_w_ready_i,
    output logic                       cd_done_o,
    output logic [tidW-1:0]            cd_done_tid_o,
    //  Next CD's tid
    output logic                       cd_head_valid_o,
    output logic [tidW-1:0]            cd_head_tid_o,

    //  Responses into this port
    input  rb_mem_t                    rb_mem_i,
    input  logic                       rb_mem_valid_i,
    input  rb_cd_t                     rb_cd_i,
    input  logic                       rb_cd_valid_i,
    output logic                       rb_cd_ready_o,
    //  A read's response, fixed at resolve, and the R slots that may go
    input  logic                       r_info_valid_i,
    input  r_info_t                    r_info_i,
    input  logic [ccuCfg.u.numRSlots-1:0] r_go_i,
    input  b_ret_t                     b_i,
    input  logic                       b_valid_i,

    //  ACKED: the RACK of a read, by tid
    output logic                       rack_o,
    output logic [tidW-1:0]            rack_tid_o,

    output ccu_port_events_t           events_o
);

    sub_r_t           sub_r;
    sub_b_t           sub_b;
    logic             sub_ar_ready, sub_r_valid, sub_aw_ready, sub_w_ready, sub_b_valid;
    ccu_port_events_t read_events, write_events, snoop_events;

    ccu_port_read #(
        .ccuCfg    (ccuCfg),
        .sub_req_t (sub_req_t),
        .sub_r_t   (sub_r_t),
        .ar_hdr_t  (ar_hdr_t),
        .rb_mem_t  (rb_mem_t),
        .rb_cd_t   (rb_cd_t),
        .r_info_t  (r_info_t)
    ) u_read (
        .clk_i,
        .rst_ni,
        .req_i,
        .sub_ar_ready_o (sub_ar_ready),
        .sub_r_o        (sub_r),
        .sub_r_valid_o  (sub_r_valid),
        .rack_i,
        .ar_hdr_o,
        .ar_valid_o,
        .ar_ready_i,
        .bind_valid_i,
        .bind_rslot_i,
        .bind_tid_i,
        .rb_mem_i,
        .rb_mem_valid_i,
        .rb_cd_i,
        .rb_cd_valid_i,
        .rb_cd_ready_o,
        .r_info_valid_i,
        .r_info_i,
        .r_go_i,
        .rack_o,
        .rack_tid_o,
        .events_o       (read_events)
    );

    ccu_port_write #(
        .ccuCfg    (ccuCfg),
        .sub_req_t (sub_req_t),
        .sub_b_t   (sub_b_t),
        .aw_hdr_t  (aw_hdr_t),
        .w_beat_t  (w_beat_t),
        .b_ret_t   (b_ret_t)
    ) u_write (
        .clk_i,
        .rst_ni,
        .req_i,
        .sub_aw_ready_o (sub_aw_ready),
        .sub_w_ready_o  (sub_w_ready),
        .sub_b_o        (sub_b),
        .sub_b_valid_o  (sub_b_valid),
        .wack_i,
        .aw_hdr_o,
        .aw_valid_o,
        .aw_ready_i,
        .remove_valid_o,
        .remove_line_o,
        .remove_ready_i,
        .w_o,
        .w_valid_o,
        .w_ready_i,
        .b_i,
        .b_valid_i,
        .events_o       (write_events)
    );

    ccu_port_snoop #(
        .ccuCfg       (ccuCfg),
        .snoop_req_t  (snoop_req_t),
        .snoop_resp_t (snoop_resp_t),
        .snoop_cd_t   (snoop_cd_t),
        .ac_req_t     (ac_req_t),
        .cr_ret_t     (cr_ret_t),
        .route_t      (route_t),
        .cd_r_t       (cd_r_t),
        .cd_w_t       (cd_w_t)
    ) u_snoop (
        .clk_i,
        .rst_ni,
        .port_i,
        .snoop_req_o,
        .snoop_resp_i,
        .ac_i,
        .ac_valid_i,
        .ac_ready_o,
        .cr_o,
        .cr_valid_o,
        .route_valid_i,
        .route_i,
        .cd_r_o,
        .cd_r_valid_o,
        .cd_r_ready_i,
        .cd_w_o,
        .cd_w_valid_o,
        .cd_w_ready_i,
        .cd_done_o,
        .cd_done_tid_o,
        .cd_head_valid_o,
        .cd_head_tid_o,
        .events_o       (snoop_events)
    );

    always_comb begin : resp_comb
        resp_o          = '0;
        resp_o.ar_ready = sub_ar_ready;
        resp_o.r        = sub_r;
        resp_o.r_valid  = sub_r_valid;
        resp_o.aw_ready = sub_aw_ready;
        resp_o.w_ready  = sub_w_ready;
        resp_o.b        = sub_b;
        resp_o.b_valid  = sub_b_valid;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) events_o <= '0;
        else         events_o <= read_events | write_events | snoop_events;
    end
endmodule
