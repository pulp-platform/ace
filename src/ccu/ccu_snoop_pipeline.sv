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
//
// Authors:
// - Riccardo Tedeschi <riccardo.tedeschi6@unibo.it>

`include "axi/assign.svh"

module ccu_snoop_pipeline
    import ace_pkg::*;
    import ccu_pkg::*;
#(
    parameter ccu_config_t ccuCfg         = '{default: '0},
    parameter type         ccu_ace_ar_t   = logic,
    parameter type         ccu_ace_r_t    = logic,
    parameter type         ccu_snoop_ac_t = logic,
    parameter type         ccu_snoop_cr_t = logic,
    parameter type         ccu_snoop_cd_t = logic,
    parameter type         ccu_w_t        = logic,
    parameter type         ccu_axi_ar_t   = logic,
    parameter type         ccu_axi_aw_t   = logic,
    parameter type         domain_map_t   = logic
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    input domain_map_t  [ccuCfg.u.numSubordinates-1:0]       domain_map_i,

    input  ccu_ace_ar_t                                      ar_i,
    input  logic                                             ar_valid_i,
    output logic                                             ar_ready_o,

    output logic          [ccuCfg.u.numSubordinates-1:0]     ac_valid_o,
    input  logic          [ccuCfg.u.numSubordinates-1:0]     ac_ready_i,
    output ccu_snoop_ac_t [ccuCfg.u.numSubordinates-1:0]     ac_o,

    input  logic          [ccuCfg.u.numSubordinates-1:0]     cr_valid_i,
    output logic          [ccuCfg.u.numSubordinates-1:0]     cr_ready_o,
    input  ccu_snoop_cr_t [ccuCfg.u.numSubordinates-1:0]     cr_i,

    input  logic          [ccuCfg.u.numSubordinates-1:0]     cd_valid_i,
    output logic          [ccuCfg.u.numSubordinates-1:0]     cd_ready_o,
    input  ccu_snoop_cd_t [ccuCfg.u.numSubordinates-1:0]     cd_i,

    output logic                                             write_engine_aw_valid_o,
    input  logic                                             write_engine_aw_ready_i,
    output ccu_axi_aw_t                                      write_engine_aw_o,
    output logic                                             write_engine_w_valid_o,
    input  logic                                             write_engine_w_ready_i,
    output ccu_w_t                                           write_engine_w_o,

    output logic                                             read_engine_ar_valid_o,
    input  logic                                             read_engine_ar_ready_i,
    output ccu_axi_ar_t                                      read_engine_ar_o,
    output logic                                             read_engine_r_valid_o,
    input  logic                                             read_engine_r_ready_i,
    output ccu_ace_r_t                                       read_engine_r_o,

    output ccu_snoop_pipeline_events_t                       events_o
);

//  AC channel
//  {{{
    typedef struct packed {
        ccu_snoop_ac_t                              ac;
        logic        [ccuCfg.u.numSubordinates-1:0] sel;
    } ac_fifo_entry_t;

    ccu_snoop_ac_t                                  ac;
    logic           [ccuCfg.u.numSubordinates-1:0]  ac_sel;
    logic                                           ac_valid;
    logic                                           ac_ready;
    ac_fifo_entry_t                                 ac_fifo_wdata;
    ac_fifo_entry_t                                 ac_fifo_rdata;
    logic                                           ac_fifo_valid;
    logic                                           ac_fifo_ready;

    assign ac_fifo_wdata = '{
        ac:  ac,
        sel: ac_sel
    };

    stream_fifo #(
        .FALL_THROUGH (ccuCfg.u.snoopReqFifoFallthrough),
        .DEPTH        (ccuCfg.u.numSnoopTransactions),
        .T            (ac_fifo_entry_t)
    ) u_ac_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .data_i     (ac_fifo_wdata),
        .valid_i    (ac_valid),
        .ready_o    (ac_ready),
        .data_o     (ac_fifo_rdata),
        .valid_o    (ac_fifo_valid),
        .ready_i    (ac_fifo_ready)
    );

    assign ac_o = {ccuCfg.u.numSubordinates{ac_fifo_rdata.ac}};

    stream_fork_dynamic #(
        .N_OUP (ccuCfg.u.numSubordinates)
    ) u_ac_fifo_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (ac_fifo_valid),
        .ready_o     (ac_fifo_ready),
        .sel_i       (ac_fifo_rdata.sel),
        .sel_valid_i (1'b1),
        .sel_ready_o (),
        .valid_o     (ac_valid_o),
        .ready_i     (ac_ready_i)
    );
//  }}}

//  CR channel
//  {{{
    logic          [ccuCfg.u.numSubordinates-1:0] cr_fifo_valid;
    logic          [ccuCfg.u.numSubordinates-1:0] cr_fifo_ready;
    ccu_snoop_cr_t [ccuCfg.u.numSubordinates-1:0] cr_fifo_rdata;

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_cr_fifo
        stream_fifo #(
            .FALL_THROUGH (ccuCfg.u.snoopRespFifoFallthrough),
            .DEPTH        (ccuCfg.u.numSnoopTransactions),
            .T            (ccu_snoop_cr_t)
        ) u_cr_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .usage_o    (),
            .data_i     (cr_i[s]),
            .valid_i    (cr_valid_i[s]),
            .ready_o    (cr_ready_o[s]),
            .data_o     (cr_fifo_rdata[s]),
            .valid_o    (cr_fifo_valid[s]),
            .ready_i    (cr_fifo_ready[s])
        );
    end
//  }}}

//  CD channel
//  {{{
    logic          [ccuCfg.u.numSubordinates-1:0] cd_fifo_valid;
    logic          [ccuCfg.u.numSubordinates-1:0] cd_fifo_ready;
    ccu_snoop_cd_t [ccuCfg.u.numSubordinates-1:0] cd_fifo_rdata;

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_cd_fifo
        stream_fifo #(
            .FALL_THROUGH (ccuCfg.u.snoopRespFifoFallthrough),
            .DEPTH        (ccuCfg.u.numSnoopTransactions),
            .T            (ccu_snoop_cd_t)
        ) u_cd_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .usage_o    (),
            .data_i     (cd_i[s]),
            .valid_i    (cd_valid_i[s]),
            .ready_o    (cd_ready_o[s]),
            .data_o     (cd_fifo_rdata[s]),
            .valid_o    (cd_fifo_valid[s]),
            .ready_i    (cd_fifo_ready[s])
        );
    end
//  }}}


// Stage 0
// {{{
    logic        [ccuCfg.subordinateIndexWidth-1:0] subordinate_ar_index;
    logic                                           ar_is_read_no_snoop;
    acsnoop_t                                       ac_snoop;
    logic                                           stage0_valid;
    logic                                           stage0_ready;

    assign ac_snoop = ace_ar_acsnoop_map(
        ar_i.bar[0],
        ar_i.domain,
        ar_i.snoop
    );

    assign ar_is_read_no_snoop = ace_is_read_no_snoop(
        ar_i.bar[0],
        ar_i.domain,
        ar_i.snoop
    );

    assign subordinate_ar_index = ar_i.id[ccuCfg.u.axiSubordinateIdWidth+:ccuCfg.subordinateIndexWidth];

    always_comb begin : ace_sel_comb
        unique case (ar_i.domain)
            NonShareable  : ac_sel = '0;
            InnerShareable: ac_sel = domain_map_i[subordinate_ar_index].inner;
            OuterShareable: ac_sel = domain_map_i[subordinate_ar_index].outer;
            default:        ac_sel = ~domain_map_i[subordinate_ar_index].initiator;
        endcase
    end

    assign ac = '{
        addr: axi_pkg::aligned_addr(ar_i.addr, ccuCfg.cachelineByteIndexWidth),
        snoop: ac_snoop,
        prot: ar_i.prot
    };

    stream_fork_dynamic #(
        .N_OUP (2)
    ) u_ac_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (ar_valid_i),
        .ready_o     (ar_ready_o),
        .sel_i       ({!ar_is_read_no_snoop, 1'b1}),
        .sel_valid_i (1'b1),
        .sel_ready_o (),
        .valid_o     ({ac_valid, stage0_valid}),
        .ready_i     ({ac_ready, stage0_ready})
    );
//  }}}

//  Stage 1
//  {{{
    typedef struct packed {
        ccu_ace_ar_t                                ar;
        logic        [ccuCfg.u.numSubordinates-1:0] sel;
    } stage1_fifo_entry_t;

    logic                                stage1_fifo_valid;
    logic                                stage1_fifo_ready;
    stage1_fifo_entry_t                  stage1_fifo_wdata;
    stage1_fifo_entry_t                  stage1_fifo_rdata;
    logic                                accepts_dirty;
    logic                                accepts_shared;
    logic                                is_clean_or_make;
    ccu_snoop_cr_t                       cr;
    logic [ccuCfg.u.numSubordinates-1:0] cd_data_transfer;
    logic                                engine_fork_valid;
    logic                                engine_fork_ready;
    logic                                read_engine_sel;
    logic                                cd_engine_sel;
    logic                                cd_engine_forward_to_read;
    logic                                cd_engine_forward_to_write;
    logic                                cd_engine_ack_to_read;
    logic                                cd_engine_valid;
    logic                                cd_engine_ready;
    logic                                cd_engine_resp_shared;
    logic                                cd_engine_resp_dirty;

    assign stage1_fifo_wdata = '{
        ar : ar_i,
        sel: ac_sel
    };

    stream_fifo #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (ccuCfg.u.numSnoopTransactions),
        .T            (stage1_fifo_entry_t)
    ) u_stage1_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .data_i     (stage1_fifo_wdata),
        .valid_i    (stage0_valid),
        .ready_o    (stage0_ready),
        .data_o     (stage1_fifo_rdata),
        .valid_o    (stage1_fifo_valid),
        .ready_i    (stage1_fifo_ready)
    );

    stream_join_dynamic #(
        .N_INP (ccuCfg.u.numSubordinates+1)
    ) u_cr_join (
        .inp_valid_i ({cr_fifo_valid, stage1_fifo_valid}),
        .inp_ready_o ({cr_fifo_ready, stage1_fifo_ready}),
        .sel_i       ({stage1_fifo_rdata.sel, 1'b1}),
        .oup_valid_o (engine_fork_valid),
        .oup_ready_i (engine_fork_ready)
    );

    always_comb begin : cr_comb
        cr = '0;
        cd_data_transfer = '0;
        for (int unsigned s = 0; s < ccuCfg.u.numSubordinates; s++) begin
            if (stage1_fifo_rdata.sel[s]) begin
                cr = cr | cr_fifo_rdata[s];
                cd_data_transfer[s] = cr_fifo_rdata[s].resp.DataTransfer;
            end
        end
    end

    assign accepts_dirty = ace_ar_accepts_dirty(
        stage1_fifo_rdata.ar.bar[0],
        stage1_fifo_rdata.ar.domain,
        stage1_fifo_rdata.ar.snoop
    );

    assign accepts_shared = ace_ar_accepts_shared(
        stage1_fifo_rdata.ar.bar[0],
        stage1_fifo_rdata.ar.domain,
        stage1_fifo_rdata.ar.snoop
    );

    assign is_clean_or_make = ace_ar_is_clean(
        stage1_fifo_rdata.ar.bar[0],
        stage1_fifo_rdata.ar.domain,
        stage1_fifo_rdata.ar.snoop
    ) || ace_ar_is_make(
        stage1_fifo_rdata.ar.bar[0],
        stage1_fifo_rdata.ar.domain,
        stage1_fifo_rdata.ar.snoop
    );

    always_comb begin : engine_sel_comb
        read_engine_sel            = 1'b0;
        cd_engine_sel              = 1'b0;
        cd_engine_forward_to_read  = 1'b0;
        cd_engine_forward_to_write = 1'b0;
        cd_engine_ack_to_read      = 1'b0;

        case ({cr.resp.DataTransfer, is_clean_or_make})
            //  Forward the request to memory
            2'b00: read_engine_sel = 1'b1;
            //  Clean/make with no data: acknowledge only
            2'b01: begin
                cd_engine_sel         = 1'b1;
                cd_engine_ack_to_read = 1'b1;
            end
            //  At least one snooped manager is providing data: forward it to
            //  the initiator (normal read) or acknowledge (clean/make)
            default: begin
                cd_engine_sel             = 1'b1;
                cd_engine_forward_to_read = !is_clean_or_make;
                cd_engine_ack_to_read     = is_clean_or_make;
                if (cr.resp.PassDirty && !accepts_dirty) begin
                    //  The initiator cannot accept dirty data, writeback
                    cd_engine_forward_to_write = 1'b1;
                end
            end
        endcase
    end

    stream_fork_dynamic #(
        .N_OUP(2)
    ) u_engine_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (engine_fork_valid),
        .ready_o    (engine_fork_ready),
        .sel_i      ({read_engine_sel, cd_engine_sel}),
        .sel_valid_i(1'b1),
        .sel_ready_o(),
        .valid_o    ({read_engine_ar_valid_o, cd_engine_valid}),
        .ready_i    ({read_engine_ar_ready_i, cd_engine_ready})
    );

    always_comb begin : read_engine_ar_comb
        //  ACE to AXI conversion can be done via the macro
        `AXI_SET_AR_STRUCT(read_engine_ar_o, stage1_fifo_rdata.ar)
    end

    assign cd_engine_resp_shared = cr.resp.IsShared  && accepts_shared;
    assign cd_engine_resp_dirty  = cr.resp.PassDirty && accepts_dirty;
