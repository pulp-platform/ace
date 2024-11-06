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
// Authors:
// - Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// - Andreas Kurth <akurth@iis.ee.ethz.ch>

// Directed Random Verification Testbench for `axi_xbar`:  The crossbar is instantiated with
// a number of random axi master and slave modules.  Each random master executes a fixed number of
// writes and reads over the whole addess map.  All masters simultaneously issue transactions
// through the crossbar, thereby saturating it.  A monitor, which snoops the transactions of each
// master and slave port and models the crossbar with a network of FIFOs, checks whether each
// transaction follows the expected route.

`include "ace/typedef.svh"
`include "ace/assign.svh"

module tb_ace_ccu_top #(
  parameter bit TbEnAtop = 1'b1,            // enable atomic operations (ATOPs)
  parameter bit TbEnExcl = 1'b0,            // enable exclusive accesses
  parameter bit TbUniqueIds = 1'b0,         // restrict to only unique IDs
  parameter int unsigned TbNumMst = 32'd4,  // how many AXI masters there are
  parameter int unsigned TbNumSlv = 32'd1   // how many AXI slaves there are
);
  // Random master no Transactions
  localparam int unsigned NoWrites = 80;   // How many writes per master
  localparam int unsigned NoReads  = 80;   // How many reads per master
  // timing parameters
  localparam time CyclTime = 10ns;
  localparam time ApplTime =  2ns;
  localparam time TestTime =  8ns;

  // axi configuration
  localparam int unsigned AxiIdWidthMasters =  4;
  localparam int unsigned AxiIdUsed         =  3; // Has to be <= AxiIdWidthMasters
  localparam int unsigned AxiIdWidthSlaves  =  AxiIdWidthMasters + $clog2(TbNumMst)+$clog2(TbNumMst+1);
  localparam int unsigned AxiAddrWidth      =  32;    // Axi Address Width
  localparam int unsigned AxiDataWidth      =  64;    // Axi Data Width
  localparam int unsigned AxiStrbWidth      =  AxiDataWidth / 8;
  localparam int unsigned AxiUserWidth      =  5;

  // in the bench can change this variables which are set here freely
  localparam ace_pkg::ccu_cfg_t ccu_cfg = '{
    NoSlvPorts:         TbNumMst,
    MaxMstTrans:        10,
    MaxSlvTrans:        6,
    FallThrough:        1'b1,
    LatencyMode:        ace_pkg::NO_LATENCY,
    AxiIdWidthSlvPorts: AxiIdWidthMasters,
    AxiIdUsedSlvPorts:  AxiIdUsed,
    UniqueIds:          TbUniqueIds,
    AxiAddrWidth:       AxiAddrWidth,
    AxiDataWidth:       AxiDataWidth
  };


  typedef logic [AxiIdWidthMasters-1:0] id_mst_t;
  typedef logic [AxiIdWidthSlaves-1:0]  id_slv_t;
  typedef logic [AxiAddrWidth-1:0]      addr_t;
  typedef logic [AxiDataWidth-1:0]      data_t;
  typedef logic [AxiStrbWidth-1:0]      strb_t;
  typedef logic [AxiUserWidth-1:0]      user_t;

  `ACE_TYPEDEF_AW_CHAN_T(aw_chan_mst_t, addr_t, id_mst_t, user_t)
  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_slv_t, addr_t, id_slv_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_mst_t, id_mst_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_slv_t, id_slv_t, user_t)

  `ACE_TYPEDEF_AR_CHAN_T(ar_chan_mst_t, addr_t, id_mst_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_slv_t, addr_t, id_slv_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(r_chan_mst_t, data_t, id_mst_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(r_chan_slv_t, data_t, id_slv_t, user_t)

  `ACE_TYPEDEF_REQ_T(mst_req_t, aw_chan_mst_t, w_chan_t, ar_chan_mst_t)
  `ACE_TYPEDEF_RESP_T(mst_resp_t, b_chan_mst_t, r_chan_mst_t)
  `AXI_TYPEDEF_REQ_T(slv_req_t, aw_chan_slv_t, w_chan_t, ar_chan_slv_t)
  `AXI_TYPEDEF_RESP_T(slv_resp_t, b_chan_slv_t, r_chan_slv_t)

  `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
  `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)  
  `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)  
  `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
  `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)


  typedef ace_test::ace_rand_master #(
    // AXI interface parameters
    .AW ( AxiAddrWidth       ),
    .DW ( AxiDataWidth       ),
    .IW ( AxiIdWidthMasters  ),
    .UW ( AxiUserWidth       ),
    // Stimuli application and test time
    .TA ( ApplTime           ),
    .TT ( TestTime           ),
    // Maximum number of read and write transactions in flight
    .MAX_READ_TXNS  ( 20     ),
    .MAX_WRITE_TXNS ( 20     ),
    .AXI_EXCLS      ( TbEnExcl ),
    .AXI_ATOPS      ( TbEnAtop ),
    .UNIQUE_IDS     ( TbUniqueIds )
  ) ace_rand_master_t;
  typedef axi_test::axi_rand_slave #(
    // AXI interface parameters
    .AW ( AxiAddrWidth     ),
    .DW ( AxiDataWidth     ),
    .IW ( AxiIdWidthSlaves ),
    .UW ( AxiUserWidth     ),
    // Stimuli application and test time
    .TA ( ApplTime         ),
    .TT ( TestTime         )
  ) axi_rand_slave_t;

  typedef snoop_test::snoop_rand_slave #(
    // ADDR and Data interface parameters
    .AW ( AxiAddrWidth    ),
    .DW ( AxiDataWidth    ),
    // Stimuli application and test time
    .TA ( ApplTime),
    .TT ( TestTime),
    .RAND_RESP ( '0),
    // Upper and lower bounds on wait cycles on Ax, W, and resp (R and B) channels
    .AC_MIN_WAIT_CYCLES ( 2),
    .AC_MAX_WAIT_CYCLES ( 15),
    .CR_MIN_WAIT_CYCLES ( 2),
    .CR_MAX_WAIT_CYCLES ( 15),
    .CD_MIN_WAIT_CYCLES ( 2),
    .CD_MAX_WAIT_CYCLES ( 15)
  )snoop_rand_slave_t;
  // -------------
  // DUT signals
  // -------------
  logic clk;
  // DUT signals
  logic rst_n;
  logic [TbNumMst-1:0] end_of_sim;

  // master structs
  mst_req_t  [TbNumMst-1:0] masters_req;
  mst_resp_t [TbNumMst-1:0] masters_resp;

  // slave structs
  slv_req_t  [TbNumSlv-1:0] slaves_req;
  slv_resp_t [TbNumSlv-1:0] slaves_resp;

  // snoop structs
  snoop_req_t  [TbNumMst-1:0] snoop_req;
  snoop_resp_t [TbNumMst-1:0] snoop_resp;


  // -------------------------------
  // AXI Interfaces
  // -------------------------------
  ACE_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      ),
    .AXI_ID_WIDTH   ( AxiIdWidthMasters ),
    .AXI_USER_WIDTH ( AxiUserWidth      )
  ) master [TbNumMst-1:0] ();
  ACE_BUS_DV #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      ),
    .AXI_ID_WIDTH   ( AxiIdWidthMasters ),
    .AXI_USER_WIDTH ( AxiUserWidth      )
  ) master_dv [TbNumMst-1:0] (clk);
  ACE_BUS_DV #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      ),
    .AXI_ID_WIDTH   ( AxiIdWidthMasters ),
    .AXI_USER_WIDTH ( AxiUserWidth      )
  ) master_monitor_dv [TbNumMst-1:0] (clk);
  for (genvar i = 0; i < TbNumMst; i++) begin : gen_conn_dv_masters
    `ACE_ASSIGN (master[i], master_dv[i])
    `ACE_ASSIGN_TO_REQ(masters_req[i], master[i])
    `ACE_ASSIGN_TO_RESP(masters_resp[i], master[i])
  end

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
  ) slave [TbNumSlv-1:0] ();
  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
  ) slave_dv [TbNumSlv-1:0](clk);
  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
  ) slave_monitor_dv [TbNumSlv-1:0](clk);
  for (genvar i = 0; i < TbNumSlv; i++) begin : gen_conn_dv_slaves
    `AXI_ASSIGN(slave_dv[i], slave[i])
    `AXI_ASSIGN_TO_REQ(slaves_req[i], slave[i])
    `AXI_ASSIGN_TO_RESP(slaves_resp[i], slave[i])
  end

  SNOOP_BUS #(
    .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
    .SNOOP_DATA_WIDTH ( AxiDataWidth      )
  ) snoop [TbNumMst-1:0] ();
  SNOOP_BUS_DV #(
    .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
    .SNOOP_DATA_WIDTH ( AxiDataWidth      )
  ) snoop_dv [TbNumMst-1:0](clk);
  SNOOP_BUS_DV #(
    .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
    .SNOOP_DATA_WIDTH ( AxiDataWidth      )
  ) snoop_monitor_dv [TbNumMst-1:0](clk);
   for (genvar i = 0; i < TbNumMst; i++) begin : gen_conn_dv_snoop
    `SNOOP_ASSIGN(snoop_dv[i], snoop[i])
    `SNOOP_ASSIGN_TO_REQ(snoop_req[i], snoop[i])
    `SNOOP_ASSIGN_TO_RESP(snoop_resp[i], snoop[i])
  end

  // -------------------------------
  // AXI and SNOOP Rand Masters and Slaves
  // -------------------------------
  // Masters control simulation run time
  ace_rand_master_t ace_rand_master [TbNumMst];
  for (genvar i = 0; i < TbNumMst; i++) begin : gen_rand_master
    initial begin
      ace_rand_master[i] = new( master_dv[i] );
      end_of_sim[i] <= 1'b0;
      ace_rand_master[i].add_memory_region(32'h0000_0000, 32'h0000_3000,
                                      axi_pkg::DEVICE_NONBUFFERABLE);
      ace_rand_master[i].reset();
      @(posedge rst_n);
      ace_rand_master[i].run(NoReads, NoWrites);
      end_of_sim[i] <= 1'b1;
    end
  end

  snoop_rand_slave_t snoop_rand_slave [TbNumMst];
  for (genvar i = 0; i < TbNumMst; i++) begin : gen_rand_snoop
    initial begin
      snoop_rand_slave[i] = new( snoop_dv[i] );
      snoop_rand_slave[i].reset();
      @(posedge rst_n);
      snoop_rand_slave[i].run();
    end
  end


  axi_rand_slave_t axi_rand_slave [1];
  for (genvar i = 0; i < TbNumSlv; i++) begin : gen_rand_slave
    initial begin
      axi_rand_slave[i] = new( slave_dv[i] );
      axi_rand_slave[i].reset();
      @(posedge rst_n);
      axi_rand_slave[i].run();
    end
  end

  


  initial begin : proc_monitor
    static tb_ace_ccu_pkg::ace_ccu_monitor #(
      .AxiAddrWidth      ( AxiAddrWidth         ),
      .AxiDataWidth      ( AxiDataWidth         ),
      .AxiIdWidthMasters ( AxiIdWidthMasters    ),
      .AxiIdWidthSlaves  ( AxiIdWidthSlaves     ),
      .AxiUserWidth      ( AxiUserWidth         ),
      .NoMasters         ( TbNumMst            ),
      .NoSlaves          ( TbNumSlv             ),
      .TimeTest          ( TestTime             )
    ) monitor = new( master_monitor_dv, slave_monitor_dv, snoop_monitor_dv );
    fork
      monitor.run();
      do begin
        #TestTime;
        if(end_of_sim == '1) begin
          monitor.print_result();
          $stop();
        end
        @(posedge clk);
      end while (1'b1);
    join
  end

  //-----------------------------------
  // Clock generator
  //-----------------------------------
    clk_rst_gen #(
    .ClkPeriod    ( CyclTime ),
    .RstClkCycles ( 5        )
  ) i_clk_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );

  //-----------------------------------
  // DUT
  //-----------------------------------
  ace_ccu_top_intf #(
    .AXI_USER_WIDTH ( AxiUserWidth  ),
    .Cfg            ( ccu_cfg      )
  ) i_ccu_dut (
    .clk_i                  ( clk     ),
    .rst_ni                 ( rst_n   ),
    .test_i                 ( 1'b0    ),
    .snoop_ports            ( snoop   ),
    .slv_ports              ( master  ),
    .mst_ports              ( slave[0]   )
  );

  // logger for master modules
  for (genvar i = 0; i < TbNumMst; i++) begin : gen_master_logger
    ace_chan_logger #(
      .TestTime  ( TestTime      ), // Time after clock, where sampling happens
      .LoggerName( $sformatf("axi_logger_master_%0d", i)),
      .aw_chan_t ( aw_chan_mst_t ), // axi AW type
      .w_chan_t  (  w_chan_t     ), // axi  W type
      .b_chan_t  (  b_chan_mst_t ), // axi  B type
      .ar_chan_t ( ar_chan_mst_t ), // axi AR type
      .r_chan_t  (  r_chan_mst_t )  // axi  R type
    ) i_mst_channel_logger (
      .clk_i      ( clk         ),    // Clock
      .rst_ni     ( rst_n       ),    // Asynchronous reset active low, when `1'b0` no sampling
      .end_sim_i  ( &end_of_sim ),
      // AW channel
      .aw_chan_i  ( masters_req[i].aw        ),
      .aw_valid_i ( masters_req[i].aw_valid  ),
      .aw_ready_i ( masters_resp[i].aw_ready ),
      //  W channel
      .w_chan_i   ( masters_req[i].w         ),
      .w_valid_i  ( masters_req[i].w_valid   ),
      .w_ready_i  ( masters_resp[i].w_ready  ),
      //  B channel
      .b_chan_i   ( masters_resp[i].b        ),
      .b_valid_i  ( masters_resp[i].b_valid  ),
      .b_ready_i  ( masters_req[i].b_ready   ),
      // AR channel
      .ar_chan_i  ( masters_req[i].ar        ),
      .ar_valid_i ( masters_req[i].ar_valid  ),
      .ar_ready_i ( masters_resp[i].ar_ready ),
      //  R channel
      .r_chan_i   ( masters_resp[i].r        ),
      .r_valid_i  ( masters_resp[i].r_valid  ),
      .r_ready_i  ( masters_req[i].r_ready   )
    );
  end
  // logger for slave modules
  for (genvar i = 0; i < 1; i++) begin : gen_slave_logger
    axi_chan_logger #(
      .TestTime  ( TestTime      ), // Time after clock, where sampling happens
      .LoggerName( $sformatf("axi_logger_slave_%0d",i)),
      .aw_chan_t ( aw_chan_slv_t ), // axi AW type
      .w_chan_t  (  w_chan_t     ), // axi  W type
      .b_chan_t  (  b_chan_slv_t ), // axi  B type
      .ar_chan_t ( ar_chan_slv_t ), // axi AR type
      .r_chan_t  (  r_chan_slv_t )  // axi  R type
    ) i_slv_channel_logger (
      .clk_i      ( clk         ),    // Clock
      .rst_ni     ( rst_n       ),    // Asynchronous reset active low, when `1'b0` no sampling
      .end_sim_i  ( &end_of_sim ),
      // AW channel
      .aw_chan_i  ( slaves_req[i].aw        ),
      .aw_valid_i ( slaves_req[i].aw_valid  ),
      .aw_ready_i ( slaves_resp[i].aw_ready ),
      //  W channel
      .w_chan_i   ( slaves_req[i].w         ),
      .w_valid_i  ( slaves_req[i].w_valid   ),
      .w_ready_i  ( slaves_resp[i].w_ready  ),
      //  B channel
      .b_chan_i   ( slaves_resp[i].b        ),
      .b_valid_i  ( slaves_resp[i].b_valid  ),
      .b_ready_i  ( slaves_req[i].b_ready   ),
      // AR channel
      .ar_chan_i  ( slaves_req[i].ar        ),
      .ar_valid_i ( slaves_req[i].ar_valid  ),
      .ar_ready_i ( slaves_resp[i].ar_ready ),
      //  R channel
      .r_chan_i   ( slaves_resp[i].r        ),
      .r_valid_i  ( slaves_resp[i].r_valid  ),
      .r_ready_i  ( slaves_req[i].r_ready   )
    );
  end

