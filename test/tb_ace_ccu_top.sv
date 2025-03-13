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

// Directed random verification testbench for `ace_ccu_top`.

`include "ace/typedef.svh"
`include "ace/assign.svh"
`include "ace/domain.svh"

module tb_ace_ccu_top #(
    /// Address space
    parameter int unsigned AddrWidth      = 0,
    /// Memory bus data width
    parameter int unsigned DataWidth      = 0,
    /// Cache word width
    parameter int unsigned WordWidth      = 0,
    /// Words per cache line
    parameter int unsigned CachelineWords = 0,
    /// Cache ways
    parameter int unsigned Ways           = 0,
    /// Cache sets
    parameter int unsigned Sets           = 0,
    /// Number of cached masters
    parameter int unsigned TbNumMst       = 0,
    /// Number of master groups (a group share the snooping FSM)
    parameter int unsigned NoMstGroups    = 1,
    /// Directory for files
    parameter string       MemDir         = ""
);

    // timing parameters
    localparam time CyclTime = 10ns;
    localparam time ApplTime =  2ns;
    localparam time TestTime =  8ns;

    localparam CachelineBits = CachelineWords * WordWidth;

    // How many cached masters per group
    localparam MstPerGroup = TbNumMst / NoMstGroups;
    localparam NoGroups = NoMstGroups;

    // axi configuration
    localparam int unsigned AxiIdWidthMasters =  4;
    localparam int unsigned AxiIdUsed         =  3;
    localparam int unsigned AxiIdWidthSlave   =  AxiIdWidthMasters
                                                 + $clog2(MstPerGroup)
                                                 + $clog2(3*NoGroups)
                                                 + 1; // R/W FSM encoding
    localparam int unsigned AxiAddrWidth      =  AddrWidth;
    localparam int unsigned AxiDataWidth      =  DataWidth;
    localparam int unsigned AxiStrbWidth      =  AxiDataWidth / 8;
    localparam int unsigned AxiUserWidth      =  5;
    localparam int unsigned WriteBackLen      = CachelineWords - 1;
    localparam int unsigned WriteBackSize     = $clog2(DataWidth / 8);

    typedef logic [AxiIdWidthMasters-1:0] id_t;
    typedef logic [AxiIdWidthSlave-1:0]   id_slv_t;
    typedef logic [AxiAddrWidth-1:0]      addr_t;
    typedef logic [AxiDataWidth-1:0]      data_t;
    typedef logic [AxiStrbWidth-1:0]      strb_t;
    typedef logic [AxiUserWidth-1:0]      user_t;

    `ACE_TYPEDEF_AW_CHAN_T(ace_aw_chan_t, addr_t, id_t,   user_t)
    `AXI_TYPEDEF_W_CHAN_T (ace_w_chan_t,  data_t, strb_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T (ace_b_chan_t,  id_t,   user_t        )
    `ACE_TYPEDEF_AR_CHAN_T(ace_ar_chan_t, addr_t, id_t, user_t  )
    `ACE_TYPEDEF_R_CHAN_T (ace_r_chan_t,  data_t, id_t, user_t  )
    `ACE_TYPEDEF_REQ_T    (ace_req_t, ace_aw_chan_t, ace_w_chan_t, ace_ar_chan_t)
    `ACE_TYPEDEF_RESP_T   (ace_resp_t, ace_b_chan_t, ace_r_chan_t)

    `AXI_TYPEDEF_AW_CHAN_T(axi_aw_chan_t, addr_t,   id_slv_t, user_t)
    `AXI_TYPEDEF_W_CHAN_T (axi_w_chan_t,  data_t,   strb_t,   user_t)
    `AXI_TYPEDEF_B_CHAN_T (axi_b_chan_t,  id_slv_t, user_t          )
    `AXI_TYPEDEF_AR_CHAN_T(axi_ar_chan_t, addr_t,   id_slv_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T (axi_r_chan_t,  data_t,   id_slv_t, user_t)
    `AXI_TYPEDEF_REQ_T    (axi_req_t, axi_aw_chan_t, axi_w_chan_t, axi_ar_chan_t)
    `AXI_TYPEDEF_RESP_T   (axi_resp_t, axi_b_chan_t, axi_r_chan_t)

    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
    `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
    `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)

    logic clk, rst_n;
    logic [TbNumMst-1:0] end_of_sim = '0;

    // Defines domain_mask_t and domain_set_t
    `DOMAIN_TYPEDEF_ALL(TbNumMst)

    domain_set_t  [TbNumMst-1:0] domain_set;
    initial begin
        for (int i = 0; i < TbNumMst; i++) begin
            domain_set[i].initiator = 1 << i;
            domain_set[i].inner = ~(1 << i);
            domain_set[i].outer = ~(1 << i);
        end
    end


    // Cache data memory initial state
    string data_mem_file_template = {MemDir, "/data_mem_%0d.mem"};
    // Cache tag memory initial state
    string tag_mem_file_template  = {MemDir, "/tag_mem_%0d.mem"};
    // Cache line status initial state
    string status_file_template   = {MemDir, "/state_%0d.mem"};
    // Cache transactions
    string txn_file_template      = {MemDir, "/txns_%0d.txt"};
    // Initial main memory state
    string init_main_mem          = {MemDir, "/main_mem.mem"};
    // Logged cache state changes
    string diff_file_template     = {MemDir, "/cache_diff_%0d.txt"};
    string diff_main_mem          = {MemDir, "/main_mem_diff.txt"};

    ACE_BUS_DV #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
        .AXI_DATA_WIDTH ( AxiDataWidth      ),
        .AXI_ID_WIDTH   ( AxiIdWidthMasters ),
        .AXI_USER_WIDTH ( AxiIdWidthMasters )
    ) ace_dv_intf [TbNumMst-1:0] (clk);

    ACE_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
        .AXI_DATA_WIDTH ( AxiDataWidth      ),
        .AXI_ID_WIDTH   ( AxiIdWidthMasters ),
        .AXI_USER_WIDTH ( AxiIdWidthMasters )
    ) ace_intf [TbNumMst-1:0]();

    SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth )
    ) snoop_dv_intf [TbNumMst-1:0](clk);

    SNOOP_BUS #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth )
    ) snoop_intf [TbNumMst-1:0]();

    AXI_BUS_DV #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlave ),
        .AXI_USER_WIDTH ( AxiUserWidth     )
    ) axi_dv_intf (clk);

    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlave  ),
        .AXI_USER_WIDTH ( AxiUserWidth     )
    ) axi_intf();

    MONITOR_BUS_DV #(
        .ADDR_WIDTH (AxiAddrWidth),
        .DATA_WIDTH ( AxiDataWidth),
        .ID_WIDTH ( AxiIdWidthSlave),
        .USER_WIDTH (AxiUserWidth)
    ) sim_mem_mon_intf (clk);

    // Interface with clock for generating delays
    CLK_IF clk_if (clk);

    typedef virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH (AxiAddrWidth),
        .AXI_DATA_WIDTH (AxiDataWidth),
        .AXI_ID_WIDTH   (AxiIdWidthMasters),
        .AXI_USER_WIDTH (AxiIdWidthMasters)
    ) ace_bus_v_t;

    typedef virtual SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH (AxiAddrWidth),
        .SNOOP_DATA_WIDTH (AxiDataWidth)
    ) snoop_bus_v_t;

    typedef virtual CLK_IF clk_if_v_t;

    typedef virtual MONITOR_BUS_DV #(
        .ADDR_WIDTH (AxiAddrWidth),
        .DATA_WIDTH ( AxiDataWidth),
        .ID_WIDTH ( AxiIdWidthSlave),
        .USER_WIDTH (AxiUserWidth)
    ) mon_bus_t;


    // Clock generator
    clk_rst_gen #(
        .ClkPeriod    ( CyclTime ),
        .RstClkCycles ( 5        )
    ) i_clk_gen (
        .clk_o  (clk),
        .rst_no (rst_n)
    );

    cache_test_pkg::mem_logger #(
        .AW(AxiAddrWidth),
        .DW(AxiDataWidth),
        .IW(AxiIdWidthSlave),
        .UW(AxiUserWidth),
        .TA(ApplTime),
        .TT(TestTime),
        .mon_bus_t(mon_bus_t)
    ) axi_mem_logger;

    cache_test_pkg::cache_top_agent #(
        .AW              (AxiAddrWidth),
        .DW              (AxiDataWidth),
        .AC_AW           (AxiAddrWidth),
        .CD_DW           (AxiDataWidth),
        .IW              (AxiIdWidthMasters),
        .UW              (AxiUserWidth),
        .TA              (ApplTime),
        .TT              (TestTime),
        .CACHELINE_WORDS (CachelineWords),
        .WORD_WIDTH      (WordWidth),
        .WAYS            (Ways),
        .SETS            (Sets),
        .ace_bus_t       (ace_bus_v_t),
        .snoop_bus_t     (snoop_bus_v_t),
        .clk_if_t        (clk_if_v_t)
    ) ace_master [TbNumMst-1:0];

    for (genvar i = 0; i < TbNumMst; i++) begin : gen_conn_cache_agents
        `ACE_ASSIGN(ace_intf[i], ace_dv_intf[i]);
    end

    for (genvar i = 0; i < TbNumMst; i++) begin : gen_conn_dv_snoop
        `SNOOP_ASSIGN(snoop_dv_intf[i], snoop_intf[i])
    end

    for (genvar i = 0; i < TbNumMst; i++) begin : init_cache_agents
        initial begin
            string data_mem_file, tag_mem_file, status_file, txn_file;
            string diff_file;
            $sformat(data_mem_file, data_mem_file_template, i);
            $sformat(tag_mem_file, tag_mem_file_template, i);
            $sformat(status_file, status_file_template, i);
            $sformat(txn_file, txn_file_template, i);
            $sformat(diff_file, diff_file_template, i);
            ace_master[i] = new(
                ace_dv_intf[i],
                snoop_dv_intf[i],
                clk_if,
                data_mem_file,
                tag_mem_file,
                status_file,
                txn_file,
                diff_file,
                i
            );
            ace_master[i].reset();
            @(posedge rst_n);
            ace_master[i].run();
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            end_of_sim[i] = '1;
        end
    end

    always @(*) begin
        if (&end_of_sim) $finish();
    end

    initial begin
        axi_mem_logger = new(
            sim_mem_mon_intf,
            diff_main_mem
        );
        @(posedge rst_n);
        axi_mem_logger.run();
    end


    // AXI Simulation Memory
    axi_sim_mem_intf #(
        // AXI interface parameters
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlave ),
        .AXI_USER_WIDTH ( AxiUserWidth     ),
        .APPL_DELAY     ( ApplTime         ),
        .ACQ_DELAY      ( TestTime         )
    ) axi_mem (
        .clk_i(clk),
        .rst_ni(rst_n),
        .axi_slv(axi_intf),
        .mon_w_valid_o(sim_mem_mon_intf.w_valid),
        .mon_w_addr_o(sim_mem_mon_intf.w_addr),
        .mon_w_data_o(sim_mem_mon_intf.w_data),
        .mon_w_id_o(sim_mem_mon_intf.w_id),
        .mon_w_user_o(sim_mem_mon_intf.w_user),
        .mon_w_beat_count_o(sim_mem_mon_intf.w_beat_count),
        .mon_w_last_o(sim_mem_mon_intf.w_last),
        .mon_r_valid_o(sim_mem_mon_intf.r_valid),
        .mon_r_addr_o(sim_mem_mon_intf.r_addr),
        .mon_r_data_o(sim_mem_mon_intf.r_data),
        .mon_r_id_o(sim_mem_mon_intf.r_id),
        .mon_r_user_o(sim_mem_mon_intf.r_user),
        .mon_r_beat_count_o(sim_mem_mon_intf.r_beat_count),
        .mon_r_last_o(sim_mem_mon_intf.r_last)
    );

    initial begin
        $readmemh(init_main_mem, axi_mem.i_sim_mem.mem);
    end

    localparam ccu_pkg::ccu_cfg_t CcuCfg = '{
        DcacheLineWidth:  CachelineBits,
        AxiAddrWidth   :  AxiAddrWidth,
        AxiDataWidth   :  AxiDataWidth,
        AxiUserWidth   :  AxiUserWidth,
        AxiSlvIdWidth  :  AxiIdWidthMasters,
        NoSlvPorts     :  TbNumMst,
        NoSlvPerGroup  :  MstPerGroup,
        AmoHotfix      :  1
    };

    ace_ccu_top_intf #(
        .CCU_CFG      (CcuCfg)
    ) ccu (
        .clk_i        (clk),
        .rst_ni       (rst_n),
        .domain_set_i (domain_set),
        .slv_ports    (ace_intf),
        .snoop_ports  (snoop_intf),
        .mst_port     (axi_intf)
    );
endmodule
