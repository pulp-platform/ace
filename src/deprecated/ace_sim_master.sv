package ace_sim_master;

import axi_test::*;

typedef enum logic [3:0] {
    AR_READ_NO_SNOOP,
    AR_READ_ONCE,
    AR_READ_SHARED,
    AR_READ_CLEAN,
    AR_READ_NOT_SHARED_DIRTY,
    AR_READ_UNIQUE,
    AR_CLEAN_UNIQUE,
    AR_MAKE_UNIQUE,
    AR_CLEAN_SHARED,
    AR_CLEAN_INVALID,
    AR_MAKE_INVALID,
    AR_BARRIER,
    AR_DVM_COMPLETE,
    AR_DVM_MESSAGE
} ar_snoop_e;

ar_snoop_e ar_unsupported_ops[] = '{AR_READ_NO_SNOOP, AR_BARRIER, AR_DVM_COMPLETE, AR_DVM_MESSAGE};

typedef enum logic [2:0] {
    AW_WRITE_NO_SNOOP,
    AW_WRITE_UNIQUE,
    AW_WRITE_LINE_UNIQUE,
    AW_WRITE_CLEAN,
    AW_WRITE_BACK,
    AW_EVICT,
    AW_WRITE_EVICT,
    AW_BARRIER
} aw_snoop_e;

aw_snoop_e aw_unsupported_ops[] = '{AW_WRITE_NO_SNOOP, AW_BARRIER};

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
    rand logic [3:0]    ax_snoop    = '0; // AW channel requires 3 bits, AR channel requires 4 bits
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

/// The data transferred on a beat on the AC channel.
/// Plus an extra signal to determine data transfer
class ace_ac_beat #(
    parameter AW = 32
);
    logic [AW-1:0] ac_addr = '0;
    logic [3:0] ac_snoop        = '0;
    logic [2:0] ac_prot         = '0;
    logic data_transfer         = '0;
endclass

/// The data transferred on a beat on the CD channel.
class ace_cd_beat #(
    parameter DW = 32
);
    rand logic [DW-1:0] cd_data = '0;
    logic cd_last;
endclass

/// The data transferred on a beat on the CR channel.
class ace_cr_beat;
    ace_pkg::crresp_t cr_resp = '0;
endclass

