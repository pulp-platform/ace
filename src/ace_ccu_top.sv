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
  parameter type mst_stg_aw_chan_t = logic,
  parameter type w_chan_t          = logic,
  parameter type slv_b_chan_t      = logic,
  parameter type mst_b_chan_t      = logic,
  parameter type mst_stg_b_chan_t  = logic,
  parameter type slv_ar_chan_t     = logic,
  parameter type mst_ar_chan_t     = logic,
  parameter type mst_stg_ar_chan_t = logic,
  parameter type slv_r_chan_t      = logic,
  parameter type mst_r_chan_t      = logic,
  parameter type mst_stg_r_chan_t  = logic,
  parameter type slv_req_t         = logic,
  parameter type slv_resp_t        = logic,
  parameter type mst_req_t         = logic,
  parameter type mst_resp_t        = logic,
  parameter type mst_stg_req_t     = logic,
  parameter type mst_stg_resp_t    = logic,
  parameter type snoop_req_t       = logic,
  parameter type snoop_resp_t      = logic

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
slv_req_t  [Cfg.NoSlvPorts-1:0] [1:0]      slv_reqs;   // one for non-shareable and one for shareable req
slv_resp_t [Cfg.NoSlvPorts-1:0] [1:0]      slv_resps;
// signals into the ace_muxes
mst_stg_req_t  [Cfg.NoSlvPorts:0]          mst_reqs;   // one extra port for CCU
mst_stg_resp_t [Cfg.NoSlvPorts:0]          mst_resps;
mst_stg_req_t  [Cfg.NoSlvPorts:0]          mst_reqs_tmp;
// signals into the CCU
slv_req_t  [Cfg.NoSlvPorts-1:0]            ccu_reqs_i;
slv_resp_t [Cfg.NoSlvPorts-1:0]            ccu_resps_o;
// signals from the CCU
mst_stg_req_t                              ccu_reqs_mux_o;
mst_stg_resp_t                             ccu_resps_mux_i;
mst_stg_req_t                              ccu_reqs_o;
mst_stg_resp_t                             ccu_resps_i;

// selection lines for mux and demuxes
logic [Cfg.NoSlvPorts-1:0]    slv_aw_select, slv_ar_select;


for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_slv_port_demux

    // routing of incoming request through transaction type
    ace_trs_dec #(
      .slv_ace_req_t  (       slv_req_t        )
    ) i_ace_trs_dec (
      .slv_reqs_i     (   slv_ports_req_i[i]   ),
      .snoop_aw_trs   (   slv_aw_select[i]     ),
      .snoop_ar_trs   (   slv_ar_select[i]     )
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
      .MaxTrans       ( Cfg.MaxMstTrans        ),
      .AxiLookBits    ( Cfg.AxiIdUsedSlvPorts  ),
      .UniqueIds      ( Cfg.UniqueIds          ),
      //.FallThrough    ( Cfg.FallThrough        ),
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
      .slv_aw_select_i ( slv_aw_select[i]      ),
      .slv_ar_select_i ( slv_ar_select[i]      ),
      .slv_resp_o      ( slv_ports_resp_o[i]   ),
      .mst_reqs_o      ( slv_reqs[i]           ),
      .mst_resps_i     ( slv_resps[i]          )
    );
end

axi_mux #(
  .SlvAxiIDWidth ( Cfg.AxiIdWidthSlvPorts+$clog2(Cfg.NoSlvPorts) ), // ID width of the slave ports
  .slv_aw_chan_t ( mst_stg_aw_chan_t      ), // AW Channel Type, slave ports
  .mst_aw_chan_t ( mst_aw_chan_t          ), // AW Channel Type, master port
  .w_chan_t      ( w_chan_t               ), //  W Channel Type, all ports
  .slv_b_chan_t  ( mst_stg_b_chan_t       ), //  B Channel Type, slave ports
  .mst_b_chan_t  ( mst_b_chan_t           ), //  B Channel Type, master port
  .slv_ar_chan_t ( mst_stg_ar_chan_t      ), // AR Channel Type, slave ports
  .mst_ar_chan_t ( mst_ar_chan_t          ), // AR Channel Type, master port
  .slv_r_chan_t  ( mst_stg_r_chan_t       ), //  R Channel Type, slave ports
  .mst_r_chan_t  ( mst_r_chan_t           ), //  R Channel Type, master port
  .slv_req_t     ( mst_stg_req_t          ),
  .slv_resp_t    ( mst_stg_resp_t         ),
  .mst_req_t     ( mst_req_t              ),
  .mst_resp_t    ( mst_resp_t             ),
  .NoSlvPorts    ( Cfg.NoSlvPorts + 1     ), // Number of Masters for the modules
  .MaxWTrans     ( Cfg.MaxMstTrans        ),
  .FallThrough   ( Cfg.FallThrough        ),
  .SpillAw       ( Cfg.LatencyMode[4]     ),
  .SpillW        ( Cfg.LatencyMode[3]     ),
  .SpillB        ( Cfg.LatencyMode[2]     ),
  .SpillAr       ( Cfg.LatencyMode[1]     ),
  .SpillR        ( Cfg.LatencyMode[0]     )
) i_axi_mux (
  .clk_i,   // Clock
  .rst_ni,  // Asynchronous reset active low
  .test_i,  // Test Mode enable
  .slv_reqs_i  ( mst_reqs         ),
  .slv_resps_o ( mst_resps        ),
  .mst_req_o   ( mst_ports_req_o  ),
  .mst_resp_i  ( mst_ports_resp_i )
);


