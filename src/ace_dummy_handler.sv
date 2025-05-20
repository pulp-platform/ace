// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Zexin Fu <zexifu@iis.ee.ethz.ch>

// To handle some c910 coherence transaction when in single core configuration

module ace_dummy_handler #(
  // AXI channel structs
  parameter type  aw_chan_t = logic,
  parameter type   w_chan_t = logic,
  parameter type   b_chan_t = logic,
  parameter type  ar_chan_t = logic,
  parameter type   r_chan_t = logic,
  // AXI request & response structs
  parameter type  axi_req_t = logic,
  parameter type axi_resp_t = logic
) (
  input logic       clk_i,
  input logic       rst_ni,
  // slave port
  input  axi_req_t  axi_slv_req_i,
  output axi_resp_t axi_slv_rsp_o
);

  localparam EVICT_OFFEST = 18'h0;

  typedef enum logic [2:0] {
    IDLE            ,
    AW_RECEIVED     ,
    W_RECEIVED      ,
    AW_W_RECEIVED   ,
    AR_RECEIVED
  } ace_dummy_handler_state_e;

  ace_dummy_handler_state_e state_q;
  ace_dummy_handler_state_e state_d;
  logic state_en;

  aw_chan_t axi_slv_req_aw_q;
  aw_chan_t axi_slv_req_aw_d;
  logic axi_slv_req_aw_en;
  ar_chan_t axi_slv_req_ar_q;
  ar_chan_t axi_slv_req_ar_d;
  logic axi_slv_req_ar_en;

  logic aw_hsk;
  logic w_last_hsk;
  logic ar_hsk;

  axi_req_t  axi_slv_req;
  axi_resp_t axi_slv_rsp;
  axi_req_t  axi_mst_req;
  axi_resp_t axi_mst_rsp;

  logic [0:0] aw_addr_hit;
  logic [0:0] ar_addr_hit;

  assign aw_hsk     = axi_slv_req_i.aw_valid & axi_slv_rsp_o.aw_ready & (|aw_addr_hit);
  assign w_last_hsk = axi_slv_req_i.w_valid  & axi_slv_rsp_o.w_ready & axi_slv_req_i.w.last;
  assign ar_hsk     = axi_slv_req_i.ar_valid & axi_slv_rsp_o.ar_ready & (|ar_addr_hit);

  always_comb begin
    state_d   = state_q;
    state_en  = 1'b0;
    axi_slv_req_aw_d  = axi_slv_req_aw_q;
    axi_slv_req_aw_en = 1'b0;
    axi_slv_req_ar_d  = axi_slv_req_ar_q;
    axi_slv_req_ar_en = 1'b0;
    axi_slv_rsp_o = axi_slv_rsp;
    axi_mst_rsp   = '0;
    case (state_q)
      IDLE: begin
        axi_slv_rsp_o.aw_ready  = 1'b1;
        axi_slv_rsp_o.w_ready   = 1'b1;
        axi_slv_rsp_o.ar_ready  = 1'b1;
        if(aw_hsk & w_last_hsk) begin
          state_d   = AW_W_RECEIVED;
          state_en  = 1'b1;
          axi_slv_req_aw_en = 1'b1;
          axi_slv_req_aw_d  = axi_slv_req_i.aw;
        end else if(aw_hsk) begin
          state_d   = AW_RECEIVED;
          state_en  = 1'b1;
          axi_slv_req_aw_en = 1'b1;
          axi_slv_req_aw_d  = axi_slv_req_i.aw;
        end else if(w_last_hsk) begin
          state_d   = W_RECEIVED;
          state_en  = 1'b1;          
        end else if (ar_hsk) begin
          state_d   = AR_RECEIVED;
          state_en  = 1'b1;
          axi_slv_req_ar_en = 1'b1;
          axi_slv_req_ar_d  = axi_slv_req_i.ar;
        end
      end
      AW_RECEIVED: begin
        axi_slv_rsp_o.aw_ready  = 1'b0;
        axi_slv_rsp_o.w_ready   = 1'b1;
        axi_slv_rsp_o.ar_ready  = 1'b0;
        if(w_last_hsk) begin
          state_d   = AW_W_RECEIVED;
          state_en  = 1'b1;          
        end
      end
      W_RECEIVED: begin
        axi_slv_rsp_o.aw_ready  = 1'b1;
        axi_slv_rsp_o.w_ready   = 1'b0;
        axi_slv_rsp_o.ar_ready  = 1'b0;
        if(aw_hsk) begin
          state_d   = AW_W_RECEIVED;
          state_en  = 1'b1;     
          axi_slv_req_aw_en = 1'b1;
          axi_slv_req_aw_d  = axi_slv_req_i.aw;
        end
      end
      AW_W_RECEIVED: begin
        axi_slv_rsp_o.aw_ready  = 1'b0;
        axi_slv_rsp_o.w_ready   = 1'b0;
        axi_slv_rsp_o.ar_ready  = 1'b0;
        
        axi_mst_rsp.b_valid     = 1'b1;
        axi_mst_rsp.b.id        = axi_slv_req_aw_q.id;
        axi_mst_rsp.b.user      = axi_slv_req_aw_q.user;
        axi_mst_rsp.b.resp      = '0;

        if(axi_mst_req.b_ready) begin
          state_d   = IDLE;
          state_en  = 1'b1;          
        end
      end
      AR_RECEIVED: begin
        axi_slv_rsp_o.aw_ready  = 1'b0;
        axi_slv_rsp_o.w_ready   = 1'b0;
        axi_slv_rsp_o.ar_ready  = 1'b0;

        axi_mst_rsp.r_valid     = 1'b1;
        axi_mst_rsp.r.id        = axi_slv_req_ar_q.id;
        axi_mst_rsp.r.user      = axi_slv_req_ar_q.user;
        axi_mst_rsp.r.resp      = '0;
        axi_mst_rsp.r.data      = 'hBADADD22BADADD33;
        axi_mst_rsp.r.last      = 1'b1;

        if(axi_mst_req.r_ready) begin
          state_d   = IDLE;
          state_en  = 1'b1;          
        end
      end
      default:;
    endcase
  end

  always_comb begin
    aw_addr_hit = '0;
    ar_addr_hit = '0;
    aw_addr_hit [0] = (axi_slv_req_i.aw.addr[17:0] == EVICT_OFFEST);
    ar_addr_hit [0] = (axi_slv_req_i.ar.addr[17:0] == EVICT_OFFEST);
  end

  `ASSERT(aw_mapped, axi_slv_req_i.aw_valid |-> aw_addr_hit[0], clk_i, rst_ni, "Unmapped ace handler address")

  always_comb begin
    axi_slv_req = '0;
    axi_slv_req.b_ready = axi_slv_req_i.b_ready;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      state_q <= IDLE;
    end else begin
      if(state_en) begin
        state_q <= state_d;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if(axi_slv_req_aw_en) begin
      axi_slv_req_aw_q <= axi_slv_req_aw_d;
    end
  end
  
  always_ff @(posedge clk_i) begin
    if(axi_slv_req_ar_en) begin
      axi_slv_req_ar_q <= axi_slv_req_ar_d;
    end
  end

  axi_fifo #(
      .Depth      (1),
      .FallThrough(1),
      .aw_chan_t  (aw_chan_t),
      .w_chan_t   (w_chan_t),
      .b_chan_t   (b_chan_t),
      .ar_chan_t  (ar_chan_t),
      .r_chan_t   (r_chan_t),
      .axi_req_t  (axi_req_t),
      .axi_resp_t (axi_resp_t)
  ) i_axi_resp_fifo (
      .clk_i,
      .rst_ni,
      .test_i    ('0),
      .slv_req_i (axi_slv_req),
      .slv_resp_o(axi_slv_rsp),
      .mst_req_o (axi_mst_req),
      .mst_resp_i(axi_mst_rsp)
  );

endmodule