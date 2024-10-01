module ace_ccu_snoop_interconnect import ace_pkg::*; #(
    parameter int unsigned  NumInp       = 0,
    parameter int unsigned  NumOup       = 0,
    parameter type          ac_chan_t    = logic,
    parameter type          cr_chan_t    = logic,
    parameter type          cd_chan_t    = logic,
    parameter type          snoop_req_t  = logic,
    parameter type          snoop_resp_t = logic,

    localparam type         sel_mask_t = logic [NumOup-1:0]
) (

    input  logic                     clk_i,
    input  logic                     rst_ni,

    input  sel_mask_t   [NumInp-1:0] inp_sel_i,
    input  logic        [NumInp-1:0] inp_sel_valids_i,
    output logic        [NumInp-1:0] inp_sel_readies_o,

    input  snoop_req_t  [NumInp-1:0] inp_req_i,
    output snoop_resp_t [NumInp-1:0] inp_resp_o,
    output snoop_req_t  [NumOup-1:0] oup_req_o,
    input  snoop_resp_t [NumOup-1:0] oup_resp_i
);

typedef logic [$clog2(NumInp)-1:0] inp_idx_t;
typedef logic [$clog2(NumOup)-1:0] oup_idx_t;

logic     [NumInp-1:0] inp_ac_valids, inp_ac_readies;
ac_chan_t [NumInp-1:0] inp_ac_chans;
logic     [NumInp-1:0] inp_cr_valids, inp_cr_readies;
cr_chan_t [NumInp-1:0] inp_cr_chans;
logic     [NumInp-1:0] inp_cd_valids, inp_cd_readies;
cd_chan_t [NumInp-1:0] inp_cd_chans;


logic     [NumOup-1:0] oup_ac_valids, oup_ac_readies;
ac_chan_t [NumOup-1:0] oup_ac_chans;
logic     [NumOup-1:0] oup_cr_valids, oup_cr_readies;
cr_chan_t [NumOup-1:0] oup_cr_chans;
logic     [NumOup-1:0] oup_cd_valids, oup_cd_readies;
cd_chan_t [NumOup-1:0] oup_cd_chans;

logic     [NumOup-1:0][NumInp-1:0] cr_valids, cr_readies;
cr_chan_t [NumOup-1:0][NumInp-1:0] cr_chans;
logic     [NumOup-1:0][NumInp-1:0] cd_valids, cd_readies;
cd_chan_t [NumOup-1:0][NumInp-1:0] cd_chans;

logic     [NumInp-1:0][NumOup-1:0] cr_valids_rev, cr_readies_rev;
cr_chan_t [NumInp-1:0][NumOup-1:0] cr_chans_rev;
logic     [NumInp-1:0][NumOup-1:0] cd_valids_rev, cd_readies_rev;
cd_chan_t [NumInp-1:0][NumOup-1:0] cd_chans_rev;

logic [NumOup-1:0] to_arb_sel_valid, from_arb_sel_ready;
logic [NumOup-1:0] fork_ac_valids, fork_ac_readies;

sel_mask_t ac_sel;
logic      ac_sel_valid, ac_sel_ready;

logic     arb_ac_valid, arb_ac_ready;
ac_chan_t arb_ac_chan;
inp_idx_t arb_ac_idx;

for (genvar i = 0; i < NumInp; i++) begin
    assign inp_ac_valids[i]       = inp_req_i[i].ac_valid;
    assign inp_resp_o[i].ac_ready = inp_ac_readies[i];
    assign inp_ac_chans[i]        = inp_req_i[i].ac;
    assign inp_cr_readies[i]      = inp_req_i[i].cr_ready;
    assign inp_resp_o[i].cr_valid = inp_cr_valids[i];
    assign inp_resp_o[i].cr_resp  = inp_cr_chans[i];
    assign inp_cd_readies[i]      = inp_req_i[i].cd_ready;
    assign inp_resp_o[i].cd_valid = inp_cd_valids[i];
    assign inp_resp_o[i].cd       = inp_cd_chans[i];
end

for (genvar i = 0; i < NumOup; i++) begin
    assign oup_ac_readies[i]     = oup_resp_i[i].ac_ready;
    assign oup_req_o[i].ac_valid = oup_ac_valids[i];
    assign oup_req_o[i].ac       = oup_ac_chans[i];
    assign oup_req_o[i].cr_ready = oup_cr_readies[i];
    assign oup_cr_valids[i]      = oup_resp_i[i].cr_valid;
    assign oup_cr_chans[i]       = oup_resp_i[i].cr_resp;
    assign oup_req_o[i].cd_ready = oup_cd_readies[i];
    assign oup_cd_valids[i]      = oup_resp_i[i].cd_valid;
    assign oup_cd_chans[i]       = oup_resp_i[i].cd;
end

