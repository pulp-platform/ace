module ace_demux #(
    parameter int unsigned AxiIdWidth     = 32'd0,
    parameter bit          AtopSupport    = 1'b1,
    parameter type         aw_chan_t      = logic,
    parameter type         w_chan_t       = logic,
    parameter type         b_chan_t       = logic,
    parameter type         ar_chan_t      = logic,
    parameter type         r_chan_t       = logic,
    parameter type         axi_req_t      = logic,
    parameter type         axi_resp_t     = logic,
    parameter int unsigned NoMstPorts     = 32'd0,
    parameter int unsigned MaxTrans       = 32'd8,
    parameter int unsigned AxiLookBits    = 32'd3,
    parameter bit          UniqueIds      = 1'b0,
    parameter bit          SpillAw        = 1'b1,
    parameter bit          SpillW         = 1'b0,
    parameter bit          SpillB         = 1'b0,
    parameter bit          SpillAr        = 1'b1,
    parameter bit          SpillR         = 1'b0,
    // Dependent parameters, DO NOT OVERRIDE!
    parameter int unsigned SelectWidth    = (NoMstPorts > 32'd1) ? $clog2(NoMstPorts) : 32'd1,
    parameter type         select_t       = logic [SelectWidth-1:0]
) (
    input  logic                          clk_i,
    input  logic                          rst_ni,
    input  logic                          test_i,
    // Slave Port
    input  axi_req_t                      slv_req_i,
    input  select_t                       slv_aw_select_i,
    input  select_t                       slv_ar_select_i,
    output axi_resp_t                     slv_resp_o,
    // Master Ports
    output axi_req_t    [NoMstPorts-1:0]  mst_reqs_o,
    input  axi_resp_t   [NoMstPorts-1:0]  mst_resps_i
);

    logic [cf_math_pkg::idx_width(NoMstPorts)-1:0] b_idx_in, b_idx_out;
    logic [cf_math_pkg::idx_width(NoMstPorts)-1:0] r_idx_in, r_idx_out;

    logic b_fifo_full, r_fifo_full;

    axi_req_t  slv_req;
    axi_resp_t slv_resp;
    axi_req_t  [NoMstPorts-1:0] mst_reqs;

    axi_demux #(
        .AxiIdWidth         (AxiIdWidth ),
        .AtopSupport        (AtopSupport),
        .aw_chan_t          (aw_chan_t  ),
        .w_chan_t           (w_chan_t   ),
        .b_chan_t           (b_chan_t   ),
        .ar_chan_t          (ar_chan_t  ),
        .r_chan_t           (r_chan_t   ),
        .axi_req_t          (axi_req_t  ),
        .axi_resp_t         (axi_resp_t ),
        .NoMstPorts         (NoMstPorts ),
        .MaxTrans           (MaxTrans   ),
        .AxiLookBits        (AxiLookBits),
        .UniqueIds          (UniqueIds  ),
        .SpillAw            (SpillAw    ),
        .SpillW             (SpillW     ),
        .SpillB             (SpillB     ),
        .SpillAr            (SpillAr    ),
        .SpillR             (SpillR     )
    ) i_axi_demux (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .test_i             (test_i),
        // Slave Port
        .slv_req_i          (slv_req),
        .slv_aw_select_i    (slv_aw_select_i),
        .slv_ar_select_i    (slv_ar_select_i),
        .slv_resp_o         (slv_resp),
        // Master Ports
        .mst_reqs_o         (mst_reqs),
        .mst_resps_i        (mst_resps_i)
    );

    if (NoMstPorts == 1) begin : gen_no_demux
        always_comb begin
            slv_req     = slv_req_i;
            slv_resp_o  = slv_resp;
            mst_reqs_o  = mst_reqs;
            mst_reqs_o[0].wack = slv_req_i.wack;
            mst_reqs_o[0].rack = slv_req_i.rack;
        end
    end else begin : gen_demux

        assign b_idx_in = i_axi_demux.i_demux_simple.genblk1.b_idx; // TODO: add idx as port in demux

        fifo_v3 #(
            .FALL_THROUGH (1'b0),
            .DEPTH        (MaxTrans),
            .dtype        (select_t)
        ) i_b_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (b_fifo_full),
            .empty_o    (),
            .usage_o    (),
            .data_i     (b_idx_in),
            .push_i     (slv_resp_o.b_valid && slv_req_i.b_ready),
            .data_o     (b_idx_out),
            .pop_i      (slv_req_i.wack)
        );

        assign r_idx_in = i_axi_demux.i_demux_simple.genblk1.r_idx; // TODO: add idx as port in demux

        fifo_v3 #(
            .FALL_THROUGH (1'b0),
            .DEPTH        (MaxTrans),
            .dtype        (select_t)
        ) i_r_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (r_fifo_full),
            .empty_o    (),
            .usage_o    (),
            .data_i     (r_idx_in),
            .push_i     (slv_resp_o.r_valid && slv_req_i.r_ready && slv_resp_o.r.last),
            .data_o     (r_idx_out),
            .pop_i      (slv_req_i.rack)
        );

        always_comb begin
            slv_req     = slv_req_i;
            slv_resp_o  = slv_resp;

            mst_reqs_o  = mst_reqs;

            for (int unsigned i = 0; i < NoMstPorts; i++) begin
                mst_reqs_o[i].wack = '0;
                mst_reqs_o[i].rack = '0;
            end

            // Response stalling
            if (b_fifo_full) begin
                slv_req.b_ready    = 1'b0;
                slv_resp_o.b_valid = 1'b0;
            end

            if (r_fifo_full) begin
                slv_req.r_ready    = 1'b0;
                slv_resp_o.r_valid = 1'b0;
            end

            // xACK steering
            mst_reqs_o[b_idx_out].wack = slv_req_i.wack;
            mst_reqs_o[r_idx_out].rack = slv_req_i.rack;
        end

    end

endmodule
