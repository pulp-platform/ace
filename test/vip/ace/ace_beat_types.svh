`ifndef _ACE_TEST_PKG
*** INCLUDED IN ace_test_pkg ***
`endif
/// The data transferred on a beat on the AW/AR channels.
class ace_ax_beat #(
    parameter AW   = 32,
    parameter IW   = 8 ,
    parameter UW   = 1,
    parameter SNP_W = 4
);
    rand logic [IW-1:0]    id       = '0;
    rand logic [AW-1:0]    addr     = '0;
    logic      [7:0]       len      = '0;
    logic      [2:0]       size     = '0;
    logic      [1:0]       burst    = '0;
    logic                  lock     = '0;
    logic      [3:0]       cache    = '0;
    logic      [2:0]       prot     = '0;
    rand logic [3:0]       qos      = '0;
    logic      [3:0]       region   = '0;
    rand logic [UW-1:0]    user     = '0;
    rand logic [1:0]       bar      = '0;
    rand logic [1:0]       domain   = '0;
    rand logic [SNP_W-1:0] snoop    = '0;
endclass

class ace_aw_beat #(
    parameter AW = 32,
    parameter IW = 8 ,
    parameter UW = 1
) extends ace_ax_beat #(
  .AW(AW), .IW(IW), .UW(UW), .SNP_W(3)
);
    logic      [5:0] atop     = '0;
    rand logic       awunique = '0;
endclass

class ace_ar_beat #(
    parameter AW = 32,
    parameter IW = 8 ,
    parameter UW = 1
) extends ace_ax_beat #(
  .AW(AW), .IW(IW), .UW(UW), .SNP_W(4)
);
endclass

class ace_ax_comb_beat #(
    parameter AW = 32,
    parameter IW = 8 ,
    parameter UW = 1
) extends ace_ax_beat #(
  .AW(AW), .IW(IW), .UW(UW), .SNP_W(4)
);
    logic      [5:0] atop     = '0;
    rand logic       awunique = '0;
endclass

class ace_r_beat #(
    parameter DW = 32,
    parameter IW = 8 ,
    parameter UW = 1
);
    rand logic [IW-1:0] id   = '0;
    rand logic [DW-1:0] data = '0;
    ace_pkg::rresp_t    resp = '0;
    logic               last = '0;
    rand logic [UW-1:0] user = '0;
endclass

class ace_w_beat #(
    parameter DW = 32,
    parameter UW = 1
);
    rand logic [DW-1:0]   data = '0;
    rand logic [DW/8-1:0] strb = '0;
    logic                 last = '0;
    rand logic [UW-1:0]   user = '0;
endclass

class ace_b_beat #(
    parameter IW = 8,
    parameter UW = 1
);
    rand logic [IW-1:0] id   = '0;
    logic      [1:0]    resp = '0;
    rand logic [UW-1:0] user = '0;
endclass