//  }}}

//  CD engine
//  {{{
    localparam int unsigned cachelineTransferIndexWidth = ccuCfg.cachelineAxiTransfers > 1 ?
                                                          $clog2(ccuCfg.cachelineAxiTransfers) : 1;

    typedef struct packed {
        logic [ccuCfg.u.numSubordinates-1:0]     sel;
        logic                                    forward_to_read;
        logic                                    forward_to_write;
        logic                                    ack_to_read;
        logic                                    resp_shared;
        logic                                    resp_dirty;
        ccu_ace_ar_t                             ar;
    } cd_engine_fifo_entry_t;

    logic                  cd_engine_fifo_valid;
    logic                  cd_engine_fifo_ready;
    cd_engine_fifo_entry_t cd_engine_fifo_wdata;
    cd_engine_fifo_entry_t cd_engine_fifo_rdata;

    assign cd_engine_fifo_wdata  = '{
        sel:              cd_data_transfer,
        forward_to_read:  cd_engine_forward_to_read,
        forward_to_write: cd_engine_forward_to_write,
        ack_to_read:      cd_engine_ack_to_read,
        resp_shared:      cd_engine_resp_shared,
        resp_dirty:       cd_engine_resp_dirty,
        ar:               stage1_fifo_rdata.ar
    };

    logic                                   cd_global_counter_en;
    logic [cachelineTransferIndexWidth-1:0] cd_global_counter_q;

    rresp_t                                 cd_r_resp;
    logic [ccuCfg.u.numSubordinates-1:0]    cd_up_to_date;
    logic [ccuCfg.u.numSubordinates-1:0]    cd_valid;
    logic [ccuCfg.u.numSubordinates-1:0]    cd_ready;
    ccu_snoop_cd_t                          cd;
    logic                                   cd_engine_data_valid;
    logic                                   cd_engine_data_ready;
    logic                                   cd_read_valid;
    logic                                   cd_read_ready;

    stream_fifo #(
        .FALL_THROUGH (1'b0),
        .DEPTH        (ccuCfg.u.numSnoopTransactions),
        .T            (cd_engine_fifo_entry_t)
    ) u_cd_engine_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .data_i     (cd_engine_fifo_wdata),
        .valid_i    (cd_engine_valid),
        .ready_o    (cd_engine_ready),
        .data_o     (cd_engine_fifo_rdata),
        .valid_o    (cd_engine_fifo_valid),
        .ready_i    (cd_engine_fifo_ready)
    );

    //  Head-entry fork branches: writeback AW, CD data, initiator ack
    logic cd_fork_valid;
    logic cd_fork_ready;
    logic ack_branch_valid;
    logic ack_branch_ready;
    logic aw_committed_q;
    logic aw_committed_set;
    logic aw_committed_clear;
    logic aw_committed_d;
    logic aw_handshake;
    logic aw_token_valid;
    logic aw_token_ready;
    logic ordered_ack_valid;
    logic ordered_ack_ready;

    always_comb begin : write_engine_aw_comb
        //  Derive the writeback AW from the AR. The id is irrelevant here:
        //  the write engine swaps it for the address hash.
        write_engine_aw_o.id     = '0;
        write_engine_aw_o.addr   = axi_pkg::aligned_addr(cd_engine_fifo_rdata.ar.addr, ccuCfg.cachelineByteIndexWidth);
        write_engine_aw_o.len    = ccuCfg.cachelineAxiTransfers - 1;
        write_engine_aw_o.size   = ccuCfg.axiDataSize;
        write_engine_aw_o.burst  = axi_pkg::BURST_INCR;
        write_engine_aw_o.lock   = 1'b0;
        write_engine_aw_o.cache  = cd_engine_fifo_rdata.ar.cache;
        write_engine_aw_o.prot   = cd_engine_fifo_rdata.ar.prot;
        write_engine_aw_o.qos    = cd_engine_fifo_rdata.ar.qos;
        write_engine_aw_o.region = cd_engine_fifo_rdata.ar.region;
        write_engine_aw_o.atop   = '0;
        write_engine_aw_o.user   = cd_engine_fifo_rdata.ar.user;
    end

    assign cd_valid      = cd_fifo_valid & cd_engine_fifo_rdata.sel;
    assign cd_fifo_ready = cd_ready      & cd_engine_fifo_rdata.sel;

    assign cd_engine_data_valid = |(cd_valid & cd_up_to_date);
    assign cd_global_counter_en = cd_engine_data_valid && cd_engine_data_ready;

    counter #(
        .WIDTH (cachelineTransferIndexWidth)
    ) u_cd_global_counter (
        .clk_i,
        .rst_ni,
        .clear_i     (1'b0),
        .en_i        (cd_global_counter_en),
        .load_i      (1'b0),
        .down_i      (1'b0),
        .d_i         ('0),
        .q_o         (cd_global_counter_q),
        .overflow_o  ()
    );

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_cd_local_counter

        logic                                   cd_local_counter_en;
        logic [cachelineTransferIndexWidth-1:0] cd_local_counter_q;

        counter #(
            .WIDTH (cachelineTransferIndexWidth)
        ) u_cd_local_counter (
            .clk_i,
            .rst_ni,
            .clear_i     (1'b0),
            .en_i        (cd_local_counter_en),
            .load_i      (1'b0),
            .down_i      (1'b0),
            .d_i         ('0),
            .q_o         (cd_local_counter_q),
            .overflow_o  ()
        );
        assign cd_local_counter_en = cd_valid[s] && cd_ready[s];
        assign cd_up_to_date[s]    = cd_local_counter_q == cd_global_counter_q;
        assign cd_ready[s]         = !cd_up_to_date[s] || cd_engine_data_ready;
    end

    always_comb begin : cd_mux_comb
        cd = cd_fifo_rdata[0];
        for (int s = 0; s < ccuCfg.u.numSubordinates; s++) begin
            if (cd_valid[s] && cd_up_to_date[s]) begin
                cd = cd_fifo_rdata[s];
                break;
            end
        end
    end

    //  {ACK, AW, DATA}: pops the entry only when every selected branch has
    //  handshaked; DATA completes on the last CD beat
    stream_fork_dynamic #(
        .N_OUP (3)
    ) u_cd_engine_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (cd_engine_fifo_valid),
        .ready_o     (cd_engine_fifo_ready),
        .sel_i       ({cd_engine_fifo_rdata.ack_to_read,
                       cd_engine_fifo_rdata.forward_to_write,
                       |cd_engine_fifo_rdata.sel}),
        .sel_valid_i (1'b1),
        .sel_ready_o (),
        .valid_o     ({ack_branch_valid, write_engine_aw_valid_o, cd_fork_valid}),
        .ready_i     ({ack_branch_ready, write_engine_aw_ready_i, cd_fork_ready && cd.last})
    );

    //  Per-beat CD data fork to the initiator (read) and/or the writeback W,
    //  driven while the entry's DATA branch is active
    stream_fork_dynamic #(
        .N_OUP (2)
    ) u_cd_data_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (cd_engine_data_valid),
        .ready_o     (cd_engine_data_ready),
        .sel_i       ({cd_engine_fifo_rdata.forward_to_read, cd_engine_fifo_rdata.forward_to_write}),
        .sel_valid_i (cd_fork_valid),
        .sel_ready_o (cd_fork_ready),
        .valid_o     ({cd_read_valid, write_engine_w_valid_o}),
        .ready_i     ({cd_read_ready, write_engine_w_ready_i})
    );

    always_comb begin : rresp_comb
        cd_r_resp[RESP_IS_DIRTY]  = cd_engine_fifo_rdata.resp_dirty;
        cd_r_resp[RESP_IS_SHARED] = cd_engine_fifo_rdata.resp_shared;
        if (cd_engine_fifo_rdata.ar.lock)
            cd_r_resp[axi_pkg::RespWidth-1:0] = axi_pkg::RESP_EXOKAY;
        else
            cd_r_resp[axi_pkg::RespWidth-1:0] = axi_pkg::RESP_OKAY;
    end

    assign write_engine_w_o = '{
        data: cd.data,
        strb: '1,
        last: cd.last,
        user: cd_engine_fifo_rdata.ar.user
    };

    ccu_ace_r_t ack_r;
    ccu_ace_r_t cd_read_r;

    //  AW-committed token, joined with the ack branch to order the ack
    assign aw_handshake   = write_engine_aw_valid_o && write_engine_aw_ready_i;
    assign aw_token_valid = !cd_engine_fifo_rdata.forward_to_write || aw_committed_q;

    assign aw_committed_set   = aw_handshake;
    assign aw_committed_clear = cd_engine_fifo_valid && cd_engine_fifo_ready;
    assign aw_committed_d     = !aw_committed_clear && (aw_committed_q || aw_committed_set);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) aw_committed_q <= 1'b0;
        else         aw_committed_q <= aw_committed_d;
    end

    stream_join #(
        .N_INP (2)
    ) u_ack_join (
        .inp_valid_i ({aw_token_valid, ack_branch_valid}),
        .inp_ready_o ({aw_token_ready, ack_branch_ready}),
        .oup_valid_o (ordered_ack_valid),
        .oup_ready_i (ordered_ack_ready)
    );

    assign ack_r = '{
        id:   cd_engine_fifo_rdata.ar.id,
        data: '0,
        resp: cd_r_resp,
        last: 1'b1,
        user: cd_engine_fifo_rdata.ar.user
    };

    assign cd_read_r = '{
        id:   cd_engine_fifo_rdata.ar.id,
        data: cd.data,
        resp: cd_r_resp,
        last: cd.last,
        user: cd_engine_fifo_rdata.ar.user
    };

    //  One initiator R source is active per head entry (read data XOR ack),
    //  so a mux selected by ack_to_read suffices
    stream_mux #(
        .DATA_T (ccu_ace_r_t),
        .N_INP  (2)
    ) u_read_r_mux (
        .inp_data_i  ({ack_r,             cd_read_r}),
        .inp_valid_i ({ordered_ack_valid, cd_read_valid}),
        .inp_ready_o ({ordered_ack_ready, cd_read_ready}),
        .inp_sel_i   (cd_engine_fifo_rdata.ack_to_read),
        .oup_data_o  (read_engine_r_o),
        .oup_valid_o (read_engine_r_valid_o),
        .oup_ready_i (read_engine_r_ready_i)
    );
