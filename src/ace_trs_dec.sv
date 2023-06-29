// Copyright (c) 2019 ETH Zurich and University of Bologna.
// Copyright (c) 2022 PlanV GmbH
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

module ace_trs_dec
#(
  parameter type slv_ace_req_t = logic
) (
  // incoming request from master
  input     slv_ace_req_t   slv_reqs_i,
  // Write transaction shareable
  output    logic           snoop_aw_trs,
  // Read transaction shareable
  output    logic           snoop_ar_trs
);

/// Types of transactions bypassing CCU
logic write_back, write_no_snoop, read_no_snoop;

assign write_back     =   (slv_reqs_i.aw.snoop == 'b011) && (slv_reqs_i.aw.bar[0] == 'b0) &&
                          ((slv_reqs_i.aw.domain == 'b00) || (slv_reqs_i.aw.domain == 'b01) ||
                          (slv_reqs_i.aw.domain == 'b10));

assign write_no_snoop =   (slv_reqs_i.aw.snoop == 'b000) && (slv_reqs_i.aw.bar[0] == 'b0) &&
                        ((slv_reqs_i.aw.domain == 'b00) || (slv_reqs_i.aw.domain == 'b11) );
assign read_no_snoop  =    (slv_reqs_i.ar.snoop == 'b0000) && (slv_reqs_i.ar.bar[0] =='b0) &&
                        ((slv_reqs_i.ar.domain == 'b00) || (slv_reqs_i.ar.domain == 'b11) );

assign snoop_aw_trs = ~(write_back | write_no_snoop); 
assign snoop_ar_trs = ~(read_no_snoop);

endmodule
