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


/// A set of testbench utilities for AXI interfaces.
package snoop_test;

  import axi_pkg::*;
  import ace_pkg::*;

  /// The data transferred on a beat on the AC channel.
  class ace_ac_beat #(
    parameter AW = 32
  );
    rand logic [AW-1:0] ac_addr     = '0;
    logic [3:0] ac_snoop    = '0;
    logic [2:0] ac_prot    = '0;
  endclass

  /// The data transferred on a beat on the CR channel.
  class ace_cr_beat;
    snoop_pkg::crresp_t cr_resp    = '0;
  endclass

  /// The data transferred on a beat on the CD channel.
  class ace_cd_beat #(
    parameter DW = 32
  );
    rand logic [DW-1:0] cd_data    = '0;
    logic cd_last;
  endclass

  class snoop_driver #(
    parameter AW = 32,
    parameter DW = 32,
    parameter time TA = 0ns , // stimuli application time
    parameter time TT = 0ns   // stimuli test time
  );
    virtual SNOOP_BUS_DV #(
      .SNOOP_ADDR_WIDTH(AW),
      .SNOOP_DATA_WIDTH(DW)
    ) snoop;

    typedef ace_ac_beat #(.AW(AW)) ace_ac_beat_t;
    typedef ace_cd_beat #(.DW(DW)) ace_cd_beat_t;
    typedef ace_cr_beat ace_cr_beat_t;

    function new(
      virtual SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH(AW),
        .SNOOP_DATA_WIDTH(DW)
      ) snoop
    );
      this.snoop = snoop;
    endfunction

    function void reset_master();
      snoop.ac_valid <= '0;
      snoop.ac_addr <= '0;
      snoop.ac_snoop <= '0;
      snoop.ac_prot <= '0;
      snoop.cr_ready <= '0;
      snoop.cd_ready <= '0;
    endfunction

    function void reset_slave();
      snoop.ac_ready <= '0;
      snoop.cr_valid <= '0;
      snoop.cr_resp <= '0;
      snoop.cd_valid <= '0;
      snoop.cd_data <= '0;
      snoop.cd_last <= '0;
    endfunction

    task cycle_start;
      #TT;
    endtask

    task cycle_end;
      @(posedge snoop.clk_i);
    endtask

    /// Issue a beat on the AC channel.
    task send_ac (
      input ace_ac_beat_t beat
    );
      snoop.ac_valid <= #TA 1;
      snoop.ac_addr <= #TA beat.ac_addr;
      snoop.ac_snoop <= #TA beat.ac_snoop;
      snoop.ac_prot <= #TA beat.ac_prot;
      cycle_start();
      while (snoop.ac_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      snoop.ac_valid <= #TA '0;
      snoop.ac_addr <= #TA '0;
      snoop.ac_snoop <= #TA '0;
      snoop.ac_prot <= #TA '0;
    endtask

    /// Issue a beat on the CR channel.
    task send_cr (
      input ace_cr_beat_t beat
    );
      snoop.cr_valid <= #TA 1;
      snoop.cr_resp <= #TA beat.cr_resp;
      cycle_start();
      while (snoop.cr_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      snoop.cr_valid <= #TA '0;
      snoop.cr_resp <= #TA '0;
    endtask

    /// Issue a beat on the CD channel.
    task send_cd (
      input ace_cd_beat_t beat
    );
      snoop.cd_valid <= #TA 1;
      snoop.cd_data <= #TA beat.cd_data;
      snoop.cd_last <= #TA beat.cd_last;
      cycle_start();
      while (snoop.cd_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      snoop.cd_valid <= #TA '0;
      snoop.cd_data <= #TA '0;
      snoop.cd_last <= #TA '0;
    endtask

    /// Wait for a beat on the AC channel.
    task recv_ac (
      output ace_ac_beat_t beat
    );
      snoop.ac_ready <= #TA 1;
      cycle_start();
      while (snoop.ac_valid != 1) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.ac_addr = snoop.ac_addr;
      beat.ac_snoop = snoop.ac_snoop;
      beat.ac_prot = snoop.ac_prot;
      cycle_end();
      snoop.ac_ready <= #TA 0;
    endtask

    /// Wait for a beat on the CR channel.
    task recv_cr (
      output ace_cr_beat_t beat
    );
      snoop.cr_ready <= #TA 1;
      cycle_start();
      while (snoop.cr_valid != 1) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.cr_resp = snoop.cr_resp;
      cycle_end();
      snoop.cr_ready <= #TA 0;
    endtask

    /// Wait for a beat on the CD channel.
    task recv_cd (
                  output ace_cd_beat_t beat
                  );
      beat = new;
      beat.cd_last = '0;
      while (!beat.cd_last) begin
        snoop.cd_ready <= #TA 1;
        cycle_start();
        while (snoop.cd_valid != 1) begin cycle_end(); cycle_start(); end
        beat.cd_data = snoop.cd_data;
        beat.cd_last = snoop.cd_last;
        cycle_end();
        snoop.cd_ready <= #TA 0;
      end
    endtask

    /// Monitor the AC channel and return the next beat.
    task mon_ac (
      output ace_ac_beat_t beat
    );
      cycle_start();
      while (!(snoop.ac_valid && snoop.ac_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.ac_addr      = snoop.ac_addr;
      beat.ac_snoop     = snoop.ac_snoop;
      beat.ac_prot      = snoop.ac_prot;
      cycle_end();
    endtask

    /// Monitor the CR channel and return the next beat.
    task mon_cr (
      output ace_cr_beat_t beat
    );
      cycle_start();
      while (!(snoop.cr_valid && snoop.cr_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.cr_resp      = snoop.cr_resp;
      cycle_end();
    endtask

    /// Monitor the CD channel and return the next beat.
    task mon_cd (
      output ace_cd_beat_t beat
    );
      cycle_start();
      while (!(snoop.cd_valid && snoop.cd_ready)) begin cycle_end(); cycle_start(); end
      beat = new;
      beat.cd_data      = snoop.cd_data;
      beat.cd_last      = snoop.cd_last;
      cycle_end();
    endtask

  endclass

  class snoop_rand_master #(
    // AXI interface parameters
    parameter int   AW = 32,
    parameter int   DW = 32,
    // Stimuli application and test time
    parameter time  TA = 0ps,
    parameter time  TT = 0ps,
    // Upper and lower bounds on wait cycles on AC, CR, and CD channels
    parameter int   AC_MIN_WAIT_CYCLES = 0,
    parameter int   AC_MAX_WAIT_CYCLES = 100,
    parameter int   CR_MIN_WAIT_CYCLES = 0,
    parameter int   CR_MAX_WAIT_CYCLES = 5,
    parameter int   CD_MIN_WAIT_CYCLES = 0,
    parameter int   CD_MAX_WAIT_CYCLES = 20
  );
    typedef snoop_test::snoop_driver #(
      .AW(AW), .DW(DW), .TA(TA), .TT(TT)
    ) snoop_driver_t;
    typedef logic [AW-1:0]      addr_t;
    typedef logic [DW-1:0]      data_t;
    typedef snoop_pkg::acsnoop_t  acsnoop_t;
    typedef snoop_pkg::acprot_t   acprot_t;
    typedef snoop_pkg::crresp_t   crresp_t;

    typedef snoop_driver_t::ace_ac_beat_t ace_ac_beat_t;
    typedef snoop_driver_t::ace_cr_beat_t ace_cr_beat_t;
    typedef snoop_driver_t::ace_cd_beat_t ace_cd_beat_t;

    snoop_driver_t drv;

    typedef struct packed {
      addr_t     addr_begin;
      addr_t     addr_end;
      mem_type_t mem_type;
    } mem_region_t;
    mem_region_t mem_map[$];

    function new(
      virtual SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH(AW),
        .SNOOP_DATA_WIDTH(DW)
      ) snoop
    );
      this.drv = new(snoop);
      this.reset();
    endfunction

    function void reset();
      drv.reset_master();
    endfunction

    function void add_memory_region(input addr_t addr_begin, input addr_t addr_end, input mem_type_t mem_type);
      mem_map.push_back({addr_begin, addr_end, mem_type});
    endfunction

    function ace_ac_beat_t new_rand_burst();
      automatic logic rand_success;
      automatic ace_ac_beat_t ace_ac_beat = new;
      automatic addr_t addr;
      automatic snoop_pkg::acsnoop_t snoop;
      automatic snoop_pkg::acprot_t prot;
      automatic int unsigned mem_region_idx;
      automatic mem_region_t mem_region;

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

      // Randomize address
      addr  = mem_region.addr_begin + $urandom_range(mem_region.addr_end-mem_region.addr_begin+1);

      ace_ac_beat.ac_addr = addr;
      snoop      = $urandom();
      prot     = $urandom();

      // rand_success = std::randomize(id); assert(rand_success);
      // rand_success = std::randomize(qos); assert(rand_success);
      // The random ID *must* be legalized with `legalize_id()` before the beat is sent!  This is
      // currently done in the functions `create_aws()` and `send_ars()`.
      ace_ac_beat.ac_snoop      = snoop;
      ace_ac_beat.ac_prot       = prot;

      return ace_ac_beat;
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
      repeat (cycles) @(posedge this.drv.snoop.clk_i);
    endtask

    task send_acs(input int n_reads);
      automatic logic rand_success;
      repeat (n_reads) begin
        automatic ace_ac_beat_t ace_ac_beat = new_rand_burst();
        rand_wait(AC_MIN_WAIT_CYCLES, AC_MAX_WAIT_CYCLES);
        drv.send_ac(ace_ac_beat);
      end
    endtask

    task recv_crs(ref logic ac_done);
      while (!ac_done) begin
        automatic ace_cr_beat_t ace_cr_beat;
        automatic ace_cd_beat_t ace_cd_beat;
        rand_wait(CR_MIN_WAIT_CYCLES, CR_MAX_WAIT_CYCLES);
        drv.recv_cr(ace_cr_beat);
        if (!ace_cr_beat.cr_resp.error & ace_cr_beat.cr_resp.dataTransfer)
          drv.recv_cd(ace_cd_beat);
      end
    endtask

    task recv_cds(ref logic ac_done);
      while (!ac_done) begin
        automatic ace_cd_beat_t ace_cd_beat;
        rand_wait(CD_MIN_WAIT_CYCLES, CD_MAX_WAIT_CYCLES);
        drv.recv_cd(ace_cd_beat);
      end
    endtask

    // Issue n_reads random read transactions to an address range
    task run(input int n_reads);
      automatic logic  ac_done = 1'b0;
      fork
        begin
          send_acs(n_reads);
          ac_done = 1'b1;
        end
        recv_crs(ac_done);
      join
    endtask

  endclass

  class snoop_rand_slave #(
    // AXI interface parameters
    parameter int   AW = 32,
    parameter int   DW = 32,
    // Stimuli application and test time
    parameter time  TA = 0ps,
    parameter time  TT = 0ps,
    parameter bit   RAND_RESP = 0,
    // Upper and lower bounds on wait cycles on Ax, W, and resp (R and B) channels
    parameter int   AC_MIN_WAIT_CYCLES = 0,
    parameter int   AC_MAX_WAIT_CYCLES = 100,
    parameter int   CR_MIN_WAIT_CYCLES = 0,
    parameter int   CR_MAX_WAIT_CYCLES = 5,
    parameter int   CD_MIN_WAIT_CYCLES = 0,
    parameter int   CD_MAX_WAIT_CYCLES = 20
  );
    typedef snoop_test::snoop_driver #(
      .AW(AW), .DW(DW), .TA(TA), .TT(TT)
    ) snoop_driver_t;
    typedef snoop_driver_t::ace_ac_beat_t ace_ac_beat_t;
    typedef snoop_driver_t::ace_cr_beat_t ace_cr_beat_t;
    typedef snoop_driver_t::ace_cd_beat_t ace_cd_beat_t;

    typedef logic [AW-1:0] addr_t;

    snoop_driver_t          drv;
    ace_ac_beat_t             ace_ac_queue[$];
    int unsigned          cd_wait_cnt;

    function new(
      virtual SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH(AW),
        .SNOOP_DATA_WIDTH(DW)
      ) snoop
    );
      this.drv = new(snoop);
      this.cd_wait_cnt = 0;
      this.reset();
    endfunction

    function void reset();
      this.drv.reset_slave();
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
      repeat (cycles) @(posedge this.drv.snoop.clk_i);
    endtask

    task recv_acs();
      forever begin
        automatic ace_ac_beat_t ace_ac_beat;
        rand_wait(AC_MIN_WAIT_CYCLES, AC_MAX_WAIT_CYCLES);
        drv.recv_ac(ace_ac_beat);
        ace_ac_queue.push_back(ace_ac_beat);
      end
    endtask

    task send_crs();
      forever begin
        automatic logic rand_success;
        automatic ace_ac_beat_t ace_ac_beat;
        automatic ace_cr_beat_t  ace_cr_beat = new;
        wait (ace_ac_queue.size() > 0);
        ace_ac_beat         = ace_ac_queue.pop_front();
        if(ace_ac_beat.ac_snoop == snoop_pkg::CLEAN_INVALID) begin
          ace_cr_beat.cr_resp = 0;
        end else begin
          ace_cr_beat.cr_resp[4:2] = $urandom_range(0,3'b111);//$urandom_range(0,5'b11111);
          ace_cr_beat.cr_resp[1]   = 'b0;
          ace_cr_beat.cr_resp[0]   = $urandom_range(0,1);
        end
        rand_wait(CR_MIN_WAIT_CYCLES, CR_MAX_WAIT_CYCLES);
        drv.send_cr(ace_cr_beat);
        if (ace_cr_beat.cr_resp.dataTransfer && !ace_cr_beat.cr_resp.error) begin
          cd_wait_cnt++;
        end
      end
    endtask

    task send_cds();
      forever begin
        automatic logic rand_success;
        automatic ace_ac_beat_t ace_ac_beat;
        automatic ace_cd_beat_t  ace_cd_beat = new;
        automatic addr_t    byte_addr;
        wait (cd_wait_cnt > 0);
        // random response
        ace_cd_beat.cd_data = $urandom();
        ace_cd_beat.cd_last = 1'b0;
        rand_wait(CD_MIN_WAIT_CYCLES, CD_MAX_WAIT_CYCLES);
        drv.send_cd(ace_cd_beat);
        ace_cd_beat.cd_data = $urandom();
        ace_cd_beat.cd_last = 1'b1;
        rand_wait(CD_MIN_WAIT_CYCLES, CD_MAX_WAIT_CYCLES);
        drv.send_cd(ace_cd_beat);
        cd_wait_cnt--;
      end
    endtask

    task run();
      fork
        recv_acs();
        send_crs();
        send_cds();
      join
    endtask

  endclass

  /// Snoop Monitor.
  class snoop_monitor #(
    parameter AW = 32,
    parameter DW = 32,
    parameter time TA = 0ns , // stimuli application time
    parameter time TT = 0ns   // stimuli test time
  );

    typedef snoop_test::snoop_driver #(
      .AW(AW), .DW(DW), .TA(TA), .TT(TT)
    ) snoop_driver_t;

    typedef snoop_driver_t::ace_ac_beat_t ace_ac_beat_t;
    typedef snoop_driver_t::ace_cd_beat_t ace_cd_beat_t;
    typedef snoop_driver_t::ace_cr_beat_t ace_cr_beat_t;

    snoop_driver_t          drv;
    mailbox ac_mbx = new, cd_mbx = new, cr_mbx = new;

    virtual SNOOP_BUS_DV #(
      .SNOOP_ADDR_WIDTH(AW),
      .SNOOP_DATA_WIDTH(DW)
    ) snoop;

    function new(
      virtual SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH(AW),
        .SNOOP_DATA_WIDTH(DW)
      ) snoop
    );
      this.drv = new(snoop);
    endfunction

    task monitor;
      fork
        // AC
        forever begin
          automatic ace_ac_beat_t beat;
          this.drv.mon_ac(beat);
          ac_mbx.put(beat);
        end
        // CR
        forever begin
          automatic ace_cr_beat_t beat;
          this.drv.mon_cr(beat);
          cr_mbx.put(beat);
        end
        // CD
        forever begin
          automatic ace_cd_beat_t beat;
          this.drv.mon_cd(beat);
          cd_mbx.put(beat);
        end
      join
    endtask
  endclass

