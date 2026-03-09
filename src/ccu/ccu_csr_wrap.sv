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

module ccu_csr_wrap
      import ccu_pkg::*;
      import ccu_csr_pkg::*;
#(
  parameter ccu_config_t  ccuCfg      = '{default: '0},
  parameter type          apb_req_t   = logic,
  parameter type          apb_resp_t  = logic,
  parameter  int unsigned numEvents   = 16
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  // APB interface
  input  apb_req_t  apb_req_i,
  output apb_resp_t apb_resp_o,
  // Performance events
  input  logic [numEvents-1:0] events_i
);

  localparam int unsigned numPerfCounters =
    $bits(ccu_csr__perf_countinhibit_r__inh__out_t);

  ccu_csr__in_t  hwif_in;
  ccu_csr__out_t hwif_out;

  for (genvar i = 0; i < numPerfCounters; i++) begin : gen_hwif
    assign hwif_in.perf_counter[i].val.incr = &{
      hwif_out.perf_eventsel[i].event_id.value < numEvents,
      !hwif_out.perf_countinhibit.inh.value[i],
      events_i[hwif_out.perf_eventsel[i].event_id.value]
    };
  end

  ccu_csr u_csr_regs (
    .clk           (clk_i),
    .arst_n        (rst_ni),
    .s_apb_psel    (apb_req_i.psel),
    .s_apb_penable (apb_req_i.penable),
    .s_apb_pwrite  (apb_req_i.pwrite),
    .s_apb_pprot   (apb_req_i.pprot),
    .s_apb_paddr   (apb_req_i.paddr[CCU_CSR_MIN_ADDR_WIDTH-1:0]),
    .s_apb_pwdata  (apb_req_i.pwdata),
    .s_apb_pstrb   (apb_req_i.pstrb),
    .s_apb_pready  (apb_resp_o.pready),
    .s_apb_prdata  (apb_resp_o.prdata),
    .s_apb_pslverr (apb_resp_o.pslverr),

    .hwif_in  (hwif_in),
    .hwif_out (hwif_out)
  );

  // pragma translate_off
  `ifndef VERILATOR
  initial begin
    tooManyPerformanceEvents: assert (numEvents <= 256)
      else $fatal("Number of events exceeds 256!");
  end
  `endif
  // pragma translate_on

endmodule
