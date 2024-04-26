module ccu_ctrl_decoder import ccu_ctrl_pkg::*;
#(
    parameter int unsigned DcacheLineWidth = 0,
    parameter int unsigned AxiDataWidth = 0,
    parameter int unsigned AxiAddrWidth = 0,
    parameter int unsigned NoMstPorts = 4,
    parameter int unsigned SlvAxiIDWidth = 0,
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

    output logic                         slv_aw_ready_o,
    output logic                         slv_ar_ready_o,

    output slv_req_t                     ccu_req_holder_o,

    output logic                         su_valid_o,
    input  logic                         su_ready_i,
    output logic                         mu_valid_o,
    input  logic                         mu_ready_i,

    output mu_op_e                       mu_op_o,
    output su_op_e                       su_op_o,
    output logic                         shared_o,
    output logic                         dirty_o,
    output logic        [NoMstPorts-1:0] data_available_o,
    output logic        [MstIdxBits-1:0] first_responder_o,

    output logic                         lookup_req_o,
    output logic      [AxiAddrWidth-1:0] lookup_addr_o,
    input  logic                         b_queue_full_i,
    input  logic                         r_queue_full_i,
    input  logic                         b_collision_i,
    input  logic                         r_collision_i,

    input  logic                         cd_fifo_stall_i
);

    typedef enum logic [1:0] { INVALID_W, INVALID_R, RESP_R } cr_cmd_fifo_t;

    logic [NoMstPorts-1:0] ac_initiator;
    logic [NoMstPorts-1:0] ac_handshake_q, ac_handshake;

    logic [NoMstPorts-1:0] cr_aw_initiator, cr_ar_initiator;
    logic [NoMstPorts-1:0] cr_aw_mask, cr_ar_mask;
    logic [NoMstPorts-1:0] cr_handshake_q, cr_handshake;

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

    logic collision;

    assign collision = b_collision_i || r_collision_i;

    enum {
      IDLE,
      DECODE_R,
      DECODE_W,
      SEND_READ,
      SEND_INVALID_R,
      SEND_INVALID_W
    } state_d, state_q;

    typedef struct packed {
      logic waiting_w;
      logic waiting_r;
    } prio_t;

    prio_t prio_d, prio_q;

    logic prio_r, prio_w;

    assign prio_r = !ccu_req_i.aw_valid || prio_q.waiting_r || !prio_q.waiting_w;
    assign prio_w = !ccu_req_i.ar_valid || prio_q.waiting_w;

    logic decode_r, decode_w;

    logic send_invalid_r;

    assign send_invalid_r = ccu_req_holder_q.ar.snoop == snoop_pkg::CLEAN_UNIQUE || ccu_req_holder_q.ar.lock;

    for (genvar i = 0; i < NoMstPorts; i = i + 1) begin
        assign ac_handshake[i] = m2s_resp_i[i].ac_ready & s2m_req_o[i].ac_valid;
        assign cr_handshake[i] = m2s_resp_i[i].cr_valid & s2m_req_o[i].cr_ready;
    end

    logic cr_done;

    snoop_ac_t [NoMstPorts-1:0] ac;
    logic      [NoMstPorts-1:0] ac_valid;
    logic      [NoMstPorts-1:0] cr_ready;

    // Hold incoming ACE request
    slv_req_t ccu_req_holder_q;

    always_ff @(posedge clk_i , negedge rst_ni) begin
        if(!rst_ni) begin
            ccu_req_holder_q <= '0;
        end else if(decode_r) begin
            ccu_req_holder_q.ar       <=  ccu_req_i.ar;
            ccu_req_holder_q.ar_valid <=  ccu_req_i.ar_valid;
            ccu_req_holder_q.r_ready  <=  ccu_req_i.r_ready;
        end  else if(decode_w) begin
            ccu_req_holder_q.aw       <=  ccu_req_i.aw;
            ccu_req_holder_q.aw_valid <=  ccu_req_i.aw_valid;
        end
    end

    // Hold snoop AC handshakes
    for (genvar i = 0; i < NoMstPorts; i = i + 1) begin
        always_ff @ (posedge clk_i, negedge rst_ni) begin
            if(!rst_ni) begin
                ac_handshake_q[i] <= '0;
            end else if(state_q inside {DECODE_R, DECODE_W}) begin
                ac_handshake_q[i] <= ac_initiator[i];
            end else if(state_q inside {SEND_READ, SEND_INVALID_R, SEND_INVALID_W}) begin
                if (ac_handshake[i])
                    ac_handshake_q[i] <= 1'b1;
            end else begin
                ac_handshake_q[i] <= '0;
            end
        end
    end

    // Hold snoop CR handshakes
    logic [NoMstPorts-1:0] data_available_q, response_error_q, shared_q, dirty_q;
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
        for (int i = 0; i < NoMstPorts; i = i + 1) begin
            if(cr_handshake[i]) begin
                cr_handshake_q[i]   <=   1'b1;
                data_available_q[i] <=   m2s_resp_i[i].cr_resp.dataTransfer;
                shared_q[i]         <=   m2s_resp_i[i].cr_resp.isShared;
                dirty_q[i]          <=   m2s_resp_i[i].cr_resp.passDirty;
                response_error_q[i] <=   m2s_resp_i[i].cr_resp.error;
            end
        end
      end
    end

    assign dirty_o  = |dirty_q;
    assign shared_o = |shared_q;
    assign data_available_o = data_available_q;

    logic [MstIdxBits-1:0] first_responder_q;
    logic snoop_resp_found_q;

    always_ff @ (posedge clk_i, negedge rst_ni) begin
        if(!rst_ni) begin
            first_responder_q  <= '0;
            snoop_resp_found_q <= 1'b0;
        end else if(cr_done) begin
            first_responder_q  <= '0;
            snoop_resp_found_q <= 1'b0;
        end else if (!snoop_resp_found_q) begin
          for (int i = 0; i < NoMstPorts; i = i + 1) begin
            if(cr_handshake[i] & m2s_resp_i[i].cr_resp.dataTransfer & !m2s_resp_i[i].cr_resp.error) begin
              first_responder_q <= i[MstIdxBits-1:0];
              snoop_resp_found_q <= 1'b1;
              break;
            end
          end
        end
    end

    assign first_responder_o = first_responder_q;

    // ----------------------
    // Current State Block
    // ----------------------
    always_ff @(posedge clk_i, negedge rst_ni) begin : ccu_present_state
        if(!rst_ni) begin
            state_q <= IDLE;
            prio_q <= '0;
        end else begin
            state_q <= state_d;
            prio_q <= prio_d;
        end
    end

    // ----------------------
    // Current State Block
    // ----------------------

    always_comb begin

        ac = '0;
        ac_valid = '0;

        // Next state
        state_d = state_q;
        prio_d = prio_q;

        slv_ar_ready_o = '0;
        slv_aw_ready_o = '0;

        // Ctrl flags
        decode_r = 1'b0;
        decode_w = 1'b0;

        lookup_req_o  = 1'b0;
        lookup_addr_o = axi_pkg::aligned_addr(ccu_req_holder_q.ar.addr,ccu_req_holder_q.ar.size);

        cr_cmd_fifo_in = RESP_R;
        aw_fifo_push = 1'b0;
        ar_fifo_push = 1'b0;

        ac_initiator = '0;

        case (state_q)
            IDLE: begin

                prio_d = '0;
                //  wait for incoming valid request from master
                if(ccu_req_i.ar_valid & prio_r) begin
                    decode_r = 1'b1;
                    state_d = DECODE_R;
                    prio_d.waiting_w = ccu_req_i.aw_valid;
                end else if(ccu_req_i.aw_valid & prio_w) begin
                    decode_w = 1'b1;
                    state_d = DECODE_W;
                    prio_d.waiting_r = ccu_req_i.ar_valid;
                end
            end

            DECODE_W: begin
                // AC initiator
                ac_initiator = '0;
                ac_initiator[ccu_req_i.aw.id[SlvAxiIDWidth+:MstIdxBits]] = 1'b1;
                // Collision lookup
                lookup_req_o = 1'b1;
                lookup_addr_o = axi_pkg::aligned_addr(ccu_req_holder_q.aw.addr,ccu_req_holder_q.aw.size);
                // Stall or accept request
                if (!collision && !b_queue_full_i && !cd_fifo_stall_i) begin
                    state_d = SEND_INVALID_W;
                    slv_aw_ready_o = 1'b1;
                end
            end

            DECODE_R: begin
                // AC initiator
                ac_initiator = '0;
                ac_initiator[ccu_req_i.ar.id[SlvAxiIDWidth+:MstIdxBits]] = 1'b1;
                // Collision lookup
                lookup_req_o = 1'b1;
                lookup_addr_o = axi_pkg::aligned_addr(ccu_req_holder_q.ar.addr,ccu_req_holder_q.ar.size);
                // Stall or accept request
                if (!collision && !r_queue_full_i && !cd_fifo_stall_i) begin
                    state_d = send_invalid_r ? SEND_INVALID_R : SEND_READ;
                    slv_ar_ready_o = 1'b1;
                end
            end

            SEND_READ: begin
                cr_cmd_fifo_in = RESP_R;
                // wait for all snoop masters to perform an handshake
                if (ac_handshake_q == '1 && !cr_cmd_fifo_full && !ar_fifo_full) begin
                    state_d = IDLE;
                    ar_fifo_push = 1'b1;
                end
                // send request to snooping masters
                for (int unsigned n = 0; n < NoMstPorts; n = n + 1) begin
                    ac[n].addr   =   ccu_req_holder_q.ar.addr;
                    ac[n].prot   =   ccu_req_holder_q.ar.prot;
                    ac[n].snoop  =   ccu_req_holder_q.ar.snoop;
                    ac_valid[n]  =   !ac_handshake_q[n];
                end
            end

            SEND_INVALID_R: begin
                cr_cmd_fifo_in = INVALID_R;
                // wait for all snoop masters to perform an handshake
                if (ac_handshake_q == '1 && !cr_cmd_fifo_full && !ar_fifo_full) begin
                    state_d = IDLE;
                    ar_fifo_push = 1'b1;
                end
                // send request to snooping masters
                for (int unsigned n = 0; n < NoMstPorts; n = n + 1) begin
                ac[n].addr   =   ccu_req_holder_q.ar.addr;
                ac[n].prot   =   ccu_req_holder_q.ar.prot;
                ac[n].snoop  =   snoop_pkg::CLEAN_INVALID;
                ac_valid[n]  =   !ac_handshake_q[n];
            end
            end

            SEND_INVALID_W: begin
                cr_cmd_fifo_in = INVALID_W;
                 // wait for all snoop masters to perform an handshake
                if (ac_handshake_q == '1 && !cr_cmd_fifo_full && !aw_fifo_full) begin
                    state_d = IDLE;
                    aw_fifo_push = 1'b1;
                end
                // send request to snooping masters
                for (int unsigned n = 0; n < NoMstPorts; n = n + 1) begin
                    ac[n].addr  = ccu_req_holder_q.aw.addr;
                    ac[n].prot  = ccu_req_holder_q.aw.prot;
                    ac[n].snoop = snoop_pkg::CLEAN_INVALID;
                    ac_valid[n] = !ac_handshake_q[n];
                end
            end
        endcase
    end

    assign cr_aw_initiator = 1 << aw_fifo_out.id[SlvAxiIDWidth+:MstIdxBits];
    assign cr_ar_initiator = 1 << ar_fifo_out.id[SlvAxiIDWidth+:MstIdxBits];
    assign cr_aw_mask      = cr_aw_initiator | cr_handshake_q;
    assign cr_ar_mask      = cr_ar_initiator | cr_handshake_q;

    assign cr_done         = (mu_valid_o && mu_ready_i) || (su_valid_o && su_ready_i);

    always_comb begin

        su_valid_o  = 1'b0;
        mu_valid_o  = 1'b0;
        su_op_o = READ_SNP_DATA;
        mu_op_o = SEND_AXI_REQ_R;

        aw_fifo_pop = '0;
        ar_fifo_pop = '0;

        cr_ready = '0;

        if (!cr_cmd_fifo_empty) begin
            case (cr_cmd_fifo_out)

                RESP_R: begin
                    // wait for all CR handshakes
                    if (cr_ar_mask == '1) begin

                        if(|(data_available_q & ~response_error_q)) begin
                            su_op_o = READ_SNP_DATA;
                            su_valid_o = 1'b1;
                            if (su_ready_i) begin
                                ar_fifo_pop = 1'b1;
                            end
                        end else begin
                            mu_op_o = SEND_AXI_REQ_R;
                            mu_valid_o = 1'b1;
                            if (mu_ready_i) begin
                                ar_fifo_pop = 1'b1;
                            end
                        end
                    end

                    for (int unsigned n = 0; n < NoMstPorts; n = n + 1)
                        cr_ready[n]  = !cr_ar_mask[n];
                end

                INVALID_R: begin
                    // wait for all CR handshakes
                    if (cr_ar_mask == '1) begin

                        if (mu_ready_i && (ar_fifo_out.lock || su_ready_i)) begin
                            ar_fifo_pop = 1'b1;
                            su_valid_o = !ar_fifo_out.lock;
                        end

                        if(|(data_available_q & ~response_error_q)) begin
                            mu_op_o = SEND_AXI_REQ_WRITE_BACK_R;
                            mu_valid_o = 1'b1;
                        end else if (ar_fifo_out.lock) begin
                            mu_op_o = SEND_AXI_REQ_R;
                            mu_valid_o = 1'b1;
                        end
                    end

                    su_op_o = SEND_INVALID_ACK_R;

                    for (int unsigned n = 0; n < NoMstPorts; n = n + 1)
                        cr_ready[n]  =  !cr_ar_mask[n];
                end

                INVALID_W: begin
                    // wait for all CR handshakes
                    if (cr_aw_mask == '1) begin

                        mu_valid_o = 1'b1;

                        if (mu_ready_i) begin
                            aw_fifo_pop = 1'b1;
                        end

                        if(|(data_available_q & ~response_error_q)) begin
                            mu_op_o = SEND_AXI_REQ_WRITE_BACK_W;
                        end else begin
                            mu_op_o = SEND_AXI_REQ_W;
                        end
                    end

                    for (int unsigned n = 0; n < NoMstPorts; n = n + 1)
                        cr_ready[n]  = !cr_aw_mask[n];
                end
            endcase
        end
    end

    always_comb begin
        s2m_req_o = '0;
        for (int unsigned n = 0; n < NoMstPorts; n = n + 1) begin
            s2m_req_o[n].ac = ac[n];
            s2m_req_o[n].ac_valid = ac_valid[n];
            s2m_req_o[n].cr_ready = cr_ready[n];
        end
    end

    assign cr_cmd_fifo_push = aw_fifo_push || ar_fifo_push;
    assign cr_cmd_fifo_pop  = aw_fifo_pop  || ar_fifo_pop;

    fifo_v3 #(
        .FALL_THROUGH(1),
        .DEPTH(NoMstPorts),
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

    assign ar_fifo_in = ccu_req_holder_q.ar;
    assign ccu_req_holder_o.ar = ar_fifo_out;

    fifo_v3 #(
        .FALL_THROUGH(1),
        .DEPTH(NoMstPorts),
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

    assign aw_fifo_in = ccu_req_holder_q.aw;
    assign ccu_req_holder_o.aw = aw_fifo_out;

    fifo_v3 #(
        .FALL_THROUGH(1),
        .DEPTH(NoMstPorts),
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

endmodule