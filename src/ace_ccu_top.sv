// Copyright (c) 2014-2018 ETH Zurich, University of Bologna
// Copyright (c) 2023 PlanV GmbH
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// ace_ccu_top: Top level module for closely coupled cache coherency protocol
`include "ace/assign.svh"
`include "ace/typedef.svh"

module ace_ccu_top
  import cf_math_pkg::idx_width;
#(
  parameter ace_pkg::ccu_cfg_t Cfg = '0,
  parameter bit  ATOPs             = 1'b1,
  parameter type slv_aw_chan_t     = logic,
  parameter type mst_aw_chan_t     = logic,
  parameter type int_aw_chan_t     = logic,
  parameter type w_chan_t          = logic,
  parameter type slv_b_chan_t      = logic,
  parameter type mst_b_chan_t      = logic,
  parameter type int_b_chan_t      = logic,
  parameter type slv_ar_chan_t     = logic,
  parameter type mst_ar_chan_t     = logic,
  parameter type int_ar_chan_t     = logic,
  parameter type slv_r_chan_t      = logic,
  parameter type mst_r_chan_t      = logic,
  parameter type int_r_chan_t      = logic,
  parameter type slv_req_t         = logic,
  parameter type slv_resp_t        = logic,
  parameter type mst_req_t         = logic,
  parameter type mst_resp_t        = logic,
  parameter type int_req_t         = logic,
  parameter type int_resp_t        = logic,
  parameter type snoop_req_t       = logic,
  parameter type snoop_resp_t      = logic,
  parameter type ac_chan_t         = logic,
  parameter type cr_chan_t         = logic,
  parameter type cd_chan_t         = logic

) (
  input  logic                             clk_i,
  input  logic                             rst_ni,
  input  logic                             test_i,
  input  slv_req_t    [Cfg.NoSlvPorts-1:0] slv_ports_req_i,
  output slv_resp_t   [Cfg.NoSlvPorts-1:0] slv_ports_resp_o,
  output snoop_req_t  [Cfg.NoSlvPorts-1:0] slv_snp_req_o,
  input  snoop_resp_t [Cfg.NoSlvPorts-1:0] slv_snp_resp_i,
  output mst_req_t                         mst_ports_req_o,
  input  mst_resp_t                        mst_ports_resp_i
);

// signals from the ace_demuxes
slv_req_t  [Cfg.NoSlvPorts-1:0] [1:0]      demuxed_reqs;   // one for non-shareable and one for shareable req
slv_resp_t [Cfg.NoSlvPorts-1:0] [1:0]      demuxed_resps;
// signals into the dispatch
slv_req_t  [Cfg.NoSlvPorts-1:0]            cached_reqs;
slv_resp_t [Cfg.NoSlvPorts-1:0]            cached_resps;
// signals into the CCU
slv_req_t  [Cfg.NoSlvPorts-1:0]            to_ccu_reqs;
slv_resp_t [Cfg.NoSlvPorts-1:0]            to_ccu_resps;
// signals from the CCU
int_req_t  [Cfg.NoSlvPorts-1:0]            fetch_ccu_reqs;
int_resp_t [Cfg.NoSlvPorts-1:0]            fetch_ccu_resps;
// signals to the mux
int_req_t  [Cfg.NoSlvPorts*2-1:0]          out_reqs;
int_req_t  [Cfg.NoSlvPorts*2-1:0]          out_reqs_tmp;
int_resp_t [Cfg.NoSlvPorts*2-1:0]          out_resps;

// selection lines for mux and demuxes
logic [Cfg.NoSlvPorts-1:0]    demux_aw_select, demux_ar_select;