for (genvar i = 0; i < NumInp; i++) begin
    for (genvar j = 0; j < NumOup; j++) begin
        assign cr_valids_rev  [i][j] = cr_valids     [j][i];
        assign cr_readies     [j][i] = cr_readies_rev[i][j];
        assign cr_chans_rev   [i][j] = cr_chans      [j][i];
        assign cd_valids_rev  [i][j] = cd_valids     [j][i];
        assign cd_readies     [j][i] = cd_readies_rev[i][j];
        assign cd_chans_rev   [i][j] = cd_chans      [j][i];
    end
end

rr_arb_tree #(
    .NumIn      (NumInp),
    .DataType   (ac_chan_t),
    .ExtPrio    (1'b0),
    .AxiVldRdy  (1'b1),
    .LockIn     (1'b1)
) i_arbiter (
    .clk_i,
    .rst_ni,
    .flush_i ('0),
    .rr_i    ('0),
    .req_i   (inp_ac_valids),
    .gnt_o   (inp_ac_readies),
    .data_i  (inp_ac_chans),
    .req_o   (arb_ac_valid),
    .gnt_i   (arb_ac_ready),
    .data_o  (arb_ac_chan),
    .idx_o   (arb_ac_idx)
);

assign ac_sel             = inp_sel_i[arb_ac_idx];
assign ac_sel_valid       = to_arb_sel_valid[arb_ac_idx];
always_comb begin
    from_arb_sel_ready = '0;
    if (ac_sel_ready)
        from_arb_sel_ready[arb_ac_idx] = 1'b1;
end

stream_fork_dynamic #(
  .N_OUP (NumOup)
) i_ac_fork (
    .clk_i,
    .rst_ni,
    .valid_i     (arb_ac_valid),
    .ready_o     (arb_ac_ready),
    .sel_i       (ac_sel),
    .sel_valid_i (ac_sel_valid),
    .sel_ready_o (ac_sel_ready),
    .valid_o     (fork_ac_valids),
    .ready_i     (fork_ac_readies)
);

for (genvar i = 0; i < NumOup; i++) begin : gen_oup

    // Control valid/ready
    ace_ccu_snoop_port_ctrl #(
        .NumInp                (NumInp),
        .NumOup                (NumOup)
    ) i_snoop_port_ctrl (
        .clk_i,
        .rst_ni,
        .inp_ac_valid_i        (fork_ac_valids[i]),
        .inp_ac_ready_o        (fork_ac_readies[i]),
        .inp_cr_valids_o       (cr_valids[i]),
        .inp_cr_readies_i      (cr_readies[i]),
        .inp_cd_valids_o       (cd_valids[i]),
        .inp_cd_readies_i      (cd_readies[i]),
        .inp_idx_i             (arb_ac_idx),
        .cd_last_i             (oup_cd_chans[i].last),
        .cr_data_transfer_i    (oup_cr_chans[i].DataTransfer),
        .oup_ac_valid_o        (oup_ac_valids[i]),
        .oup_ac_ready_i        (oup_ac_readies[i]),
        .oup_cr_valid_i        (oup_cr_valids[i]),
        .oup_cr_ready_o        (oup_cr_readies[i]),
        .oup_cd_valid_i        (oup_cd_valids[i]),
        .oup_cd_ready_o        (oup_cd_readies[i])
    );

    // Data channels
    assign oup_ac_chans[i] = arb_ac_chan;
    assign cr_chans[i]     = {NumInp{oup_cr_chans[i]}};
    assign cd_chans[i]     = {NumInp{oup_cd_chans[i]}};

end

for (genvar i = 0; i < NumInp; i++) begin : gen_inp

    logic to_resp_sel_valid, from_resp_sel_ready;

    stream_fork #(
        .N_OUP (2)
    ) i_cr_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (inp_sel_valids_i[i]),
        .ready_o     (inp_sel_readies_o[i]),
        .valid_o     ({to_arb_sel_valid[i], to_resp_sel_valid}),
        .ready_i     ({from_arb_sel_ready[i], from_resp_sel_ready})
    );

    ace_ccu_snoop_resp #(
        .NumOup          (NumOup),
        .cr_chan_t       (cr_chan_t),
        .cd_chan_t       (cd_chan_t)
    ) i_inp_resp (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .cr_valids_i     (cr_valids_rev[i]),
        .cr_readies_o    (cr_readies_rev[i]),
        .cr_chans_i      (cr_chans_rev[i]),
        .cd_valids_i     (cd_valids_rev[i]),
        .cd_readies_o    (cd_readies_rev[i]),
        .cd_chans_i      (cd_chans_rev[i]),
        .oup_sel_i       (inp_sel_i[i]),
        .oup_sel_valid_i (to_resp_sel_valid),
        .oup_sel_ready_o (from_resp_sel_ready),
        .cr_valid_o      (inp_cr_valids[i]),
        .cr_ready_i      (inp_cr_readies[i]),
        .cr_chan_o       (inp_cr_chans[i]),
        .cd_valid_o      (inp_cd_valids[i]),
        .cd_ready_i      (inp_cd_readies[i]),
        .cd_chan_o       (inp_cd_chans[i])
    );
end

endmodule