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
//


/// A set of testbench utilities for ACE interfaces.
package ace_test;

  import axi_pkg::*;
  import ace_pkg::*;

  /// The data transferred on a beat on the AW/AR channels.
  class ace_ax_beat #(
    parameter AW = 32,
    parameter IW = 8 ,
    parameter UW = 1
  );
    rand logic [IW-1:0] ax_id       = '0;
    rand logic [AW-1:0] ax_addr     = '0;
    logic [7:0]         ax_len      = '0;
    logic [2:0]         ax_size     = '0;
    logic [1:0]         ax_burst    = '0;
    logic               ax_lock     = '0;
    logic [3:0]         ax_cache    = '0;
    logic [2:0]         ax_prot     = '0;
    rand logic [3:0]    ax_qos      = '0;
    logic [3:0]         ax_region   = '0;
    logic [5:0]         ax_atop     = '0; // Only defined on the AW channel.
    rand logic [UW-1:0] ax_user     = '0;
    rand logic [3:0]    ax_snoop  = '0; // AW channel requires 3 bits, AR channel requires 4 bits
    rand logic [1:0]    ax_bar      = '0;
    rand logic [1:0]    ax_domain   = '0;
    rand logic          ax_awunique = '0; // Only for AW
  endclass

 /// The data transferred on a beat on the R channel.
  class ace_r_beat #(
    parameter DW = 32,
    parameter IW = 8 ,
    parameter UW = 1
  );
    rand logic [IW-1:0] r_id   = '0;
    rand logic [DW-1:0] r_data = '0;
    ace_pkg::rresp_t    r_resp = '0;
    logic               r_last = '0;
    rand logic [UW-1:0] r_user = '0;
  endclass

   /// The data transferred on a beat on the W channel.
  class axi_w_beat #(
    parameter DW = 32,
    parameter UW = 1
  );
   rand logic [DW-1:0]  w_data = '0;
   rand logic [DW/8-1:0] w_strb = '0;
   logic                 w_last = '0;
   rand logic [UW-1:0]   w_user = '0;
endclass

   /// The data transferred on a beat on the B channel.
class axi_b_beat #(
                   parameter IW = 8,
                   parameter UW = 1
                   );
   rand logic [IW-1:0]   b_id   = '0;
   axi_pkg::resp_t     b_resp = '0;
   rand logic [UW-1:0]   b_user = '0;
endclass


  /// A driver for AXI4 interface.
  class ace_driver #(
    parameter int  AW = 32  ,
    parameter int  DW = 32  ,
    parameter int  IW = 8   ,
    parameter int  UW = 1   ,
    parameter time TA = 0ns , // stimuli application time
    parameter time TT = 0ns   // stimuli test time
  );
    virtual ACE_BUS_DV #(
      .AXI_ADDR_WIDTH(AW),
      .AXI_DATA_WIDTH(DW),
      .AXI_ID_WIDTH(IW),
      .AXI_USER_WIDTH(UW)
    ) ace;

//    typedef axi_test::axi_driver #(
//       .AW(AW), .DW(DW), .IW(IW), .UW(UW), .TA(TA), .TT(TT)
//                                   ) axi_driver_t;
    typedef ace_ax_beat #(.AW(AW), .IW(IW), .UW(UW)) ax_ace_beat_t;
    typedef axi_w_beat  #(.DW(DW), .UW(UW))          w_beat_t;
    typedef axi_b_beat  #(.IW(IW), .UW(UW))          b_beat_t;