endpackage


// non synthesisable ace snoop logger module
// this module logs the activity of the input snoop channel
// the log files will be found in "./ace_log/<LoggerName>/"
// one log file for all writes
// a log file per id for the reads
// atomic transactions with read response are injected into the corresponding log file of the read
module snoop_chan_logger #(
  parameter time TestTime     = 8ns,          // Time after clock, where sampling happens
  parameter string LoggerName = "snoop_logger", // name of the logger
  parameter type ac_chan_t    = logic,        // ACE AC type
  parameter type cr_chan_t    = logic,        // ACE CR type
  parameter type cd_chan_t    = logic         // ACE CD type
) (
  input logic     clk_i,     // Clock
  input logic     rst_ni,    // Asynchronous reset active low, when `1'b0` no sampling
  input logic     end_sim_i, // end of simulation
  // AC channel
  input ac_chan_t ac_chan_i,
  input logic     ac_valid_i,
  input logic     ac_ready_i,
  // CR channel
  input cr_chan_t cr_chan_i,
  input logic     cr_valid_i,
  input logic     cr_ready_i,
  // CD channel
  input cd_chan_t cd_chan_i,
  input logic     cd_valid_i,
  input logic     cd_ready_i
);

  // queues for writes and reads
  ac_chan_t ac_queues[$];
  cr_chan_t  cr_queues[$];
  cd_chan_t  cd_queues[$];

  // channel sampling into queues
  always @(posedge clk_i) #TestTime begin : proc_channel_sample
    automatic ac_chan_t ac_beat;
    automatic int       fd;
    automatic string    log_file;
    automatic string    log_str;
    // only execute when reset is high
    if (rst_ni) begin
      // AC channel
      if (ac_valid_i && ac_ready_i) begin
        log_file = $sformatf("./ace_log/%s/snoop_read.log", LoggerName);
        fd = $fopen(log_file, "a");
        if (fd) begin
          log_str = $sformatf("%0t> AC, ADDR: 0x%h SNOOP %b, PROT %b", $time, ac_chan_i.addr, ac_chan_i.snoop, ac_chan_i.prot);
          $fdisplay(fd, log_str);
          $fclose(fd);
        end
        ac_beat.addr   = ac_chan_i.addr;
        ac_beat.snoop  = ac_chan_i.snoop;
        ac_beat.prot   = ac_chan_i.prot;
        ac_queues.push_back(ac_beat);
      end
      // CR channel
      if (cr_valid_i && cr_ready_i) begin
        cr_queues.push_back(cr_chan_i);
      end
      // CD channel
      if (cd_valid_i && cd_ready_i) begin
        cd_queues.push_back(cd_chan_i);
      end
    end
  end

  initial begin : proc_log
    automatic string       log_name;
    automatic string       log_string;
    automatic ac_chan_t    ac_beat;
    automatic cr_chan_t    cr_beat;
    automatic cd_chan_t    cd_beat;
    automatic int unsigned no_r_beat;
    automatic int          fd;

    no_r_beat = 0;

    // make the log dirs
    log_name = $sformatf("mkdir -p ./ace_log/%s/", LoggerName);
    $system(log_name);

    // open log files
    log_name = $sformatf("./ace_log/%s/snoop_read.log", LoggerName);
    fd = $fopen(log_name, "w");
    if (fd) begin
      $display("File was opened successfully : %0d", fd);
      $fclose(fd);
    end else
      $display("File was NOT opened successfully : %0d", fd);

    // on each clock cycle update the logs if there is something in the queues
    wait (rst_ni);
    while (!end_sim_i) begin
      @(posedge clk_i);

      // update the read log files
      while (ac_queues.size() != 0 && cr_queues.size() != 0) begin
        ac_beat = ac_queues.pop_front();
        cr_beat  = cr_queues.pop_front();
        log_name = $sformatf("./ace_log/%s/snoop_read.log", LoggerName);
        fd = $fopen(log_name, "a");
        if (fd) begin
          log_string = $sformatf("%0t ns> CR %d RESP: %b, ",
                          $time, no_r_beat, cr_beat);
          $fdisplay(fd, log_string);
          if (cr_beat.dataTransfer && !cr_beat.error) begin
            while(cd_queues.size() != 0) begin
              cd_beat = cd_queues.pop_front();
              log_string = $sformatf("%0t ns> CD %d DATA: %h, ",
                              $time, no_r_beat, cd_beat.data);
              $fdisplay(fd, log_string);
            end
          end
          $fclose(fd);
        end
        no_r_beat++;
      end
    end
    $fclose(fd);
  end
endmodule