// connection reqs and resps for non-shareable transactions with axi_mux
for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_non_shared_conn
  `ACE_ASSIGN_REQ_STRUCT(mst_reqs_tmp[i], slv_reqs[i][0])
  `ACE_ASSIGN_RESP_STRUCT(slv_resps[i][0], mst_resps[i])

  always_comb begin
    mst_reqs[i] = mst_reqs_tmp[i];
    mst_reqs[i].aw.user[$clog2(Cfg.NoSlvPorts)-1:0] = i[$clog2(Cfg.NoSlvPorts)-1:0];
    mst_reqs[i].ar.user[$clog2(Cfg.NoSlvPorts)-1:0] = i[$clog2(Cfg.NoSlvPorts)-1:0];

  end
end

// connect CCU reqs and resps to mux
always_comb begin
  mst_reqs[Cfg.NoSlvPorts] = mst_reqs_tmp[Cfg.NoSlvPorts];
  mst_reqs[Cfg.NoSlvPorts].aw.user[$clog2(Cfg.NoSlvPorts)-1:0] = mst_reqs_tmp[Cfg.NoSlvPorts].aw.id[Cfg.AxiIdWidthSlvPorts +: $clog2(Cfg.NoSlvPorts)];
  mst_reqs[Cfg.NoSlvPorts].ar.user[$clog2(Cfg.NoSlvPorts)-1:0] = mst_reqs_tmp[Cfg.NoSlvPorts].ar.id[Cfg.AxiIdWidthSlvPorts +: $clog2(Cfg.NoSlvPorts)];
end
`ACE_ASSIGN_REQ_STRUCT(mst_reqs_tmp[Cfg.NoSlvPorts], ccu_reqs_o)
`ACE_ASSIGN_RESP_STRUCT(ccu_resps_i, mst_resps[Cfg.NoSlvPorts])

// connection reqs and resps for shareable transactions with CCU
for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_shared_conn
  `ACE_ASSIGN_REQ_STRUCT(ccu_reqs_i[i], slv_reqs[i][1])
  `ACE_ASSIGN_RESP_STRUCT(slv_resps[i][1], ccu_resps_o[i])
end


axi_mux #(
  .SlvAxiIDWidth ( Cfg.AxiIdWidthSlvPorts ), // ID width of the slave ports
  .slv_aw_chan_t ( slv_aw_chan_t          ), // AW Channel Type, slave ports
  .mst_aw_chan_t ( mst_stg_aw_chan_t      ), // AW Channel Type, master port
  .w_chan_t      ( w_chan_t               ), //  W Channel Type, all ports
  .slv_b_chan_t  ( slv_b_chan_t           ), //  B Channel Type, slave ports
  .mst_b_chan_t  ( mst_stg_b_chan_t       ), //  B Channel Type, master port
  .slv_ar_chan_t ( slv_ar_chan_t          ), // AR Channel Type, slave ports
  .mst_ar_chan_t ( mst_stg_ar_chan_t      ), // AR Channel Type, master port
  .slv_r_chan_t  ( slv_r_chan_t           ), //  R Channel Type, slave ports
  .mst_r_chan_t  ( mst_stg_r_chan_t       ), //  R Channel Type, master port
  .slv_req_t     ( slv_req_t              ),
  .slv_resp_t    ( slv_resp_t             ),
  .mst_req_t     ( mst_stg_req_t          ),
  .mst_resp_t    ( mst_stg_resp_t         ),
  .NoSlvPorts    ( Cfg.NoSlvPorts         ), // Number of Masters for the modules
  .MaxWTrans     ( Cfg.MaxMstTrans        ),
  .FallThrough   ( Cfg.FallThrough        ),
  .SpillAw       ( Cfg.LatencyMode[4]     ),
  .SpillW        ( Cfg.LatencyMode[3]     ),
  .SpillB        ( Cfg.LatencyMode[2]     ),
  .SpillAr       ( Cfg.LatencyMode[1]     ),
  .SpillR        ( Cfg.LatencyMode[0]     )
) i_ace_mux (
  .clk_i,   // Clock
  .rst_ni,  // Asynchronous reset active low
  .test_i,  // Test Mode enable
  .slv_reqs_i  ( ccu_reqs_i       ),
  .slv_resps_o ( ccu_resps_o      ),
  .mst_req_o   ( ccu_reqs_mux_o   ),
  .mst_resp_i  ( ccu_resps_mux_i  )
);