class ace_driver #(
    parameter int  AW    = 32,
    parameter int  DW    = 32,
    parameter int  AC_AW = AW,
    parameter int  CD_DW = DW,
    parameter int  IW    = 8,
    parameter int  UW    = 1,
    parameter time TA    = 0ns, // stimuli application time
    parameter time TT    = 0ns  // stimuli test time
);
    virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH (AW),
        .AXI_DATA_WIDTH (DW),
        .AXI_ID_WIDTH   (IW),
        .AXI_USER_WIDTH (UW)
    ) ace;

    virtual SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH (AC_AW),
        .SNOOP_DATA_WIDTH (CD_DW)
    ) snoop;

    typedef ace_ax_beat #(.AW(AW), .IW(IW), .UW(UW)) ax_beat_t;
    typedef axi_w_beat  #(.DW(DW), .UW(UW))          w_beat_t;
    typedef axi_b_beat  #(.IW(IW), .UW(UW))          b_beat_t;
    typedef ace_r_beat  #(.DW(DW), .IW(IW), .UW(UW)) r_beat_t;
    typedef ace_ac_beat #(.AW(AC_AW)) ac_beat_t;
    typedef ace_cd_beat #(.DW(CD_DW)) cd_beat_t;
    typedef ace_cr_beat            cr_beat_t;

    function new (
      virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH (AW),
        .AXI_DATA_WIDTH (DW),
        .AXI_ID_WIDTH   (IW),
        .AXI_USER_WIDTH (UW)
      ) ace,
      virtual SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH (AC_AW),
        .SNOOP_DATA_WIDTH (CD_DW)
      ) snoop
    );
      this.ace   = ace;
      this.snoop = snoop;
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
        ace.aw_snoop    <= '0;
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
        ace.ar_snoop    <= '0;
        ace.ar_bar      <= '0;
        ace.ar_domain   <= '0;
        ace.ar_valid    <= '0;
        ace.r_ready     <= '0;
        ace.wack        <= '0;
        ace.rack        <= '0;
        snoop.ac_ready  <= '0;
        snoop.cr_valid  <= '0;
        snoop.cr_resp   <= '0;
        snoop.cd_valid  <= '0;
        snoop.cd_data   <= '0;
        snoop.cd_last   <= '0;
    endfunction

    function void reset_slave();
        ace.aw_ready   <= '0;
        ace.w_ready    <= '0;
        ace.b_id       <= '0;
        ace.b_resp     <= '0;
        ace.b_user     <= '0;
        ace.b_valid    <= '0;
        ace.ar_ready   <= '0;
        ace.r_id       <= '0;
        ace.r_data     <= '0;
        ace.r_resp     <= '0;
        ace.r_last     <= '0;
        ace.r_user     <= '0;
        ace.r_valid    <= '0;
        snoop.ac_valid <= '0;
        snoop.ac_addr  <= '0;
        snoop.ac_prot  <= '0;
        snoop.ac_snoop <= '0;
        snoop.cr_ready <= '0;
        snoop.cd_ready <= '0;
    endfunction

    task cycle_start;
        #TT;
    endtask

    task cycle_end;
        @(posedge ace.clk_i);
    endtask

    /// Issue a beat on the AW channel.
    task send_aw (
        input ax_beat_t beat
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
        ace.aw_snoop    <= #TA beat.ax_snoop;
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
        ace.aw_snoop    <= #TA '0;
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
        input ax_beat_t beat
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
        ace.ar_snoop    <= #TA beat.ax_snoop;
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
        ace.ar_snoop    <= #TA '0;
        ace.ar_bar      <= #TA '0;
        ace.ar_domain   <= #TA '0;
    endtask

    /// Issue a beat on the R channel.
    task send_r (
        input r_beat_t beat
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
        output ax_beat_t beat
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
        beat.ax_snoop     = ace.aw_snoop;
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
        ace.wack    <= #TA 1;
        cycle_start();
        ace.wack <= #TA 0;
    endtask

    /// Wait for a beat on the AR channel.
    task recv_ar (
        output ax_beat_t beat
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
        beat.ax_snoop   = ace.ar_snoop;
        beat.ax_bar     = ace.ar_bar;
        beat.ax_domain  = ace.ar_domain;
        cycle_end();
        ace.ar_ready  <= #TA 0;
    endtask

    /// Wait for a beat on the R channel.
    task recv_r (
        output r_beat_t beat
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
        ace.rack    <= #TA ace.r_last;
        cycle_start();
        ace.rack <= #TA 0;
    endtask

    /// Issue a beat on the AC channel.
    task send_ac (
        input ac_beat_t beat
    );
        snoop.ac_valid <= #TA 1;
        snoop.ac_addr  <= #TA beat.ac_addr;
        snoop.ac_snoop <= #TA beat.ac_snoop;
        snoop.ac_prot  <= #TA beat.ac_prot;
        cycle_start();
        while (snoop.ac_ready != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        snoop.ac_valid <= #TA '0;
        snoop.ac_addr  <= #TA '0;
        snoop.ac_snoop <= #TA '0;
        snoop.ac_prot  <= #TA '0;
    endtask

    /// Issue a beat on the CR channel.
    task send_cr (
        input cr_beat_t beat
    );
        snoop.cr_valid <= #TA 1;
        snoop.cr_resp  <= #TA beat.cr_resp;
        cycle_start();
        while (snoop.cr_ready != 1) begin cycle_end(); cycle_start(); end
        cycle_end();
        snoop.cr_valid <= #TA '0;
        snoop.cr_resp  <= #TA '0;
    endtask

    /// Issue a beat on the CD channel.
    task send_cd (
        input cd_beat_t beat
    );
      snoop.cd_valid <= #TA 1;
      snoop.cd_data  <= #TA beat.cd_data;
      snoop.cd_last  <= #TA beat.cd_last;
      cycle_start();
      while (snoop.cd_ready != 1) begin cycle_end(); cycle_start(); end
      cycle_end();
      snoop.cd_valid <= #TA '0;
      snoop.cd_data  <= #TA '0;
      snoop.cd_last  <= #TA '0;
    endtask

    /// Wait for a beat on the AC channel.
    task recv_ac (
        output ac_beat_t beat,
        ref logic sim_done
    );
        snoop.ac_ready <= #TA 1;
        cycle_start();
        while ((snoop.ac_valid != 1) && !sim_done) begin
            cycle_end(); cycle_start();
        end
        if (!sim_done) begin
            beat          = new;
            beat.ac_addr  = snoop.ac_addr;
            beat.ac_snoop = snoop.ac_snoop;
            beat.ac_prot  = snoop.ac_prot;
            cycle_end();
            snoop.ac_ready <= #TA 0;
        end
    endtask

    /// Wait for a beat on the CR channel.
    task recv_cr (
        output cr_beat_t beat
    );
        snoop.cr_ready <= #TA 1;
        cycle_start();
        while (snoop.cr_valid != 1) begin cycle_end(); cycle_start(); end
        beat         = new;
        beat.cr_resp = snoop.cr_resp;
        cycle_end();
        snoop.cr_ready <= #TA 0;
    endtask

    /// Wait for a beat on the CD channel.
    task recv_cd (
        output cd_beat_t beat
    );
        beat         = new;
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
        output ac_beat_t beat
    );
        cycle_start();
        while (!(snoop.ac_valid && snoop.ac_ready)) begin cycle_end(); cycle_start(); end
        beat          = new;
        beat.ac_addr  = snoop.ac_addr;
        beat.ac_snoop = snoop.ac_snoop;
        beat.ac_prot  = snoop.ac_prot;
        cycle_end();
    endtask

    /// Monitor the CR channel and return the next beat.
    task mon_cr (
        output cr_beat_t beat
    );
        cycle_start();
        while (!(snoop.cr_valid && snoop.cr_ready)) begin cycle_end(); cycle_start(); end
        beat         = new;
        beat.cr_resp = snoop.cr_resp;
        cycle_end();
    endtask

    /// Monitor the CD channel and return the next beat.
    task mon_cd (
        output cd_beat_t beat
    );
        cycle_start();
        while (!(snoop.cd_valid && snoop.cd_ready)) begin cycle_end(); cycle_start(); end
        beat         = new;
        beat.cd_data = snoop.cd_data;
        beat.cd_last = snoop.cd_last;
        cycle_end();
    endtask

    /// Monitor the AW channel and return the next beat.
    task mon_aw (
        output ax_beat_t beat
    );
        cycle_start();
        while (!(ace.aw_valid && ace.aw_ready)) begin cycle_end(); cycle_start(); end
        beat             = new;
        beat.ax_id       = ace.aw_id;
        beat.ax_addr     = ace.aw_addr;
        beat.ax_len      = ace.aw_len;
        beat.ax_size     = ace.aw_size;
        beat.ax_burst    = ace.aw_burst;
        beat.ax_lock     = ace.aw_lock;
        beat.ax_cache    = ace.aw_cache;
        beat.ax_prot     = ace.aw_prot;
        beat.ax_qos      = ace.aw_qos;
        beat.ax_region   = ace.aw_region;
        beat.ax_atop     = ace.aw_atop;
        beat.ax_user     = ace.aw_user;
        beat.ax_snoop    = ace.aw_snoop;
        beat.ax_bar      = ace.aw_bar;
        beat.ax_domain   = ace.aw_domain;
        beat.ax_awunique = ace.aw_awunique;
        cycle_end();
    endtask

    /// Monitor the W channel and return the next beat.
    task mon_w (
        output w_beat_t beat
    );
        cycle_start();
        while (!(ace.w_valid && ace.w_ready)) begin cycle_end(); cycle_start(); end
        beat        = new;
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
        beat        = new;
        beat.b_id   = ace.b_id;
        beat.b_resp = ace.b_resp;
        beat.b_user = ace.b_user;
        cycle_end();
    endtask

    /// Monitor the AR channel and return the next beat.
    task mon_ar (
        output ax_beat_t beat
    );
        cycle_start();
        while (!(ace.ar_valid && ace.ar_ready)) begin cycle_end(); cycle_start(); end
        beat            = new;
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
        beat.ax_snoop   = ace.ar_snoop;
        beat.ax_bar     = ace.ar_bar;
        beat.ax_domain  = ace.ar_domain;
        cycle_end();
    endtask

    /// Monitor the R channel and return the next beat.
    task mon_r (
        output r_beat_t beat
    );
        cycle_start();
        while (!(ace.r_valid && ace.r_ready)) begin cycle_end(); cycle_start(); end
        beat        = new;
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
    // Snoop interface parameters
    parameter int   AC_AW = AW, // AC addr width
    parameter int   CD_DW = DW, // CD data width
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
    parameter bit   AXI_BURST_FIXED   = 1'b0,
    parameter bit   AXI_BURST_INCR    = 1'b1,
    parameter bit   AXI_BURST_WRAP    = 1'b1,
    parameter bit   UNIQUE_IDS        = 1'b0, // guarantee that the ID of each transaction is
                                              // unique among all in-flight transactions in the
                                              // same direction
    parameter int   AC_MIN_WAIT_CYCLES = 0,
    parameter int   AC_MAX_WAIT_CYCLES = 100,
    parameter int   CR_MIN_WAIT_CYCLES = 0,
    parameter int   CR_MAX_WAIT_CYCLES = 5,
    parameter int   CD_MIN_WAIT_CYCLES = 0,
    parameter int   CD_MAX_WAIT_CYCLES = 20,

    parameter int   MEM_ADDR_SPACE  = 8, // Address space for internal memory
    parameter int   CACHELINE_WIDTH = 0, // How many bytes in a cache line

    // Dependent parameters, do not override.
    parameter int   CACHELINE_WORD_SIZE = DW/8, // How many bytes in one word
    parameter int   AXI_STRB_WIDTH      = DW/8,
    parameter int   N_AXI_IDS           = 2**IW
);

    typedef ace_driver #(
        .AW(AW), .DW(DW), .IW(IW), .UW(UW), .TA(TA), .TT(TT)
    ) ace_driver_t;

    typedef logic [AW-1:0]                addr_t;
    typedef logic [MEM_ADDR_SPACE-1:0]    mem_addr_t;
    typedef logic [DW-1:0]                data_t;
    typedef logic [CD_DW-1:0]             cd_data_t;
    typedef logic [IW-1:0]                id_t;
    typedef logic [7:0]                   byte_t;

    // Internal "cache" memory
    byte_t memory_q[mem_addr_t];

    // Bitmask to check whether cache line boundary is crossed
    static addr_t CLINE_BOUNDARY_MASK = ~((1 << $clog2(CACHELINE_WIDTH * 8)) - 1);

    localparam int CLINE_WIDTH_PER_DW    = CACHELINE_WIDTH / (DW / 8);
    localparam int CLINE_WIDTH_PER_CD_DW = CACHELINE_WIDTH / (CD_DW / 8);

    // Driver
    ace_driver_t   ace_drv;

    semaphore cnt_sem;

    // List of allowed burst types
    axi_pkg::burst_t allowed_bursts[$];

    // Max value for AxSIZE
    localparam unsigned max_size = $clog2(DW);
    // AxLEN for full cache line transaction
    localparam unsigned cline_len = CACHELINE_WIDTH / CACHELINE_WORD_SIZE;

    int unsigned r_flight_cnt[N_AXI_IDS-1:0],
                 w_flight_cnt[N_AXI_IDS-1:0],
                 tot_r_flight_cnt,
                 tot_w_flight_cnt;

    ace_driver_t::ax_beat_t aw_ace_queue[$], w_queue[$];
    ace_driver_t::ac_beat_t ac_cr_queue[$], ac_cd_queue[$];

    typedef struct packed {
        addr_t              addr_begin;
        addr_t              addr_end;
        axi_pkg::mem_type_t mem_type;
    } mem_region_t;

    mem_region_t mem_map[$];

    function new(
        virtual ACE_BUS_DV #(
            .AXI_ADDR_WIDTH (AW),
            .AXI_DATA_WIDTH (DW),
            .AXI_ID_WIDTH   (IW),
            .AXI_USER_WIDTH (UW)
        ) ace,
        virtual SNOOP_BUS_DV #(
            .SNOOP_ADDR_WIDTH (AW),
            .SNOOP_DATA_WIDTH (DW)
        ) snoop
    );
        this.ace_drv = new(ace, snoop);
        this.cnt_sem = new(1);
        this.reset();
        if (AXI_BURST_FIXED) begin
            this.allowed_bursts.push_back(axi_pkg::BURST_FIXED);
        end
        if (AXI_BURST_INCR) begin
            this.allowed_bursts.push_back(axi_pkg::BURST_INCR);
        end
        if (AXI_BURST_WRAP) begin
            this.allowed_bursts.push_back(axi_pkg::BURST_WRAP);
        end
        assert(allowed_bursts.size()) else $fatal(1, "At least one burst type has to be specified!");
    endfunction

    function void reset();
        ace_drv.reset_master();
        r_flight_cnt = '{default: 0};
        w_flight_cnt = '{default: 0};
        tot_r_flight_cnt = 0;
        tot_w_flight_cnt = 0;
    endfunction

    function void init_cache_memory();
        for (int addr = 0; addr < 2**MEM_ADDR_SPACE; addr++) begin
            memory_q[addr] = $urandom();
        end
    endfunction

    function void add_memory_region(
        input addr_t addr_begin,
        input addr_t addr_end,
        input axi_pkg::mem_type_t mem_type
    );
        mem_map.push_back({addr_begin, addr_end, mem_type});
    endfunction

    // Generate random AxSize that
    // maps between allowed values
    function axi_pkg::size_t gen_rand_size();
        automatic logic rand_success;
        axi_pkg::size_t size;
        rand_success = std::randomize(size) with {
            size >= 0;
            size <= max_size;
        }; assert(rand_success);
        return size;
    endfunction

    // Generate random AxLen that
    // maps between allowed values
    // AxLEN cannot be wider than cache line width
    function axi_pkg::len_t gen_rand_len(
        input axi_pkg::size_t size,
        input logic snoop_trs,
        input axi_pkg::burst_t burst
    );
        automatic logic rand_success;
        axi_pkg::len_t len;
        if (snoop_trs) begin
            rand_success = std::randomize(len) with {
                len inside {1, 2, 4, 8, 16};
                len <= cline_len;
            }; assert(rand_success);
            if ((burst == axi_pkg::BURST_WRAP) && (len == 1)) begin
                // AxLEN 1 not allowed for wrap bursts
                len = 2;
            end
        end else begin
            if (burst == axi_pkg::BURST_WRAP) begin
                rand_success = std::randomize(len) with {
                    len inside {2, 4, 8, 16};
                }; assert(rand_success);
            end else begin
                len = $urandom_range(1, 256);
            end
        end
        return len;
    endfunction

    function axi_pkg::burst_t get_rand_burst();
        automatic logic rand_success;
        axi_pkg::burst_t burst;
        rand_success = std::randomize(burst) with {
            burst inside {this.allowed_bursts};
        }; assert(rand_success);
        return burst;
    endfunction

    function ace_driver_t::ax_beat_t new_rand_burst(input logic is_read);

        automatic ace_driver_t::ax_beat_t ax_ace_beat = new;
        automatic axi_pkg::cache_t        cache;
        automatic axi_pkg::burst_t        burst;
        automatic          id_t           id;
        automatic axi_pkg::qos_t          qos;
        automatic          addr_t         addr;
        automatic axi_pkg::len_t          len;
        automatic axi_pkg::size_t         size;
        automatic ace_pkg::axbar_t        bar;
        automatic ace_pkg::axdomain_t     domain;
        automatic ace_pkg::arsnoop_t      snoop;
        automatic ace_pkg::awunique_t     awunique;
        automatic mem_region_t            mem_region;
        automatic ar_snoop_e              ar_trs;
        automatic aw_snoop_e              aw_trs;
        
        logic snoop_trs, accepts_dirty, accepts_shared, accepts_dirty_shared;

        cache = axi_pkg::get_arcache(axi_pkg::DEVICE_BUFFERABLE);
        burst = get_rand_burst();
        id    = $urandom();
        qos   = $urandom();


        // Most of ACE transactions are restricted to have
        // a size of the data bus width
        size = max_size;

        awunique  = 1'b0;
        snoop_trs = 1'b1;

        // Accepted RRESP responses
        accepts_dirty        = 1'b0;
        accepts_shared       = 1'b0;
        accepts_dirty_shared = 1'b0;

        if (is_read) begin
            // Read operation
            std::randomize(ar_trs) with
                { !(ar_trs inside {ar_unsupported_ops}); };
            case( ar_trs )
                AR_READ_NO_SNOOP: begin
                    snoop     = ace_pkg::ReadNoSnoop;
                    domain    = 'b00;
                    bar       = 'b00;
                    snoop_trs = 1'b0;
                    size      = gen_rand_size();
                    len       = gen_rand_len(size, snoop_trs, burst);
                end
                AR_READ_ONCE: begin
                    snoop   = ace_pkg::ReadOnce;
                    domain  = 'b01;
                    bar     = 'b00;
                    size    = gen_rand_size();
                    len     = gen_rand_len(size, snoop_trs, burst);
                    accepts_shared = 1'b1;
                end
                AR_READ_SHARED: begin
                    snoop   = ace_pkg::ReadShared;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                    accepts_dirty        = 1'b1;
                    accepts_dirty_shared = 1'b1;
                    accepts_shared       = 1'b1;
                end
                AR_READ_CLEAN: begin
                    snoop   = ace_pkg::ReadClean;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                    accepts_shared = 1'b1;
                end
                AR_READ_NOT_SHARED_DIRTY: begin
                    snoop   = ace_pkg::ReadNotSharedDirty;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                    accepts_dirty  = 1'b1;
                    accepts_shared = 1'b1;
                end
                AR_READ_UNIQUE: begin
                    snoop   = ace_pkg::ReadUnique;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                    accepts_dirty = 1'b1;
                end
                AR_CLEAN_UNIQUE: begin
                    snoop   = ace_pkg::CleanUnique;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AR_MAKE_UNIQUE: begin
                    snoop   = ace_pkg::CleanUnique;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AR_CLEAN_SHARED: begin
                    snoop   = ace_pkg::CleanShared;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                    accepts_shared = 1'b1;
                end
                AR_CLEAN_INVALID: begin
                    snoop   = ace_pkg::CleanInvalid;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AR_MAKE_INVALID: begin
                    snoop   = ace_pkg::MakeInvalid;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AR_BARRIER: begin
                    snoop   = ace_pkg::Barrier;
                    domain  = 'b01;
                    bar     = 'b01;
                    len     = cline_len;
                end
                AR_DVM_COMPLETE: begin
                    snoop   = ace_pkg::DVMComplete;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AR_DVM_MESSAGE: begin
                    snoop   = ace_pkg::DVMMessage;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                default: begin
                    $error("Invalid snoop op enumeration.");
                    snoop   = 'b0000;
                    domain  = 'b00;
                    bar     = 'b00;
                    len     = $urandom();
                end
            endcase
        end else begin
            // Write operation
            std::randomize(aw_trs) with
                { !(aw_trs inside {aw_unsupported_ops}); };
            case( aw_trs )
                AW_WRITE_NO_SNOOP: begin
                    snoop     = ace_pkg::WriteNoSnoop;
                    domain    = 'b00;
                    bar       = 'b00;
                    snoop_trs = 1'b0;
                    size      = gen_rand_size();
                    len       = $urandom();
                end
                AW_WRITE_UNIQUE: begin
                    snoop   = ace_pkg::WriteUnique;
                    domain  = 'b01;
                    bar     = 'b00;
                    size    = gen_rand_size();
                    len     = gen_rand_len(size, snoop_trs, burst);
                end
                AW_WRITE_LINE_UNIQUE: begin
                    snoop   = ace_pkg::WriteLineUnique;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AW_WRITE_CLEAN: begin
                    snoop   = ace_pkg::WriteClean;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AW_WRITE_BACK: begin
                    snoop   = ace_pkg::WriteBack;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AW_EVICT: begin
                    snoop   = ace_pkg::Evict;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AW_WRITE_EVICT: begin
                    snoop   = ace_pkg::WriteEvict;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AR_MAKE_UNIQUE: begin
                    snoop   = ace_pkg::CleanUnique;
                    domain  = 'b01;
                    bar     = 'b00;
                    len     = cline_len;
                end
                AW_BARRIER: begin
                    snoop   = ace_pkg::Barrier;
                    domain  = 'b01;
                    bar     = 'b01;
                    len     = cline_len;
                end
                default: begin
                    $error("Invalid snoop op enumeration.");
                    snoop   = 'b0000;
                    domain  = 'b00;
                    bar     = 'b00;
                    len     = $urandom();
                end
            endcase
        end

        mem_region = '{
            addr_begin: '0,
            addr_end:   '1,
            mem_type: axi_pkg::NORMAL_NONCACHEABLE_BUFFERABLE
        };

        forever begin
            // Randomize address
            addr = $urandom_range(mem_region.addr_begin, mem_region.addr_end);
            addr[AXI_STRB_WIDTH:0] = '0; // align address to word boundary
            if (snoop_trs) begin
                if (burst == axi_pkg::BURST_FIXED) begin
                    $error("FIXED type burst not allowed!");
                end else if (burst == axi_pkg::BURST_INCR) begin
                    // Assert that transaction does not cross cache line boundary
                    if (((addr + ((2**size * len)-1)) & CLINE_BOUNDARY_MASK) == (addr & CLINE_BOUNDARY_MASK)) begin
                        break;
                    end
                end else begin
                    // WRAP bursts should be fine in all situations
                    break;
                end
            end else begin
                break;
            end
        end

        ax_ace_beat.ax_addr     = addr;
        ax_ace_beat.ax_burst    = burst;
        ax_ace_beat.ax_size     = size;
        ax_ace_beat.ax_len      = len - 1;
        ax_ace_beat.ax_id       = id;
        ax_ace_beat.ax_qos      = qos;
        ax_ace_beat.ax_snoop    = snoop;
        ax_ace_beat.ax_bar      = bar;
        ax_ace_beat.ax_domain   = domain;
        ax_ace_beat.ax_awunique = awunique;

        return ax_ace_beat;

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
        repeat (cycles) @(posedge this.ace_drv.ace.clk_i);
    endtask

    task send_ars(input int n_reads);
        automatic logic rand_success;
        repeat (n_reads) begin
            automatic id_t id;
            automatic ace_driver_t::ax_beat_t ar_ace_beat = new_rand_burst(1'b1);
            while (tot_r_flight_cnt >= MAX_READ_TXNS) begin
                rand_wait(1, 1);
            end
            tot_r_flight_cnt++;
            rand_wait(AX_MIN_WAIT_CYCLES, AX_MAX_WAIT_CYCLES);
            ace_drv.send_ar(ar_ace_beat);
        end
        $info("Finish ARs");
    endtask

    task recv_rs(ref logic ar_done);
        while (!(ar_done && tot_r_flight_cnt == 0)) begin
            automatic ace_driver_t::r_beat_t r_ace_beat;
            rand_wait(RESP_MIN_WAIT_CYCLES, RESP_MAX_WAIT_CYCLES);
            if (tot_r_flight_cnt > 0) begin
                ace_drv.recv_r(r_ace_beat);
                if (r_ace_beat.r_last) begin
                    cnt_sem.get();
                    r_flight_cnt[r_ace_beat.r_id]--;
                    tot_r_flight_cnt--;
                    cnt_sem.put();
                end
            end
        end
        $info("Finish Rs");
    endtask

    task create_aws(input int n_writes);
        automatic logic rand_success;
        repeat (n_writes) begin
            automatic bit excl = 1'b0;
            automatic ace_driver_t::ax_beat_t aw_ace_beat;
            aw_ace_beat = new_rand_burst(1'b0);
            while (tot_w_flight_cnt >= MAX_WRITE_TXNS) begin
                rand_wait(1, 1);
            end
            tot_w_flight_cnt++;
            aw_ace_queue.push_back(aw_ace_beat);
            w_queue.push_back(aw_ace_beat);
        end
        $info("Finish AW creates");
    endtask

    task send_aws(ref logic aw_done);
        while (!(aw_done && aw_ace_queue.size() == 0)) begin
            automatic ace_driver_t::ax_beat_t aw_ace_beat;
            wait (aw_ace_queue.size() > 0 || (aw_done && aw_ace_queue.size() == 0));
            aw_ace_beat = aw_ace_queue.pop_front();
            rand_wait(AX_MIN_WAIT_CYCLES, AX_MAX_WAIT_CYCLES);
            ace_drv.send_aw(aw_ace_beat);
        end
        $info("Finish AW sends");
    endtask

    task send_ws(ref logic aw_done);
        while (!(aw_done && w_queue.size() == 0)) begin
            automatic ace_driver_t::ax_beat_t aw_ace_beat;
            automatic addr_t addr;
            static logic rand_success;
            wait (w_queue.size() > 0 || (aw_done && w_queue.size() == 0));
            aw_ace_beat = w_queue.pop_front();
            for (int unsigned i = 0; i < aw_ace_beat.ax_len + 1; i++) begin
                automatic ace_driver_t::w_beat_t w_beat = new;
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
                ace_drv.send_w(w_beat);
            end
        end
        $info("Finish Ws");
    endtask

    task recv_bs(ref logic aw_done);
        while (!(aw_done && tot_w_flight_cnt == 0)) begin
            automatic ace_driver_t::b_beat_t b_beat;
            rand_wait(RESP_MIN_WAIT_CYCLES, RESP_MAX_WAIT_CYCLES);
            ace_drv.recv_b(b_beat);
            cnt_sem.get();
            w_flight_cnt[b_beat.b_id]--;
            tot_w_flight_cnt--;
            cnt_sem.put();
        end
        $info("Finish Bs");
    endtask

    task recv_acs(ref logic sim_done);
        while (!sim_done) begin
            automatic ace_driver_t::ac_beat_t ace_ac_beat;
            rand_wait(AC_MIN_WAIT_CYCLES, AC_MAX_WAIT_CYCLES);
            ace_drv.recv_ac(ace_ac_beat, sim_done);
            if (!sim_done) begin
                // Determine randomly already here whether this AC causes datatransfer
                // Ideally, this would be replaced by looking up the internal cache memory
                ace_ac_beat.data_transfer = $urandom_range(0,1);
                ac_cr_queue.push_back(ace_ac_beat);
                ac_cd_queue.push_back(ace_ac_beat);
            end
        end
        $info("Finish ACs");
    endtask

    task send_crs(ref logic sim_done);
        while (!sim_done) begin
            automatic logic rand_success;
            automatic ace_driver_t::ac_beat_t ace_ac_beat;
            automatic ace_driver_t::cr_beat_t ace_cr_beat = new;
            wait ((ac_cr_queue.size() > 0) || sim_done);
            if (ac_cr_queue.size() > 0) begin
                ace_ac_beat         = ac_cr_queue.pop_front();
                ace_cr_beat.cr_resp[4:2] = $urandom_range(0,3'b111);//$urandom_range(0,5'b11111);
                ace_cr_beat.cr_resp[1]   = 1'b0;
                ace_cr_beat.cr_resp[0]   = ace_ac_beat.data_transfer;
                rand_wait(CR_MIN_WAIT_CYCLES, CR_MAX_WAIT_CYCLES);
                ace_drv.send_cr(ace_cr_beat);
            end
        end
        $info("CR done");
    endtask

    task send_cds(ref logic sim_done);
        while (!sim_done) begin
            automatic logic rand_success;
            automatic ace_driver_t::ac_beat_t ace_ac_beat;
            automatic ace_driver_t::cd_beat_t ace_cd_beat = new;
            automatic addr_t     byte_addr;
            automatic mem_addr_t mem_addr;
            automatic cd_data_t  cd_word;
            wait ((ac_cd_queue.size() > 0) || sim_done);
            if (ac_cd_queue.size() > 0) begin
                ace_ac_beat = ac_cd_queue.pop_front();
                // If data transfer, send CD data. Otherwise, ignore.
                if (ace_ac_beat.data_transfer) begin
                    mem_addr = ace_ac_beat.ac_addr[MEM_ADDR_SPACE-1:0];
                    for (int i = 0; i < CLINE_WIDTH_PER_CD_DW; i++) begin
                        for (int j = 0; j < (CD_DW / 8); j++) begin
                            // Compose CD word that is CD_DW bits wide
                            cd_word[j*(CD_DW/8) +: 8] = memory_q[mem_addr+(i*(CD_DW/8)+j)];
                        end
                        // random response
                        ace_cd_beat.cd_data = cd_word;
                        if (i == (CLINE_WIDTH_PER_CD_DW - 1)) begin
                            ace_cd_beat.cd_last = 1'b1;
                        end else begin
                            ace_cd_beat.cd_last = 1'b0;
                        end
                        rand_wait(CD_MIN_WAIT_CYCLES, CD_MAX_WAIT_CYCLES);
                        ace_drv.send_cd(ace_cd_beat);
                    end
                end
            end
        end
        $info("CD done");
    endtask

    task sim_done_task(ref logic first, ref logic second);
        forever begin
            if (first && second) begin
                break;
            end
            #TT;
        end
    endtask

    // Issue n_reads random read and n_writes random 
    // write transactions to an address range.
    task run(input int n_reads, input int n_writes);
        automatic logic ar_done  = 1'b0,
                        aw_done  = 1'b0,
                        b_done   = 1'b0,
                        r_done   = 1'b0,
                        sim_done = 1'b0;
        fork
            begin
                send_ars(n_reads);
                ar_done = 1'b1;
            end
            begin
                recv_rs(ar_done);
                r_done = 1'b1;
            end
            begin
                create_aws(n_writes);
                aw_done = 1'b1;
            end
            send_aws(aw_done);
            send_ws(aw_done);
            begin
                recv_bs(aw_done);
                b_done = 1'b1;
            end
            begin
                sim_done_task(r_done, b_done);
                sim_done = 1'b1;
            end
            recv_acs(sim_done);
            send_crs(sim_done);
            send_cds(sim_done);
        join
    endtask

endclass

// Datatype for storing the data that was transferred in
// an AXI transaction
class axi_transaction #(
    /// AXI4+ATOP address width
    parameter int unsigned AW = 0,
    /// AXI4+ATOP data width
    parameter int unsigned DW = 0,
);
    rand bit [AW-1:0] address;
    rand bit [DW-1:0] data;
    rand bit          write_en;

    function new();
        address  = 0;
        data     = 0;
        write_en = 0;
    endfunction

endclass


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

    typedef axi_transaction #(
        .AW(AW), .DW(DW)
    ) axi_txn_t;

    typedef ace_driver #(
        .AW(AW), .DW(DW), .IW(IW), .UW(UW), .TA(TT), .TT(TT)
    ) ace_driver_t;

    ace_driver_t ace_drv;
    axi_txn_t axi_txn;
    event new_axi_txn_event;

    ace_driver_t::ax_beat_t new_ax_transaction;

    mailbox aw_mbx = new, w_mbx = new, b_mbx = new,
            ar_mbx = new, r_mbx = new;

    function new(
        virtual ACE_BUS_DV #(
            .AXI_ADDR_WIDTH(AW),
            .AXI_DATA_WIDTH(DW),
            .AXI_ID_WIDTH(IW),
            .AXI_USER_WIDTH(UW)
        ) ace,
        virtual SNOOP_BUS_DV #(
            .SNOOP_ADDR_WIDTH (AW),
            .SNOOP_DATA_WIDTH (DW)
        ) snoop
    );
        this.ace_drv           = new(ace, snoop);
        this.new_axi_txn_event = new();
    endfunction

    task monitor;
        fork
            // AW
            forever begin
                automatic ace_driver_t::ax_beat_t ax;
                this.ace_drv.mon_aw(ax);
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
                automatic ax_beat_t ax;
                this.drv.mon_ar(ax);
                ar_mbx.put(ax);
            end
            // R
            forever begin
                automatic r_beat_t r;
                this.drv.mon_r(r);
                r_mbx.put(r);
                -> txn_event;
            end
        join
    endtask

endclass


class ace_scoreboard #(
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

    typedef axi_transaction #(
        .AW(AW), .DW(DW)
    ) axi_txn_t;

    ref event new_axi_txn_event;
    ref axi_txn_t axi_txn;

    // Monitor interface
    virtual ACE_BUS_DV #(
        .AXI_ADDR_WIDTH ( AW ),
        .AXI_DATA_WIDTH ( DW ),
        .AXI_ID_WIDTH   ( IW ),
        .AXI_USER_WIDTH ( UW )
    ) ace;

    /// New constructor
    function new(
        ref event e,
        ref axi_txn_t t
    );
      this.new_axi_txn_event = e;
      this.axi_txn           = t;
    endfunction

endpackage