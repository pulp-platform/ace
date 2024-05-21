module ccu_ctrl_decoder import ccu_ctrl_pkg::*;
#(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiDataWidth = 0,
    parameter int unsigned AxiAddrWidth = 0,
    parameter int unsigned NoMstPorts = 4,
    parameter int unsigned SlvAxiIDWidth = 0,
    parameter bit          PerfCounters  = 1,
    parameter type slv_aw_chan_t = logic,
    parameter type w_chan_t      = logic,
    parameter type slv_b_chan_t  = logic,
    parameter type slv_ar_chan_t = logic,
    parameter type slv_r_chan_t  = logic,
    parameter type slv_req_t     = logic,
    parameter type slv_resp_t    = logic,
    parameter type snoop_ac_t    = logic,
    parameter type snoop_cr_t    = logic,
    parameter type snoop_cd_t    = logic,
    parameter type snoop_req_t   = logic,
    parameter type snoop_resp_t  = logic,
    parameter type ar_msg_t      = logic,
    parameter type aw_msg_t      = logic,
    parameter type snp_flags_t   = logic,
    localparam int unsigned DcacheLineWords = DcacheLineWidth / AxiDataWidth,
    localparam int unsigned MstIdxBits      = $clog2(NoMstPorts)
) (
    //clock and reset
    input                               clk_i,
    input                               rst_ni,
    // CCU Request in
    input  slv_req_t                    ccu_req_i,
    // Snoop channel resuest and response
    output snoop_req_t  [NoMstPorts-1:0] s2m_req_o,
    input  snoop_resp_t [NoMstPorts-1:0] m2s_resp_i,

    output slv_r_chan_t                  r_o,
    output logic                         r_valid_o,
    input  logic                         r_ready_i,

    output logic                         slv_aw_ready_o,
    output logic                         slv_ar_ready_o,

    output aw_msg_t                      aw_msg_o,
    output ar_msg_t                      ar_msg_o,

    output snp_flags_t                   snp_flags_o,

    output logic [MstIdxBits-1:0]        first_responder_o,

    output logic                         aw_req_o,
    input  logic                         aw_gnt_i,
    output logic                         ar_req_o,
    input  logic                         ar_gnt_i,

    output dest_t                        dest_o,
    output logic                         dest_push_o,

    output logic        [NoMstPorts-1:0] data_available_o,

    output logic                         lookup_req_o,
    output logic      [AxiAddrWidth-1:0] lookup_addr_o,
    output logic                         b_queue_push_o,
    output slv_aw_chan_t                 b_queue_aw_o,
    input  logic                         b_queue_full_i,
    output logic                         r_queue_push_o,
    output slv_ar_chan_t                 r_queue_ar_o,
    input  logic                         r_queue_full_i,
    input  logic                         b_collision_i,
    input  logic                         r_collision_i,

    input  logic                         cd_fifo_stall_i,

    output logic                   [7:0] perf_evt_o
);

    logic [NoMstPorts-1:0] ac_handshake_q, ac_handshake_d, ac_handshake;

    logic [NoMstPorts-1:0] cr_aw_initiator, cr_ar_initiator;
    logic [NoMstPorts-1:0] cr_handshake_q, cr_handshake_d, cr_handshake;

    typedef enum logic [1:0] { INVALID_W, INVALID_R, RESP_R } cr_cmd_fifo_t;

    logic stall;
    logic ac_done, cr_done;
    logic aw_wb, ar_wb;

    // AW FIFO
    logic aw_fifo_empty, aw_fifo_full;
    logic aw_fifo_pop, aw_fifo_push;
    slv_aw_chan_t aw_fifo_in, aw_fifo_out;

    // AR FIFO
    logic ar_fifo_empty, ar_fifo_full;
    logic ar_fifo_pop, ar_fifo_push;
    slv_ar_chan_t ar_fifo_in, ar_fifo_out;

    // CR CMD FIFO
    logic cr_cmd_fifo_empty, cr_cmd_fifo_full;
    logic cr_cmd_fifo_pop, cr_cmd_fifo_push;
    cr_cmd_fifo_t cr_cmd_fifo_in, cr_cmd_fifo_out;

    logic ac_busy_q, ac_busy_d;

    // Hold incoming ACE request

    slv_aw_chan_t                    aw_holder;
    logic                            aw_holder_valid, aw_holder_ready;
    slv_ar_chan_t                    ar_holder;
    logic                            ar_holder_valid, ar_holder_ready;
    snoop_ac_t                       aw_ac, ar_ac;
    logic           [NoMstPorts-1:0] aw_initiator, ar_initiator;

    assign b_queue_push_o = aw_holder_ready && aw_holder_valid;
    assign r_queue_push_o = ar_holder_ready && ar_holder_valid;

    assign b_queue_aw_o   = aw_holder;
    assign r_queue_ar_o   = ar_holder;

    assign aw_initiator = 1 << aw_holder.id[SlvAxiIDWidth+:MstIdxBits];
    assign ar_initiator = 1 << ar_holder.id[SlvAxiIDWidth+:MstIdxBits];


    logic send_invalid_r;
    logic collision;

    assign send_invalid_r = ar_holder.snoop == snoop_pkg::CLEAN_UNIQUE || ar_holder.lock;
    assign collision      = b_collision_i || r_collision_i;

    always_comb begin
        aw_ac       = '0;
        aw_ac.addr  = aw_holder.addr;
        aw_ac.prot  = aw_holder.prot;
        aw_ac.snoop = snoop_pkg::CLEAN_INVALID;

        ar_ac       = '0;
        ar_ac.addr  = ar_holder.addr;
        ar_ac.prot  = ar_holder.prot;
        ar_ac.snoop = send_invalid_r ? snoop_pkg::CLEAN_INVALID : ar_holder.snoop;
    end

    spill_register #(
        .T       (slv_aw_chan_t),
        .Bypass  (1'b1)
    ) aw_spill_register (
        .clk_i,
        .rst_ni,
        .valid_i (ccu_req_i.aw_valid),
        .ready_o (slv_aw_ready_o),
        .data_i  (ccu_req_i.aw),
        .valid_o (aw_holder_valid),
        .ready_i (aw_holder_ready),
        .data_o  (aw_holder)
    );

    spill_register #(
        .T       (slv_ar_chan_t),
        .Bypass  (1'b1)
    ) ar_spill_register (
        .clk_i,
        .rst_ni,
        .valid_i (ccu_req_i.ar_valid),
        .ready_o (slv_ar_ready_o),
        .data_i  (ccu_req_i.ar),
        .valid_o (ar_holder_valid),
        .ready_i (ar_holder_ready),
        .data_o  (ar_holder)
    );

    logic           [1:0] arb_req_in, arb_gnt_in;
    logic                 arb_req_out, arb_gnt_out;
    snoop_ac_t            arb_ac_out;
    logic                 arb_idx_out;

    assign arb_req_in = {aw_holder_valid, ar_holder_valid};
    assign {aw_holder_ready, ar_holder_ready} = arb_gnt_in;

    rr_arb_tree #(
        .NumIn    ( 2          ),
        .DataType ( snoop_ac_t ),
        .AxiVldRdy( 1'b1       ),
        .LockIn   ( 1'b1       ),
        .ExtPrio  ( 1'b0       )
    ) arbiter_i (
        .clk_i  ( clk_i          ),
        .rst_ni ( rst_ni         ),
        .flush_i( 1'b0           ),
        .rr_i   ( '0             ),
        .req_i  ( arb_req_in     ),
        .gnt_o  ( arb_gnt_in     ),
        .data_i ( {aw_ac, ar_ac} ),
        .req_o  ( arb_req_out    ),
        .gnt_i  ( arb_gnt_out    ),
        .data_o ( arb_ac_out     ),
        .idx_o  ( arb_idx_out    )
    );

    assign stall = |{
        // Collission on address
        collision,
        // CR CMD FIFO full
        cr_cmd_fifo_full,
        // CD CMD FIFO full
        cd_fifo_stall_i,
        // AR requests, ID queue or FIFO full
        arb_idx_out == 0 && (r_queue_full_i || ar_fifo_full),
        // AW requests, ID queue or FIFO full
        arb_idx_out == 1 && (b_queue_full_i || aw_fifo_full),
        // AC is busy
        ac_busy_q && !ac_done
    };
    assign arb_gnt_out   = !stall;
    assign lookup_req_o  = arb_req_out;
    assign lookup_addr_o = arb_idx_out == 1 ?
                           axi_pkg::aligned_addr(aw_holder.addr,aw_holder.size):
                           axi_pkg::aligned_addr(ar_holder.addr,ar_holder.size);


    for (genvar i = 0; i < NoMstPorts; i = i + 1) begin
        assign ac_handshake[i] = m2s_resp_i[i].ac_ready & s2m_req_o[i].ac_valid;
        assign cr_handshake[i] = m2s_resp_i[i].cr_valid & s2m_req_o[i].cr_ready;
    end

    snoop_ac_t [NoMstPorts-1:0] ac_out;
    logic      [NoMstPorts-1:0] ac_out_valid;
    logic      [NoMstPorts-1:0] cr_out_ready;

    // Hold snoop AC handshakes
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ac_handshake_q <= '0;
        end else begin
            ac_handshake_q <= ac_handshake_d;
        end
    end

    assign ac_done = (ac_handshake_q | ac_handshake) == '1;

    // Hold snoop CR handshakes
    logic [NoMstPorts-1:0] data_available_q, response_error_q, shared_q, dirty_q;
    logic [NoMstPorts-1:0] data_available_d, response_error_d, shared_d, dirty_d;
    always_ff @ (posedge clk_i, negedge rst_ni) begin
      if(!rst_ni) begin
        cr_handshake_q   <= '0;
        data_available_q <= '0;
        shared_q         <= '0;
        dirty_q          <= '0;
        response_error_q <= '0;
      end else if(cr_done) begin
        cr_handshake_q   <= '0;
        data_available_q <= '0;
        shared_q         <= '0;
        dirty_q          <= '0;
        response_error_q <= '0;
      end else begin
        cr_handshake_q   <= cr_handshake_d;
        data_available_q <= data_available_d;
        shared_q         <= shared_d;
        dirty_q          <= dirty_d;
        response_error_q <= response_error_d;
      end
    end

    for (genvar i = 0; i < NoMstPorts; i = i + 1) begin
        assign cr_handshake_d[i]   =  cr_handshake[i] ? 1'b1                               : cr_handshake_q[i];
        assign data_available_d[i] =  cr_handshake[i] ? m2s_resp_i[i].cr_resp.dataTransfer : data_available_q[i];
        assign shared_d[i]         =  cr_handshake[i] ? m2s_resp_i[i].cr_resp.isShared     : shared_q[i];
        assign dirty_d[i]          =  cr_handshake[i] ? m2s_resp_i[i].cr_resp.passDirty    : dirty_q[i];
        assign response_error_d[i] =  cr_handshake[i] ? m2s_resp_i[i].cr_resp.error        : response_error_q[i];
    end

    assign snp_flags_o.dirty  = |dirty_d;
    assign snp_flags_o.shared = |shared_d;
    assign data_available_o = data_available_d;

    logic [MstIdxBits-1:0] first_responder_q, first_responder_d;
    logic snoop_resp_found_q, snoop_resp_found_d;

    always_ff @ (posedge clk_i, negedge rst_ni) begin
        if(!rst_ni) begin
            first_responder_q  <= '0;
            snoop_resp_found_q <= 1'b0;
        end else if(cr_done) begin
            first_responder_q  <= '0;
            snoop_resp_found_q <= 1'b0;
        end else if (!snoop_resp_found_q) begin
            first_responder_q <= first_responder_d;
            snoop_resp_found_q <= snoop_resp_found_d;
        end
    end

    always_comb begin
        first_responder_d  = first_responder_q;
        snoop_resp_found_d = snoop_resp_found_q;
        for (int i = 0; i < NoMstPorts; i = i + 1) begin
            if(cr_handshake[i] & m2s_resp_i[i].cr_resp.dataTransfer & !m2s_resp_i[i].cr_resp.error) begin
                first_responder_d  = i[MstIdxBits-1:0];
                snoop_resp_found_d = 1'b1;
                break;
            end
        end
    end

    snoop_ac_t ac_q, ac_d;

    logic ar_handshake_d, ar_handshake_q;
    logic r_handshake_d, r_handshake_q;
    logic dest_pushed_d, dest_pushed_q;

    // ----------------------
    // Current State Block
    // ----------------------
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if(!rst_ni) begin
            ac_busy_q <= '0;
            ac_q      <= '0;
            ar_handshake_q <= '0;
            r_handshake_q  <= '0;
            dest_pushed_q  <= '0;
        end else begin
            ac_busy_q <= ac_busy_d;
            ac_q      <= ac_d;
            ar_handshake_q <= ar_handshake_d;
            r_handshake_q  <= r_handshake_d;
            dest_pushed_q  <= dest_pushed_d;
        end
    end

    // ----------------------
    // Current State Block
    // ----------------------

    always_comb begin

        ac_d = ac_q;
        ac_out_valid = '0;

        // Next state
        ac_busy_d = ac_busy_q;
        ac_handshake_d = ac_handshake_q;

        cr_cmd_fifo_in = RESP_R;
        aw_fifo_push = 1'b0;
        ar_fifo_push = 1'b0;

        if (ac_busy_q) begin
            ac_out_valid = ~ac_handshake_q;
            ac_handshake_d = ac_handshake | ac_handshake_q;
        end

        if (!ac_busy_q || ac_done) begin
            if (arb_req_out && !stall) begin
                ac_d = arb_ac_out;
                ac_busy_d = 1'b1;
                if (arb_idx_out == 1) begin
                    aw_fifo_push   = 1'b1;
                    cr_cmd_fifo_in = INVALID_W;
                    ac_handshake_d = aw_initiator;
                end else if (arb_idx_out == 0) begin
                    ar_fifo_push   = 1'b1;
                    cr_cmd_fifo_in = send_invalid_r ? INVALID_R : RESP_R;
                    ac_handshake_d = ar_initiator;
                end
            end else begin
                ac_busy_d      = 1'b0;
                ac_handshake_d = '0;
            end
        end
    end

    assign ac_out = {NoMstPorts{ac_q}};

    assign cr_aw_initiator = 1 << aw_fifo_out.id[SlvAxiIDWidth+:MstIdxBits];
    assign cr_ar_initiator = 1 << ar_fifo_out.id[SlvAxiIDWidth+:MstIdxBits];

    always_comb begin

        r_valid_o = 1'b0;

        ar_handshake_d = ar_handshake_q;
        r_handshake_d  = r_handshake_q;
        dest_pushed_d  = 1'b0;

        aw_fifo_pop = '0;
        ar_fifo_pop = '0;

        ar_wb = 1'b0;
        aw_wb = 1'b0;
        ar_req_o = 1'b0;
        aw_req_o = 1'b0;

        dest_o      = MEMORY_UNIT;
        dest_push_o = 1'b0;

        cr_out_ready = '0;

        cr_done      = 1'b0;

        if (!cr_cmd_fifo_empty) begin
            case (cr_cmd_fifo_out)
                RESP_R: begin
                    // wait for all CR handshakes
                    if (cr_handshake_d == ~cr_ar_initiator) begin

                        dest_pushed_d = 1'b1;
                        dest_push_o   = !dest_pushed_q;

                        if(|(data_available_d & ~response_error_d)) begin
                            dest_o          = SNOOP_UNIT;
                            ar_req_o        = 1'b1;
                            if (ar_gnt_i) begin
                                ar_fifo_pop = 1'b1;
                                cr_done     = 1'b1;
                                dest_pushed_d = 1'b0;
                            end
                        end else begin
                            dest_o   = MEMORY_UNIT;
                            ar_req_o = 1'b1;
                            if (ar_gnt_i) begin
                                ar_fifo_pop = 1'b1;
                                cr_done     = 1'b1;
                                dest_pushed_d = 1'b0;
                            end
                        end
                    end

                    cr_out_ready = ~(cr_handshake_q | cr_ar_initiator);
                end

                INVALID_R: begin
                    // wait for all CR handshakes
                    if (cr_handshake_d == ~cr_ar_initiator) begin

                        dest_o = MEMORY_UNIT;

                        r_valid_o     = !ar_fifo_out.lock && !r_handshake_q;
                        r_handshake_d = !ar_fifo_out.lock && (r_handshake_q || r_ready_i);

                        ar_handshake_d = ar_handshake_q || ar_gnt_i;

                        if(|(data_available_d & ~response_error_d)) begin
                            ar_wb    = 1'b1;
                            ar_req_o = !ar_handshake_q;
                            cr_done  = (ar_handshake_q || ar_gnt_i) &&
                                       (ar_fifo_out.lock || r_handshake_q || r_ready_i);
                            dest_pushed_d = 1'b1;
                            dest_push_o   = !dest_pushed_q;
                        end else if (ar_fifo_out.lock) begin
                            cr_done  = ar_gnt_i;
                            ar_req_o = !ar_handshake_q;
                        end else begin
                            cr_done  = r_ready_i;
                        end

                        if (cr_done) begin
                            ar_fifo_pop = 1'b1;
                            ar_handshake_d = 1'b0;
                            r_handshake_d  = 1'b0;
                            dest_pushed_d  = 1'b0;
                        end
                    end

                    cr_out_ready = ~(cr_handshake_q | cr_ar_initiator);
                end

                INVALID_W: begin
                    // wait for all CR handshakes
                    if (cr_handshake_d == ~cr_aw_initiator) begin
                        aw_req_o        = 1'b1;
                        dest_o          = MEMORY_UNIT;
                        dest_pushed_d   = 1'b1;
                        dest_push_o     = !dest_pushed_q;
                        aw_wb           = |(data_available_d & ~response_error_d);
                        if (aw_gnt_i) begin
                            aw_fifo_pop = 1'b1;
                            cr_done     = 1'b1;
                            dest_pushed_d = 1'b0;
                        end
                    end

                    cr_out_ready = ~(cr_handshake_q | cr_aw_initiator);
                end
            endcase
        end
    end

    always_comb begin
        s2m_req_o = '0;
        for (int unsigned n = 0; n < NoMstPorts; n = n + 1) begin
            s2m_req_o[n].ac       = ac_out[n];
            s2m_req_o[n].ac_valid = ac_out_valid[n];
            s2m_req_o[n].cr_ready = cr_out_ready[n];
        end
    end

    assign cr_cmd_fifo_push = aw_fifo_push || ar_fifo_push;
    assign cr_cmd_fifo_pop  = aw_fifo_pop  || ar_fifo_pop;

    fifo_v3 #(
        .FALL_THROUGH(0),
        .DEPTH(4),
        .dtype (cr_cmd_fifo_t)
    ) cr_cmd_fifo_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (cr_cmd_fifo_full),
        .empty_o    (cr_cmd_fifo_empty),
        .usage_o    (),
        .data_i     (cr_cmd_fifo_in),
        .push_i     (cr_cmd_fifo_push),
        .data_o     (cr_cmd_fifo_out),
        .pop_i      (cr_cmd_fifo_pop)
    );

    assign ar_fifo_in = ar_holder;

    fifo_v3 #(
        .FALL_THROUGH(0),
        .DEPTH(4),
        .dtype (slv_ar_chan_t)
    ) ar_fifo_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (ar_fifo_full),
        .empty_o    (ar_fifo_empty),
        .usage_o    (),
        .data_i     (ar_fifo_in),
        .push_i     (ar_fifo_push),
        .data_o     (ar_fifo_out),
        .pop_i      (ar_fifo_pop)
    );

    assign aw_fifo_in = aw_holder;

    fifo_v3 #(
        .FALL_THROUGH(0),
        .DEPTH(4),
        .dtype (slv_aw_chan_t)
    ) aw_fifo_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .full_o     (aw_fifo_full),
        .empty_o    (aw_fifo_empty),
        .usage_o    (),
        .data_i     (aw_fifo_in),
        .push_i     (aw_fifo_push),
        .data_o     (aw_fifo_out),
        .pop_i      (aw_fifo_pop)
    );

    assign ar_msg_o.ar             = ar_fifo_out;
    assign ar_msg_o.wb             = ar_wb;

    assign aw_msg_o.aw             = aw_fifo_out;
    assign aw_msg_o.wb             = aw_wb;

    assign first_responder_o       = first_responder_d;

    always_comb begin
        r_o       = '0;
        r_o.id    =ar_fifo_out.id;
        r_o.last  = 'b1;
    end

    if (PerfCounters) begin : gen_perf_events
        logic perf_snoop_hit;
        logic perf_snoop_miss;
        logic perf_writeback;
        logic perf_collision_cycles;
        logic perf_collision_req;
        logic perf_generic_stall;
        logic perf_ac_busy_stall;
        logic perf_mu_stall;
        logic generic_stall;

        logic collision_req_observed_q, collision_req_observed_d;

        assign generic_stall =  |{
            cr_cmd_fifo_full,
            cd_fifo_stall_i,
            arb_idx_out == 0 && (r_queue_full_i || ar_fifo_full),
            arb_idx_out == 1 && (b_queue_full_i || aw_fifo_full)
        };

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                collision_req_observed_q <= '0;
            end else begin
                collision_req_observed_q <= collision_req_observed_d;
            end
        end

        // Perf counters
        assign perf_snoop_hit        = ar_req_o && ar_gnt_i && cr_cmd_fifo_out == RESP_R && dest_o == SNOOP_UNIT;
        assign perf_snoop_miss       = ar_req_o && ar_gnt_i && cr_cmd_fifo_out == RESP_R && dest_o == MEMORY_UNIT;
        assign perf_writeback        = |({ar_req_o, aw_req_o} & {ar_gnt_i, aw_gnt_i} & {ar_wb, aw_wb}) && dest_o == MEMORY_UNIT;
        assign perf_collision_cycles = !ac_busy_q && arb_req_out && !generic_stall && collision;
        assign perf_collision_req    = perf_collision_cycles && !collision_req_observed_q;
        assign perf_generic_stall    = !ac_busy_q && arb_req_out && generic_stall;
        assign perf_ac_busy_stall    = ac_busy_q && arb_req_out && !ac_done;
        assign perf_mu_stall         = |({ar_req_o, aw_req_o} & ~{ar_gnt_i, aw_gnt_i}) && dest_o == MEMORY_UNIT;

        assign perf_evt_o = {
            perf_snoop_hit,
            perf_snoop_miss,
            perf_writeback,
            perf_collision_cycles,
            perf_collision_req,
            perf_generic_stall,
            perf_ac_busy_stall,
            perf_mu_stall
        };

        assign collision_req_observed_d = perf_collision_cycles;
    end else begin
        assign perf_evt_o = '0;
    end
endmodule