// logger for snoop modules
  for (genvar i = 0; i < TbNumMst; i++) begin : gen_snoop_logger
    snoop_chan_logger #(
      .TestTime  ( TestTime      ), // Time after clock, where sampling happens
      .LoggerName( $sformatf("axi_logger_snoop_%0d",i)),
      .ac_chan_t ( snoop_ac_t ), // AW type
      .cr_chan_t ( snoop_cr_t ), // CR type
      .cd_chan_t ( snoop_cd_t )  // CD type
    ) i_snoop_channel_logger (
      .clk_i      ( clk         ),    // Clock
      .rst_ni     ( rst_n       ),    // Asynchronous reset active low, when `1'b0` no sampling
      .end_sim_i  ( &end_of_sim ),
      // AC channel
      .ac_chan_i  ( snoop_req[i].ac        ),
      .ac_valid_i ( snoop_req[i].ac_valid  ),
      .ac_ready_i ( snoop_resp[i].ac_ready ),
      // CR channel
      .cr_chan_i   ( snoop_resp[i].cr_resp ),
      .cr_valid_i  ( snoop_resp[i].cr_valid),
      .cr_ready_i  ( snoop_req[i].cr_ready ),
      // CR channel
      .cd_chan_i   ( snoop_resp[i].cd      ),
      .cd_valid_i  ( snoop_resp[i].cd_valid),
      .cd_ready_i  ( snoop_req[i].cd_ready )
    );
  end

  for (genvar i = 0; i < TbNumMst; i++) begin : gen_connect_master_monitor
    assign master_monitor_dv[i].aw_id       = master[i].aw_id    ;
    assign master_monitor_dv[i].aw_addr     = master[i].aw_addr  ;
    assign master_monitor_dv[i].aw_len      = master[i].aw_len   ;
    assign master_monitor_dv[i].aw_size     = master[i].aw_size  ;
    assign master_monitor_dv[i].aw_burst    = master[i].aw_burst ;
    assign master_monitor_dv[i].aw_lock     = master[i].aw_lock  ;
    assign master_monitor_dv[i].aw_cache    = master[i].aw_cache ;
    assign master_monitor_dv[i].aw_prot     = master[i].aw_prot  ;
    assign master_monitor_dv[i].aw_qos      = master[i].aw_qos   ;
    assign master_monitor_dv[i].aw_region   = master[i].aw_region;
    assign master_monitor_dv[i].aw_atop     = master[i].aw_atop  ;
    assign master_monitor_dv[i].aw_user     = master[i].aw_user  ;
    assign master_monitor_dv[i].aw_valid    = master[i].aw_valid ;
    assign master_monitor_dv[i].aw_ready    = master[i].aw_ready ;
    assign master_monitor_dv[i].aw_snoop    = master[i].aw_snoop;
    assign master_monitor_dv[i].aw_bar      = master[i].aw_bar ;
    assign master_monitor_dv[i].aw_domain   = master[i].aw_domain ;
    assign master_monitor_dv[i].aw_awunique = master[i].aw_awunique ;
    assign master_monitor_dv[i].w_data      = master[i].w_data   ;
    assign master_monitor_dv[i].w_strb      = master[i].w_strb   ;
    assign master_monitor_dv[i].w_last      = master[i].w_last   ;
    assign master_monitor_dv[i].w_user      = master[i].w_user   ;
    assign master_monitor_dv[i].w_valid     = master[i].w_valid  ;
    assign master_monitor_dv[i].w_ready     = master[i].w_ready  ;
    assign master_monitor_dv[i].b_id        = master[i].b_id     ;
    assign master_monitor_dv[i].b_resp      = master[i].b_resp   ;
    assign master_monitor_dv[i].b_user      = master[i].b_user   ;
    assign master_monitor_dv[i].b_valid     = master[i].b_valid  ;
    assign master_monitor_dv[i].b_ready     = master[i].b_ready  ;
    assign master_monitor_dv[i].ar_id       = master[i].ar_id    ;
    assign master_monitor_dv[i].ar_addr     = master[i].ar_addr  ;
    assign master_monitor_dv[i].ar_len      = master[i].ar_len   ;
    assign master_monitor_dv[i].ar_size     = master[i].ar_size  ;
    assign master_monitor_dv[i].ar_burst    = master[i].ar_burst ;
    assign master_monitor_dv[i].ar_lock     = master[i].ar_lock  ;
    assign master_monitor_dv[i].ar_cache    = master[i].ar_cache ;
    assign master_monitor_dv[i].ar_prot     = master[i].ar_prot  ;
    assign master_monitor_dv[i].ar_qos      = master[i].ar_qos   ;
    assign master_monitor_dv[i].ar_region   = master[i].ar_region;
    assign master_monitor_dv[i].ar_user     = master[i].ar_user  ;
    assign master_monitor_dv[i].ar_valid    = master[i].ar_valid ;
    assign master_monitor_dv[i].ar_ready    = master[i].ar_ready ;
    assign master_monitor_dv[i].ar_snoop    = master[i].ar_snoop ;
    assign master_monitor_dv[i].ar_bar      = master[i].ar_bar ;
    assign master_monitor_dv[i].ar_domain   = master[i].ar_domain ;
    assign master_monitor_dv[i].r_id        = master[i].r_id     ;
    assign master_monitor_dv[i].r_data      = master[i].r_data   ;
    assign master_monitor_dv[i].r_resp      = master[i].r_resp   ;
    assign master_monitor_dv[i].r_last      = master[i].r_last   ;
    assign master_monitor_dv[i].r_user      = master[i].r_user   ;
    assign master_monitor_dv[i].r_valid     = master[i].r_valid  ;
    assign master_monitor_dv[i].r_ready     = master[i].r_ready  ;
  end
  for (genvar i = 0; i < TbNumSlv; i++) begin : gen_connect_slave_monitor
    assign slave_monitor_dv[i].aw_id        = slave[i].aw_id    ;
    assign slave_monitor_dv[i].aw_addr      = slave[i].aw_addr  ;
    assign slave_monitor_dv[i].aw_len       = slave[i].aw_len   ;
    assign slave_monitor_dv[i].aw_size      = slave[i].aw_size  ;
    assign slave_monitor_dv[i].aw_burst     = slave[i].aw_burst ;
    assign slave_monitor_dv[i].aw_lock      = slave[i].aw_lock  ;
    assign slave_monitor_dv[i].aw_cache     = slave[i].aw_cache ;
    assign slave_monitor_dv[i].aw_prot      = slave[i].aw_prot  ;
    assign slave_monitor_dv[i].aw_qos       = slave[i].aw_qos   ;
    assign slave_monitor_dv[i].aw_region    = slave[i].aw_region;
    assign slave_monitor_dv[i].aw_atop      = slave[i].aw_atop  ;
    assign slave_monitor_dv[i].aw_user      = slave[i].aw_user  ;
    assign slave_monitor_dv[i].aw_valid     = slave[i].aw_valid ;
    assign slave_monitor_dv[i].aw_ready     = slave[i].aw_ready ;
    assign slave_monitor_dv[i].w_data       = slave[i].w_data   ;
    assign slave_monitor_dv[i].w_strb       = slave[i].w_strb   ;
    assign slave_monitor_dv[i].w_last       = slave[i].w_last   ;
    assign slave_monitor_dv[i].w_user       = slave[i].w_user   ;
    assign slave_monitor_dv[i].w_valid      = slave[i].w_valid  ;
    assign slave_monitor_dv[i].w_ready      = slave[i].w_ready  ;
    assign slave_monitor_dv[i].b_id         = slave[i].b_id     ;
    assign slave_monitor_dv[i].b_resp       = slave[i].b_resp   ;
    assign slave_monitor_dv[i].b_user       = slave[i].b_user   ;
    assign slave_monitor_dv[i].b_valid      = slave[i].b_valid  ;
    assign slave_monitor_dv[i].b_ready      = slave[i].b_ready  ;
    assign slave_monitor_dv[i].ar_id        = slave[i].ar_id    ;
    assign slave_monitor_dv[i].ar_addr      = slave[i].ar_addr  ;
    assign slave_monitor_dv[i].ar_len       = slave[i].ar_len   ;
    assign slave_monitor_dv[i].ar_size      = slave[i].ar_size  ;
    assign slave_monitor_dv[i].ar_burst     = slave[i].ar_burst ;
    assign slave_monitor_dv[i].ar_lock      = slave[i].ar_lock  ;
    assign slave_monitor_dv[i].ar_cache     = slave[i].ar_cache ;
    assign slave_monitor_dv[i].ar_prot      = slave[i].ar_prot  ;
    assign slave_monitor_dv[i].ar_qos       = slave[i].ar_qos   ;
    assign slave_monitor_dv[i].ar_region    = slave[i].ar_region;
    assign slave_monitor_dv[i].ar_user      = slave[i].ar_user  ;
    assign slave_monitor_dv[i].ar_valid     = slave[i].ar_valid ;
    assign slave_monitor_dv[i].ar_ready     = slave[i].ar_ready ;
    assign slave_monitor_dv[i].r_id         = slave[i].r_id     ;
    assign slave_monitor_dv[i].r_data       = slave[i].r_data   ;
    assign slave_monitor_dv[i].r_resp       = slave[i].r_resp   ;
    assign slave_monitor_dv[i].r_last       = slave[i].r_last   ;
    assign slave_monitor_dv[i].r_user       = slave[i].r_user   ;
    assign slave_monitor_dv[i].r_valid      = slave[i].r_valid  ;
    assign slave_monitor_dv[i].r_ready      = slave[i].r_ready  ;
  end
  for (genvar i = 0; i < TbNumMst; i++) begin : gen_connect_snoop_monitor
    assign snoop_monitor_dv[i].ac_valid     = snoop[i].ac_valid;
    assign snoop_monitor_dv[i].ac_ready     = snoop[i].ac_ready;
    assign snoop_monitor_dv[i].ac_snoop     = snoop[i].ac_snoop;
    assign snoop_monitor_dv[i].ac_addr      = snoop[i].ac_addr;
    assign snoop_monitor_dv[i].ac_prot      = snoop[i].ac_prot;
    assign snoop_monitor_dv[i].cr_valid     = snoop[i].cr_valid;
    assign snoop_monitor_dv[i].cr_ready     = snoop[i].cr_ready;
    assign snoop_monitor_dv[i].cr_resp      = snoop[i].cr_resp;
    assign snoop_monitor_dv[i].cd_valid     = snoop[i].cd_valid;
    assign snoop_monitor_dv[i].cd_ready     = snoop[i].cd_ready;
    assign snoop_monitor_dv[i].cd_data      = snoop[i].cd_data;
    assign snoop_monitor_dv[i].cd_last      = snoop[i].cd_last;
  end
endmodule