for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_slv_port_demux

    // routing of incoming request through transaction type
    ace_trs_dec #(
      .slv_ace_req_t  (       slv_req_t        )
    ) i_ace_trs_dec (
      .slv_reqs_i     (   slv_ports_req_i[i]   ),
      .snoop_aw_trs   (   demux_aw_select[i]   ),
      .snoop_ar_trs   (   demux_ar_select[i]   )
    );

    // demux
    axi_demux #(
      .AxiIdWidth     ( Cfg.AxiIdWidthSlvPorts ),  // ID Width
      .AtopSupport    ( ATOPs                  ),
      .aw_chan_t      ( slv_aw_chan_t          ),  // AW Channel Type
      .w_chan_t       ( w_chan_t               ),  //  W Channel Type
      .b_chan_t       ( slv_b_chan_t           ),  //  B Channel Type
      .ar_chan_t      ( slv_ar_chan_t          ),  // AR Channel Type
      .r_chan_t       ( slv_r_chan_t           ),  //  R Channel Type
      .axi_req_t      ( slv_req_t              ),
      .axi_resp_t     ( slv_resp_t             ),
      .NoMstPorts     ( 2                      ),  // one for CCU module and one for mux
      .MaxTrans       ( 4                      ),
      .AxiLookBits    ( Cfg.AxiIdUsedSlvPorts  ),
      .UniqueIds      ( Cfg.UniqueIds          ),
      .SpillAw        ( Cfg.LatencyMode[9]     ),
      .SpillW         ( Cfg.LatencyMode[8]     ),
      .SpillB         ( Cfg.LatencyMode[7]     ),
      .SpillAr        ( Cfg.LatencyMode[6]     ),
      .SpillR         ( Cfg.LatencyMode[5]     )
    ) i_axi_demux (
      .clk_i,   // Clock
      .rst_ni,  // Asynchronous reset active low
      .test_i,  // Testmode enable
      .slv_req_i       ( slv_ports_req_i[i]    ),
      .slv_resp_o      ( slv_ports_resp_o[i]   ),
      .slv_aw_select_i ( demux_aw_select[i]    ),
      .slv_ar_select_i ( demux_ar_select[i]    ),
      .mst_reqs_o      ( demuxed_reqs[i]       ),
      .mst_resps_i     ( demuxed_resps[i]      )
    );
end

axi_mux #(
  .SlvAxiIDWidth ( Cfg.AxiIdWidthSlvPorts+1 ), // ID width of the slave ports
  .slv_aw_chan_t ( int_aw_chan_t            ), // AW Channel Type, slave ports
  .mst_aw_chan_t ( mst_aw_chan_t            ), // AW Channel Type, master port
  .w_chan_t      ( w_chan_t                 ), //  W Channel Type, all ports
  .slv_b_chan_t  ( int_b_chan_t             ), //  B Channel Type, slave ports
  .mst_b_chan_t  ( mst_b_chan_t             ), //  B Channel Type, master port
  .slv_ar_chan_t ( int_ar_chan_t            ), // AR Channel Type, slave ports
  .mst_ar_chan_t ( mst_ar_chan_t            ), // AR Channel Type, master port
  .slv_r_chan_t  ( int_r_chan_t             ), //  R Channel Type, slave ports
  .mst_r_chan_t  ( mst_r_chan_t             ), //  R Channel Type, master port
  .slv_req_t     ( int_req_t                ),
  .slv_resp_t    ( int_resp_t               ),
  .mst_req_t     ( mst_req_t                ),
  .mst_resp_t    ( mst_resp_t               ),
  .NoSlvPorts    ( Cfg.NoSlvPorts * 2       ), // Number of Masters for the modules
  .MaxWTrans     ( 4                        ),
  .FallThrough   ( Cfg.FallThrough          ),
  .SpillAw       ( Cfg.LatencyMode[4]       ),
  .SpillW        ( Cfg.LatencyMode[3]       ),
  .SpillB        ( Cfg.LatencyMode[2]       ),
  .SpillAr       ( Cfg.LatencyMode[1]       ),
  .SpillR        ( Cfg.LatencyMode[0]       )
) i_axi_mux (
  .clk_i,   // Clock
  .rst_ni,  // Asynchronous reset active low
  .test_i,  // Test Mode enable
  .slv_reqs_i  ( out_reqs         ),
  .slv_resps_o ( out_resps        ),
  .mst_req_o   ( mst_ports_req_o  ),
  .mst_resp_i  ( mst_ports_resp_i )
);


