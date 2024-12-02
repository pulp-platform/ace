module ace_ccu_snoop_interconnect import ace_pkg::*; #(
    parameter int unsigned  NumInp        = 0,
    parameter int unsigned  NumOup        = 0,
    parameter int unsigned  NumLup        = 0,
    parameter bit           BufferOupReq  = 1,
    parameter bit           BufferOupResp = 1,
    parameter bit           BufferInpReq  = 1,
    parameter bit           BufferInpResp = 1,
    parameter int unsigned  CmAddrWidth   = 0,
    parameter int unsigned  CmAddrBase    = 0,
    parameter type          ac_chan_t     = logic,
    parameter type          cr_chan_t     = logic,
    parameter type          cd_chan_t     = logic,
    parameter type          snoop_req_t   = logic,
    parameter type          snoop_resp_t  = logic,

    localparam type         oup_sel_t     = logic [NumOup-1:0],
    localparam type         cm_addr_t     = logic [CmAddrWidth-1:0]
) (

    input  logic                     clk_i,
    input  logic                     rst_ni,

    input  oup_sel_t    [NumInp-1:0] inp_sel_i,
    input  snoop_req_t  [NumInp-1:0] inp_req_i,
    output snoop_resp_t [NumInp-1:0] inp_resp_o,
    output snoop_req_t  [NumOup-1:0] oup_req_o,
    input  snoop_resp_t [NumOup-1:0] oup_resp_i,

    output  logic                    cm_valid_o,
    output  logic                    cm_ready_o,
    output  cm_addr_t                cm_addr_o,
    input   logic                    cm_stall_i
);

    typedef logic [$clog2(NumInp)-1:0] inp_idx_t;

    typedef struct packed {
        oup_sel_t sel;
        inp_idx_t idx;
    } ctrl_t;

    logic     [NumInp-1:0] inp_ac_valids, inp_ac_readies;
    ac_chan_t [NumInp-1:0] inp_ac_chans;
    logic     [NumInp-1:0] inp_cr_valids, inp_cr_readies;
    cr_chan_t [NumInp-1:0] inp_cr_chans;
    logic     [NumInp-1:0] inp_cd_valids, inp_cd_readies;
    cd_chan_t [NumInp-1:0] inp_cd_chans;

    oup_sel_t [NumInp-1:0] inp_sel;


    logic     [NumOup-1:0] oup_ac_valids, oup_ac_readies;
    ac_chan_t [NumOup-1:0] oup_ac_chans;
    logic     [NumOup-1:0] oup_cr_valids, oup_cr_readies;
    cr_chan_t [NumOup-1:0] oup_cr_chans;
    logic     [NumOup-1:0] oup_cd_valids, oup_cd_readies;
    cd_chan_t [NumOup-1:0] oup_cd_chans;

    logic      ac_valid, ac_ready;
    logic      oup_ac_valid, oup_ac_ready;
    ac_chan_t  ac_chan;

    logic  req_ctrl_valid, req_ctrl_ready;
    logic  resp_ctrl_valid, resp_ctrl_ready;
    ctrl_t req_ctrl, resp_ctrl;

    logic     cr_valid, cr_ready;
    cr_chan_t cr_chan;
    ctrl_t    cr_ctrl;
    logic     cd_valid, cd_ready;
    cd_chan_t cd_chan;
    ctrl_t    cd_ctrl;

    for (genvar i = 0; i < NumInp; i++) begin : gen_unpack_inp
        if (BufferInpReq) begin : gen_buffer_req
            typedef struct packed {
                ac_chan_t ac;
                oup_sel_t sel;
            } ac_fifo_entry_t;

            // Data type needed to avoid errors with Design Compiler
            typedef logic [$bits(ac_fifo_entry_t)-1:0] ac_fifo_entry_vec_t;

            ac_fifo_entry_vec_t ac_fifo_out_vec;
            ac_fifo_entry_t     ac_fifo_in, ac_fifo_out;

            assign ac_fifo_in.ac  = inp_req_i[i].ac;
            assign ac_fifo_in.sel = inp_sel_i[i];

            assign ac_fifo_out     = ac_fifo_entry_t'(ac_fifo_out_vec);
            assign inp_ac_chans[i] = ac_fifo_out.ac;
            assign inp_sel[i]      = ac_fifo_out.sel;

            stream_fifo_optimal_wrap #(
                .Depth  (2),
                .type_t (ac_fifo_entry_vec_t)
            ) i_ac_fifo (
                .clk_i,
                .rst_ni,
                .flush_i    (1'b0),
                .testmode_i (1'b0),
                .usage_o    (),
                .valid_i    (inp_req_i [i].ac_valid),
                .ready_o    (inp_resp_o[i].ac_ready),
                .data_i     (ac_fifo_entry_vec_t'(ac_fifo_in)),
                .valid_o    (inp_ac_valids [i]),
                .ready_i    (inp_ac_readies[i]),
                .data_o     (ac_fifo_out_vec)
            );
        end else begin : gen_no_buffer_req
            assign inp_ac_valids[i]       = inp_req_i[i].ac_valid;
            assign inp_resp_o[i].ac_ready = inp_ac_readies[i];
            assign inp_ac_chans[i]        = inp_req_i[i].ac;
            assign inp_sel[i]             = inp_sel_i[i];
        end
        if (BufferInpResp) begin : gen_buffer_resp
            stream_fifo_optimal_wrap #(
                .Depth  (2),
                .type_t (cr_chan_t)
            ) i_cr_fifo (
                .clk_i,
                .rst_ni,
                .flush_i    (1'b0),
                .testmode_i (1'b0),
                .usage_o    (),
                .valid_i    (inp_cr_valids [i]),
                .ready_o    (inp_cr_readies[i]),
                .data_i     (inp_cr_chans  [i]),
                .valid_o    (inp_resp_o[i].cr_valid),
                .ready_i    (inp_req_i [i].cr_ready),
                .data_o     (inp_resp_o[i].cr_resp)
            );
            stream_fifo_optimal_wrap #(
                .Depth  (4),
                .type_t (cd_chan_t)
            ) i_cd_fifo (
                .clk_i,
                .rst_ni,
                .flush_i    (1'b0),
                .testmode_i (1'b0),
                .usage_o    (),
                .valid_i    (inp_cd_valids [i]),
                .ready_o    (inp_cd_readies[i]),
                .data_i     (inp_cd_chans  [i]),
                .valid_o    (inp_resp_o[i].cd_valid),
                .ready_i    (inp_req_i [i].cd_ready),
                .data_o     (inp_resp_o[i].cd)
            );
        end else begin : gen_no_buffer_resp
            assign inp_cr_readies[i]      = inp_req_i[i].cr_ready;
            assign inp_resp_o[i].cr_valid = inp_cr_valids[i];
            assign inp_resp_o[i].cr_resp  = inp_cr_chans[i];
            assign inp_cd_readies[i]      = inp_req_i[i].cd_ready;
            assign inp_resp_o[i].cd_valid = inp_cd_valids[i];
            assign inp_resp_o[i].cd       = inp_cd_chans[i];
        end
    end

    for (genvar i = 0; i < NumOup; i++) begin : gen_unpack_oup
        if (BufferOupReq) begin : gen_buffer_req
            stream_fifo_optimal_wrap #(
                .Depth  (2),
                .type_t (ac_chan_t)
            ) i_ac_fifo (
                .clk_i,
                .rst_ni,
                .flush_i    (1'b0),
                .testmode_i (1'b0),
                .usage_o    (),
                .valid_i    (oup_ac_valids [i]),
                .ready_o    (oup_ac_readies[i]),
                .data_i     (oup_ac_chans  [i]),
                .valid_o    (oup_req_o [i].ac_valid),
                .ready_i    (oup_resp_i[i].ac_ready),
                .data_o     (oup_req_o [i].ac)
            );
        end else begin : gen_no_buffer_req
            assign oup_ac_readies[i]     = oup_resp_i[i].ac_ready;
            assign oup_req_o[i].ac_valid = oup_ac_valids[i];
            assign oup_req_o[i].ac       = oup_ac_chans[i];
        end
        if (BufferOupResp) begin : gen_buffer_resp
            stream_fifo_optimal_wrap #(
                .Depth  (2),
                .type_t (cr_chan_t)
            ) i_cr_fifo (
                .clk_i,
                .rst_ni,
                .flush_i    (1'b0),
                .testmode_i (1'b0),
                .usage_o    (),
                .valid_i    (oup_resp_i[i].cr_valid),
                .ready_o    (oup_req_o [i].cr_ready),
                .data_i     (oup_resp_i[i].cr_resp),
                .valid_o    (oup_cr_valids [i]),
                .ready_i    (oup_cr_readies[i]),
                .data_o     (oup_cr_chans  [i])
            );
            stream_fifo_optimal_wrap #(
                .Depth  (4),
                .type_t (cd_chan_t)
            ) i_cd_fifo (
                .clk_i,
                .rst_ni,
                .flush_i    (1'b0),
                .testmode_i (1'b0),
                .usage_o    (),
                .valid_i    (oup_resp_i[i].cd_valid),
                .ready_o    (oup_req_o [i].cd_ready),
                .data_i     (oup_resp_i[i].cd),
                .valid_o    (oup_cd_valids [i]),
                .ready_i    (oup_cd_readies[i]),
                .data_o     (oup_cd_chans  [i])
            );
        end else begin : gen_no_buffer_resp
            assign oup_req_o[i].cr_ready = oup_cr_readies[i];
            assign oup_cr_valids[i]      = oup_resp_i[i].cr_valid;
            assign oup_cr_chans[i]       = oup_resp_i[i].cr_resp;
            assign oup_req_o[i].cd_ready = oup_cd_readies[i];
            assign oup_cd_valids[i]      = oup_resp_i[i].cd_valid;
            assign oup_cd_chans[i]       = oup_resp_i[i].cd;
        end
    end

    ace_ccu_snoop_req #(
        .NumInp    (NumInp),
        .NumOup    (NumOup),
        .ac_chan_t (ac_chan_t),
        .ctrl_t    (ctrl_t)
    ) i_snoop_req (
        .clk_i,
        .rst_ni,
        .ac_valids_i     (inp_ac_valids),
        .ac_readies_o    (inp_ac_readies),
        .ac_chans_i      (inp_ac_chans),
        .ac_sel_i        (inp_sel),
        .ac_valid_o      (ac_valid),
        .ac_ready_i      (ac_ready),
        .ac_chan_o       (ac_chan),
        .ctrl_valid_o    (req_ctrl_valid),
        .ctrl_ready_i    (req_ctrl_ready),
        .ctrl_o          (req_ctrl)
    );

    assign cm_valid_o    = ac_valid;
    assign cm_ready_o    = oup_ac_ready;
    assign cm_addr_o     = ac_chan.addr[CmAddrBase+:CmAddrWidth];
    assign ac_ready      = oup_ac_ready && !cm_stall_i;
    assign oup_ac_valid  = ac_valid     && !cm_stall_i;

    stream_fifo_optimal_wrap #(
        .Depth  (2),
        .type_t (ctrl_t)
    ) i_oup_ctrl_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .valid_i    (req_ctrl_valid),
        .ready_o    (req_ctrl_ready),
        .data_i     (req_ctrl),
        .valid_o    (resp_ctrl_valid),
        .ready_i    (resp_ctrl_ready),
        .data_o     (resp_ctrl)
    );

    stream_fork_dynamic #(
        .N_OUP (NumOup)
    ) i_ac_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (oup_ac_valid),
        .ready_o     (oup_ac_ready),
        .sel_i       (req_ctrl.sel),
        .sel_valid_i (oup_ac_valid),
        .sel_ready_o ( ),
        .valid_o     (oup_ac_valids),
        .ready_i     (oup_ac_readies)
    );

    assign oup_ac_chans = {NumOup{ac_chan}};

    ace_ccu_snoop_resp #(
        .NumOup          (NumOup),
        .cr_chan_t       (cr_chan_t),
        .cd_chan_t       (cd_chan_t),
        .ctrl_t          (ctrl_t)
    ) i_snoop_resp (
        .clk_i,
        .rst_ni,
        .cr_valids_i     (oup_cr_valids),
        .cr_readies_o    (oup_cr_readies),
        .cr_chans_i      (oup_cr_chans),
        .cd_valids_i     (oup_cd_valids),
        .cd_readies_o    (oup_cd_readies),
        .cd_chans_i      (oup_cd_chans),
        .ctrl_i          (resp_ctrl),
        .ctrl_valid_i    (resp_ctrl_valid),
        .ctrl_ready_o    (resp_ctrl_ready),
        .cr_valid_o      (cr_valid),
        .cr_ready_i      (cr_ready),
        .cr_chan_o       (cr_chan),
        .cr_ctrl_o       (cr_ctrl),
        .cd_valid_o      (cd_valid),
        .cd_ready_i      (cd_ready),
        .cd_chan_o       (cd_chan),
        .cd_ctrl_o       (cd_ctrl)
    );

    stream_demux #(
        .N_OUP (NumInp)
    ) i_cr_demux (
        .inp_valid_i (cr_valid),
        .inp_ready_o (cr_ready),
        .oup_sel_i   (cr_ctrl.idx),
        .oup_valid_o (inp_cr_valids),
        .oup_ready_i (inp_cr_readies)
    );

    assign inp_cr_chans = {NumInp{cr_chan}};

    stream_demux #(
        .N_OUP (NumInp)
    ) i_cd_demux (
        .inp_valid_i (cd_valid),
        .inp_ready_o (cd_ready),
        .oup_sel_i   (cd_ctrl.idx),
        .oup_valid_o (inp_cd_valids),
        .oup_ready_i (inp_cd_readies)
    );

    assign inp_cd_chans = {NumInp{cd_chan}};

endmodule
