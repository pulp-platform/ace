module ace_ccu_snoop_req #(
    parameter int unsigned NumInp = 0,
    parameter int unsigned NumOup = 0,
    parameter type         ac_chan_t = logic,
    parameter type         ctrl_t    = logic
) (

    input  logic                              clk_i,
    input  logic                              rst_ni,
    input  logic     [NumInp-1:0]             ac_valids_i,
    output logic     [NumInp-1:0]             ac_readies_o,
    input  ac_chan_t [NumInp-1:0]             ac_chans_i,
    input  logic     [NumInp-1:0][NumOup-1:0] ac_sel_i,
    output logic                              ac_valid_o,
    input  logic                              ac_ready_i,
    output ac_chan_t                          ac_chan_o,
    output logic                              ctrl_valid_o,
    input  logic                              ctrl_ready_i,
    output ctrl_t                             ctrl_o
);

logic [$clog2(NumInp)-1:0] ac_idx;
logic [NumOup-1:0]         ac_sel;

logic ac_valid, ac_ready;

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
    .req_i   (ac_valids_i),
    .gnt_o   (ac_readies_o),
    .data_i  (ac_chans_i),
    .req_o   (ac_valid),
    .gnt_i   (ac_ready),
    .data_o  (ac_chan_o),
    .idx_o   (ac_idx)
);

assign ac_sel = ac_sel_i[ac_idx];

stream_fork #(
    .N_OUP (2)
) i_ac_fork (
    .clk_i,
    .rst_ni,
    .valid_i     (ac_valid),
    .ready_o     (ac_ready),
    .valid_o     ({ac_valid_o, ctrl_valid_o}),
    .ready_i     ({ac_ready_i, ctrl_ready_i})
);

assign ctrl_o = '{sel: ac_sel, idx: ac_idx};

endmodule