// connection reqs and resps for non-shareable transactions with axi_mux
for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_non_shared_conn
  `ACE_ASSIGN_REQ_STRUCT(out_reqs_tmp[i], demuxed_reqs[i][0])
  `ACE_ASSIGN_RESP_STRUCT(demuxed_resps[i][0], out_resps[i])

  `ACE_ASSIGN_REQ_STRUCT(out_reqs_tmp[Cfg.NoSlvPorts+i], fetch_ccu_reqs[i])
  `ACE_ASSIGN_RESP_STRUCT(fetch_ccu_resps[i], out_resps[Cfg.NoSlvPorts+i])

  always_comb begin
    out_reqs[i] = out_reqs_tmp[i];
    out_reqs[i].aw.user[$clog2(Cfg.NoSlvPorts*2)-1:0] = i[$clog2(Cfg.NoSlvPorts*2)-1:0];
    out_reqs[i].ar.user[$clog2(Cfg.NoSlvPorts*2)-1:0] = i[$clog2(Cfg.NoSlvPorts*2)-1:0];

    out_reqs[Cfg.NoSlvPorts+i] = out_reqs_tmp[Cfg.NoSlvPorts+i];
    out_reqs[Cfg.NoSlvPorts+i].aw.user[$clog2(Cfg.NoSlvPorts*2)-1:0] = Cfg.NoSlvPorts+i;
    out_reqs[Cfg.NoSlvPorts+i].ar.user[$clog2(Cfg.NoSlvPorts*2)-1:0] = Cfg.NoSlvPorts+i;
  end
end

// connection reqs and resps for shareable transactions with CCU
for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_shared_conn
  `ACE_ASSIGN_REQ_STRUCT(cached_reqs[i], demuxed_reqs[i][1])
  `ACE_ASSIGN_RESP_STRUCT(demuxed_resps[i][1], cached_resps[i])
end

assign to_ccu_reqs  = cached_reqs;
assign cached_resps = to_ccu_resps;

////////////////////
// Lookup Handler //
////////////////////

localparam bit          CollisionOnSetOnly = 0; // Hardcoded, can be used fort later exploration

// Collision happens when the tag and set bits match
localparam int unsigned IdQueueDataWidth = CollisionOnSetOnly ?
                                           Cfg.DCacheIndexWidth :
                                           Cfg.AxiAddrWidth - $clog2(Cfg.DcacheLineWidth/8);

// From CCUs
logic [Cfg.NoSlvPorts-1:0]                       lookup_req_out;
logic [Cfg.NoSlvPorts-1:0]                       lookup_resp_in;
logic [Cfg.NoSlvPorts-1:0][IdQueueDataWidth-1:0] lookup_addr_out;
// To CCUs
logic [Cfg.NoSlvPorts-1:0]                       lookup_req_in;
logic [Cfg.NoSlvPorts-1:0][Cfg.NoSlvPorts-1:0]   lookup_resp_out;
logic [Cfg.NoSlvPorts-1:0][IdQueueDataWidth-1:0] lookup_addr_in;

logic [Cfg.NoSlvPorts-1:0] overlapping, lookup_resp_compacted;

// Overlapping happens when multiple cores try to initiate
// a transaction on the same cacheline
// The priority is statically given to the CCU with the lowest
// index between those competing for the same cacheline
always_comb begin
  overlapping = '0;
  for (int i = 0; i < Cfg.NoSlvPorts; i++) begin
    for (int j = 0; j < i; j++) begin
      overlapping [i] |= lookup_req_out[i] && lookup_req_out[j] &&
                         lookup_addr_out[i] == lookup_addr_out[j];
    end
  end
end

// Simple assign
assign lookup_req_in  = lookup_req_out;
assign lookup_addr_in = lookup_addr_out;

