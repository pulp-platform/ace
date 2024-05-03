// Copyright (c) 2019 ETH Zurich, University of Bologna
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
// - Luca Valente <luca.valente@unibo.it>

// AC Multiplexer: This module multiplexes the AC slave ports down to one master port.

// register macros
`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

module snoop_mux #(
  // Snoop parameter and channel types
  parameter type         snoop_req_t  = logic,
  parameter type         snoop_resp_t = logic,
  parameter type         ac_chan_t   = logic, // Ac Channel Type, slave ports
  parameter type         cr_chan_t   = logic, // Cr Channel Type, all ports
  parameter type         cd_chan_t   = logic, // Cd Channel Type, slave ports
  parameter int unsigned NoSlvPorts  = 32'd0, // Number of slave ports
  // add spill register on write master ports when number of slave ports is 0
  parameter bit          SpillAc     = 1'b1,
  parameter bit          SpillCr     = 1'b0,
  parameter bit          SpillCd     = 1'b0
) (
  input  logic                         clk_i,    // Clock
  input  logic                         rst_ni,   // Asynchronous reset active low
  // slave ports, connect master modules here
  input  snoop_req_t  [NoSlvPorts-1:0] slv_reqs_i,
  output snoop_resp_t [NoSlvPorts-1:0] slv_resps_o,
  // master port, connect slave modules here
  output snoop_req_t                   mst_req_o,
  input  snoop_resp_t                  mst_resp_i
);

  // pass through if only one slave port
  if (NoSlvPorts == 32'h1) begin : gen_no_mux
    spill_register #(
      .T       ( ac_chan_t ),
      .Bypass  ( ~SpillAc  )
    ) i_ac_spill_reg (
      .clk_i   ( clk_i                    ),
      .rst_ni  ( rst_ni                   ),
      .valid_i ( slv_reqs_i[0].ac_valid   ),
      .ready_o ( slv_resps_o[0].ac_ready  ),
      .data_i  ( slv_reqs_i[0].ac         ),
      .valid_o ( mst_req_o.ac_valid       ),
      .ready_i ( mst_resp_i.ac_ready      ),
      .data_o  ( mst_req_o.ac             )
    );
    spill_register #(
      .T       ( cr_chan_t ),
      .Bypass  ( ~SpillCr  )
    ) i_cr_spill_reg (
      .clk_i   ( clk_i                   ),
      .rst_ni  ( rst_ni                  ),
      .valid_i ( mst_resp_i.cr_valid     ),
      .ready_o ( mst_req_o.cr_ready      ),
      .data_i  ( mst_resp_i.cr_resp      ),
      .valid_o ( slv_resps_o[0].cr_valid ),
      .ready_i ( slv_reqs_i[0].cr_ready  ),
      .data_o  ( slv_resps_o[0].cr_resp  )
    );
    spill_register #(
      .T       ( cd_chan_t ),
      .Bypass  ( ~SpillCd  )
    ) i_cd_spill_reg (
      .clk_i   ( clk_i                   ),
      .rst_ni  ( rst_ni                  ),
      .valid_i ( mst_resp_i.cd_valid     ),
      .ready_o ( mst_req_o.cd_ready      ),
      .data_i  ( mst_resp_i.cd           ),
      .valid_o ( slv_resps_o[0].cd_valid ),
      .ready_i ( slv_reqs_i[0].cd_ready  ),
      .data_o  ( slv_resps_o[0].cd       )
    );

  // other non degenerate cases
  end else begin : gen_mux

    localparam int unsigned IdxWidth   = unsigned'($clog2(NoSlvPorts));
    typedef logic [IdxWidth-1:0] idx_t;

    idx_t s_id_inflight, id_inflight_d, id_inflight_q;

    logic lock_d, lock_q;

    // AXI channels between the ID prepend unit and the rest of the multiplexer
    ac_chan_t     [NoSlvPorts-1:0] slv_ac_chans;
    logic         [NoSlvPorts-1:0] slv_ac_valids, slv_ac_readies;
    cr_chan_t     [NoSlvPorts-1:0] slv_cr_chans;
    logic         [NoSlvPorts-1:0] slv_cr_valids,  slv_cr_readies;
    cd_chan_t     [NoSlvPorts-1:0] slv_cd_chans;
    logic         [NoSlvPorts-1:0] slv_cd_valids,  slv_cd_readies;
    ac_chan_t     mst_ac_chan;

    logic                         ac_valid, ac_ready;
    assign ac_ready = mst_resp_i.ac_ready & !lock_q;
    assign mst_req_o.ac_valid = ac_valid;
    assign mst_req_o.ac = mst_ac_chan;

    assign mst_req_o.cr_ready = slv_reqs_i[id_inflight_d].cr_ready;
    assign mst_req_o.cd_ready = slv_reqs_i[id_inflight_d].cd_ready;

    for (genvar i = 0; i < NoSlvPorts; i++) begin : gen_slv_resp_bind
       assign slv_resps_o[i].cr_valid = (lock_q & (i==id_inflight_d)) ? mst_resp_i.cr_valid : 1'b0;
       assign slv_resps_o[i].cr_resp = (lock_q & (i==id_inflight_d)) ? mst_resp_i.cr_resp : '0;
       assign slv_resps_o[i].cd_valid = (lock_q & (i==id_inflight_d)) ? mst_resp_i.cd_valid : 1'b0;
       assign slv_resps_o[i].cd = (lock_q & (i==id_inflight_d)) ? mst_resp_i.cd : '0;
    end

    for (genvar i = 0; i < NoSlvPorts; i++) begin : gen_slv_req_bind
       assign slv_ac_valids[i] = slv_reqs_i[i].ac_valid;
       assign slv_resps_o[i].ac_ready = slv_ac_readies[i];
       assign slv_ac_chans[i] = slv_reqs_i[i].ac;
    end

    //--------------------------------------
    // AC Channel
    //--------------------------------------
    rr_arb_tree #(
      .NumIn    ( NoSlvPorts ),
      .DataType ( ac_chan_t  ),
      .AxiVldRdy( 1'b1       ),
      .LockIn   ( 1'b1       )
    ) i_ac_arbiter (
      .clk_i  ( clk_i           ),
      .rst_ni ( rst_ni          ),
      .flush_i( 1'b0            ),
      .rr_i   ( '0              ),
      .req_i  ( slv_ac_valids   ),
      .gnt_o  ( slv_ac_readies  ),
      .data_i ( slv_ac_chans    ),
      .gnt_i  ( ac_ready        ),
      .req_o  ( ac_valid        ),
      .data_o ( mst_ac_chan     ),
      .idx_o  ( s_id_inflight   )
    );

    assign id_inflight_d = (ac_ready & ac_valid) ? s_id_inflight : id_inflight_q;
    always_comb begin
       lock_d = lock_q;
       if(ac_ready & ac_valid)
          lock_d = 1'b1;
       else if( (mst_resp_i.cd_valid & mst_resp_i.cd.last & mst_req_o.cd_ready) | (mst_resp_i.cr_valid & mst_req_o.cr_ready & ~mst_resp_i.cr_resp[0]))
         lock_d = 1'b0;
    end

    `FF(id_inflight_q, id_inflight_d, '0, clk_i, rst_ni)
    `FF(lock_q, lock_d, '0, clk_i, rst_ni)

  end

endmodule
