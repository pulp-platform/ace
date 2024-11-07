module ace_mux #(
    // AXI parameter and channel types
    parameter int unsigned SlvAxiIDWidth = 32'd0, // AXI ID width, slave ports
    parameter type         slv_aw_chan_t = logic, // AW Channel Type, slave ports
    parameter type         mst_aw_chan_t = logic, // AW Channel Type, master port
    parameter type         w_chan_t      = logic, //  W Channel Type, all ports
    parameter type         slv_b_chan_t  = logic, //  B Channel Type, slave ports
    parameter type         mst_b_chan_t  = logic, //  B Channel Type, master port
    parameter type         slv_ar_chan_t = logic, // AR Channel Type, slave ports
    parameter type         mst_ar_chan_t = logic, // AR Channel Type, master port
    parameter type         slv_r_chan_t  = logic, //  R Channel Type, slave ports
    parameter type         mst_r_chan_t  = logic, //  R Channel Type, master port
    parameter type         slv_req_t     = logic, // Slave port request type
    parameter type         slv_resp_t    = logic, // Slave port response type
    parameter type         mst_req_t     = logic, // Master ports request type
    parameter type         mst_resp_t    = logic, // Master ports response type
    parameter int unsigned NoSlvPorts    = 32'd0, // Number of slave ports
    // Maximum number of outstanding transactions per write
    parameter int unsigned MaxWTrans     = 32'd8,
    // Maximum number of outstanding responses per B/R channels
    parameter int unsigned MaxRespTrans  = 32'd8,
    // If enabled, this multiplexer is purely combinatorial
    parameter bit          FallThrough   = 1'b0,
    // add spill register on write master ports, adds a cycle latency on write channels
    parameter bit          SpillAw       = 1'b1,
    parameter bit          SpillW        = 1'b0,
    parameter bit          SpillB        = 1'b0,
    // add spill register on read master ports, adds a cycle latency on read channels
    parameter bit          SpillAr       = 1'b1,
    parameter bit          SpillR        = 1'b0
) (
    input  logic                       clk_i,    // Clock
    input  logic                       rst_ni,   // Asynchronous reset active low
    input  logic                       test_i,   // Test Mode enable
    // slave ports (AXI inputs), connect master modules here
    input  slv_req_t  [NoSlvPorts-1:0] slv_reqs_i,
    output slv_resp_t [NoSlvPorts-1:0] slv_resps_o,
    // master port (AXI outputs), connect slave modules here
    output mst_req_t                   mst_req_o,
    input  mst_resp_t                  mst_resp_i
);

    localparam int unsigned MstIdxBits = $clog2(NoSlvPorts);
    typedef logic [MstIdxBits-1:0] switch_id_t;

    logic b_fifo_full, r_fifo_full;

    mst_req_t  mst_req;
    mst_resp_t mst_resp;

    switch_id_t b_idx_in, b_idx_out;
    switch_id_t r_idx_in, r_idx_out;

    axi_mux #(
        .SlvAxiIDWidth (SlvAxiIDWidth),
        .slv_aw_chan_t (slv_aw_chan_t),
        .mst_aw_chan_t (mst_aw_chan_t),
        .w_chan_t      (w_chan_t     ),
        .slv_b_chan_t  (slv_b_chan_t ),
        .mst_b_chan_t  (mst_b_chan_t ),
        .slv_ar_chan_t (slv_ar_chan_t),
        .mst_ar_chan_t (mst_ar_chan_t),
        .slv_r_chan_t  (slv_r_chan_t ),
        .mst_r_chan_t  (mst_r_chan_t ),
        .slv_req_t     (slv_req_t    ),
        .slv_resp_t    (slv_resp_t   ),
        .mst_req_t     (mst_req_t    ),
        .mst_resp_t    (mst_resp_t   ),
        .NoSlvPorts    (NoSlvPorts   ),
        .MaxWTrans     (MaxWTrans    ),
        .FallThrough   (FallThrough  ),
        .SpillAw       (SpillAw      ),
        .SpillW        (SpillW       ),
        .SpillB        (SpillB       ),
        .SpillAr       (SpillAr      ),
        .SpillR        (SpillR       )
    ) i_axi_mux (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .test_i           (test_i),
        .slv_reqs_i       (slv_reqs_i),
        .slv_resps_o      (slv_resps_o),
        .mst_req_o        (mst_req),
        .mst_resp_i       (mst_resp)
    );

    if (NoSlvPorts == 1) begin : gen_no_mux
        always_comb begin
            mst_req_o  = mst_req;
            mst_resp   = mst_resp_i;

            mst_req_o.wack = slv_reqs_i[0].wack;
            mst_req_o.rack = slv_reqs_i[0].rack;
        end
    end else begin : gen_mux

        assign b_idx_in = mst_resp.b.id[SlvAxiIDWidth+:MstIdxBits];

        fifo_v3 #(
            .FALL_THROUGH (!SpillB),
            .DEPTH        (MaxRespTrans),
            .dtype        (switch_id_t)
        ) i_b_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (b_fifo_full),
            .empty_o    (),
            .usage_o    (),
            .data_i     (b_idx_in),
            .push_i     (mst_resp_i.b_valid && mst_req_o.b_ready),
            .data_o     (b_idx_out),
            .pop_i      (mst_req_o.wack)
        );

        assign r_idx_in = mst_resp.r.id[SlvAxiIDWidth+:MstIdxBits];

        fifo_v3 #(
            .FALL_THROUGH (!SpillR),
            .DEPTH        (MaxRespTrans),
            .dtype        (switch_id_t)
        ) i_r_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (r_fifo_full),
            .empty_o    (),
            .usage_o    (),
            .data_i     (r_idx_in),
            .push_i     (mst_resp_i.r_valid && mst_req_o.r_ready && mst_resp_i.r.last),
            .data_o     (r_idx_out),
            .pop_i      (mst_req_o.rack)
        );

        always_comb begin
            mst_req_o  = mst_req;
            mst_resp   = mst_resp_i;
            mst_req_o.rack = 1'b0;
            mst_req_o.wack = 1'b0;

            // Response stalling
            if (b_fifo_full) begin
                mst_req_o.b_ready = 1'b0;
                mst_resp.b_valid  = 1'b0;
            end

            if (r_fifo_full) begin
                mst_req_o.r_ready = 1'b0;
                mst_resp.r_valid  = 1'b0;
            end

            // xACK steering
            mst_req_o.wack = slv_reqs_i[b_idx_out].wack;
            mst_req_o.rack = slv_reqs_i[r_idx_out].rack;
        end

    end

endmodule
