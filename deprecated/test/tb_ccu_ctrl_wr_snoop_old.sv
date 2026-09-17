`include "ace/typedef.svh"
`include "ace/assign.svh"

module tb_ccu_ctrl_wr_snoop #(
);


    localparam int unsigned NoWrites = 8000;   // How many writes per master
    localparam int unsigned NoReads  = 0;   // How many reads per master

    // axi configuration
    localparam int unsigned AxiIdWidthMasters =  1;
    localparam int unsigned AxiIdUsed         =  1; // Has to be <= AxiIdWidthMasters
    localparam int unsigned AxiIdWidthSlaves  =  1;
    localparam int unsigned AxiAddrWidth      =  32;    // Axi Address Width
    localparam int unsigned AxiDataWidth      =  64;    // Axi Data Width
    localparam int unsigned AxiStrbWidth      =  AxiDataWidth / 8;
    localparam int unsigned AxiUserWidth      =  5;

    // Address space for memory which is initialized
    localparam int mem_addr_space = 8;

    localparam time CyclTime = 10ns;
    localparam time ApplTime =  2ns;
    localparam time TestTime =  8ns;

    // in the bench can change this variables which are set here freely
    localparam ccu_pkg::ccu_cfg_t ccu_cfg = '{
        NoSlvPorts:         1,
        MaxMstTrans:        10,
        MaxSlvTrans:        6,
        FallThrough:        1'b1,
        LatencyMode:        ccu_pkg::NO_LATENCY,
        AxiIdWidthSlvPorts: AxiIdWidthMasters,
        AxiIdUsedSlvPorts:  AxiIdUsed,
        UniqueIds:          1,
        AxiAddrWidth:       AxiAddrWidth,
        AxiDataWidth:       AxiDataWidth
    };

    logic clk, rst_n;
    logic end_of_sim;

    typedef logic [AxiAddrWidth-1:0] addr_t;
    typedef logic [AxiIdWidthMasters-1:0] id_t;
    typedef logic [AxiUserWidth-1:0] user_t;
    typedef logic [AxiDataWidth-1:0] data_t;
    typedef logic [AxiDataWidth/8 -1:0] strb_t;

    `ACE_TYPEDEF_AW_CHAN_T(slave_aw_chan_t, addr_t, id_t, user_t)
    `AXI_TYPEDEF_W_CHAN_T(slave_w_chan_t, data_t, strb_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(slave_b_chan_t, id_t, user_t)
    `ACE_TYPEDEF_AR_CHAN_T(slave_ar_chan_t, addr_t, id_t, user_t)
    `ACE_TYPEDEF_R_CHAN_T(slave_r_chan_t, data_t, id_t, user_t)
    `ACE_TYPEDEF_REQ_T(mst_req_t, slave_aw_chan_t, slave_w_chan_t, slave_ar_chan_t)
    `ACE_TYPEDEF_REQ_T(slv_req_t, slave_aw_chan_t, slave_w_chan_t, slave_ar_chan_t)
    `ACE_TYPEDEF_RESP_T(mst_resp_t, slave_b_chan_t, slave_r_chan_t)
    `ACE_TYPEDEF_RESP_T(slv_resp_t, slave_b_chan_t, slave_r_chan_t)
    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
    `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
    `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)

    //-----------------------------------
    // Clock generator
    //-----------------------------------
    clk_rst_gen #(
        .ClkPeriod    ( CyclTime ),
        .RstClkCycles ( 5        )
    ) i_clk_gen (
        .clk_o  (clk),
        .rst_no (rst_n)
    );

    ACE_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
        .AXI_DATA_WIDTH ( AxiDataWidth      ),
        .AXI_ID_WIDTH   ( AxiIdWidthMasters ),
        .AXI_USER_WIDTH ( AxiUserWidth      )
    ) master ();
    ACE_BUS_DV #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
        .AXI_DATA_WIDTH ( AxiDataWidth      ),
        .AXI_ID_WIDTH   ( AxiIdWidthMasters ),
        .AXI_USER_WIDTH ( AxiUserWidth      )
    ) master_dv (clk);

    mst_req_t  masters_req;
    mst_resp_t masters_resp;

    `ACE_ASSIGN (master, master_dv)
    `ACE_ASSIGN_TO_REQ(masters_req, master)
    `ACE_ASSIGN_FROM_RESP(master, masters_resp)

    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
        .AXI_USER_WIDTH ( AxiUserWidth     )
    ) slave ();
    AXI_BUS_DV #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
        .AXI_USER_WIDTH ( AxiUserWidth     )
    ) slave_dv(clk);

    slv_req_t   slaves_req;
    slv_resp_t  slaves_resp;

    `AXI_ASSIGN(slave_dv, slave)
    `AXI_ASSIGN_FROM_REQ(slave, slaves_req)
    `AXI_ASSIGN_TO_RESP(slaves_resp, slave)

    SNOOP_BUS #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth      )
    ) snoop ();
    SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth      )
    ) snoop_dv (clk);

    snoop_req_t  snoop_req;
    snoop_resp_t snoop_resp;

    `SNOOP_ASSIGN(snoop_dv, snoop)
    `SNOOP_ASSIGN_FROM_REQ(snoop, snoop_req)
    `SNOOP_ASSIGN_TO_RESP(snoop_resp, snoop)


    ace_sim_master::ace_rand_master #(
        .AW (AxiAddrWidth),
        .DW (AxiDataWidth),
        .IW (AxiIdWidthMasters),
        .UW (AxiUserWidth),
        .MAX_READ_TXNS (20),
        .MAX_WRITE_TXNS (20),
        .UNIQUE_IDS (1),
        .TA ( ApplTime ),
        .TT (TestTime ),
        .CACHELINE_WIDTH (32),
        .MEM_ADDR_SPACE (mem_addr_space)
    ) ace_master;

    axi_test::axi_rand_slave #(
        // AXI interface parameters
        .AW ( AxiAddrWidth     ),
        .DW ( AxiDataWidth     ),
        .IW ( AxiIdWidthSlaves ),
        .UW ( AxiUserWidth     ),
        .TA ( ApplTime ),
        .TT (TestTime )
    ) axi_rand_slave;

    snoop_chan_logger #(
        .TestTime (TestTime),
        .LoggerName ( "snoop_logger" ),
        .ac_chan_t (snoop_ac_t),
        .cr_chan_t (snoop_cr_t),
        .cd_chan_t (snoop_cd_t)
    ) snoop_chan_logger (
        .clk_i (clk),
        .rst_ni (rst_n),
        .end_sim_i (end_of_sim),
        .ac_chan_i (snoop_req.ac),
        .ac_valid_i (snoop_req.ac_valid),
        .ac_ready_i (snoop_resp.ac_ready),
        .cr_chan_i (snoop_resp.cr_resp),
        .cr_valid_i (snoop_resp.cr_valid),
        .cr_ready_i (snoop_req.cr_ready),
        .cd_chan_i (snoop_resp.cd),
        .cd_valid_i (snoop_resp.cd_valid),
        .cd_ready_i ( snoop_req.cd_ready)
    );

    initial begin
        ace_master = new(master_dv, snoop_dv);
        end_of_sim <= 1'b0;
        ace_master.add_memory_region(
            32'h0000_0000, 32'h0000_3000,
            axi_pkg::DEVICE_NONBUFFERABLE);
        ace_master.init_cache_memory();
        ace_master.reset();
        @(posedge rst_n);
        ace_master.run(NoReads, NoWrites);
        end_of_sim <= 1'b1;
        $finish;
    end

    initial begin
        axi_rand_slave = new(slave_dv);
        axi_rand_slave.reset();
        @(posedge rst_n);
        axi_rand_slave.run();
    end

    ace_pkg::acsnoop_t snoopy_trs;
    logic snoop_trs, illegal;

    ace_aw_transaction_decoder #(
        .aw_chan_t(slave_aw_chan_t)
    ) aw_trs_decoder (
        .aw_i(slaves_req.aw),
        .acsnoop_o(snoopy_trs),
        .snoop_trs_o(snoop_trs),
        .illegal_trs_o(illegal)
    );

    ccu_ctrl_wr_snoop #(
        .slv_req_t(slv_req_t),
        .slv_resp_t(slv_resp_t),
        .mst_req_t(mst_req_t),
        .mst_resp_t(mst_resp_t),
        .slv_aw_chan_t(slave_aw_chan_t),
        .mst_snoop_req_t(snoop_req_t),
        .mst_snoop_resp_t(snoop_resp_t)
    ) DUT (
        .clk_i(clk),
        .rst_ni(rst_n),
        .snoop_trs_i(snoopy_trs),
        .slv_req_i(masters_req),
        .slv_resp_o(masters_resp),
        .mst_req_o(slaves_req),
        .mst_resp_i(slaves_resp),
        .snoop_resp_i(snoop_resp),
        .snoop_req_o(snoop_req)
    );

endmodule