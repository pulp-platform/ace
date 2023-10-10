// Copyright (c) 2014-2018 ETH Zurich, University of Bologna
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


//! ACE Package
/// Contains all necessary type definitions, constants, and generally useful functions.
package ace_pkg;

   // Support for snoop channels
   typedef logic [3:0] arsnoop_t;
   typedef logic [2:0] awsnoop_t;
   typedef logic [1:0] bar_t;
   typedef logic [1:0] domain_t;
   typedef logic [0:0] awunique_t;
   typedef logic [3:0] rresp_t;

  /// Slice on Demux AW channel.
  localparam logic [9:0] DemuxAw = (1 << 9);
  /// Slice on Demux W channel.
  localparam logic [9:0] DemuxW  = (1 << 8);
  /// Slice on Demux B channel.
  localparam logic [9:0] DemuxB  = (1 << 7);
  /// Slice on Demux AR channel.
  localparam logic [9:0] DemuxAr = (1 << 6);
  /// Slice on Demux R channel.
  localparam logic [9:0] DemuxR  = (1 << 5);
  /// Slice on Mux AW channel.
  localparam logic [9:0] MuxAw   = (1 << 4);
  /// Slice on Mux W channel.
  localparam logic [9:0] MuxW    = (1 << 3);
  /// Slice on Mux B channel.
  localparam logic [9:0] MuxB    = (1 << 2);
  /// Slice on Mux AR channel.
  localparam logic [9:0] MuxAr   = (1 << 1);
  /// Slice on Mux R channel.
  localparam logic [9:0] MuxR    = (1 << 0);
  /// Latency configuration for `ace_xbar`.
  typedef enum logic [9:0] {
    NO_LATENCY    = 10'b000_00_000_00,
    CUT_SLV_AX    = DemuxAw | DemuxAr,
    CUT_MST_AX    = MuxAw | MuxAr,
    CUT_ALL_AX    = DemuxAw | DemuxAr | MuxAw | MuxAr,
    CUT_SLV_PORTS = DemuxAw | DemuxW | DemuxB | DemuxAr | DemuxR,
    CUT_MST_PORTS = MuxAw | MuxW | MuxB | MuxAr | MuxR,
    CUT_ALL_PORTS = 10'b111_11_111_11
  } ccu_latency_e;

  /// Configuration for `ace_ccu`.
  typedef struct packed {
    int unsigned  NoSlvPorts;
    int unsigned  MaxMstTrans;
    int unsigned  MaxSlvTrans;
    bit           FallThrough;
    ccu_latency_e LatencyMode;
    int unsigned  AxiIdWidthSlvPorts;
    int unsigned  AxiIdUsedSlvPorts;
    bit           UniqueIds;
    int unsigned  AxiAddrWidth;
    int unsigned  AxiDataWidth;
    int unsigned  DcacheLineWidth;
  } ccu_cfg_t;

 /// transaction type
  typedef enum logic[2:0] {READ_NO_SNOOP, READ_ONCE, READ_SHARED, READ_UNIQUE, CLEAN_UNIQUE, WRITE_NO_SNOOP, WRITE_BACK, WRITE_UNIQUE} ace_trs_t;

endpackage