// Collision happens when:
// 1) A CCU reports a collision with an inflight transaction
// 2) Multiple requests overlap on the same cacheline
for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin
  always_comb begin
    lookup_resp_compacted[i] = '0;
    for (int j = 0; j < Cfg.NoSlvPorts; j++) begin
      lookup_resp_compacted[i] |= lookup_resp_out[j][i];
    end
  end
  assign lookup_resp_in[i] = lookup_resp_compacted[i] || overlapping[i];
end

snoop_req_t  [Cfg.NoSlvPorts*2-1:0] slv_snp_req ;
snoop_resp_t [Cfg.NoSlvPorts*2-1:0] slv_snp_resp;

for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_ccu_fsm
   snoop_req_t  [Cfg.NoSlvPorts-1:0] ccu_snp_req ;
   snoop_resp_t [Cfg.NoSlvPorts-1:0] ccu_snp_resp;
   for (genvar j = 0; j < Cfg.NoSlvPorts; j++) begin : gen_transpose_mux
      assign slv_snp_req[j+Cfg.NoSlvPorts*i] = ccu_snp_req[j];
      assign ccu_snp_resp[j] = slv_snp_resp[j+Cfg.NoSlvPorts*i];
   end

    ccu_ctrl #(
    .DcacheLineWidth ( Cfg.DcacheLineWidth    ),
    .DCacheIndexWidth( Cfg.DCacheIndexWidth   ),
    .AxiDataWidth    ( Cfg.AxiDataWidth       ),
    .AxiAddrWidth    ( Cfg.AxiAddrWidth       ),
    .NoMstPorts      ( Cfg.NoSlvPorts         ),
    .SlvAxiIDWidth   ( Cfg.AxiIdWidthSlvPorts ), // ID width of the slave ports
    .IdQueueDataWidth( IdQueueDataWidth       ),
    .mst_aw_chan_t   ( int_aw_chan_t          ), // AW Channel Type, master port
    .w_chan_t        ( w_chan_t               ), //  W Channel Type, all ports
    .mst_b_chan_t    ( int_b_chan_t           ), //  B Channel Type, master port
    .mst_ar_chan_t   ( int_ar_chan_t          ), // AR Channel Type, master port
    .mst_r_chan_t    ( int_r_chan_t           ), //  R Channel Type, master port
    .mst_req_t       ( int_req_t              ),
    .mst_resp_t      ( int_resp_t             ),
    .slv_aw_chan_t   ( slv_aw_chan_t          ),
    .slv_b_chan_t    ( slv_b_chan_t           ),
    .slv_ar_chan_t   ( slv_ar_chan_t          ),
    .slv_r_chan_t    ( slv_r_chan_t           ),
    .slv_req_t       ( slv_req_t              ),
    .slv_resp_t      ( slv_resp_t             ),
    .snoop_ac_t      ( ac_chan_t              ),
    .snoop_cr_t      ( cr_chan_t              ),
    .snoop_cd_t      ( cd_chan_t              ),
    .snoop_req_t     ( snoop_req_t            ),
    .snoop_resp_t    ( snoop_resp_t           ),
    .IDCCU           ( i                      )
  ) ccu_ctrl_i (
    .clk_i,
    .rst_ni,
    .ccu_req_i       ( to_ccu_reqs[i]     ),
    .ccu_resp_o      ( to_ccu_resps[i]    ),
    .ccu_req_o       ( fetch_ccu_reqs[i]  ),
    .ccu_resp_i      ( fetch_ccu_resps[i] ),
    .s2m_req_o       ( ccu_snp_req        ),
    .m2s_resp_i      ( ccu_snp_resp       ),

    .lookup_req_o    ( lookup_req_out[i]  ),
    .lookup_resp_i   ( lookup_resp_in[i]  ),
    .lookup_addr_o   ( lookup_addr_out[i] ),

    .lookup_req_i    ( lookup_req_in      ),
    .lookup_resp_o   ( lookup_resp_out[i] ),
    .lookup_addr_i   ( lookup_addr_in     )
);

end // block: gen_ccu_fsm

