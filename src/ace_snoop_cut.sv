// Copyright (c) 2014-2018 ETH Zurich, University of Bologna
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

/// An ACE4 snoop cut.
///
/// Breaks all combinatorial paths between its input and output.
module ace_snoop_cut #(
  // bypass enable
  parameter bit  Bypass     = 1'b0,
  // ACE snoop channel structs
  parameter type  ac_chan_t = logic,
  parameter type  cd_chan_t = logic,
  parameter type  cr_chan_t = logic,
  // ACE snoop request & response structs
  parameter type  snoop_req_t  = logic,
  parameter type  snoop_resp_t = logic
) (
  input logic       clk_i,
  input logic       rst_ni,
  // salve port
  input  snoop_req_t  slv_req_i,
  output snoop_resp_t slv_resp_o,
  // master port
  output snoop_req_t  mst_req_o,
  input  snoop_resp_t mst_resp_i
);

    // Snoop channels cut
    spill_register #(
    .T       ( ac_chan_t ),
    .Bypass  ( Bypass    )
    ) i_reg_ac (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( slv_req_i.ac_valid  ),
    .ready_o ( slv_resp_o.ac_ready ),
    .data_i  ( slv_req_i.ac        ),
    .valid_o ( mst_req_o.ac_valid  ),
    .ready_i ( mst_resp_i.ac_ready ),
    .data_o  ( mst_req_o.ac        )
    );

    spill_register #(
    .T       ( cd_chan_t ),
    .Bypass  ( Bypass    )
    ) i_reg_cd (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( mst_resp_i.cd_valid ),
    .ready_o ( mst_req_o.cd_ready  ),
    .data_i  ( mst_resp_i.cd       ),
    .valid_o ( slv_resp_o.cd_valid ),
    .ready_i ( slv_req_i.cd_ready  ),
    .data_o  ( slv_resp_o.cd       )
    );

    spill_register #(
    .T       ( cr_chan_t ),
    .Bypass  ( Bypass    )
    ) i_reg_cr (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( mst_resp_i.cr_valid ),
    .ready_o ( mst_req_o.cr_ready  ),
    .data_i  ( mst_resp_i.cr_resp  ),
    .valid_o ( slv_resp_o.cr_valid ),
    .ready_i ( slv_req_i.cr_ready  ),
    .data_o  ( slv_resp_o.cr_resp  )
    );

endmodule

`include "ace/assign.svh"
`include "ace/typedef.svh"

// interface wrapper
module ace_snoop_cut_intf #(
  // Bypass eneable
  parameter bit          BYPASS     = 1'b0,
  // The address width.
  parameter int unsigned ADDR_WIDTH = 0,
  // The data width.
  parameter int unsigned DATA_WIDTH = 0
) (
  input logic       clk_i  ,
  input logic       rst_ni ,
  SNOOP_BUS.Slave   in     ,
  SNOOP_BUS.Master  out
);

  typedef logic [ADDR_WIDTH-1:0]   addr_t;
  typedef logic [DATA_WIDTH-1:0]   data_t;

  `SNOOP_TYPEDEF_ALL(snoop, addr_t, data_t)

  snoop_req_t  slv_req,  mst_req;
  snoop_resp_t slv_resp, mst_resp;

  `SNOOP_ASSIGN_TO_REQ(slv_req, in)
  `SNOOP_ASSIGN_FROM_RESP(in, slv_resp)

  `SNOOP_ASSIGN_FROM_REQ(out, mst_req)
  `SNOOP_ASSIGN_TO_RESP(mst_resp, out)

  ace_snoop_cut #(
    .Bypass       ( BYPASS ),
    .ac_chan_t    (snoop_ac_chan_t),
    .cd_chan_t    (snoop_cd_chan_t),
    .cr_chan_t    (snoop_cr_chan_t),
    .snoop_req_t  (snoop_req_t),
    .snoop_resp_t (snoop_resp_t)
  ) i_ace_snoop_cut (
    .clk_i,
    .rst_ni,
    .slv_req_i  ( slv_req  ),
    .slv_resp_o ( slv_resp ),
    .mst_req_o  ( mst_req  ),
    .mst_resp_i ( mst_resp )
  );

  // Check the invariants.
  // pragma translate_off
  `ifndef VERILATOR
  initial begin
    assert (ADDR_WIDTH > 0) else $fatal(1, "Wrong addr width parameter");
    assert (DATA_WIDTH > 0) else $fatal(1, "Wrong data width parameter");
    assert (in.SNOOP_ADDR_WIDTH  == ADDR_WIDTH) else $fatal(1, "Wrong interface definition");
    assert (in.SNOOP_DATA_WIDTH  == DATA_WIDTH) else $fatal(1, "Wrong interface definition");
    assert (out.SNOOP_ADDR_WIDTH == ADDR_WIDTH) else $fatal(1, "Wrong interface definition");
    assert (out.SNOOP_DATA_WIDTH == DATA_WIDTH) else $fatal(1, "Wrong interface definition");
  end
  `endif
  // pragma translate_on
endmodule
