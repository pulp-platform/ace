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
    input  ccu_ar_flags_t                                    ar_flags_i,
    input  logic          [ccuCfg.u.numSubordinates-1:0]     ar_present_i,
    input  logic          [ccuCfg.transactionIndexWidth-1:0] ar_tid_i,
    input  logic                                             ar_valid_i,
    output logic                                             ar_ready_o,

    //  Back-invalidation from the snoop filter (no initiator)
    input  logic                                             maint_valid_i,
    input  logic          [ccuCfg.u.axiAddressWidth-1:0]     maint_addr_i,
    input  logic          [ccuCfg.u.numSubordinates-1:0]     maint_sel_i,
    output logic                                             maint_ready_o,

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
    //  Write-back reservation in the pending-write scoreboard
    output logic                                             write_engine_wb_alloc_valid_o,
    input  logic                                             write_engine_wb_alloc_ready_i,
    output logic          [ccuCfg.addressCheckWidth-1:0]     write_engine_wb_alloc_slice_o,

    output logic                                             read_engine_ar_valid_o,
    input  logic                                             read_engine_ar_ready_i,
    output ccu_axi_ar_t                                      read_engine_ar_o,
    output logic [ccuCfg.transactionIndexWidth-1:0]          read_engine_ar_tid_o,
    //  A peer keeps a copy but supplies no data
    output logic                                             read_engine_ar_is_shared_o,
    //  Shareable exclusive load, reserved by the CCU monitor
    output logic                                             read_engine_ar_exclusive_o,
    output logic                                             read_engine_r_valid_o,
    input  logic                                             read_engine_r_ready_i,
    output ccu_ace_r_t                                       read_engine_r_o,
    output logic [ccuCfg.transactionIndexWidth-1:0]          read_engine_r_tid_o,

    output logic                                             sf_cr_remove_valid_o,
    input  logic                                             sf_cr_remove_ready_i,
    output logic          [ccuCfg.u.numSubordinates-1:0]     sf_cr_remove_sel_o,
    output logic [ccuCfg.u.axiAddressWidth-1:0]              sf_cr_remove_addr_o,
    output logic                                             sf_cr_remove_maint_o,

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
    //  Who an ordinary AR would snoop, before the arbiter picks a producer
    logic           [ccuCfg.u.numSubordinates-1:0]  ar_ac_sel;
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

    assign ac_snoop            = ar_flags_i.acsnoop;
    assign ar_is_read_no_snoop = ar_flags_i.is_no_snoop;

    assign subordinate_ar_index = ar_i.id[ccuCfg.u.axiSubordinateIdWidth+:ccuCfg.subordinateIndexWidth];

    //  NonShareable and System lines snoop nobody
    always_comb begin : ace_sel_comb
        unique case (ar_i.domain)
            InnerShareable: ar_ac_sel = domain_map_i[subordinate_ar_index].inner;
            OuterShareable: ar_ac_sel = domain_map_i[subordinate_ar_index].outer;
            default:        ar_ac_sel = '0;
        endcase
        ar_ac_sel &= ar_present_i;
    end

    //  Common request for ARs and back-invalidations
    typedef struct packed {
        ccu_ace_ar_t                                ar;
        ccu_ar_flags_t                              flags;
        logic [ccuCfg.transactionIndexWidth-1:0]    tid;
        logic [ccuCfg.u.numSubordinates-1:0]        sel;
        logic                                       maintenance;
    } stage0_req_t;

    stage0_req_t stage0_req, ar_req, maint_req;
    logic        stage0_req_valid, stage0_req_ready;

    assign ar_req = '{
        ar: ar_i, flags: ar_flags_i, tid: ar_tid_i, sel: ar_ac_sel,
        maintenance: 1'b0
    };

    //  Back-invalidation as CleanInvalid
    always_comb begin : maint_req_comb
        maint_req             = '0;
        maint_req.ar.addr     = maint_addr_i;
        //  Its write-back must stay modifiable, as the LLC refills and evicts with it
        maint_req.ar.cache    = axi_pkg::CACHE_BUFFERABLE | axi_pkg::CACHE_MODIFIABLE |
                                axi_pkg::CACHE_RD_ALLOC   | axi_pkg::CACHE_WR_ALLOC;
        maint_req.flags.acsnoop = CleanInvalid;
        maint_req.sel         = maint_sel_i;
        maint_req.maintenance = 1'b1;
    end

    //  "rr" for LockIn
    stream_arbiter #(
        .DATA_T  (stage0_req_t),
        .N_INP   (2),
        .ARBITER ("rr")
    ) u_stage0_arb (
        .clk_i,
        .rst_ni,
        .inp_data_i  ({ar_req, maint_req}),
        .inp_valid_i ({ar_valid_i, maint_valid_i}),
        .inp_ready_o ({ar_ready_o, maint_ready_o}),
        .oup_data_o  (stage0_req),
        .oup_valid_o (stage0_req_valid),
        .oup_ready_i (stage0_req_ready)
    );

    assign ac_sel = stage0_req.sel;

    assign ac = '{
        addr: axi_pkg::aligned_addr(stage0_req.ar.addr, ccuCfg.cachelineByteIndexWidth),
        snoop: stage0_req.flags.acsnoop,
        prot: stage0_req.ar.prot
    };

    stream_fork_dynamic #(
        .N_OUP (2)
    ) u_ac_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (stage0_req_valid),
        .ready_o     (stage0_req_ready),
        .sel_i       ({|ac_sel, 1'b1}),
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
        ccu_ar_flags_t                              flags;
        logic [ccuCfg.transactionIndexWidth-1:0]    tid;
        logic        [ccuCfg.u.numSubordinates-1:0] sel;
        //  Back-invalidation: no initiator
        logic                                       maintenance;
    } stage1_fifo_entry_t;

    logic                                stage1_fifo_valid;
    logic                                stage1_fifo_ready;
    stage1_fifo_entry_t                  stage1_fifo_wdata;
    stage1_fifo_entry_t                  stage1_fifo_rdata;
    logic                                accepts_dirty;
    logic                                accepts_dirty_shared;
    logic                                accepts_shared;
    logic                                rresp_is_shared;
    logic                                rresp_pass_dirty;
    logic                                is_clean_or_make;
    ccu_snoop_cr_t                       cr;
    logic [ccuCfg.u.numSubordinates-1:0] cd_data_transfer;
    logic [ccuCfg.u.numSubordinates-1:0] cd_data_source;
    logic [ccuCfg.u.numSubordinates-1:0] cd_data_discard;
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
        ar   : stage0_req.ar,
        flags: stage0_req.flags,
        tid  : stage0_req.tid,
        sel  : stage0_req.sel,
        maintenance: stage0_req.maintenance
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

    always_comb begin : sf_cr_remove_comb
        unique case (stage1_fifo_rdata.flags.acsnoop)
            ReadUnique, CleanInvalid, MakeInvalid:
                sf_cr_remove_sel_o = stage1_fifo_rdata.sel;
            ReadClean, ReadNotSharedDirty, ReadShared:
                for (int unsigned s = 0; s < ccuCfg.u.numSubordinates; s++)
                    sf_cr_remove_sel_o[s] = stage1_fifo_rdata.sel[s] &&
                                            !cr_fifo_rdata[s].resp.IsShared;
            default: sf_cr_remove_sel_o = '0;
        endcase
    end

    assign sf_cr_remove_addr_o  = stage1_fifo_rdata.ar.addr;
    assign sf_cr_remove_maint_o = stage1_fifo_rdata.maintenance;

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

    assign accepts_dirty        = stage1_fifo_rdata.flags.accepts_dirty;
    assign accepts_dirty_shared = stage1_fifo_rdata.flags.accepts_dirty_shared;
    assign accepts_shared       = stage1_fifo_rdata.flags.accepts_shared;
    assign is_clean_or_make     = stage1_fifo_rdata.flags.is_clean_or_make;

    always_comb begin : engine_sel_comb
        read_engine_sel            = 1'b0;
        cd_engine_sel              = 1'b0;
        cd_engine_forward_to_read  = 1'b0;
        cd_engine_forward_to_write = 1'b0;
        cd_engine_ack_to_read      = 1'b0;

        //  No initiator: only write back dirty data
        if (stage1_fifo_rdata.maintenance) begin
            cd_engine_sel              = cr.resp.DataTransfer;
            cd_engine_forward_to_write = cr.resp.DataTransfer && cr.resp.PassDirty;
        end else
        case ({cr.resp.DataTransfer, is_clean_or_make})
            //  Forward the request to memory
            2'b00: read_engine_sel = 1'b1;
            //  Clean/make with no data: acknowledge only
            2'b01: begin
                cd_engine_sel         = 1'b1;
                cd_engine_ack_to_read = 1'b1;
            end
            //  Snoop data: forward (read) or acknowledge (clean/make)
            default: begin
                cd_engine_sel             = 1'b1;
                cd_engine_forward_to_read = !is_clean_or_make;
                cd_engine_ack_to_read     = is_clean_or_make;
                if (cr.resp.PassDirty && !rresp_pass_dirty) begin
                    //  The initiator cannot accept dirty data, writeback
                    cd_engine_forward_to_write = 1'b1;
                end
            end
        endcase
    end

    //  A write-back is pending before its entry pops, so no later read overtakes it
    stream_fork_dynamic #(
        .N_OUP(4)
    ) u_engine_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (engine_fork_valid),
        .ready_o    (engine_fork_ready),
        .sel_i      ({read_engine_sel, cd_engine_sel, |sf_cr_remove_sel_o,
                      cd_engine_forward_to_write}),
        .sel_valid_i(1'b1),
        .sel_ready_o(),
        .valid_o    ({read_engine_ar_valid_o, cd_engine_valid, sf_cr_remove_valid_o,
                      write_engine_wb_alloc_valid_o}),
        .ready_i    ({read_engine_ar_ready_i, cd_engine_ready, sf_cr_remove_ready_i,
                      write_engine_wb_alloc_ready_i})
    );

    assign write_engine_wb_alloc_slice_o =
        stage1_fifo_rdata.ar.addr[ccuCfg.u.addressCheckMsb:ccuCfg.u.addressCheckLsb];

    always_comb begin : read_engine_ar_comb
        //  ACE to AXI conversion can be done via the macro
        `AXI_SET_AR_STRUCT(read_engine_ar_o, stage1_fifo_rdata.ar)
    end

    assign read_engine_ar_tid_o = stage1_fifo_rdata.tid;
    assign read_engine_ar_is_shared_o = rresp_is_shared;
    assign read_engine_ar_exclusive_o = stage1_fifo_rdata.flags.is_exclusive_load;

    //  A peer keeping its copy narrows who may accept the dirty data (C4-199)
    assign rresp_is_shared  = cr.resp.IsShared && accepts_shared;
    assign rresp_pass_dirty = cr.resp.PassDirty &&
                              (cr.resp.IsShared ? accepts_dirty_shared : accepts_dirty);

    assign cd_engine_resp_shared = rresp_is_shared;
    assign cd_engine_resp_dirty  = rresp_pass_dirty;

    //  Lowest-indexed responder supplies the data, others are drained
    always_comb begin : cd_data_role_comb
        cd_data_source = '0;
        if (cd_engine_forward_to_read || cd_engine_forward_to_write) begin
            for (int unsigned s = 0; s < ccuCfg.u.numSubordinates; s++) begin
                if (cd_data_transfer[s]) begin
                    cd_data_source[s] = 1'b1;
                    break;
                end
            end
        end
    end

    assign cd_data_discard = cd_data_transfer & ~cd_data_source;
//  }}}

//  CD engine
//  {{{
    typedef struct packed {
        logic [ccuCfg.u.numSubordinates-1:0]     source;
        logic [ccuCfg.u.numSubordinates-1:0]     discard;
        logic                                    forward_to_read;
        logic                                    forward_to_write;
        logic                                    ack_to_read;
        logic                                    resp_shared;
        logic                                    resp_dirty;
        ccu_ace_ar_t                             ar;
        logic [ccuCfg.transactionIndexWidth-1:0] tid;
    } cd_engine_fifo_entry_t;

    logic                  cd_engine_fifo_valid;
    logic                  cd_engine_fifo_ready;
    cd_engine_fifo_entry_t cd_engine_fifo_wdata;
    cd_engine_fifo_entry_t cd_engine_fifo_rdata;

    assign cd_engine_fifo_wdata  = '{
        source:           cd_data_source,
        discard:          cd_data_discard,
        forward_to_read:  cd_engine_forward_to_read,
        forward_to_write: cd_engine_forward_to_write,
        ack_to_read:      cd_engine_ack_to_read,
        resp_shared:      cd_engine_resp_shared,
        resp_dirty:       cd_engine_resp_dirty,
        ar:               stage1_fifo_rdata.ar,
        tid:              stage1_fifo_rdata.tid
    };


    rresp_t                                 cd_r_resp;
    logic [ccuCfg.u.numSubordinates-1:0]    cd_head_source;
    logic [ccuCfg.u.numSubordinates-1:0]    cd_head_discard;
    logic [ccuCfg.u.numSubordinates-1:0]    cd_done;
    logic [ccuCfg.u.numSubordinates-1:0]    cd_discard;
    logic                                   cd_entry_pop;
    logic                                   cd_all_done;
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

    //  Head-entry legs: writeback AW, CD data, initiator ack
    logic cd_fork_valid;
    logic cd_fork_ready;
    logic ack_branch_valid;
    logic ack_branch_ready;

    always_comb begin : write_engine_aw_comb
        //  Writeback AW from the AR; the write engine replaces the id
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

    assign cd_head_source  = cd_engine_fifo_valid ? cd_engine_fifo_rdata.source  : '0;
    assign cd_head_discard = cd_engine_fifo_valid ? cd_engine_fifo_rdata.discard : '0;

    assign cd_entry_pop = cd_engine_fifo_valid && cd_engine_fifo_ready;
    assign cd_all_done  = &(cd_done | ~(cd_head_source | cd_head_discard));

    //  A master is done once its last beat is taken, until the entry pops
    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_cd_done
        logic cd_done_q, cd_last_hs;

        assign cd_last_hs = cd_fifo_valid[s] && cd_ready[s] && cd_fifo_rdata[s].last;

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni)           cd_done_q <= 1'b0;
            else if (cd_entry_pop) cd_done_q <= 1'b0;
            else if (cd_last_hs)   cd_done_q <= 1'b1;
        end

        assign cd_done[s]    = cd_done_q;
        assign cd_valid[s]   = cd_fifo_valid[s] && cd_head_source[s]  && !cd_done[s];
        assign cd_discard[s] = cd_fifo_valid[s] && cd_head_discard[s] && !cd_done[s];
        assign cd_ready[s]   = cd_discard[s] || (cd_valid[s] && cd_engine_data_ready);
    end

    assign cd_fifo_ready        = cd_ready;
    assign cd_engine_data_valid = |cd_valid;

    always_comb begin : cd_mux_comb
        cd = '0;
        for (int s = 0; s < ccuCfg.u.numSubordinates; s++) begin
            if (cd_valid[s]) cd = cd_fifo_rdata[s];
        end
    end

    //  AW, then DATA, then ACK: R never precedes the writeback AW (C6.5.3)
    stream_iterator #(
        .N_OUP (3)
    ) u_cd_engine_iterator (
        .clk_i,
        .rst_ni,
        .valid_i (cd_engine_fifo_valid),
        .ready_o (cd_engine_fifo_ready),
        .sel_i   ({cd_engine_fifo_rdata.ack_to_read,
                   |(cd_engine_fifo_rdata.source | cd_engine_fifo_rdata.discard),
                   cd_engine_fifo_rdata.forward_to_write}),
        .valid_o ({ack_branch_valid, cd_fork_valid, write_engine_aw_valid_o}),
        .ready_i ({ack_branch_ready, cd_all_done,   write_engine_aw_ready_i})
    );

    //  Per-beat CD data fork to the initiator and/or the writeback W
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

    //  Read data XOR ack per entry
    stream_mux #(
        .DATA_T (ccu_ace_r_t),
        .N_INP  (2)
    ) u_read_r_mux (
        .inp_data_i  ({ack_r,            cd_read_r}),
        .inp_valid_i ({ack_branch_valid, cd_read_valid}),
        .inp_ready_o ({ack_branch_ready, cd_read_ready}),
        .inp_sel_i   (cd_engine_fifo_rdata.ack_to_read),
        .oup_data_o  (read_engine_r_o),
        .oup_valid_o (read_engine_r_valid_o),
        .oup_ready_i (read_engine_r_ready_i)
    );

    assign read_engine_r_tid_o = cd_engine_fifo_rdata.tid;

//  }}}

//  Performance events
//  {{{
    ccu_snoop_pipeline_events_t events_d;

    always_comb begin : perf_events_comb
        events_d = '0;
        // Transaction occurrence
        if (stage1_fifo_valid && stage1_fifo_ready
                && !stage1_fifo_rdata.maintenance) begin
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
        // Stage 0 stalls
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

        if (stage1_fifo_valid && stage1_fifo_ready && |stage1_fifo_rdata.sel
                && !is_clean_or_make && !stage1_fifo_rdata.maintenance) begin
            events_d.snoop_hit  = cr.resp.DataTransfer;
            events_d.snoop_miss = !cr.resp.DataTransfer;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) events_o <= '0;
        else         events_o <= events_d;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ar_valid_i && ar_i.domain inside {NonShareable, System} |-> ar_ac_sel == '0)
        else $error("non-shareable domain selected a snoop target");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cd_engine_valid |-> !(rresp_is_shared && rresp_pass_dirty && !accepts_dirty_shared))
        else $error("IsShared and PassDirty returned to a transaction accepting only one");

    //  no PassDirty without data
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        engine_fork_valid |-> !(cr.resp.PassDirty && !cr.resp.DataTransfer))
        else $error("PassDirty without DataTransfer");

    //  a MakeInvalid snoopee discards its line, dirty or not
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        engine_fork_valid && stage1_fifo_rdata.flags.acsnoop == MakeInvalid |-> !cr.resp.PassDirty)
        else $error("PassDirty on a MakeInvalid response");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        engine_fork_valid && cr.resp.DataTransfer && cr.resp.PassDirty && !rresp_pass_dirty
        |-> cd_engine_forward_to_write)
        else $error("dirty snoop data dropped without a writeback");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cd_engine_valid |-> $onehot0(cd_data_source))
        else $error("more than one CD source");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cd_engine_valid |->
        (cd_data_source | cd_data_discard) == cd_data_transfer &&
        (cd_data_source & cd_data_discard) == '0)
        else $error("CD responders not partitioned into source and discard");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        cd_engine_data_valid |-> $onehot(cd_valid))
        else $error("more than one CD source forwarded in one beat");

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_cd_beats_check
        logic [$clog2(ccuCfg.cachelineAxiTransfers + 1)-1:0] beats_q;

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni)                              beats_q <= '0;
            else if (cd_fifo_valid[s] && cd_ready[s]) beats_q <= cd_fifo_rdata[s].last ? '0 : beats_q + 1'b1;
        end

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            cd_fifo_valid[s] && cd_ready[s] |->
            cd_fifo_rdata[s].last == (beats_q == ccuCfg.cachelineAxiTransfers - 1))
            else $error("CD burst is not one cacheline");
    end

    //  carried flags match the AR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        stage1_fifo_valid && !stage1_fifo_rdata.maintenance |->
        stage1_fifo_rdata.flags ==
            ccu_ar_decode(stage1_fifo_rdata.ar.bar[0], stage1_fifo_rdata.ar.domain,
                          stage1_fifo_rdata.ar.snoop,  stage1_fifo_rdata.ar.lock))
        else $error("carried AR flags disagree with the AR");

    //  the initiator R is stable while stalled
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        read_engine_r_valid_o && !read_engine_r_ready_i |=>
        read_engine_r_valid_o && $stable(read_engine_r_o))
        else $error("R channel unstable while stalled");

    for (genvar s = 0; s < ccuCfg.u.numSubordinates; s++) begin : gen_ac_assert
        //  the AC channel is stable while stalled
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            ac_valid_o[s] && !ac_ready_i[s] |=> ac_valid_o[s] && $stable(ac_o[s]))
            else $error("AC channel unstable while stalled");
    end
    `endif
    // pragma translate_on
//  }}}
endmodule