//  }}}

//  Performance events
//  {{{
    ccu_snoop_pipeline_events_t events_d;

    always_comb begin : perf_events_comb
        events_d = '0;
        // Transaction occurrence
        if (stage1_fifo_valid && stage1_fifo_ready) begin
            events_d.stage1_read_no_snoop         =
                ace_is_read_no_snoop(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_read_once             =
                ace_is_read_once(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_read_shared           =
                ace_is_read_shared(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_read_clean            =
                ace_is_read_clean(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_read_not_shared_dirty =
                ace_is_read_not_shared_dirty(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_read_unique           =
                ace_is_read_unique(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_clean_unique          =
                ace_is_clean_unique(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_make_unique           =
                ace_is_make_unique(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_clean_shared          =
                ace_is_clean_shared(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_clean_invalid         =
                ace_is_clean_invalid(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
            events_d.stage1_make_invalid          =
                ace_is_make_invalid(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain, stage1_fifo_rdata.ar.snoop);
        end
        // Stage 0 stalls (address hazards now handled by the AR dispatch unit)
        if (ar_valid_i && !ar_ready_o) begin
            events_d.stage0_stall_ac_fifo_full     = ac_valid && !ac_ready;
            events_d.stage0_stall_stage1_fifo_full = stage0_valid && !stage0_ready;
            // Catch all event
            events_d.stage0_stall_other            = ~|{
                events_d.stage0_stall_ac_fifo_full,
                events_d.stage0_stall_stage1_fifo_full
            };
        end
        // Stage 1 stalls
        if (stage1_fifo_valid && !stage1_fifo_ready) begin
            events_d.stage1_stall_cr_not_valid      = stage1_fifo_valid && |(~cr_fifo_valid & stage1_fifo_rdata.sel);
            events_d.stage1_stall_write_engine_busy = write_engine_aw_valid_o && !write_engine_aw_ready_i;
            events_d.stage1_stall_read_engine_busy  = read_engine_ar_valid_o && !read_engine_ar_ready_i;
            events_d.stage1_stall_cd_engine_busy    = cd_engine_valid && !cd_engine_ready;
            // Catch all event
            events_d.stage1_stall_other             = ~|{
                events_d.stage1_stall_cr_not_valid,
                events_d.stage1_stall_write_engine_busy,
                events_d.stage1_stall_read_engine_busy,
                events_d.stage1_stall_cd_engine_busy
            };
        end

        if (stage1_fifo_valid && stage1_fifo_ready && |stage1_fifo_rdata.sel && !is_clean_or_make) begin
            events_d.snoop_hit  = cr.resp.DataTransfer;
            events_d.snoop_miss = !cr.resp.DataTransfer;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) events_o <= '0;
        else         events_o <= events_d;
    end
//  }}}
endmodule
