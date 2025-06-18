// Copyright (c) 2025 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

module ace_ccu_tracker
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg    = '{default: '0},
    parameter type          slv_bv_t  = logic,
    parameter type          slv_idx_t = logic,
    parameter type          nline_t   = logic,
    parameter type          ccu_id_t  = logic,
    parameter type          tid_t     = logic
) (
    input logic clk_i,
    input logic rst_ni,

    output logic full_o,

    //  Check/alloc interface
    //  {{{
    input  logic    check_i,
    output logic    check_hit_o,
    input  logic    alloc_i,
    input  logic    alloc_b_i,
    input  logic    alloc_r_i,
    input  nline_t  alloc_nline_i,
    input  ccu_id_t alloc_id_i,
    output tid_t    alloc_tid_o,
    //  }}}

    //  Lookup/dealloc interface
    //  {{{
    input  slv_bv_t dealloc_rack_i,
    input  slv_bv_t dealloc_wack_i,
    input  logic    dealloc_r_resp_i,
    input  ccu_id_t dealloc_r_resp_id_i,
    input  logic    dealloc_b_resp_i,
    input  logic    dealloc_check_b_resp_i,
    input  ccu_id_t dealloc_b_resp_id_i,
    output logic    dealloc_b_resp_wb_o,
    //  }}}

    input logic updt_wb_i,
    input tid_t updt_wb_tid_i
);

    //  Typedefs
    //  {{{
    typedef struct packed {
        logic r;
        logic b;
        logic wb;
    } meta_t;

    typedef struct packed {
        nline_t  nline;
        ccu_id_t id;
    } data_t;
    //  }}}

    //  Internal signals
    //  {{{
    logic  [CcuCfg.u.MaxTransactions-1:0] valid_q;
    logic  [CcuCfg.u.MaxTransactions-1:0] valid_d;
    logic  [CcuCfg.u.MaxTransactions-1:0] valid_set;
    logic  [CcuCfg.u.MaxTransactions-1:0] valid_clr;

    meta_t [CcuCfg.u.MaxTransactions-1:0] meta_q;
    meta_t [CcuCfg.u.MaxTransactions-1:0] meta_d;
    meta_t [CcuCfg.u.MaxTransactions-1:0] meta_set;
    meta_t [CcuCfg.u.MaxTransactions-1:0] meta_clr;
    data_t [CcuCfg.u.MaxTransactions-1:0] data_q;

    logic  [CcuCfg.u.MaxTransactions-1:0] hit_id_bv;
    logic  [CcuCfg.u.MaxTransactions-1:0] hit_nline_bv;

    tid_t                                 rack_queue_wdata;
    tid_t                                 wack_queue_wdata;
    tid_t  [           CcuCfg.u.SlvPorts] rack_queue_rdata;
    tid_t  [           CcuCfg.u.SlvPorts] wack_queue_rdata;
    //  }}}

    //  Alloc logic
    //  {{{
    for (genvar i = 0; i < CcuCfg.u.MaxTransactions; i++) begin : gen_alloc
        assign valid_set[i]  = alloc_i && (i == alloc_tid_o);
        assign meta_set[i].r = valid_set[i] && alloc_r_i;
        assign meta_set[i].b = valid_set[i] && alloc_b_i;
    end

    always_comb begin : alloc_tid_comb
        alloc_tid_o = '0;
        for (int unsigned i = 0; i < CcuCfg.u.MaxTransactions; i++) begin
            if (!valid_q[i]) begin
                alloc_tid_o = CcuCfg.TransactionIdxWidth'(i);
                break;
            end
        end
    end
    //  }}}

    //  Dealloc logic
    //  {{{

    // Deallocation logic has some complexity due to the need of handling the rack and wack signals
    // from all master, which cannot be stalled and can arrive in parallel in the same cycle
    // TODO: can this be simplified?
    for (genvar i = 0; i < CcuCfg.u.MaxTransactions; i++) begin : gen_dealloc
        slv_idx_t dealloc_slv_id;
        assign dealloc_slv_id = data_q[i].id[CcuCfg.AxiCcuIdWidth-1 : CcuCfg.u.AxiSlvIdWidth];
        assign meta_clr[i].r  = dealloc_rack_i[dealloc_slv_id] && (i == rack_queue_rdata[dealloc_slv_id]);
        assign meta_clr[i].b  = dealloc_wack_i[dealloc_slv_id] && (i == wack_queue_rdata[dealloc_slv_id]);
        assign valid_clr[i] = ~|meta_d[i];
    end


    always_comb begin : xack_queue_wdata_mux
        rack_queue_wdata = '0;
        wack_queue_wdata = '0;

        for (int unsigned i = 0; i < CcuCfg.u.MaxTransactions; i++) begin
            if (dealloc_b_resp_id_i == data_q[i].id && valid_q[i])
                wack_queue_wdata = CcuCfg.TransactionIdxWidth'(i);
            if (dealloc_r_resp_id_i == data_q[i].id && valid_q[i])
                rack_queue_wdata = CcuCfg.TransactionIdxWidth'(i);
        end
    end

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_xack_queues
        logic wack_queue_push;
        logic rack_queue_push;

        // Push an entry ID to the wack/rack queues if the dealloc response matches the ID of the transaction
        // that is being deallocated
        assign wack_queue_push = dealloc_b_resp_i && data_q[wack_queue_wdata].id[CcuCfg.AxiCcuIdWidth-1 : CcuCfg.u.AxiSlvIdWidth] == CcuCfg.SlvPortIdxWidth'(i);
        assign rack_queue_push = dealloc_r_resp_i && data_q[rack_queue_wdata].id[CcuCfg.AxiCcuIdWidth-1 : CcuCfg.u.AxiSlvIdWidth] == CcuCfg.SlvPortIdxWidth'(i);

        fifo_v3 #(
            .FALL_THROUGH(1'b0),
            .DEPTH       (CcuCfg.u.MaxTransactions),
            .dtype       (tid_t)
        ) u_tracker_wack_queue (
            .clk_i,
            .rst_ni,
            .flush_i   (1'b0),
            .testmode_i(1'b0),
            .full_o    (),
            .empty_o   (),
            .usage_o   (),
            .data_i    (wack_queue_wdata),
            .push_i    (wack_queue_push),
            .data_o    (wack_queue_rdata[i]),
            .pop_i     (dealloc_wack_i[i])
        );

        fifo_v3 #(
            .FALL_THROUGH(1'b0),
            .DEPTH       (CcuCfg.u.MaxTransactions),
            .dtype       (tid_t)
        ) u_tracker_rack_queue (
            .clk_i,
            .rst_ni,
            .flush_i   (1'b0),
            .testmode_i(1'b0),
            .full_o    (),
            .empty_o   (),
            .usage_o   (),
            .data_i    (rack_queue_wdata),
            .push_i    (rack_queue_push),
            .data_o    (rack_queue_rdata[i]),
            .pop_i     (dealloc_rack_i[i])
        );
    end
    //  }}}

    //  State holding elements
    //  {{{
    for (genvar i = 0; i < CcuCfg.u.MaxTransactions; i++) begin : gen_ffs
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                data_q[i] <= '0;
            end else if (valid_set[i]) begin
                data_q[i] <= '{nline: alloc_nline_i, id: alloc_id_i};
            end
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                meta_q[i]  <= '0;
                valid_q[i] <= 1'b0;
            end else begin
                meta_q[i]  <= meta_d[i];
                valid_q[i] <= valid_d[i];
            end
        end

        assign meta_d[i]  = (meta_set[i] & ~meta_q[i]) | (~meta_clr[i] & meta_q[i]);
        assign valid_d[i] = (valid_set[i] & ~valid_q[i]) | (~valid_clr[i] & valid_q[i]);
    end
    //  }}}

    //  Check logic
    //  {{{
    for (genvar i = 0; i < CcuCfg.u.MaxTransactions; i++) begin : gen_check
        assign hit_id_bv[i]    = valid_q[i] && (data_q[i].id == alloc_id_i);
        assign hit_nline_bv[i] = valid_q[i] && (data_q[i].nline == alloc_nline_i);
    end

    assign check_hit_o = check_i && |{hit_id_bv, hit_nline_bv};
    //  }}}

    //  Writeback logic
    //  {{{
    for (genvar i = 0; i < CcuCfg.u.MaxTransactions; i++) begin : gen_writeback
        assign meta_set[i].wb = updt_wb_i && updt_wb_tid_i == CcuCfg.TransactionIdxWidth'(i);
        assign meta_clr[i].wb = dealloc_check_b_resp_i && wack_queue_wdata == CcuCfg.TransactionIdxWidth'(i);
    end

    assign dealloc_b_resp_wb_o = dealloc_check_b_resp_i && meta_q[wack_queue_wdata].wb;
    //  }}}

    //  Global control
    //  {{{
    assign full_o              = (valid_q == '1);
    //  }}}

endmodule
