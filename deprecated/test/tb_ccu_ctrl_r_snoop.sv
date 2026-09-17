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

`include "ace/typedef.svh"
`include "ace/assign.svh"

module tb_ccu_ctrl_r_snoop #(
    parameter int unsigned AddrWidth = 0,
    parameter int unsigned DataWidth = 0,
    parameter int unsigned WordWidth = 0,
    parameter int unsigned CachelineWords = 0,
    parameter int unsigned Ways = 0,
    parameter int unsigned Sets = 0,
    parameter int unsigned TbNumMst = 0,
    parameter string       MemDir = ""
);
    // Random ace_intf no Transactions
    localparam int unsigned NoWrites = 80;   // How many writes per ace_intf
    localparam int unsigned NoReads  = 0;   // How many reads per ace_intf
    // timing parameters
    localparam time CyclTime = 10ns;
    localparam time ApplTime =  2ns;
    localparam time TestTime =  8ns;

    // axi configuration
    localparam int unsigned AxiIdWidthMasters =  4;
    localparam int unsigned AxiIdUsed         =  3;
    localparam int unsigned AxiIdWidthSlaves  =  AxiIdWidthMasters + $clog2(TbNumMst)+$clog2(TbNumMst+1);
    localparam int unsigned AxiAddrWidth      =  AddrWidth;
    localparam int unsigned AxiDataWidth      =  DataWidth;
    localparam int unsigned AxiStrbWidth      =  AxiDataWidth / 8;
    localparam int unsigned AxiUserWidth      =  5;
    localparam int unsigned WriteBackLen      = CachelineWords - 1;
    localparam int unsigned WriteBackSize     = $clog2(DataWidth / 8);

    typedef logic [AxiIdWidthMasters-1:0] id_t;
    typedef logic [AxiIdWidthSlaves-1:0]  id_slv_t;
    typedef logic [AxiAddrWidth-1:0]      addr_t;
    typedef logic [AxiDataWidth-1:0]      data_t;
    typedef logic [AxiStrbWidth-1:0]      strb_t;
    typedef logic [AxiUserWidth-1:0]      user_t;

    `ACE_TYPEDEF_AW_CHAN_T(slave_aw_chan_t, addr_t, id_t, user_t)
    `AXI_TYPEDEF_AW_CHAN_T(master_aw_chan_t, addr_t, id_t, user_t)
    `AXI_TYPEDEF_W_CHAN_T(slave_w_chan_t, data_t, strb_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(slave_b_chan_t, id_t, user_t)
    `ACE_TYPEDEF_AR_CHAN_T(slave_ar_chan_t, addr_t, id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(master_ar_chan_t, addr_t, id_t, user_t)
    `ACE_TYPEDEF_R_CHAN_T(slave_r_chan_t, data_t, id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(master_r_chan_t, data_t, id_t, user_t)
    `ACE_TYPEDEF_REQ_T(slv_req_t, slave_aw_chan_t, slave_w_chan_t, slave_ar_chan_t)
    `AXI_TYPEDEF_REQ_T(mst_req_t, master_aw_chan_t, slave_w_chan_t, master_ar_chan_t)
    `ACE_TYPEDEF_RESP_T(slv_resp_t, slave_b_chan_t, slave_r_chan_t)
    `AXI_TYPEDEF_RESP_T(mst_resp_t, slave_b_chan_t, master_r_chan_t)
    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
    `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
    `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)

    logic clk, rst_n;

    string data_mem_file_template = {MemDir, "/data_mem_%0d.mem"};
    string tag_mem_file_template = {MemDir, "/tag_mem_%0d.mem"};
    string status_file_template = {MemDir, "/state_%0d.mem"};
    string txn_file_template = {MemDir, "/txns_%0d.txt"};

    ACE_BUS_DV #(
        .AXI_ADDR_WIDTH (AxiAddrWidth),
        .AXI_DATA_WIDTH (AxiDataWidth),
        .AXI_ID_WIDTH   (AxiIdWidthMasters),
        .AXI_USER_WIDTH (AxiIdWidthMasters)
    ) ace_intf [TbNumMst] (clk);

    SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH (AxiAddrWidth),
        .SNOOP_DATA_WIDTH (AxiDataWidth)
    ) snoop_intf [TbNumMst](clk);

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

    // Connections:
    // cache_top_agent -> ACE -> DUT -> ACE -> AXI -> axi_sim_mem
    // DUT outputs ACE, but it connects to an AXI interface
    // This is fine because each subfield is connected separately
    // ace.aw = axi.aw would not work because the structs have different widths

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


    cache_test_pkg::cache_top_agent #(
        .AW(AxiAddrWidth),
        .DW(AxiDataWidth),
        .AC_AW(AxiAddrWidth),
        .CD_DW(AxiDataWidth),
        .IW(AxiIdWidthMasters),
        .UW(AxiUserWidth),
        .TA(ApplTime),
        .TT(TestTime),
        .CACHELINE_WORDS(CachelineWords),
        .WORD_WIDTH(WordWidth),
        .WAYS(Ways),
        .SETS(Sets),
        .ace_bus_t(ace_bus_v_t),
        .snoop_bus_t(snoop_bus_v_t),
        .clk_if_t(clk_if_v_t)
    ) ace_master [TbNumMst];

    slv_req_t  [TbNumMst] masters_req;
    slv_resp_t [TbNumMst] masters_resp;

    for (genvar i = 0; i < TbNumMst; i++) begin : gen_conn_dv_masters
        `ACE_ASSIGN_TO_REQ(masters_req[i], ace_intf[i])
        `ACE_ASSIGN_FROM_RESP(ace_intf[i], masters_resp[i])
    end

    AXI_BUS_DV #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
        .AXI_USER_WIDTH ( AxiUserWidth     )
    ) axi_intf (clk);

    slv_req_t slaves_req;
    slv_resp_t slaves_resp;
    
    mst_req_t main_mem_req;
    mst_resp_t main_mem_resp;

    `AXI_ASSIGN_FROM_REQ(axi_intf, slaves_req)
    `AXI_ASSIGN_TO_RESP(slaves_resp, axi_intf)

    `AXI_ASSIGN_TO_REQ(main_mem_req, axi_intf)
    `AXI_ASSIGN_FROM_RESP(axi_intf, main_mem_resp)

    snoop_req_t  [TbNumMst] snoop_req;
    snoop_resp_t [TbNumMst] snoop_resp;

    for (genvar i = 0; i < TbNumMst; i++) begin : gen_conn_dv_snoop
        `SNOOP_ASSIGN_FROM_REQ(snoop_intf[i], snoop_req[i])
        `SNOOP_ASSIGN_TO_RESP(snoop_resp[i], snoop_intf[i])
    end

    for (genvar i = 0; i < TbNumMst; i++) begin : gen_rand_master
        initial begin
            string data_mem_file, tag_mem_file, status_file, txn_file;
            $sformat(data_mem_file, data_mem_file_template, i);
            $sformat(tag_mem_file, tag_mem_file_template, i);
            $sformat(status_file, status_file_template, i);
            $sformat(txn_file, txn_file_template, i);
            ace_master[i] = new(
                ace_intf[i],
                snoop_intf[i],
                clk_if,
                data_mem_file,
                tag_mem_file,
                status_file,
                txn_file
            );
            ace_master[i].reset();
            @(posedge rst_n);
            ace_master[i].run();
        end
    end

    axi_sim_mem #(
        // AXI interface parameters
        .AddrWidth ( AxiAddrWidth     ),
        .DataWidth ( AxiDataWidth     ),
        .IdWidth ( AxiIdWidthSlaves ),
        .UserWidth ( AxiUserWidth     ),
        .NumPorts (1),
        .axi_req_t(mst_req_t),
        .axi_rsp_t(mst_resp_t),
        .ApplDelay ( ApplTime ),
        .AcqDelay (TestTime )
    ) axi_mem (
        .clk_i(clk),
        .rst_ni(rst_n),
        .axi_req_i(main_mem_req),
        .axi_rsp_o(main_mem_resp),
        .mon_w_valid_o(),
        .mon_w_addr_o(),
        .mon_w_data_o(),
        .mon_w_id_o(),
        .mon_w_user_o(),
        .mon_w_beat_count_o(),
        .mon_w_last_o(),
        .mon_r_valid_o(),
        .mon_r_addr_o(),
        .mon_r_data_o(),
        .mon_r_id_o(),
        .mon_r_user_o(),
        .mon_r_beat_count_o(),
        .mon_r_last_o()
    );

    initial begin
        $readmemh({MemDir, "/main_mem.mem"}, axi_mem.mem);
    end

    ace_pkg::snoop_info_t snoopy_trs;

    // DUT

    ace_ar_transaction_decoder #(
        .ar_chan_t(slave_ar_chan_t)
    ) aw_trs_decoder (
        .ar_i(slaves_req.ar),
        .snoop_info_o(snoopy_trs),
        .illegal_trs_o(illegal)
    );

    ccu_ctrl_r_snoop #(
        .slv_req_t(slv_req_t),
        .slv_resp_t(slv_resp_t),
        .mst_req_t(slv_req_t),
        .mst_resp_t(slv_resp_t),
        .slv_ar_chan_t(slave_ar_chan_t),
        .mst_snoop_req_t(snoop_req_t),
        .mst_snoop_resp_t(snoop_resp_t),
        .AXLEN(WriteBackLen),
        .AXSIZE(WriteBackSize)
    ) DUT (
        .clk_i(clk),
        .rst_ni(rst_n),
        .snoop_info_i(snoopy_trs),
        .slv_req_i(masters_req[0]),
        .slv_resp_o(masters_resp[0]),
        .mst_req_o(slaves_req),
        .mst_resp_i(slaves_resp),
        .snoop_resp_i(snoop_resp),
        .snoop_req_o(snoop_req),
        .ardomain_o()
    );

endmodule