for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_snoop_mux
   snoop_req_t  [Cfg.NoSlvPorts-1:0] ccu_snp_req ;
   snoop_resp_t [Cfg.NoSlvPorts-1:0] ccu_snp_resp;
   for (genvar j = 0; j < Cfg.NoSlvPorts; j++) begin : gen_transpose_mux
      assign ccu_snp_req[j] = slv_snp_req[j*Cfg.NoSlvPorts+i];
      assign slv_snp_resp[j*Cfg.NoSlvPorts+i] = ccu_snp_resp[j];
   end

   snoop_mux #(
     .snoop_req_t  ( snoop_req_t    ),
     .snoop_resp_t ( snoop_resp_t   ),
     .ac_chan_t    ( ac_chan_t      ),
     .cr_chan_t    ( cr_chan_t      ),
     .cd_chan_t    ( cd_chan_t      ),
     .NoSlvPorts   ( Cfg.NoSlvPorts )
   ) i_snoop_mux (
       .clk_i,
       .rst_ni,
       .slv_reqs_i   ( ccu_snp_req       ),
       .slv_resps_o  ( ccu_snp_resp      ),
       .mst_req_o    ( slv_snp_req_o[i]  ),
       .mst_resp_i   ( slv_snp_resp_i[i] )
   );
end // block: gen_ccu_fsm

endmodule



module ace_ccu_top_intf
  import cf_math_pkg::idx_width;
