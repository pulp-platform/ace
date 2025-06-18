`include "ace/typedef.svh"
`include "ace/assign.svh"

`timescale 1ns/1ps

module tb_ace_ccu_snoop_interconnect import ace_pkg::*; (

);

    localparam time CyclTime = 10ns;
    localparam time ApplTime =  2ns;
    localparam time TestTime =  8ns;

    localparam int unsigned AxiAddrWidth = 64;
    localparam int unsigned AxiDataWidth = 64;

    localparam int unsigned TbNumMst = 4;

    typedef snoop_test::snoop_rand_slave #(
    .AW ( AxiAddrWidth ),
    .DW ( AxiDataWidth ),
    .TA ( ApplTime),
    .TT ( TestTime),
    .RAND_RESP ( '0),
    .AC_MIN_WAIT_CYCLES ( 2),
    .AC_MAX_WAIT_CYCLES ( 15),
    .CR_MIN_WAIT_CYCLES ( 2),
    .CR_MAX_WAIT_CYCLES ( 15),
    .CD_MIN_WAIT_CYCLES ( 2),
    .CD_MAX_WAIT_CYCLES ( 15)
    ) snoop_rand_slave_t;

    typedef snoop_test::snoop_rand_master #(
        .AW ( AxiAddrWidth ),
        .DW ( AxiDataWidth ),
        .TA ( ApplTime),
        .TT ( TestTime),
        .AC_MIN_WAIT_CYCLES ( 2),
        .AC_MAX_WAIT_CYCLES ( 15),
        .CR_MIN_WAIT_CYCLES ( 2),
        .CR_MAX_WAIT_CYCLES ( 15),
        .CD_MIN_WAIT_CYCLES ( 2),
        .CD_MAX_WAIT_CYCLES ( 15)
    ) snoop_rand_master_t;

    typedef logic [AxiAddrWidth-1:0] addr_t;
    typedef logic [AxiDataWidth-1:0] data_t;

    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
    `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
    `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)


    logic clk;
    logic rst_n;

    task cycle_start;
      #(ApplTime);
    endtask

    task cycle_end;
      @(posedge clk);
    endtask

    // snoop structs
    snoop_req_t  [TbNumMst-1:0] inp_snoop_req;
    snoop_resp_t [TbNumMst-1:0] inp_snoop_resp;
    snoop_req_t  [TbNumMst-1:0] oup_snoop_req;
    snoop_resp_t [TbNumMst-1:0] oup_snoop_resp;

    SNOOP_BUS #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth      )
    ) inp_snoop [TbNumMst-1:0] ();

    SNOOP_BUS #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth      )
    ) oup_snoop [TbNumMst-1:0] ();

    SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth      )
    ) inp_snoop_dv [TbNumMst-1:0](clk);

    SNOOP_BUS_DV #(
        .SNOOP_ADDR_WIDTH ( AxiAddrWidth      ),
        .SNOOP_DATA_WIDTH ( AxiDataWidth      )
    ) oup_snoop_dv [TbNumMst-1:0](clk);

    for (genvar i = 0; i < TbNumMst; i++) begin : gen_conn_dv_snoop
        `SNOOP_ASSIGN(inp_snoop[i], inp_snoop_dv[i])
        `SNOOP_ASSIGN(oup_snoop_dv[i], oup_snoop[i])
        `SNOOP_ASSIGN_TO_REQ(inp_snoop_req[i], inp_snoop[i])
        `SNOOP_ASSIGN_FROM_RESP(inp_snoop[i], inp_snoop_resp[i])
        `SNOOP_ASSIGN_FROM_REQ(oup_snoop[i], oup_snoop_req[i])
        `SNOOP_ASSIGN_TO_RESP(oup_snoop_resp[i], oup_snoop[i])
    end

    snoop_rand_master_t snoop_rand_master [TbNumMst];
    for (genvar i = 0; i < TbNumMst; i++) begin : gen_rand_snoop_mst
        initial begin
            snoop_rand_master[i] = new( inp_snoop_dv[i] );
            snoop_rand_master[i].reset();
            @(posedge rst_n);
            snoop_rand_master[i].run(1024);
        end
    end

    snoop_rand_slave_t snoop_rand_slave [TbNumMst];
    for (genvar i = 0; i < TbNumMst; i++) begin : gen_rand_snoop_slv
        initial begin
            snoop_rand_slave[i] = new( oup_snoop_dv[i] );
            snoop_rand_slave[i].reset();
            @(posedge rst_n);
            snoop_rand_slave[i].run();
        end
    end

    initial begin : rst_gen
        rst_n = 1'b0;

        repeat (5) @(negedge clk);

        rst_n = 1'b1;
    end

    initial begin : clk_gen
        clk = 1'b0;
        forever #(CyclTime/2) clk = !clk;
    end

    logic [TbNumMst-1:0][TbNumMst-1:0] inp_sel;

    logic [TbNumMst-1:0] sel_done;

    initial begin
        @(posedge rst_n);
        cycle_start();
        while (sel_done != '1) begin
            cycle_end();
            cycle_start();
        end
        cycle_end();
        $finish;
    end

    logic [TbNumMst-1:0] sel_done;

    initial begin
        @(posedge rst_n);
        cycle_start();
        while (sel_done != '1) begin
            cycle_end();
            cycle_start();
        end
        cycle_end();
        $finish;
    end


    for (genvar i = 0; i < TbNumMst; i++) begin : gen_sel

        localparam int unsigned idx = i;
        logic [TbNumMst-1:0] temp_inp_sel;

        initial begin

            sel_done[i] = 1'b0;

            @(posedge rst_n);


            repeat (64) begin
                // Randomize the temp variable with the constraint
                std::randomize(temp_inp_sel) with {
                    temp_inp_sel      != '0;
                    temp_inp_sel[idx] == 1'b0;
                };
                // Assign the randomized value to inp_sel[i]
                inp_sel[i]       <= #(ApplTime) temp_inp_sel;

                cycle_start();
                while (!(inp_snoop_req[i].ac_valid && inp_snoop_resp[i].ac_ready)) begin

                    cycle_end();
                    cycle_start();
                end
                cycle_end();

            end
            sel_done[i] = 1'b1;
        end

    end

    logic lup_valid, lup_ready;

    ace_ccu_snoop_interconnect #(
        .NumInp       (TbNumMst),
        .NumOup       (TbNumMst),
        .ConfCheck    (1),
        .NumLup       (1),
        .AddrBase     (4),
        .AddrLength   (16),
        .ac_chan_t    (snoop_ac_t),
        .cr_chan_t    (snoop_cr_t),
        .cd_chan_t    (snoop_cd_t),
        .snoop_req_t  (snoop_req_t),
        .snoop_resp_t (snoop_resp_t)
    ) i_dut (
        .clk_i             (clk),
        .rst_ni            (rst_n),
        .inp_sel_i         (inp_sel),
        .inp_req_i         (inp_snoop_req),
        .inp_resp_o        (inp_snoop_resp),
        .oup_req_o         (oup_snoop_req),
        .oup_resp_i        (oup_snoop_resp),
        .lup_valid_o       (lup_valid),
        .lup_ready_i       (lup_ready),
        .lup_addr_o        (),
        .lup_valid_i       (lup_valid),
        .lup_ready_o       (lup_ready),
        .lup_clr_o         ()
    );

endmodule