ccu_fsm #(
    .DcacheLineWidth ( Cfg.DcacheLineWidth    ),
    .AxiDataWidth    ( Cfg.AxiDataWidth       ),
    .NoMstPorts      ( Cfg.NoSlvPorts         ),
    .SlvAxiIDWidth   ( Cfg.AxiIdWidthSlvPorts ), // ID width of the slave ports
    .mst_req_t       ( mst_stg_req_t          ),
    .mst_resp_t      ( mst_stg_resp_t         ),
    .snoop_req_t     ( snoop_req_t            ),
    .snoop_resp_t    ( snoop_resp_t           )

) fsm (
    .clk_i,
    .rst_ni,
    .ccu_req_i       ( ccu_reqs_mux_o     ),
    .ccu_resp_o      ( ccu_resps_mux_i    ),
    .ccu_req_o       ( ccu_reqs_o         ),
    .ccu_resp_i      ( ccu_resps_i        ),
    .s2m_req_o       ( slv_snp_req_o      ),
    .m2s_resp_i      ( slv_snp_resp_i     )
);

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

  localparam int unsigned AxiIdWidthMstPortsStage = Cfg.AxiIdWidthSlvPorts +$clog2(Cfg.NoSlvPorts);
  localparam int unsigned AxiIdWidthMstPorts = AxiIdWidthMstPortsStage + $clog2(Cfg.NoSlvPorts+1);

  typedef logic [AxiIdWidthMstPortsStage-1:0] id_mst_stg_t;
  typedef logic [AxiIdWidthMstPorts     -1:0] id_mst_t;
  typedef logic [Cfg.AxiIdWidthSlvPorts -1:0] id_slv_t;
  typedef logic [Cfg.AxiAddrWidth       -1:0] addr_t;
  typedef logic [Cfg.AxiDataWidth       -1:0] data_t;
  typedef logic [Cfg.AxiDataWidth/8     -1:0] strb_t;
  typedef logic [Cfg.AxiUserWidth       -1:0] user_t;

    // snoop channel conversion
  `ACE_TYPEDEF_AW_CHAN_T(mst_ace_stg_aw_chan_t, addr_t, id_mst_stg_t, user_t)
  `ACE_TYPEDEF_AW_CHAN_T(mst_ace_aw_chan_t, addr_t, id_mst_t, user_t)
  `ACE_TYPEDEF_AW_CHAN_T(slv_ace_aw_chan_t, addr_t, id_slv_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(mst_ace_stg_ar_chan_t, addr_t, id_mst_stg_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(mst_ace_ar_chan_t, addr_t, id_mst_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(slv_ace_ar_chan_t, addr_t, id_slv_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(mst_stg_b_chan_t, id_mst_stg_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(mst_b_chan_t, id_mst_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, id_slv_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(mst_ace_stg_r_chan_t, data_t, id_mst_stg_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(mst_ace_r_chan_t, data_t, id_mst_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(slv_ace_r_chan_t, data_t, id_slv_t, user_t)
  `ACE_TYPEDEF_REQ_T(mst_ace_stg_req_t, mst_ace_stg_aw_chan_t, w_chan_t, mst_ace_stg_ar_chan_t)
  `ACE_TYPEDEF_REQ_T(mst_ace_req_t, mst_ace_aw_chan_t, w_chan_t, mst_ace_ar_chan_t)
  `ACE_TYPEDEF_REQ_T(slv_ace_req_t, slv_ace_aw_chan_t, w_chan_t, slv_ace_ar_chan_t)
  `ACE_TYPEDEF_RESP_T(mst_ace_stg_resp_t, mst_stg_b_chan_t, mst_ace_stg_r_chan_t)
  `ACE_TYPEDEF_RESP_T(mst_ace_resp_t, mst_b_chan_t, mst_ace_r_chan_t)
  `ACE_TYPEDEF_RESP_T(slv_ace_resp_t, slv_b_chan_t, slv_ace_r_chan_t)
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
    .mst_stg_aw_chan_t  ( mst_ace_stg_aw_chan_t ),
    .mst_aw_chan_t      ( mst_ace_aw_chan_t     ),
    .w_chan_t           ( w_chan_t              ),
    .slv_b_chan_t       ( slv_b_chan_t          ),
    .mst_b_chan_t       ( mst_b_chan_t          ),
    .mst_stg_b_chan_t   ( mst_stg_b_chan_t      ),
    .slv_ar_chan_t      ( slv_ace_ar_chan_t     ),
    .mst_ar_chan_t      ( mst_ace_ar_chan_t     ),
    .mst_stg_ar_chan_t  ( mst_ace_stg_ar_chan_t ),
    .slv_r_chan_t       ( slv_ace_r_chan_t      ),
    .mst_r_chan_t       ( mst_ace_r_chan_t      ),
    .mst_stg_r_chan_t   ( mst_ace_stg_r_chan_t  ),
    .slv_req_t          ( slv_ace_req_t         ),
    .slv_resp_t         ( slv_ace_resp_t        ),
    .mst_req_t          ( mst_ace_req_t         ),
    .mst_resp_t         ( mst_ace_resp_t        ),
    .mst_stg_req_t      ( mst_ace_stg_req_t     ),
    .mst_stg_resp_t     ( mst_ace_stg_resp_t    ),
    .snoop_req_t        ( snoop_req_t           ),
    .snoop_resp_t       ( snoop_resp_t          )
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