#(
  parameter ace_pkg::ccu_cfg_t Cfg      = '0,
  parameter bit ATOPS                   = 1'b1
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  input  logic     test_i,
  SNOOP_BUS.Slave  snoop_ports [Cfg.NoSlvPorts-1:0],
  ACE_BUS.Slave    slv_ports   [Cfg.NoSlvPorts-1:0],
  AXI_BUS.Master   mst_ports
);

  localparam int unsigned AxiIdWidthMstPort  = Cfg.AxiIdWidthSlvPorts + $clog2(Cfg.NoSlvPorts*2) + 1;
  localparam int unsigned AxiIdWidthInternal = Cfg.AxiIdWidthSlvPorts + 1;

  typedef logic [Cfg.AxiIdWidthSlvPorts -1:0] id_slv_t;
  typedef logic [AxiIdWidthMstPort      -1:0] id_mst_t;
  typedef logic [AxiIdWidthInternal     -1:0] id_int_t;
  typedef logic [Cfg.AxiAddrWidth       -1:0] addr_t;
  typedef logic [Cfg.AxiDataWidth       -1:0] data_t;
  typedef logic [Cfg.AxiDataWidth/8     -1:0] strb_t;
  typedef logic [Cfg.AxiUserWidth       -1:0] user_t;

    // snoop channel conversion
  `ACE_TYPEDEF_AW_CHAN_T(mst_ace_aw_chan_t, addr_t, id_mst_t, user_t)
  `ACE_TYPEDEF_AW_CHAN_T(slv_ace_aw_chan_t, addr_t, id_slv_t, user_t)
  `ACE_TYPEDEF_AW_CHAN_T(int_aw_chan_t, addr_t, id_int_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(mst_ace_ar_chan_t, addr_t, id_mst_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(slv_ace_ar_chan_t, addr_t, id_slv_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(int_ar_chan_t, addr_t, id_int_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(mst_b_chan_t, id_mst_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, id_slv_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(int_b_chan_t, id_int_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(mst_ace_r_chan_t, data_t, id_mst_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(slv_ace_r_chan_t, data_t, id_slv_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(int_r_chan_t, data_t, id_int_t, user_t)
  `ACE_TYPEDEF_REQ_T(mst_ace_req_t, mst_ace_aw_chan_t, w_chan_t, mst_ace_ar_chan_t)
  `ACE_TYPEDEF_REQ_T(slv_ace_req_t, slv_ace_aw_chan_t, w_chan_t, slv_ace_ar_chan_t)
  `ACE_TYPEDEF_REQ_T(int_req_t, int_aw_chan_t, w_chan_t, int_ar_chan_t)
  `ACE_TYPEDEF_RESP_T(mst_ace_resp_t, mst_b_chan_t, mst_ace_r_chan_t)
  `ACE_TYPEDEF_RESP_T(slv_ace_resp_t, slv_b_chan_t, slv_ace_r_chan_t)
  `ACE_TYPEDEF_RESP_T(int_resp_t, int_b_chan_t, int_r_chan_t)
  `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
  `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
  `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
  `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
  `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)


  mst_ace_req_t                           mst_ace_reqs;
  mst_ace_resp_t                          mst_ace_resps;
  slv_ace_req_t     [Cfg.NoSlvPorts-1:0]  slv_ace_reqs;
  slv_ace_resp_t    [Cfg.NoSlvPorts-1:0]  slv_ace_resps;
  snoop_req_t       [Cfg.NoSlvPorts-1:0]  snoop_reqs;
  snoop_resp_t      [Cfg.NoSlvPorts-1:0]  snoop_resps;


  /// Assigning ACE request from CCU Mux to slave(RAM)
  `AXI_ASSIGN_FROM_REQ(mst_ports, mst_ace_reqs)
  /// Assigning AXI response from slave (RAM) to CCU mux which accepts only ACE type response
  `ACE_ASSIGN_TO_RESP(mst_ace_resps, mst_ports)


  for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_assign_slv
    `ACE_ASSIGN_TO_REQ(slv_ace_reqs[i], slv_ports[i])
    `ACE_ASSIGN_FROM_RESP(slv_ports[i], slv_ace_resps[i])
    /// Assigning SNOOP request from CCU logic to master
    `SNOOP_ASSIGN_FROM_REQ(snoop_ports[i], snoop_reqs[i])
    /// Assigning SNOOP response from master to CCU logic
    `SNOOP_ASSIGN_TO_RESP(snoop_resps[i], snoop_ports[i])
  end


  ace_ccu_top #(
    .Cfg                ( Cfg                   ),
    .ATOPs              ( ATOPS                 ),
    .slv_aw_chan_t      ( slv_ace_aw_chan_t     ),
    .mst_aw_chan_t      ( mst_ace_aw_chan_t     ),
    .int_aw_chan_t      ( int_aw_chan_t         ),
    .w_chan_t           ( w_chan_t              ),
    .slv_b_chan_t       ( slv_b_chan_t          ),
    .mst_b_chan_t       ( mst_b_chan_t          ),
    .int_b_chan_t       ( int_b_chan_t          ),
    .slv_ar_chan_t      ( slv_ace_ar_chan_t     ),
    .mst_ar_chan_t      ( mst_ace_ar_chan_t     ),
    .int_ar_chan_t      ( int_ar_chan_t         ),
    .slv_r_chan_t       ( slv_ace_r_chan_t      ),
    .mst_r_chan_t       ( mst_ace_r_chan_t      ),
    .int_r_chan_t       ( int_r_chan_t          ),
    .slv_req_t          ( slv_ace_req_t         ),
    .slv_resp_t         ( slv_ace_resp_t        ),
    .mst_req_t          ( mst_ace_req_t         ),
    .mst_resp_t         ( mst_ace_resp_t        ),
    .int_req_t          ( int_req_t             ),
    .int_resp_t         ( int_resp_t            ),
    .snoop_req_t        ( snoop_req_t           ),
    .snoop_resp_t       ( snoop_resp_t          ),
    .ac_chan_t          ( snoop_ac_t            ),
    .cr_chan_t          ( snoop_cr_t            ),
    .cd_chan_t          ( snoop_cd_t            )
  ) i_ccu_top (
    .clk_i,
    .rst_ni,
    .test_i,
    .slv_ports_req_i    ( slv_ace_reqs          ),
    .slv_ports_resp_o   ( slv_ace_resps         ),
    .slv_snp_req_o      ( snoop_reqs            ),
    .slv_snp_resp_i     ( snoop_resps           ),
    .mst_ports_req_o    ( mst_ace_reqs          ),
    .mst_ports_resp_i   ( mst_ace_resps         )
  );

endmodule