//    typedef axi_driver_t::w_beat_t            w_beat_t;
//    typedef axi_driver_t::b_beat_t            b_beat_t;
    typedef ace_r_beat  #(.DW(DW), .IW(IW), .UW(UW)) r_ace_beat_t;

    function new(
      virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH(AW),
        .AXI_DATA_WIDTH(DW),
        .AXI_ID_WIDTH(IW),
        .AXI_USER_WIDTH(UW)
      ) ace
    );
      this.ace = ace;
    endfunction

    function void reset_master();
      ace.aw_id       <= '0;
      ace.aw_addr     <= '0;
      ace.aw_len      <= '0;
      ace.aw_size     <= '0;
      ace.aw_burst    <= '0;
      ace.aw_lock     <= '0;
      ace.aw_cache    <= '0;
      ace.aw_prot     <= '0;
      ace.aw_qos      <= '0;
      ace.aw_region   <= '0;
      ace.aw_atop     <= '0;
      ace.aw_user     <= '0;
      ace.aw_valid    <= '0;
      ace.aw_snoop  <= '0;
      ace.aw_bar      <= '0;
      ace.aw_domain   <= '0;
      ace.aw_awunique <= '0;
      ace.w_data      <= '0;
      ace.w_strb      <= '0;
      ace.w_last      <= '0;
      ace.w_user      <= '0;
      ace.w_valid     <= '0;
      ace.b_ready     <= '0;
      ace.ar_id       <= '0;
      ace.ar_addr     <= '0;
      ace.ar_len      <= '0;
      ace.ar_size     <= '0;
      ace.ar_burst    <= '0;
      ace.ar_lock     <= '0;
      ace.ar_cache    <= '0;
      ace.ar_prot     <= '0;
      ace.ar_qos      <= '0;
      ace.ar_region   <= '0;
      ace.ar_user     <= '0;
      ace.ar_snoop  <= '0;
      ace.ar_bar      <= '0;
      ace.ar_domain   <= '0;
      ace.ar_valid    <= '0;
      ace.r_ready     <= '0;
      ace.wack <= '0;
      ace.rack <= '0;
    endfunction

    function void reset_slave();
      ace.aw_ready  <= '0;
      ace.w_ready   <= '0;
      ace.b_id      <= '0;
      ace.b_resp    <= '0;
      ace.b_user    <= '0;
      ace.b_valid   <= '0;
      ace.ar_ready  <= '0;
      ace.r_id      <= '0;
      ace.r_data    <= '0;
      ace.r_resp    <= '0;
      ace.r_last    <= '0;
      ace.r_user    <= '0;
      ace.r_valid   <= '0;
    endfunction

    task cycle_start;
      #TT;
    endtask

    task cycle_end;
      @(posedge ace.clk_i);
    endtask

    /// Issue a beat on the AW channel.
    task send_aw (
      input ax_ace_beat_t beat
    );
      ace.aw_id       <= #TA beat.ax_id;
      ace.aw_addr     <= #TA beat.ax_addr;
      ace.aw_len      <= #TA beat.ax_len;
      ace.aw_size     <= #TA beat.ax_size;
      ace.aw_burst    <= #TA beat.ax_burst;
      ace.aw_lock     <= #TA beat.ax_lock;
      ace.aw_cache    <= #TA beat.ax_cache;
      ace.aw_prot     <= #TA beat.ax_prot;
      ace.aw_qos      <= #TA beat.ax_qos;
      ace.aw_region   <= #TA beat.ax_region;
      ace.aw_atop     <= #TA beat.ax_atop;
      ace.aw_user     <= #TA beat.ax_user;
      ace.aw_valid    <= #TA 1;
      ace.aw_snoop  <= #TA beat.ax_snoop;
      ace.aw_bar      <= #TA beat.ax_bar;
      ace.aw_domain   <= #TA beat.ax_domain;
      ace.aw_awunique <= #TA beat.ax_awunique;
      cycle_start();
      while (ace.aw_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      ace.aw_id       <= #TA '0;
      ace.aw_addr     <= #TA '0;
      ace.aw_len      <= #TA '0;
      ace.aw_size     <= #TA '0;
      ace.aw_burst    <= #TA '0;
      ace.aw_lock     <= #TA '0;
      ace.aw_cache    <= #TA '0;
      ace.aw_prot     <= #TA '0;
      ace.aw_qos      <= #TA '0;
      ace.aw_region   <= #TA '0;
      ace.aw_atop     <= #TA '0;
      ace.aw_user     <= #TA '0;
      ace.aw_valid    <= #TA  0;
      ace.aw_snoop  <= #TA '0;
      ace.aw_bar      <= #TA '0;
      ace.aw_domain   <= #TA '0;
      ace.aw_awunique <= #TA  0;
    endtask

    /// Issue a beat on the W channel.
    task send_w (
      input w_beat_t beat
    );
      ace.w_data  <= #TA beat.w_data;
      ace.w_strb  <= #TA beat.w_strb;
      ace.w_last  <= #TA beat.w_last;
      ace.w_user  <= #TA beat.w_user;
      ace.w_valid <= #TA 1;
      cycle_start();
      while (ace.w_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      ace.w_data  <= #TA '0;
      ace.w_strb  <= #TA '0;
      ace.w_last  <= #TA '0;
      ace.w_user  <= #TA '0;
      ace.w_valid <= #TA 0;
    endtask

    /// Issue a beat on the B channel.
    task send_b (
      input b_beat_t beat
    );
      ace.b_id    <= #TA beat.b_id;
      ace.b_resp  <= #TA beat.b_resp;
      ace.b_user  <= #TA beat.b_user;
      ace.b_valid <= #TA 1;
      cycle_start();
      while (ace.b_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      ace.b_id    <= #TA '0;
      ace.b_resp  <= #TA '0;
      ace.b_user  <= #TA '0;
      ace.b_valid <= #TA 0;
      cycle_start();
      while (ace.wack != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
    endtask

    /// Issue a beat on the AR channel.
    task send_ar (
      input ax_ace_beat_t beat
    );
      ace.ar_id       <= #TA beat.ax_id;
      ace.ar_addr     <= #TA beat.ax_addr;
      ace.ar_len      <= #TA beat.ax_len;
      ace.ar_size     <= #TA beat.ax_size;
      ace.ar_burst    <= #TA beat.ax_burst;
      ace.ar_lock     <= #TA beat.ax_lock;
      ace.ar_cache    <= #TA beat.ax_cache;
      ace.ar_prot     <= #TA beat.ax_prot;
      ace.ar_qos      <= #TA beat.ax_qos;
      ace.ar_region   <= #TA beat.ax_region;
      ace.ar_user     <= #TA beat.ax_user;
      ace.ar_valid    <= #TA 1;
      ace.ar_snoop  <= #TA beat.ax_snoop;
      ace.ar_bar      <= #TA beat.ax_bar;
      ace.ar_domain   <= #TA beat.ax_domain;
      cycle_start();
      while (ace.ar_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      ace.ar_id       <= #TA '0;
      ace.ar_addr     <= #TA '0;
      ace.ar_len      <= #TA '0;
      ace.ar_size     <= #TA '0;
      ace.ar_burst    <= #TA '0;
      ace.ar_lock     <= #TA '0;
      ace.ar_cache    <= #TA '0;
      ace.ar_prot     <= #TA '0;
      ace.ar_qos      <= #TA '0;
      ace.ar_region   <= #TA '0;
      ace.ar_user     <= #TA '0;
      ace.ar_valid    <= #TA 0;
      ace.ar_snoop  <= #TA '0;
      ace.ar_bar      <= #TA '0;
      ace.ar_domain   <= #TA '0;
    endtask

    /// Issue a beat on the R channel.
    task send_r (
      input r_ace_beat_t beat
    );
      ace.r_id    <= #TA beat.r_id;
      ace.r_data  <= #TA beat.r_data;
      ace.r_resp  <= #TA beat.r_resp;
      ace.r_last  <= #TA beat.r_last;
      ace.r_user  <= #TA beat.r_user;
      ace.r_valid <= #TA 1;
      cycle_start();
      while (ace.r_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      ace.r_id    <= #TA '0;
      ace.r_data  <= #TA '0;
      ace.r_resp  <= #TA '0;
      ace.r_last  <= #TA '0;
      ace.r_user  <= #TA '0;
      ace.r_valid <= #TA 0;
      cycle_start();
      while (ace.rack != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
    endtask

    /// Wait for a beat on the AW channel.
    task recv_aw (
      output ax_ace_beat_t beat
    );
      ace.aw_ready <= #TA 1;
      cycle_start();
      while (ace.aw_valid != 1) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.ax_id        = ace.aw_id;
      beat.ax_addr      = ace.aw_addr;
      beat.ax_len       = ace.aw_len;
      beat.ax_size      = ace.aw_size;
      beat.ax_burst     = ace.aw_burst;
      beat.ax_lock      = ace.aw_lock;
      beat.ax_cache     = ace.aw_cache;
      beat.ax_prot      = ace.aw_prot;
      beat.ax_qos       = ace.aw_qos;
      beat.ax_region    = ace.aw_region;
      beat.ax_atop      = ace.aw_atop;
      beat.ax_user      = ace.aw_user;
      beat.ax_snoop   = ace.aw_snoop;
      beat.ax_bar       = ace.aw_bar;
      beat.ax_domain    = ace.aw_domain;
      beat.ax_awunique  = ace.aw_awunique;
      cycle_end();
      ace.aw_ready <= #TA 0;
    endtask

    /// Wait for a beat on the W channel.
    task recv_w (
      output w_beat_t beat
    );
      ace.w_ready <= #TA 1;
      cycle_start();
      while (ace.w_valid != 1) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.w_data = ace.w_data;
      beat.w_strb = ace.w_strb;
      beat.w_last = ace.w_last;
      beat.w_user = ace.w_user;
      cycle_end();
      ace.w_ready <= #TA 0;
    endtask

    /// Wait for a beat on the B channel.
    task recv_b (
      output b_beat_t beat
    );
      ace.b_ready <= #TA 1;
      cycle_start();
      while (ace.b_valid != 1) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.b_id   = ace.b_id;
      beat.b_resp = ace.b_resp;
      beat.b_user = ace.b_user;
      cycle_end();
      ace.b_ready <= #TA 0;
      ace.wack <= #TA 1;
      cycle_start();
      ace.wack <= #TA 0;
    endtask

    /// Wait for a beat on the AR channel.
    task recv_ar (
      output ax_ace_beat_t beat
    );
      ace.ar_ready  <= #TA 1;
      cycle_start();
      while (ace.ar_valid != 1) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.ax_id      = ace.ar_id;
      beat.ax_addr    = ace.ar_addr;
      beat.ax_len     = ace.ar_len;
      beat.ax_size    = ace.ar_size;
      beat.ax_burst   = ace.ar_burst;
      beat.ax_lock    = ace.ar_lock;
      beat.ax_cache   = ace.ar_cache;
      beat.ax_prot    = ace.ar_prot;
      beat.ax_qos     = ace.ar_qos;
      beat.ax_region  = ace.ar_region;
      beat.ax_atop    = 'X;  // Not defined on the AR channel.
      beat.ax_user    = ace.ar_user;
      beat.ax_snoop = ace.ar_snoop;
      beat.ax_bar     = ace.ar_bar;
      beat.ax_domain  = ace.ar_domain;
      cycle_end();
      ace.ar_ready  <= #TA 0;
    endtask

    /// Wait for a beat on the R channel.
    task recv_r (
      output r_ace_beat_t beat
    );
      ace.r_ready <= #TA 1;
      cycle_start();
      while (ace.r_valid != 1) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.r_id   = ace.r_id;
      beat.r_data = ace.r_data;
      beat.r_resp = ace.r_resp;
      beat.r_last = ace.r_last;
      beat.r_user = ace.r_user;
      cycle_end();
      ace.r_ready <= #TA 0;
      ace.rack <= #TA 1;
      cycle_start();
      ace.rack <= #TA 0;
    endtask

    /// Monitor the AW channel and return the next beat.
    task mon_aw (
      output ax_ace_beat_t beat
    );
      cycle_start();
      while (!(ace.aw_valid && ace.aw_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.ax_id        = ace.aw_id;
      beat.ax_addr      = ace.aw_addr;
      beat.ax_len       = ace.aw_len;
      beat.ax_size      = ace.aw_size;
      beat.ax_burst     = ace.aw_burst;
      beat.ax_lock      = ace.aw_lock;
      beat.ax_cache     = ace.aw_cache;
      beat.ax_prot      = ace.aw_prot;
      beat.ax_qos       = ace.aw_qos;
      beat.ax_region    = ace.aw_region;
      beat.ax_atop      = ace.aw_atop;
      beat.ax_user      = ace.aw_user;
      beat.ax_snoop   = ace.aw_snoop;
      beat.ax_bar       = ace.aw_bar;
      beat.ax_domain    = ace.aw_domain;
      beat.ax_awunique  = ace.aw_awunique;
      cycle_end();
    endtask

    /// Monitor the W channel and return the next beat.
    task mon_w (
      output w_beat_t beat
    );
      cycle_start();
      while (!(ace.w_valid && ace.w_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.w_data = ace.w_data;
      beat.w_strb = ace.w_strb;
      beat.w_last = ace.w_last;
      beat.w_user = ace.w_user;
      cycle_end();
    endtask

    /// Monitor the B channel and return the next beat.
    task mon_b (
      output b_beat_t beat
    );
      cycle_start();
      while (!(ace.b_valid && ace.b_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.b_id   = ace.b_id;
      beat.b_resp = ace.b_resp;
      beat.b_user = ace.b_user;
      cycle_end();
    endtask

    /// Monitor the AR channel and return the next beat.
    task mon_ar (
      output ax_ace_beat_t beat
    );
      cycle_start();
      while (!(ace.ar_valid && ace.ar_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.ax_id      = ace.ar_id;
      beat.ax_addr    = ace.ar_addr;
      beat.ax_len     = ace.ar_len;
      beat.ax_size    = ace.ar_size;
      beat.ax_burst   = ace.ar_burst;
      beat.ax_lock    = ace.ar_lock;
      beat.ax_cache   = ace.ar_cache;
      beat.ax_prot    = ace.ar_prot;
      beat.ax_qos     = ace.ar_qos;
      beat.ax_region  = ace.ar_region;
      beat.ax_atop    = 'X;  // Not defined on the AR channel.
      beat.ax_user    = ace.ar_user;
      beat.ax_snoop = ace.ar_snoop;
      beat.ax_bar     = ace.ar_bar;
      beat.ax_domain  = ace.ar_domain;
      cycle_end();
    endtask

    /// Monitor the R channel and return the next beat.
    task mon_r (
      output r_ace_beat_t beat
    );
      cycle_start();
      while (!(ace.r_valid && ace.r_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.r_id   = ace.r_id;
      beat.r_data = ace.r_data;
      beat.r_resp = ace.r_resp;
      beat.r_last = ace.r_last;
      beat.r_user = ace.r_user;
      cycle_end();
    endtask

  endclass

  class ace_rand_master #(
    // AXI interface parameters
    parameter int   AW = 32,
    parameter int   DW = 32,
    parameter int   IW = 8,
    parameter int   UW = 1,
    // Stimuli application and test time
    parameter time  TA = 0ps,
    parameter time  TT = 0ps,
    // Maximum number of read and write transactions in flight
    parameter int   MAX_READ_TXNS = 1,
    parameter int   MAX_WRITE_TXNS = 1,
    // Upper and lower bounds on wait cycles on Ax, W, and resp (R and B) channels
    parameter int   AX_MIN_WAIT_CYCLES = 0,
    parameter int   AX_MAX_WAIT_CYCLES = 100,
    parameter int   W_MIN_WAIT_CYCLES = 0,
    parameter int   W_MAX_WAIT_CYCLES = 5,
    parameter int   RESP_MIN_WAIT_CYCLES = 0,
    parameter int   RESP_MAX_WAIT_CYCLES = 20,
    // AXI feature usage
    parameter int   AXI_MAX_BURST_LEN = 0, // maximum number of beats in burst; 0 = AXI max (256)
    parameter int   TRAFFIC_SHAPING   = 0,
    parameter bit   AXI_EXCLS         = 1'b0,
    parameter bit   AXI_ATOPS         = 1'b0,
    parameter bit   AXI_BURST_FIXED   = 1'b1,
    parameter bit   AXI_BURST_INCR    = 1'b1,
    parameter bit   AXI_BURST_WRAP    = 1'b0,
    parameter bit   UNIQUE_IDS        = 1'b0, // guarantee that the ID of each transaction is
                                              // unique among all in-flight transactions in the
                                              // same direction
    // Dependent parameters, do not override.
    parameter int   AXI_STRB_WIDTH = DW/8,
    parameter int   N_AXI_IDS = 2**IW
  );
    typedef ace_test::ace_driver #(
      .AW(AW), .DW(DW), .IW(IW), .UW(UW), .TA(TA), .TT(TT)
    ) ace_driver_t;
    typedef logic [AW-1:0]      addr_t;
    typedef axi_pkg::burst_t    burst_t;
    typedef axi_pkg::cache_t    cache_t;
    typedef logic [DW-1:0]      data_t;
    typedef logic [IW-1:0]      id_t;
    typedef axi_pkg::len_t      len_t;
    typedef axi_pkg::size_t     size_t;
    typedef ace_pkg::arsnoop_t  snoop_t; // use only arsnoop_t, which is bigger than awsnoop_t
    typedef ace_pkg::bar_t      bar_t;
    typedef ace_pkg::domain_t   domain_t;
    typedef ace_pkg::awunique_t awunique_t;


    typedef logic [UW-1:0]      user_t;
    typedef axi_pkg::mem_type_t mem_type_t;

    typedef ace_driver_t::ax_ace_beat_t ax_ace_beat_t;
    typedef ace_driver_t::b_beat_t  b_beat_t;
    typedef ace_driver_t::r_ace_beat_t  r_ace_beat_t;
    typedef ace_driver_t::w_beat_t  w_beat_t;

    static addr_t PFN_MASK = '{11: 1'b0, 10: 1'b0, 9: 1'b0, 8: 1'b0, 7: 1'b0, 6: 1'b0, 5: 1'b0,
        4: 1'b0, 3: 1'b0, 2: 1'b0, 1: 1'b0, 0: 1'b0, default: '1};

    ace_driver_t drv;

    int unsigned          r_flight_cnt[N_AXI_IDS-1:0],
                          w_flight_cnt[N_AXI_IDS-1:0],
                          tot_r_flight_cnt,
                          tot_w_flight_cnt;
    logic [N_AXI_IDS-1:0] atop_resp_b,
                          atop_resp_r;

    len_t                 max_len;
    burst_t               allowed_bursts[$];

    semaphore cnt_sem;

    ax_ace_beat_t aw_ace_queue[$],
              w_queue[$],
              excl_queue[$];

    typedef struct packed {
      addr_t     addr_begin;
      addr_t     addr_end;
      mem_type_t mem_type;
    } mem_region_t;
    mem_region_t mem_map[$];

    struct packed {
      int unsigned len  ;
      int unsigned cprob;
    } traffic_shape[$];
    int unsigned max_cprob;

    function new(
      virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH(AW),
        .AXI_DATA_WIDTH(DW),
        .AXI_ID_WIDTH(IW),
        .AXI_USER_WIDTH(UW)
      ) ace
    );
      if (AXI_MAX_BURST_LEN <= 0 || AXI_MAX_BURST_LEN > 256) begin
        this.max_len = 255;
      end else begin
        this.max_len = AXI_MAX_BURST_LEN - 1;
      end
      this.drv = new(ace);
      this.cnt_sem = new(1);
      this.reset();
      if (AXI_BURST_FIXED) begin
        this.allowed_bursts.push_back(BURST_FIXED);
      end
      if (AXI_BURST_INCR) begin
        this.allowed_bursts.push_back(BURST_INCR);
      end
      if (AXI_BURST_WRAP) begin
        this.allowed_bursts.push_back(BURST_WRAP);
      end
      assert(allowed_bursts.size()) else $fatal(1, "At least one burst type has to be specified!");
    endfunction

    function void reset();
      drv.reset_master();
      r_flight_cnt = '{default: 0};
      w_flight_cnt = '{default: 0};
      tot_r_flight_cnt = 0;
      tot_w_flight_cnt = 0;
      atop_resp_b = '0;
      atop_resp_r = '0;
    endfunction

    function void add_memory_region(input addr_t addr_begin, input addr_t addr_end, input mem_type_t mem_type);
      mem_map.push_back({addr_begin, addr_end, mem_type});
    endfunction

    function void add_traffic_shaping(input int unsigned len, input int unsigned freq);
      if (traffic_shape.size() == 0)
        traffic_shape.push_back({len, freq});
      else
        traffic_shape.push_back({len, traffic_shape[$].cprob + freq});

      max_cprob = traffic_shape[$].cprob;
    endfunction : add_traffic_shaping

    function ax_ace_beat_t new_rand_burst(input logic is_read);
      automatic logic rand_success;
      automatic ax_ace_beat_t ax_ace_beat = new;
      automatic addr_t addr;
      automatic burst_t burst;
      automatic cache_t cache;
      automatic id_t id;
      automatic qos_t qos;
      automatic len_t len;
      automatic size_t size;
      automatic bar_t bar;
      automatic domain_t domain;
      automatic snoop_t snoop;
      automatic awunique_t awunique;
      automatic int unsigned mem_region_idx;
      automatic mem_region_t mem_region;
      automatic int cprob;
      automatic logic [2:0] trs;

      // No memory regions defined
      if (mem_map.size() == 0) begin
        // Return a dummy region
        mem_region = '{
          addr_begin: '0,
          addr_end:   '1,
          mem_type:   axi_pkg::NORMAL_NONCACHEABLE_BUFFERABLE
        };
      end else begin
        // Randomly pick a memory region
        mem_region_idx = $urandom_range(0,mem_map.size()-1);
        // std::randomize(mem_region_idx) with {
        //   mem_region_idx < mem_map.size();
        // }; assert(rand_success);
        mem_region = mem_map[mem_region_idx];
      end

      // Randomly pick burst type.
      burst = BURST_FIXED;
      // rand_success = std::randomize(burst) with {
      //   burst inside {this.allowed_bursts};
      // }; assert(rand_success);
      ax_ace_beat.ax_burst = burst;
      // Determine memory type.
      ax_ace_beat.ax_cache = is_read ? axi_pkg::get_arcache(mem_region.mem_type) : axi_pkg::get_awcache(mem_region.mem_type);
      // Randomize beat size.
      if (TRAFFIC_SHAPING) begin
        cprob = $urandom_range(0,max_cprob-1);
        // rand_success = std::randomize(cprob) with {
        //   cprob >= 0; cprob < max_cprob;
        // }; assert(rand_success);

        for (int i = 0; i < traffic_shape.size(); i++)
          if (traffic_shape[i].cprob > cprob) begin
            len = traffic_shape[i].len;
            if (ax_ace_beat.ax_burst == BURST_WRAP) begin
              assert (len inside {len_t'(1), len_t'(3), len_t'(7), len_t'(15)});
            end
            break;
          end

        // Randomize address.  Make sure that the burst does not cross a 4KiB boundary.
        forever begin
          size  = $clog2(AXI_STRB_WIDTH)-1;
          // rand_success = std::randomize(size) with {
          //   2**size <= AXI_STRB_WIDTH;
          //   2**size <= len;
          // }; assert(rand_success);
          ax_ace_beat.ax_size = size;
          ax_ace_beat.ax_len = ((len + (1 << size) - 1) >> size) - 1;

          addr  = mem_region.addr_begin;
          // rand_success = std::randomize(addr) with {
          //   addr >= mem_region.addr_begin;
          //   addr <= mem_region.addr_end;
          //   addr + len <= mem_region.addr_end;
         // }; assert(rand_success);

          if (ax_ace_beat.ax_burst == axi_pkg::BURST_FIXED) begin
            if (((addr + 2**ax_ace_beat.ax_size) & PFN_MASK) == (addr & PFN_MASK)) begin
              break;
            end
          end else begin // BURST_INCR
            if (((addr + 2**ax_ace_beat.ax_size * (ax_ace_beat.ax_len + 1)) & PFN_MASK) == (addr & PFN_MASK)) begin
              break;
            end
          end
        end
      end else begin
        // Randomize address.  Make sure that the burst does not cross a 4KiB boundary.
        forever begin
          // Randomize address
          addr  = $urandom_range(mem_region.addr_begin, mem_region.addr_end);

          if (ax_ace_beat.ax_burst == axi_pkg::BURST_FIXED) begin
            if (((addr + 2**ax_ace_beat.ax_size) & PFN_MASK) == (addr & PFN_MASK)) begin
              break;
            end
          end else begin // BURST_INCR, BURST_WRAP
            if (((addr + 2**ax_ace_beat.ax_size * (ax_ace_beat.ax_len + 1)) & PFN_MASK) == (addr & PFN_MASK)) begin
              break;
            end
          end
        end
      end
      
      id       = $urandom();
      qos      = $urandom();
      awunique = 0;
      trs      = $urandom_range(0,7);
      size     = $clog2(AXI_STRB_WIDTH)-1;
      case(trs )
        ace_pkg::READ_NO_SNOOP: begin
          snoop   = 'b0000;
          domain  = 'b00;
          bar     = 'b00;
          len     = $urandom();
        end
        ace_pkg::READ_ONCE: begin
          snoop   = 'b0000;
          domain  = 'b01;
          bar     = 'b00;
          len     = 1;
        end
        ace_pkg::READ_SHARED: begin
          snoop   = 'b0001;
          domain  = 'b01;
          bar     = 'b00;
          len     = 1;
        end
        ace_pkg::READ_UNIQUE: begin
          snoop   = 'b0111;
          domain  = 'b01;
          bar     = 'b00;
          len     = 1;
        end

        ace_pkg::CLEAN_UNIQUE: begin
          snoop   = 'b1011;
          domain  = 'b01;
          bar     = 'b00;
          len     = 0;
        end

        ace_pkg::WRITE_NO_SNOOP: begin
          snoop   = 'b0000;
          domain  = 'b00;
          bar     = 'b00;
          len     = $urandom();
        end
        ace_pkg::WRITE_BACK: begin
          snoop   = 'b0011;
          domain  = 'b00;
          bar     = 'b00;
          len     = 1;
        end
        ace_pkg::WRITE_UNIQUE: begin
          snoop   = 'b0000;
          domain  = 'b10;
          bar     = 'b00;
          len     = 1;
        end


        default: begin
          snoop   = 'b0000;
          domain  = 'b00;
          bar     = 'b00;
          len     = $urandom();
        end
      endcase
         
      ax_ace_beat.ax_addr     = addr;
      ax_ace_beat.ax_size     = size;
      ax_ace_beat.ax_len      = len;
      ax_ace_beat.ax_id       = id;
      ax_ace_beat.ax_qos      = qos;
      ax_ace_beat.ax_snoop    = snoop;
      ax_ace_beat.ax_bar      = bar;
      ax_ace_beat.ax_domain   = domain;
      ax_ace_beat.ax_awunique = awunique;

      return ax_ace_beat;
    endfunction

    task rand_atop_burst(inout ax_ace_beat_t beat);
      automatic logic rand_success;
      beat.ax_atop[5:4] = $random();
      if (beat.ax_atop[5:4] != 2'b00 && !AXI_BURST_INCR) begin
        // We can emit ATOPs only if INCR bursts are allowed.
        $warning("ATOP suppressed because INCR bursts are disabled!");
        beat.ax_atop[5:4] = 2'b00;
      end
      if (beat.ax_atop[5:4] != 2'b00) begin // ATOP
        // Determine `ax_atop`.
        if (beat.ax_atop[5:4] == axi_pkg::ATOP_ATOMICSTORE ||
            beat.ax_atop[5:4] == axi_pkg::ATOP_ATOMICLOAD) begin
          // Endianness
          beat.ax_atop[3] = $random();
          // Atomic operation
          beat.ax_atop[2:0] = $random();
        end else begin // Atomic{Swap,Compare}
          beat.ax_atop[3:1] = '0;
          beat.ax_atop[0] = $random();
        end
        // Determine `ax_size` and `ax_len`.
        if (2**beat.ax_size < AXI_STRB_WIDTH) begin
          // Transaction does *not* occupy full data bus, so we must send just one beat. [E1.1.3]
          beat.ax_len = '0;
        end else begin
          automatic int unsigned bytes;
          if (beat.ax_atop == axi_pkg::ATOP_ATOMICCMP) begin
            // Total data transferred in burst can be 2, 4, 8, 16, or 32 B.
            automatic int unsigned log_bytes;
            log_bytes = 3;
            // rand_success = std::randomize(log_bytes) with {
            //   log_bytes > 0; 2**log_bytes <= 32;
            // }; assert(rand_success);
            bytes = 2**log_bytes;
          end else begin
            // Total data transferred in burst can be 1, 2, 4, or 8 B.
            if (AXI_STRB_WIDTH >= 8) begin
              bytes = AXI_STRB_WIDTH;
            end else begin
              automatic int unsigned log_bytes;
              log_bytes = 5;
              // rand_success = std::randomize(log_bytes); assert(rand_success);
              log_bytes = log_bytes % (4 - $clog2(AXI_STRB_WIDTH)) - $clog2(AXI_STRB_WIDTH);
              bytes = 2**log_bytes;
            end
          end
          beat.ax_len = bytes / AXI_STRB_WIDTH - 1;
        end
        // Determine `ax_addr` and `ax_burst`.
        if (beat.ax_atop == axi_pkg::ATOP_ATOMICCMP) begin
          // The address must be aligned to half the outbound data size. [E1.1.3]
          beat.ax_addr = beat.ax_addr & ~((1'b1 << beat.ax_size) - 1);
          // If the address is aligned to the total size of outgoing data, the burst type must be
          // INCR. Otherwise, it must be WRAP. [E1.1.3]
          beat.ax_burst = (beat.ax_addr % ((beat.ax_len+1) * 2**beat.ax_size) == 0) ?
              axi_pkg::BURST_INCR : axi_pkg::BURST_WRAP;
          // If we are not allowed to emit WRAP bursts, align the address to the total size of
          // outgoing data and fall back to INCR.
          if (beat.ax_burst == axi_pkg::BURST_WRAP && !AXI_BURST_WRAP) begin
            beat.ax_addr -= (beat.ax_addr % ((beat.ax_len+1) * 2**beat.ax_size));
            beat.ax_burst = axi_pkg::BURST_INCR;
          end
        end else begin
          // The address must be aligned to the data size. [E1.1.3]
          beat.ax_addr = beat.ax_addr & ~((1'b1 << (beat.ax_size+1)) - 1);
          // Only INCR allowed.
          beat.ax_burst = axi_pkg::BURST_INCR;
        end
      end
    endtask

    function void rand_excl_ar(inout ax_ace_beat_t ar_ace_beat);
      ar_ace_beat.ax_lock = $random();
      if (ar_ace_beat.ax_lock) begin
        automatic logic rand_success;
        automatic int unsigned n_bytes;
        automatic size_t size;
        automatic addr_t addr_mask;
        ar_ace_beat.ax_size = $clog2(AXI_STRB_WIDTH)-1;
        
        // The address must be aligned to the total number of bytes in the burst.
        ar_ace_beat.ax_addr = ar_ace_beat.ax_addr & ~(2);
        ar_ace_beat.ax_snoop = $urandom();
        if( ar_ace_beat.ax_snoop == 4'b1001 || ar_ace_beat.ax_snoop == 4'b1011) begin
          ar_ace_beat.ax_len = 0;
        end else begin
          ar_ace_beat.ax_len = 1;
        end
        ar_ace_beat.ax_bar = $urandom();
        ar_ace_beat.ax_domain = $urandom();

      end
    endfunction

    // TODO: The `rand_wait` task exists in `rand_verif_pkg`, but that task cannot be called with
    // `this.drv.ace.clk_i` as `clk` argument. What is the syntax for getting an assignable
    // reference?
    task automatic rand_wait(input int unsigned min, max);
      int unsigned rand_success, cycles;
      cycles  = $urandom_range(min,max);
      // rand_success = std::randomize(cycles) with {
      //   cycles >= min;
      //   cycles <= max;
      // };
      //assert (rand_success) else $error("Failed to randomize wait cycles!");
      repeat (cycles) @(posedge this.drv.ace.clk_i);
    endtask

    // Determine if the ID of an AXI Ax beat is currently legal.  This function may only be called
    // while holding the `cnt_sem` semaphore.
    function bit id_is_legal(input bit is_read, input ax_ace_beat_t beat);
      if (AXI_ATOPS) begin
        // The ID must not be the same as that of any in-flight ATOP.
        if (atop_resp_b[beat.ax_id] || atop_resp_r[beat.ax_id]) return 1'b0;
        // If this beat starts an ATOP, its ID must not be the same as that of any other in-flight
        // AXI transaction.
        if (!is_read && beat.ax_atop[5:4] != 2'b00 && (
          r_flight_cnt[beat.ax_id] != 0 || w_flight_cnt[beat.ax_id] !=0
        )) return 1'b0;
      end
      if (UNIQUE_IDS) begin
        // This master may only emit transactions with an ID that is unique among all in-flight
        // transactions in the same direction.
        if (is_read && r_flight_cnt[beat.ax_id] != 0) return 1'b0;
        if (!is_read && w_flight_cnt[beat.ax_id] != 0) return 1'b0;
      end
      // There is no reason why this ID would be illegal, so it is legal.
      return 1'b1;
    endfunction

    // Legalize the ID of an AXI Ax beat (drawing a new ID at random if the existing ID is currently
    // not legal) and add it to the in-flight transactions.
    task legalize_id(input bit is_read, inout ax_ace_beat_t beat);
      automatic logic rand_success;
      automatic id_t id = beat.ax_id;
      // Loop until a legal ID is found.
      forever begin
        // Acquire semaphore on in-flight counters.
        cnt_sem.get();
        // Exit loop if the current ID is legal.
        if (id_is_legal(is_read, beat)) begin
          break;
        end else begin
          // The current ID is currently not legal, so try another ID in the next cycle and
          // release the semaphore until then.
          cnt_sem.put();
          rand_wait(1, 1);
          if (!beat.ax_lock) begin // The ID of an exclusive transfer must not be changed.
            //rand_success = std::randomize(id); assert(rand_success);
            id  = 1;
            beat.ax_id = id;
          end
        end
      end
      // Mark transfer for decided ID as in flight.
      if (!is_read) begin
        w_flight_cnt[beat.ax_id]++;
        tot_w_flight_cnt++;
        if (beat.ax_atop != 2'b00) begin
          // This is an ATOP, so it gives rise to a write response.
          atop_resp_b[beat.ax_id] = 1'b1;
          if (beat.ax_atop[axi_pkg::ATOP_R_RESP]) begin
            // This ATOP type additionally gives rise to a read response.
            atop_resp_r[beat.ax_id] = 1'b1;
          end
        end
      end else begin
        r_flight_cnt[beat.ax_id]++;
        tot_r_flight_cnt++;
      end
      // Release semaphore on in-flight counters.
      cnt_sem.put();
    endtask

    task send_ars(input int n_reads);
      automatic logic rand_success;
      repeat (n_reads) begin
        automatic id_t id;
        automatic ax_ace_beat_t ar_ace_beat = new_rand_burst(1'b1);
        while (tot_r_flight_cnt >= MAX_READ_TXNS) begin
          rand_wait(1, 1);
        end
        if (AXI_EXCLS) begin
          rand_excl_ar(ar_ace_beat);
        end
        legalize_id(1'b1, ar_ace_beat);
        rand_wait(AX_MIN_WAIT_CYCLES, AX_MAX_WAIT_CYCLES);
        drv.send_ar(ar_ace_beat);
        if (ar_ace_beat.ax_lock) excl_queue.push_back(ar_ace_beat);
      end
    endtask

    task recv_rs(ref logic ar_done, aw_done);
      while (!(ar_done && tot_r_flight_cnt == 0 &&
          (!AXI_ATOPS || (AXI_ATOPS && aw_done && atop_resp_r == '0))
      )) begin
        automatic r_ace_beat_t r_ace_beat;
        rand_wait(RESP_MIN_WAIT_CYCLES, RESP_MAX_WAIT_CYCLES);
        if (tot_r_flight_cnt > 0 || atop_resp_r > 0) begin
          drv.recv_r(r_ace_beat);
          if (r_ace_beat.r_last) begin
            cnt_sem.get();
            if (atop_resp_r[r_ace_beat.r_id]) begin
              atop_resp_r[r_ace_beat.r_id] = 1'b0;
            end else begin
              r_flight_cnt[r_ace_beat.r_id]--;
              tot_r_flight_cnt--;
            end
            cnt_sem.put();
          end
        end
      end
    endtask

    task create_aws(input int n_writes);
      automatic logic rand_success;
      repeat (n_writes) begin
        automatic bit excl = 1'b0;
        automatic ax_ace_beat_t aw_ace_beat;
        if (AXI_EXCLS && excl_queue.size() > 0) excl = $random();
        if (excl) begin
          aw_ace_beat = excl_queue.pop_front();
        end else begin
          aw_ace_beat = new_rand_burst(1'b0);
          if (AXI_ATOPS) rand_atop_burst(aw_ace_beat);
        end
        while (tot_w_flight_cnt >= MAX_WRITE_TXNS) begin
          rand_wait(1, 1);
        end
        legalize_id(1'b0, aw_ace_beat);
        aw_ace_queue.push_back(aw_ace_beat);
        w_queue.push_back(aw_ace_beat);
      end
    endtask

    task send_aws(ref logic aw_done);
      while (!(aw_done && aw_ace_queue.size() == 0)) begin
        automatic ax_ace_beat_t aw_ace_beat;
        wait (aw_ace_queue.size() > 0 || (aw_done && aw_ace_queue.size() == 0));
        aw_ace_beat = aw_ace_queue.pop_front();
        rand_wait(AX_MIN_WAIT_CYCLES, AX_MAX_WAIT_CYCLES);
        drv.send_aw(aw_ace_beat);
      end
    endtask

    task send_ws(ref logic aw_done);
      while (!(aw_done && w_queue.size() == 0)) begin
        automatic ax_ace_beat_t aw_ace_beat;
        automatic addr_t addr;
        static logic rand_success;
        wait (w_queue.size() > 0 || (aw_done && w_queue.size() == 0));
        aw_ace_beat = w_queue.pop_front();
        for (int unsigned i = 0; i < aw_ace_beat.ax_len + 1; i++) begin
          automatic w_beat_t w_beat = new;
          automatic int unsigned begin_byte, end_byte, n_bytes;
          automatic logic [AXI_STRB_WIDTH-1:0] rand_strb, strb_mask;
          addr = axi_pkg::beat_addr(aw_ace_beat.ax_addr, aw_ace_beat.ax_size, aw_ace_beat.ax_len,
                                    aw_ace_beat.ax_burst, i);
          //rand_success = w_beat.randomize(); assert (rand_success);
          // Determine strobe.
          w_beat.w_strb = '0;
          n_bytes = 2**aw_ace_beat.ax_size;
          begin_byte = addr % AXI_STRB_WIDTH;
          end_byte = ((begin_byte + n_bytes) >> aw_ace_beat.ax_size) << aw_ace_beat.ax_size;
          strb_mask = '0;
          for (int unsigned b = begin_byte; b < end_byte; b++)
            strb_mask[b] = 1'b1;
          rand_strb = $urandom();
          //rand_success = std::randomize(rand_strb); assert (rand_success);
          w_beat.w_strb |= (rand_strb & strb_mask);
          // Determine last.
          w_beat.w_last = (i == aw_ace_beat.ax_len);
          rand_wait(W_MIN_WAIT_CYCLES, W_MAX_WAIT_CYCLES);
          drv.send_w(w_beat);
        end
      end
    endtask

    task recv_bs(ref logic aw_done);
      while (!(aw_done && tot_w_flight_cnt == 0)) begin
        automatic b_beat_t b_beat;
        rand_wait(RESP_MIN_WAIT_CYCLES, RESP_MAX_WAIT_CYCLES);
        drv.recv_b(b_beat);
        cnt_sem.get();
        if (atop_resp_b[b_beat.b_id]) begin
          atop_resp_b[b_beat.b_id] = 1'b0;
        end
        w_flight_cnt[b_beat.b_id]--;
        tot_w_flight_cnt--;
        cnt_sem.put();
      end
    endtask

    // Issue n_reads random read and n_writes random write transactions to an address range.
    task run(input int n_reads, input int n_writes);
      automatic logic  ar_done = 1'b0,
                       aw_done = 1'b0;
      fork
        begin
          send_ars(n_reads);
          ar_done = 1'b1;
        end
        recv_rs(ar_done, aw_done);
        begin
          create_aws(n_writes);
          aw_done = 1'b1;
        end
        send_aws(aw_done);
        send_ws(aw_done);
        recv_bs(aw_done);
      join
    endtask

  endclass

  class ace_rand_slave #(
    // AXI interface parameters
    parameter int   AW = 32,
    parameter int   DW = 32,
    parameter int   IW = 8,
    parameter int   UW = 1,
    // Stimuli application and test time
    parameter time  TA = 0ps,
    parameter time  TT = 0ps,
    parameter bit   RAND_RESP = 0,
    // Upper and lower bounds on wait cycles on Ax, W, and resp (R and B) channels
    parameter int   AX_MIN_WAIT_CYCLES = 0,
    parameter int   AX_MAX_WAIT_CYCLES = 100,
    parameter int   R_MIN_WAIT_CYCLES = 0,
    parameter int   R_MAX_WAIT_CYCLES = 5,
    parameter int   RESP_MIN_WAIT_CYCLES = 0,
    parameter int   RESP_MAX_WAIT_CYCLES = 20,
    /// This parameter eneables an internal memory, which gets randomly initialized, if it is read
    /// and retains written data. This mode does currently not support `axi_pkg::BURST_WRAP`!
    /// All responses are `axi_pkg::RESP_OKAY` when in this mode.
    parameter bit   MAPPED = 1'b0
  );
    typedef ace_test::ace_driver #(
      .AW(AW), .DW(DW), .IW(IW), .UW(UW), .TA(TA), .TT(TT)
    ) ace_driver_t;
    typedef rand_id_queue_pkg::rand_id_queue #(
      .data_t   (ace_driver_t::ax_ace_beat_t),
      .ID_WIDTH (IW)
    ) rand_ax_ace_beat_queue_t;
    typedef ace_driver_t::ax_ace_beat_t ax_ace_beat_t;
    typedef ace_driver_t::b_beat_t b_beat_t;
    typedef ace_driver_t::r_ace_beat_t r_ace_beat_t;
    typedef ace_driver_t::w_beat_t w_beat_t;

    typedef logic [AW-1:0] addr_t;
    typedef logic [7:0]    byte_t;

    ace_driver_t          drv;
    rand_ax_ace_beat_queue_t  ar_ace_queue;
    ax_ace_beat_t             aw_ace_queue[$];
    int unsigned          b_wait_cnt;

    // Memory array for when the `MAPPED` parameter is set.
    byte_t memory_q[addr_t];

    function new(
      virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH(AW),
        .AXI_DATA_WIDTH(DW),
        .AXI_ID_WIDTH(IW),
        .AXI_USER_WIDTH(UW)
      ) ace
    );
      this.drv = new(ace);
      this.ar_ace_queue = new;
      this.b_wait_cnt = 0;
      this.reset();
    endfunction

    function void reset();
      this.drv.reset_slave();
      this.memory_q.delete();
    endfunction

    // TODO: The `rand_wait` task exists in `rand_verif_pkg`, but that task cannot be called with
    // `this.drv.ace.clk_i` as `clk` argument.  What is the syntax getting an assignable reference?
    task automatic rand_wait(input int unsigned min, max);
      int unsigned rand_success, cycles;
      cycles = $urandom_range(min,max);
      // rand_success = std::randomize(cycles) with {
      //   cycles >= min;
      //   cycles <= max;
      // };
      // assert (rand_success) else $error("Failed to randomize wait cycles!");
      repeat (cycles) @(posedge this.drv.ace.clk_i);
    endtask

    task recv_ars();
      forever begin
        automatic ax_ace_beat_t ar_ace_beat;
        rand_wait(AX_MIN_WAIT_CYCLES, AX_MAX_WAIT_CYCLES);
        drv.recv_ar(ar_ace_beat);
        if (MAPPED) begin
          assert (ar_ace_beat.ax_burst != axi_pkg::BURST_WRAP) else
            $error("axi_pkg::BURST_WRAP not supported in MAPPED mode.");
        end
        ar_ace_queue.push(ar_ace_beat.ax_id, ar_ace_beat);
      end
    endtask

    task send_rs();
      forever begin
        automatic logic rand_success;
        automatic ax_ace_beat_t ar_ace_beat;
        automatic r_ace_beat_t  r_ace_beat = new;
        automatic addr_t    byte_addr;
        wait (ar_ace_queue.size > 0);
        ar_ace_beat      = ar_ace_queue.peek();
        byte_addr    = axi_pkg::aligned_addr(ar_ace_beat.ax_addr, axi_pkg::size_t'($clog2(DW/8)));
        //rand_success = std::randomize(r_beat); assert(rand_success);
        //rand_success = r_beat.randomize(); assert(rand_success);
        if (MAPPED) begin
          // Either use the actual data, or save the random generated.
          for (int unsigned i = 0; i < (DW/8); i++) begin
            if (this.memory_q.exists(byte_addr)) begin
              r_ace_beat.r_data[i*8+:8] = this.memory_q[byte_addr];
            end else begin
              this.memory_q[byte_addr] = r_ace_beat.r_data[i*8+:8];
            end
            byte_addr++;
          end
          r_ace_beat.r_resp = axi_pkg::RESP_OKAY;
        end
        r_ace_beat.r_id = ar_ace_beat.ax_id;
        if (RAND_RESP && !ar_ace_beat.ax_atop[axi_pkg::ATOP_R_RESP])
          r_ace_beat.r_resp[1] = $random();
        if (ar_ace_beat.ax_lock)
          r_ace_beat.r_resp[0]= $random();
        r_ace_beat.r_resp[2] = $random();
        r_ace_beat.r_resp[3] = $random();
        rand_wait(R_MIN_WAIT_CYCLES, R_MAX_WAIT_CYCLES);
        if (ar_ace_beat.ax_len == '0) begin
          r_ace_beat.r_last = 1'b1;
          void'(ar_ace_queue.pop_id(ar_ace_beat.ax_id));
        end else begin
          if ((ar_ace_beat.ax_burst == axi_pkg::BURST_INCR) && MAPPED) begin
            ar_ace_beat.ax_addr = axi_pkg::aligned_addr(ar_ace_beat.ax_addr, ar_ace_beat.ax_size) +
                                  2**ar_ace_beat.ax_size;
          end
          ar_ace_beat.ax_len--;
          ar_ace_queue.set(ar_ace_beat.ax_id, ar_ace_beat);
        end
        drv.send_r(r_ace_beat);
      end
    endtask

    task recv_aws();
      forever begin
        automatic ax_ace_beat_t aw_ace_beat;
        rand_wait(AX_MIN_WAIT_CYCLES, AX_MAX_WAIT_CYCLES);
        drv.recv_aw(aw_ace_beat);
        if (MAPPED) begin
          assert (aw_ace_beat.ax_atop == '0) else
            $error("ATOP not supported in MAPPED mode.");
          assert (aw_ace_beat.ax_burst != axi_pkg::BURST_WRAP) else
            $error("axi_pkg::BURST_WRAP not supported in MAPPED mode.");
        end
        aw_ace_queue.push_back(aw_ace_beat);
        // Atomic{Load,Swap,Compare}s require an R response.
        if (aw_ace_beat.ax_atop[axi_pkg::ATOP_R_RESP]) begin
          ar_ace_queue.push(aw_ace_beat.ax_id, aw_ace_beat);
        end
      end
    endtask

    task recv_ws();
      forever begin
        automatic ax_ace_beat_t aw_ace_beat;
        automatic addr_t    byte_addr;
        forever begin
          automatic w_beat_t w_beat;
          rand_wait(RESP_MIN_WAIT_CYCLES, RESP_MAX_WAIT_CYCLES);
          drv.recv_w(w_beat);
          if (MAPPED) begin
            wait (aw_ace_queue.size() > 0);
            aw_ace_beat = aw_ace_queue[0];
            byte_addr    = axi_pkg::aligned_addr(aw_ace_beat.ax_addr, $clog2(DW/8));

            // Write Data if the strobe is defined
            for (int unsigned i = 0; i < (DW/8); i++) begin
              if (w_beat.w_strb[i]) begin
                this.memory_q[byte_addr] = w_beat.w_data[i*8+:8];
              end
              byte_addr++;
            end
            // Update address in beat
            if (aw_ace_beat.ax_burst == axi_pkg::BURST_INCR) begin
              aw_ace_beat.ax_addr = axi_pkg::aligned_addr(aw_ace_beat.ax_addr, aw_ace_beat.ax_size) +
                                    2**aw_ace_beat.ax_size;
            end
            aw_ace_queue[0] = aw_ace_beat;
          end
          if (w_beat.w_last)
            break;
        end
        b_wait_cnt++;
      end
    endtask

    task send_bs();
      forever begin
        automatic ax_ace_beat_t aw_ace_beat;
        automatic b_beat_t b_beat = new;
        automatic logic rand_success;
        wait (b_wait_cnt > 0 && (aw_ace_queue.size() != 0));
        aw_ace_beat = aw_ace_queue.pop_front();
        //rand_success = b_beat.randomize(); assert(rand_success);
        b_beat.b_id = aw_ace_beat.ax_id;
        if (RAND_RESP && !aw_ace_beat.ax_atop[axi_pkg::ATOP_R_RESP])
          b_beat.b_resp[1] = $random();
        if (aw_ace_beat.ax_lock) begin
          b_beat.b_resp[0]= $random();
        end
        rand_wait(RESP_MIN_WAIT_CYCLES, RESP_MAX_WAIT_CYCLES);
        if (MAPPED) begin
          b_beat.b_resp = axi_pkg::RESP_OKAY;
        end
        drv.send_b(b_beat);
        b_wait_cnt--;
      end
    endtask

    task run();
      fork
        recv_ars();
        send_rs();
        recv_aws();
        recv_ws();
        send_bs();
      join
    endtask

  endclass

  /// ACE Monitor.
  class ace_monitor #(
    /// AXI4+ATOP ID width
    parameter int unsigned IW = 0,
    /// AXI4+ATOP address width
    parameter int unsigned AW = 0,
    /// AXI4+ATOP data width
    parameter int unsigned DW = 0,
    /// AXI4+ATOP user width
    parameter int unsigned UW = 0,
    /// Stimuli test time
    parameter time TT = 0ns
  );

    typedef ace_test::ace_driver #(
      .AW(AW), .DW(DW), .IW(IW), .UW(UW), .TA(TT), .TT(TT)
    ) ace_driver_t;

    typedef ace_driver_t::ax_ace_beat_t ax_ace_beat_t;
    typedef ace_driver_t::w_beat_t      w_beat_t;
    typedef ace_driver_t::b_beat_t      b_beat_t;
    typedef ace_driver_t::r_ace_beat_t  r_ace_beat_t;

    ace_driver_t          drv;
    mailbox aw_mbx = new, w_mbx = new, b_mbx = new,
            ar_mbx = new, r_mbx = new;

    function new(
      virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH(AW),
        .AXI_DATA_WIDTH(DW),
        .AXI_ID_WIDTH(IW),
        .AXI_USER_WIDTH(UW)
      ) axi
    );
      this.drv = new(axi);
    endfunction

    task monitor;
      fork
        // AW
        forever begin
          automatic ax_ace_beat_t ax;
          this.drv.mon_aw(ax);
          aw_mbx.put(ax);
        end
        // W
        forever begin
          automatic w_beat_t w;
          this.drv.mon_w(w);
          w_mbx.put(w);
        end
        // B
        forever begin
          automatic b_beat_t b;
          this.drv.mon_b(b);
          b_mbx.put(b);
        end
        // AR
        forever begin
          automatic ax_ace_beat_t ax;
          this.drv.mon_ar(ax);
          ar_mbx.put(ax);
        end
        // R
        forever begin
          automatic r_ace_beat_t r;
          this.drv.mon_r(r);
          r_mbx.put(r);
        end
      join
    endtask
  endclass

endpackage

// non synthesisable axi logger module
// this module logs the activity of the input axi channel
// the log files will be found in "./axi_log/<LoggerName>/"
// one log file for all writes
// a log file per id for the reads
// atomic transactions with read response are injected into the corresponding log file of the read
module ace_chan_logger #(
  parameter time TestTime     = 8ns,          // Time after clock, where sampling happens
  parameter string LoggerName = "ace_logger", // name of the logger
  parameter type aw_chan_t    = logic,        // axi AW type
  parameter type  w_chan_t    = logic,        // axi  W type
  parameter type  b_chan_t    = logic,        // axi  B type
  parameter type ar_chan_t    = logic,        // axi AR type
  parameter type  r_chan_t    = logic         // axi  R type
) (
  input logic     clk_i,     // Clock
  input logic     rst_ni,    // Asynchronous reset active low, when `1'b0` no sampling
  input logic     end_sim_i, // end of simulation
  // AW channel
  input aw_chan_t aw_chan_i,
  input logic     aw_valid_i,
  input logic     aw_ready_i,
  //  W channel
  input w_chan_t  w_chan_i,
  input logic     w_valid_i,
  input logic     w_ready_i,
  //  B channel
  input b_chan_t  b_chan_i,
  input logic     b_valid_i,
  input logic     b_ready_i,
  // AR channel
  input ar_chan_t ar_chan_i,
  input logic     ar_valid_i,
  input logic     ar_ready_i,
  //  R channel
  input r_chan_t  r_chan_i,
  input logic     r_valid_i,
  input logic     r_ready_i
);
  // id width from channel
  localparam int unsigned IdWidth = $bits(aw_chan_i.id);
  localparam int unsigned NoIds   = 2**IdWidth;

  // queues for writes and reads
  aw_chan_t aw_queue[$];
  w_chan_t  w_queue[$];
  b_chan_t  b_queue[$];
  aw_chan_t ar_queues[NoIds-1:0][$];
  r_chan_t  r_queues[NoIds-1:0][$];

  // channel sampling into queues
  always @(posedge clk_i) #TestTime begin : proc_channel_sample
    automatic aw_chan_t ar_beat;
    automatic int       fd;
    automatic string    log_file;
    automatic string    log_str;
    // only execute when reset is high
    if (rst_ni) begin
      // AW channel
      if (aw_valid_i && aw_ready_i) begin
        aw_queue.push_back(aw_chan_i);
        log_file = $sformatf("./axi_log/%s/write.log", LoggerName);
        fd = $fopen(log_file, "a");
        if (fd) begin
          log_str = $sformatf("%0t> ID: %h AW on channel: LEN: %d, ATOP: %b",
                        $time, aw_chan_i.id, aw_chan_i.len, aw_chan_i.atop);
          $fdisplay(fd, log_str);
          $fclose(fd);
        end

        // inject AR into queue, if there is an atomic
        if (aw_chan_i.atop[axi_pkg::ATOP_R_RESP]) begin
          $display("Atomic detected with response");
          ar_beat.id     = aw_chan_i.id;
          ar_beat.addr   = aw_chan_i.addr;
          if (aw_chan_i.len > 1) begin
            ar_beat.len    = aw_chan_i.len / 2;
          end else begin
            ar_beat.len    = aw_chan_i.len;
          end
          ar_beat.size   = aw_chan_i.size;
          ar_beat.burst  = aw_chan_i.burst;
          ar_beat.lock   = aw_chan_i.lock;
          ar_beat.cache  = aw_chan_i.cache;
          ar_beat.prot   = aw_chan_i.prot;
          ar_beat.qos    = aw_chan_i.qos;
          ar_beat.region = aw_chan_i.region;
          ar_beat.atop   = aw_chan_i.atop;
          ar_beat.user   = aw_chan_i.user;
          ar_queues[aw_chan_i.id].push_back(ar_beat);
          log_file = $sformatf("./axi_log/%s/read_%0h.log", LoggerName, aw_chan_i.id);
          fd = $fopen(log_file, "a");
          if (fd) begin
            log_str = $sformatf("%0t> ID: %h AR on channel: LEN: %d injected ATOP: %b",
                          $time, ar_beat.id, ar_beat.len, ar_beat.atop);
            $fdisplay(fd, log_str);
            $fclose(fd);
          end
        end
      end
      // W channel
      if (w_valid_i && w_ready_i) begin
        w_queue.push_back(w_chan_i);
      end
      // B channel
      if (b_valid_i && b_ready_i) begin
        b_queue.push_back(b_chan_i);
      end
      // AR channel
      if (ar_valid_i && ar_ready_i) begin
        log_file = $sformatf("./axi_log/%s/read_%0h.log", LoggerName, ar_chan_i.id);
        fd = $fopen(log_file, "a");
        if (fd) begin
          log_str = $sformatf("%0t> ID: %h AR on channel: LEN: %d",
                          $time, ar_chan_i.id, ar_chan_i.len);
          $fdisplay(fd, log_str);
          $fclose(fd);
        end
        ar_beat.id     = ar_chan_i.id;
        ar_beat.addr   = ar_chan_i.addr;
        ar_beat.len    = ar_chan_i.len;
        ar_beat.size   = ar_chan_i.size;
        ar_beat.burst  = ar_chan_i.burst;
        ar_beat.lock   = ar_chan_i.lock;
        ar_beat.cache  = ar_chan_i.cache;
        ar_beat.prot   = ar_chan_i.prot;
        ar_beat.qos    = ar_chan_i.qos;
        ar_beat.region = ar_chan_i.region;
        ar_beat.atop   = '0;
        ar_beat.user   = ar_chan_i.user;
        ar_beat.snoop=ar_chan_i.snoop;
        ar_beat.bar=ar_chan_i.bar;
        ar_beat.domain=ar_chan_i.domain;
        ar_queues[ar_chan_i.id].push_back(ar_beat);
      end
      // R channel
      if (r_valid_i && r_ready_i) begin
        r_queues[r_chan_i.id].push_back(r_chan_i);
      end
    end
  end

  initial begin : proc_log
    automatic string       log_name;
    automatic string       log_string;
    automatic aw_chan_t    aw_beat;
    automatic w_chan_t     w_beat;
    automatic int unsigned no_w_beat = 0;
    automatic b_chan_t     b_beat;
    automatic aw_chan_t    ar_beat;
    automatic r_chan_t     r_beat;
    automatic int unsigned no_r_beat[NoIds];
    automatic int          fd;

    // init r counter
    for (int unsigned i = 0; i < NoIds; i++) begin
      no_r_beat[i] = 0;
    end

    // make the log dirs
    log_name = $sformatf("mkdir -p ./axi_log/%s/", LoggerName);
    $system(log_name);

    // open log files
    log_name = $sformatf("./axi_log/%s/write.log", LoggerName);
    fd = $fopen(log_name, "w");
    if (fd) begin
      $display("File was opened successfully : %0d", fd);
      $fdisplay(fd, "This is the write log file");
      $fclose(fd);
    end else
      $display("File was NOT opened successfully : %0d", fd);
    for (int unsigned i = 0; i < NoIds; i++) begin
      log_name = $sformatf("./axi_log/%s/read_%0h.log", LoggerName, i);
      fd = $fopen(log_name, "w");
      if (fd) begin
        $display("File was opened successfully : %0d", fd);
        $fdisplay(fd, "This is the read log file for ID: %0h", i);
        $fclose(fd);
      end else
        $display("File was NOT opened successfully : %0d", fd);
    end

    // on each clock cycle update the logs if there is something in the queues
    wait (rst_ni);
    while (!end_sim_i) begin
      @(posedge clk_i);

      // update the write log file
      while (aw_queue.size() != 0 && w_queue.size() != 0) begin
        aw_beat = aw_queue[0];
        w_beat  = w_queue.pop_front();

        log_string = $sformatf("%0t> ID: %h W %d of %d, LAST: %b ATOP: %b",
                        $time, aw_beat.id, no_w_beat, aw_beat.len, w_beat.last, aw_beat.atop);

        log_name = $sformatf("./axi_log/%s/write.log", LoggerName);
        fd = $fopen(log_name, "a");
        if (fd) begin
          $fdisplay(fd, log_string);
          // write out error if last beat does not match!
          if (w_beat.last && !(aw_beat.len == no_w_beat)) begin
            $fdisplay(fd, "ERROR> Last flag was not expected!!!!!!!!!!!!!");
          end
          $fclose(fd);
        end
        // pop the AW if the last flag is set
        no_w_beat++;
        if (w_beat.last) begin
          aw_beat = aw_queue.pop_front();
          no_w_beat = 0;
        end
      end

      // check b queue
      if (b_queue.size() != 0) begin
        b_beat = b_queue.pop_front();
        log_string = $sformatf("%0t> ID: %h B recieved",
                        $time, b_beat.id);
        log_name = $sformatf("./axi_log/%s/write.log", LoggerName);
        fd = $fopen(log_name, "a");
        if (fd) begin
          $fdisplay(fd, log_string);
          $fclose(fd);
        end
      end

      // update the read log files
      for (int unsigned i = 0; i < NoIds; i++) begin
        while (ar_queues[i].size() != 0 && r_queues[i].size() != 0) begin
          ar_beat = ar_queues[i][0];
          r_beat  = r_queues[i].pop_front();

          log_name = $sformatf("./axi_log/%s/read_%0h.log", LoggerName, i);
          fd = $fopen(log_name, "a");
          if (fd) begin
            log_string = $sformatf("%0t> ID: %h R %d of %d, LAST: %b ATOP: %b",
                            $time, r_beat.id, no_r_beat[i], ar_beat.len, r_beat.last, ar_beat.atop);

            $fdisplay(fd, log_string);
            // write out error if last beat does not match!
            if (r_beat.last && !(ar_beat.len == no_r_beat[i])) begin
              $fdisplay(fd, "ERROR> Last flag was not expected!!!!!!!!!!!!!");
            end
            $fclose(fd);
          end
          no_r_beat[i]++;
          // pop the queue if it is the last flag
          if (r_beat.last) begin
            ar_beat = ar_queues[i].pop_front();
            no_r_beat[i] = 0;
          end
        end
      end
    end
    $fclose(fd);
  end
endmodule
