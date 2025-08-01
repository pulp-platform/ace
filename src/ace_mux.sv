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

`include "ace/typedef.svh"
`include "ace/assign.svh"

module ace_mux #(
    // ACE parameter and channel types
    parameter int unsigned SlvAxiIDWidth = 32'd0,  // AXI ID width, slave ports
    parameter type         slv_aw_chan_t = logic,  // AW Channel Type, slave ports
    parameter type         mst_aw_chan_t = logic,  // AW Channel Type, master port
    parameter type         w_chan_t      = logic,  //  W Channel Type, all ports
    parameter type         slv_b_chan_t  = logic,  //  B Channel Type, slave ports
    parameter type         mst_b_chan_t  = logic,  //  B Channel Type, master port
    parameter type         slv_ar_chan_t = logic,  // AR Channel Type, slave ports
    parameter type         mst_ar_chan_t = logic,  // AR Channel Type, master port
    parameter type         slv_r_chan_t  = logic,  //  R Channel Type, slave ports
    parameter type         mst_r_chan_t  = logic,  //  R Channel Type, master port
    parameter type         slv_req_t     = logic,  // Slave port request type
    parameter type         slv_resp_t    = logic,  // Slave port response type
    parameter type         mst_req_t     = logic,  // Master ports request type
    parameter type         mst_resp_t    = logic,  // Master ports response type
    parameter int unsigned NoSlvPorts    = 32'd0,  // Number of slave ports
    // Maximum number of outstanding transactions per write
    parameter int unsigned MaxWTrans     = 32'd8,
    // Maximum number of outstanding transactions per B channel (ACE)
    parameter int unsigned MaxBTrans     = 32'd8,
    // Maximum number of outstanding transactions per R channel (ACE)
    parameter int unsigned MaxRTrans     = 32'd8,
    // If enabled, this multiplexer is purely combinatorial
    parameter bit          FallThrough   = 1'b0,
    // add spill register on write master ports, adds a cycle latency on write channels
    parameter bit          SpillAw       = 1'b1,
    parameter bit          SpillW        = 1'b0,
    parameter bit          SpillB        = 1'b0,
    // add spill register on read master ports, adds a cycle latency on read channels
    parameter bit          SpillAr       = 1'b1,
    parameter bit          SpillR        = 1'b0,
    // add registers on xACK ports, add a cycle latency on acknowledgment signals (ACE)
    parameter bit          RegAck        = 1'b0
) (
    input  logic                       clk_i,        // Clock
    input  logic                       rst_ni,       // Asynchronous reset active low
    input  logic                       test_i,       // Test Mode enable
    // slave ports (ACE inputs), connect master modules here
    input  slv_req_t  [NoSlvPorts-1:0] slv_reqs_i,
    output slv_resp_t [NoSlvPorts-1:0] slv_resps_o,
    // master port (ACE outputs), connect slave modules here
    output mst_req_t                   mst_req_o,
    input  mst_resp_t                  mst_resp_i
);
    // All subsequent ACE defines will not use RACK/WACKS
    `define __ACE_NO_ACKS

    // Internal request type without acks
    `ACE_TYPEDEF_REQ_T(__slv_req_t, slv_aw_chan_t, w_chan_t, slv_ar_chan_t)
    `ACE_TYPEDEF_REQ_T(__mst_req_t, mst_aw_chan_t, w_chan_t, mst_ar_chan_t)

    __slv_req_t [NoSlvPorts-1:0] slv_reqs;

    __mst_req_t                  mst_req;
    mst_resp_t                   mst_resp;

    //  Input req setup
    //  {{{
    for (genvar i = 0; i < NoSlvPorts; i++) begin
        `ACE_ASSIGN_REQ_STRUCT(slv_reqs[i], slv_reqs_i[i])
    end
    //  }}}

    //  AXI MUX instance
    //  {{{
    axi_mux #(
        .SlvAxiIDWidth(SlvAxiIDWidth),
        .slv_aw_chan_t(slv_aw_chan_t),
        .mst_aw_chan_t(mst_aw_chan_t),
        .w_chan_t     (w_chan_t),
        .slv_b_chan_t (slv_b_chan_t),
        .mst_b_chan_t (mst_b_chan_t),
        .slv_ar_chan_t(slv_ar_chan_t),
        .mst_ar_chan_t(mst_ar_chan_t),
        .slv_r_chan_t (slv_r_chan_t),
        .mst_r_chan_t (mst_r_chan_t),
        .slv_req_t    (__slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (__mst_req_t),
        .mst_resp_t   (mst_resp_t),
        .NoSlvPorts   (NoSlvPorts),
        .MaxWTrans    (MaxWTrans),
        .FallThrough  (FallThrough),
        .SpillAw      (SpillAw),
        .SpillW       (SpillW),
        .SpillB       (SpillB),
        .SpillAr      (SpillAr),
        .SpillR       (SpillR)
    ) u_axi_mux (
        .clk_i,
        .rst_ni,
        .test_i     (test_i),
        .slv_reqs_i (slv_reqs),
        .slv_resps_o(slv_resps_o),
        .mst_req_o  (mst_req),
        .mst_resp_i (mst_resp)
    );

    //  }}}

    //  Output req/resp setup
    //  {{{
    logic [NoSlvPorts-1:0] slv_racks;
    logic [NoSlvPorts-1:0] slv_wacks;
    logic                  mst_rack;
    logic                  mst_wack;
    logic                  mst_b_stall;
    logic                  mst_r_stall;

    for (genvar i = 0; i < NoSlvPorts; i++) begin
        assign slv_racks[i] = slv_reqs_i[i].rack;
        assign slv_wacks[i] = slv_reqs_i[i].wack;
    end

    always_comb begin
        // Use AXI defines since we are working with
        // the AXI backward compatible req structure whithout xACKs
        `ACE_SET_REQ_STRUCT(mst_req_o, mst_req)
        `ACE_SET_RESP_STRUCT(mst_resp, mst_resp_i)
        // Get the xACKs from the dedicated logic instead
        mst_req_o.wack = mst_wack;
        mst_req_o.rack = mst_rack;

        // Stall B if the WACK ROB is full
        if (mst_b_stall) begin
            mst_resp.b_valid  = 1'b0;
            mst_req_o.b_ready = 1'b0;
        end

        // Stall R if the WACK ROB is full
        if (mst_r_stall) begin
            mst_resp.r_valid  = 1'b0;
            mst_req_o.r_ready = 1'b0;
        end
    end
    //  }}}

    //  xACKs generation
    // {{{
    if (NoSlvPorts > 1) begin : gen_xack_rob
        localparam int unsigned MstIdxBits = $clog2(NoSlvPorts);
        typedef logic [MstIdxBits-1:0] switch_id_t;

        switch_id_t switch_b_id;
        switch_id_t switch_r_id;

        logic       r_last_handshake;
        logic       b_handshake;

        assign switch_r_id      = mst_resp.r.id[SlvAxiIDWidth+:MstIdxBits];
        assign switch_b_id      = mst_resp.b.id[SlvAxiIDWidth+:MstIdxBits];

        assign r_last_handshake = mst_req_o.r_ready && mst_resp_i.r_valid && mst_resp_i.r.last;
        assign b_handshake      = mst_req_o.b_ready && mst_resp_i.b_valid;

        ace_mux_xack #(
            .N              (NoSlvPorts),
            .MAX_OUTSTANDING(MaxBTrans),
            .FALL_THROUGH   (!RegAck)
        ) u_wack_gen (
            .clk_i,
            .rst_ni,
            .empty_o    (  /* unused */),
            .full_o     (mst_b_stall),
            .handshake_i(b_handshake),
            .idx_i      (switch_b_id),
            .acks_i     (slv_wacks),
            .ack_o      (mst_wack)
        );

        ace_mux_xack #(
            .N              (NoSlvPorts),
            .MAX_OUTSTANDING(MaxRTrans),
            .FALL_THROUGH   (!RegAck)
        ) u_rack_gen (
            .clk_i,
            .rst_ni,
            .empty_o    (  /* unused */),
            .full_o     (mst_r_stall),
            .handshake_i(r_last_handshake),
            .idx_i      (switch_r_id),
            .acks_i     (slv_racks),
            .ack_o      (mst_rack)
        );
    end else if (!RegAck) begin : gen_xack_assign
        assign mst_wack    = slv_wacks[0];
        assign mst_rack    = slv_racks[0];
        assign mst_b_stall = 1'b0;
        assign mst_r_stall = 1'b0;
    end else begin : gen_xack_ffs
        always_ff @(posedge clk_i or negedge rst_ni) begin
            mst_wack <= slv_wacks[0];
            mst_rack <= slv_racks[0];
        end
        assign mst_b_stall = 1'b0;
        assign mst_r_stall = 1'b0;
    end
    // }}}

    `undef __ACE_NO_ACKS

endmodule

// interface wrap
module ace_mux_intf #(
    parameter int unsigned SLV_AXI_ID_WIDTH = 32'd0, // Synopsys DC requires default value for params
    parameter int unsigned MST_AXI_ID_WIDTH = 32'd0,
    parameter int unsigned AXI_ADDR_WIDTH = 32'd0,
    parameter int unsigned AXI_DATA_WIDTH = 32'd0,
    parameter int unsigned AXI_USER_WIDTH = 32'd0,
    parameter int unsigned NO_SLV_PORTS = 32'd0,  // Number of slave ports
    // Maximum number of outstanding transactions per write
    parameter int unsigned MAX_W_TRANS = 32'd8,
    // Maximum number of outstanding transactions per B channel (ACE)
    parameter int unsigned MAX_B_TRANS = 32'd8,
    // Maximum number of outstanding transactions per R channel (ACE)
    parameter int unsigned MAX_R_TRANS = 32'd8,
    // if enabled, this multiplexer is purely combinatorial
    parameter bit FALL_THROUGH = 1'b0,
    // add spill register on write master ports, adds a cycle latency on write channels
    parameter bit SPILL_AW = 1'b1,
    parameter bit SPILL_W = 1'b0,
    parameter bit SPILL_B = 1'b0,
    // add spill register on read master ports, adds a cycle latency on read channels
    parameter bit SPILL_AR = 1'b1,
    parameter bit SPILL_R = 1'b0,
    // add registers on xACK ports, add a cycle latency on acknowledgment signals (ACE)
    parameter bit REG_ACK = 1'b0
) (
    input logic          clk_i,                     // Clock
    input logic          rst_ni,                    // Asynchronous reset active low
    input logic          test_i,                    // Testmode enable
          ACE_BUS.Slave  slv   [NO_SLV_PORTS-1:0],  // slave ports
          ACE_BUS.Master mst                        // master port
);

    typedef logic [SLV_AXI_ID_WIDTH-1:0] slv_id_t;
    typedef logic [MST_AXI_ID_WIDTH-1:0] mst_id_t;
    typedef logic [AXI_ADDR_WIDTH -1:0] addr_t;
    typedef logic [AXI_DATA_WIDTH-1:0] data_t;
    typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
    typedef logic [AXI_USER_WIDTH-1:0] user_t;
    // channels typedef
    `ACE_TYPEDEF_AW_CHAN_T(slv_aw_chan_t, addr_t, slv_id_t, user_t)
    `ACE_TYPEDEF_AW_CHAN_T(mst_aw_chan_t, addr_t, mst_id_t, user_t)

    `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)

    `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, slv_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(mst_b_chan_t, mst_id_t, user_t)

    `ACE_TYPEDEF_AR_CHAN_T(slv_ar_chan_t, addr_t, slv_id_t, user_t)
    `ACE_TYPEDEF_AR_CHAN_T(mst_ar_chan_t, addr_t, mst_id_t, user_t)

    `ACE_TYPEDEF_R_CHAN_T(slv_r_chan_t, data_t, slv_id_t, user_t)
    `ACE_TYPEDEF_R_CHAN_T(mst_r_chan_t, data_t, mst_id_t, user_t)

    `ACE_TYPEDEF_REQ_T(slv_req_t, slv_aw_chan_t, w_chan_t, slv_ar_chan_t)
    `ACE_TYPEDEF_RESP_T(slv_resp_t, slv_b_chan_t, slv_r_chan_t)

    `ACE_TYPEDEF_REQ_T(mst_req_t, mst_aw_chan_t, w_chan_t, mst_ar_chan_t)
    `ACE_TYPEDEF_RESP_T(mst_resp_t, mst_b_chan_t, mst_r_chan_t)

    slv_req_t  [NO_SLV_PORTS-1:0] slv_reqs;
    slv_resp_t [NO_SLV_PORTS-1:0] slv_resps;
    mst_req_t                     mst_req;
    mst_resp_t                    mst_resp;

    for (genvar i = 0; i < NO_SLV_PORTS; i++) begin : gen_assign_slv_ports
        `ACE_ASSIGN_TO_REQ(slv_reqs[i], slv[i])
        `ACE_ASSIGN_FROM_RESP(slv[i], slv_resps[i])
    end

    `ACE_ASSIGN_FROM_REQ(mst, mst_req)
    `ACE_ASSIGN_TO_RESP(mst_resp, mst)

    ace_mux #(
        .SlvAxiIDWidth(SLV_AXI_ID_WIDTH),
        .slv_aw_chan_t(slv_aw_chan_t),     // AW Channel Type, slave ports
        .mst_aw_chan_t(mst_aw_chan_t),     // AW Channel Type, master port
        .w_chan_t     (w_chan_t),          //  W Channel Type, all ports
        .slv_b_chan_t (slv_b_chan_t),      //  B Channel Type, slave ports
        .mst_b_chan_t (mst_b_chan_t),      //  B Channel Type, master port
        .slv_ar_chan_t(slv_ar_chan_t),     // AR Channel Type, slave ports
        .mst_ar_chan_t(mst_ar_chan_t),     // AR Channel Type, master port
        .slv_r_chan_t (slv_r_chan_t),      //  R Channel Type, slave ports
        .mst_r_chan_t (mst_r_chan_t),      //  R Channel Type, master port
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (mst_req_t),
        .mst_resp_t   (mst_resp_t),
        .NoSlvPorts   (NO_SLV_PORTS),      // Number of slave ports
        .MaxWTrans    (MAX_W_TRANS),
        .MaxBTrans    (MAX_B_TRANS),
        .MaxRTrans    (MAX_R_TRANS),
        .FallThrough  (FALL_THROUGH),
        .SpillAw      (SPILL_AW),
        .SpillW       (SPILL_W),
        .SpillB       (SPILL_B),
        .SpillAr      (SPILL_AR),
        .SpillR       (SPILL_R),
        .RegAck       (REG_ACK)
    ) i_ace_mux (
        .clk_i      (clk_i),      // Clock
        .rst_ni     (rst_ni),     // Asynchronous reset active low
        .test_i     (test_i),     // Test Mode enable
        .slv_reqs_i (slv_reqs),
        .slv_resps_o(slv_resps),
        .mst_req_o  (mst_req),
        .mst_resp_i (mst_resp)
    );
endmodule

module ace_mux_xack
//  Parameters
//  {{{
#(
    parameter  int unsigned N               = 0,
    parameter  int unsigned MAX_OUTSTANDING = 4,
    parameter  bit          FALL_THROUGH    = 0,
    localparam int unsigned IDX_WIDTH       = N > 1 ? $clog2(N) : 1,
    localparam type         idx_t           = logic                 [IDX_WIDTH-1:0]
)
//  }}}

//  Ports
//  {{{
(
    input logic clk_i,
    input logic rst_ni,

    output logic empty_o,
    output logic full_o,

    input logic handshake_i,
    input idx_t idx_i,

    input logic [N-1:0] acks_i,

    output logic ack_o
);
    //  }}}

    //  Internal signals
    //  {{{
    idx_t         sel;
    logic [N-1:0] sel_bv;
    logic [N-1:0] ack_gnts;
    logic [N-1:0] ack_reqs;
    //  }}}

    //  Track response ordering with a FIFO
    //  {{{
    fifo_v3 #(
        .FALL_THROUGH(1'b0),
        .DEPTH       (MAX_OUTSTANDING),
        .dtype       (idx_t)
    ) i_sel_fifo (
        .clk_i,
        .rst_ni,
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (full_o),
        .empty_o   (empty_o),
        .usage_o   (),
        .data_i    (idx_i),
        .push_i    (handshake_i),
        .data_o    (sel),
        .pop_i     (ack_o)
    );
    //  }}}

    //  Per-slv port credit counter
    //  An out-of-order xACK signal increases
    //  the counter by 1
    //  When the FIFO selects the counter,
    //  it is decreased by 1
    //  {{{
    for (genvar i = 0; i < N; i++) begin : gen_credit_counters
        credit_counter #(
            .NumCredits     (MAX_OUTSTANDING),
            .InitCreditEmpty(1'b1)
        ) u_credit_counter (
            .clk_i,
            .rst_ni,
            .credit_o     (  /* unused */),
            .credit_give_i(acks_i[i]),
            .credit_take_i(ack_gnts[i]),
            .credit_init_i('0),
            .credit_left_o(ack_reqs[i]),
            .credit_crit_o(  /* unused */),
            .credit_full_o(  /* unused */)
        );
    end
    //  }}}

    //  xACK generation
    //  {{{
    assign sel_bv   = N'(1) << sel;
    // In FALL_THROUGH mode, a concurrent increase and decrease of the counter
    // does not alter its value and the xACK signal is combinationally generated
    assign ack_gnts = sel_bv & (ack_reqs | (FALL_THROUGH ? acks_i : '0));
    assign ack_o    = |ack_gnts;
    //  }}}

endmodule
