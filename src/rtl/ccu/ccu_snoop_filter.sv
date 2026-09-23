// Copyright (c) 2026 ETH Zurich, University of Bologna
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

//! Snoop filter
//
//  One tag array per subordinate mirroring its cache. Untracked addresses
//  always report present. Lookup has one cycle of latency.
module ccu_snoop_filter
    import ccu_pkg::*;
#(
    parameter  ccu_config_t ccuCfg  = '{default: '0},
    localparam int unsigned numSub  = ccuCfg.u.numSubordinates,
    localparam int unsigned addrW   = ccuCfg.u.axiAddressWidth,
    localparam int unsigned subIdxW = ccuCfg.subordinateIndexWidth,
    localparam int unsigned setW    = ccuCfg.snoopFilterSetWidth,
    localparam int unsigned tagW    = ccuCfg.snoopFilterTagWidth,
    localparam int unsigned offW    = ccuCfg.cachelineByteIndexWidth,
    localparam int unsigned trackW  = ccuCfg.u.snoopFilterAddrWidth
) (
    input  logic                            clk_i,
    input  logic                            rst_ni,

    input  logic                            lookup_valid_i,
    input  logic [addrW-1:0]                lookup_addr_i,
    output logic [numSub-1:0]               lookup_present_o,

    input  logic [numSub-1:0]               insert_valid_i,
    input  logic [numSub-1:0][addrW-1:0]    insert_addr_i,
    output logic [numSub-1:0]               insert_ready_o,

    //  De-allocation announced on the write channel, one port per subordinate
    input  logic [numSub-1:0]               aw_remove_valid_i,
    input  logic [numSub-1:0][addrW-1:0]    aw_remove_addr_i,
    output logic [numSub-1:0]               aw_remove_ready_o,

    //  De-allocation from snoop responses: one line, several responders
    input  logic                            cr_remove_valid_i,
    input  logic [numSub-1:0]               cr_remove_sel_i,
    input  logic [addrW-1:0]                cr_remove_addr_i,
    output logic                            cr_remove_ready_o,

    //  Back-invalidation of a victim when an insert finds no free way
    output logic [numSub-1:0]               backinval_valid_o,
    output logic [numSub-1:0][addrW-1:0]    backinval_addr_o,
    input  logic [numSub-1:0]               backinval_ready_i,

    //  Attempt in flight; pending without valid means the snoop was sent
    output logic [numSub-1:0]               backinval_pend_o,

    //  A removal that found nothing; legal, but worth observing
    output logic [numSub-1:0]               remove_miss_o
);

    localparam int unsigned numSets    = ccuCfg.u.subordinateCacheSets;
    localparam int unsigned numWays    = ccuCfg.u.subordinateCacheWays;
    localparam int unsigned entryW     = ccuCfg.snoopFilterEntryWidth;
    localparam int unsigned wayW       = numWays > 1 ? $clog2(numWays) : 1;

    typedef struct packed {
        logic            valid;
        logic [tagW-1:0] tag;
    } entry_t;

    typedef enum logic [1:0] { IDLE, READ, WRITE } state_e;

    //  Shift, since a part-select would not elaborate when trackW == addrW
    function automatic logic in_range(logic [addrW-1:0] addr);
        return (addr >> trackW) == '0;
    endfunction

    logic [setW-1:0]             lookup_set, cr_set;
    logic [tagW-1:0]             lookup_tag, cr_tag;
    logic                        lookup_track, cr_track, cr_port_ready;
    logic                        lookup_track_q;
    logic [numSub-1:0]           table_present;
    logic [numSub-1:0]           cr_fork_valid, cr_fork_ready;
    logic [numSub-1:0]           rem_valid, rem_ready, rem_is_cr;
    logic [numSub-1:0][setW-1:0] rem_set, aw_set, ins_set;
    logic [numSub-1:0][tagW-1:0] rem_tag, aw_tag, ins_tag;
    logic [numSub-1:0]           aw_track, ins_track, ins_gnt;

    assign lookup_set   = lookup_addr_i[offW +: setW];
    assign lookup_tag   = lookup_addr_i[offW+setW +: tagW];
    assign lookup_track = in_range(lookup_addr_i);

    assign cr_set   = cr_remove_addr_i[offW +: setW];
    assign cr_tag   = cr_remove_addr_i[offW+setW +: tagW];
    assign cr_track = in_range(cr_remove_addr_i);

    //  Every selected responder must take the removal before the snoop advances
    stream_fork_dynamic #(
        .N_OUP (numSub)
    ) u_cr_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (cr_remove_valid_i && cr_track),
        .ready_o     (cr_port_ready),
        .sel_i       (cr_remove_sel_i),
        .sel_valid_i (1'b1),
        .sel_ready_o (),
        .valid_o     (cr_fork_valid),
        .ready_i     (cr_fork_ready)
    );

    //  Drop removals of untracked addresses
    assign cr_remove_ready_o = cr_track ? cr_port_ready : 1'b1;

    for (genvar s = 0; s < numSub; s++) begin : gen_table
        entry_t [numWays-1:0] sram_rdata, sram_wdata;
        logic   [numWays-1:0] sram_be;
        logic   [setW-1:0]    sram_addr;
        logic                 sram_req, sram_we;

        state_e               state_q, state_d;
        logic                 lookup_grant, op_start, op_write, start_remove;

        logic                 op_insert_q, op_insert_d;
        logic [setW-1:0]      op_set_q, op_set_d;
        logic [tagW-1:0]      op_tag_q, op_tag_d;
        logic [wayW-1:0]      op_way_q, op_way_d;
        logic [wayW-1:0]      way_idx;
        logic                 way_none;
        logic [numWays-1:0]   way_sel, way_free, way_match;
        entry_t               op_entry;

        logic                 insert_hit;
        logic                 insert_stuck;

        //  Rotating victim: the policy only has to not keep picking one way
        logic [wayW-1:0]      victim_q, victim_d;
        logic                 backinval_q, backinval_d;
        logic                 backinval_pend_q, backinval_pend_d;
        logic                 backinval_done;
        logic [addrW-1:0]     backinval_addr_q, backinval_addr_d;

        logic [setW-1:0]      lookup_set_q;
        logic [tagW-1:0]      lookup_tag_q;
        logic                 lookup_forced_q;
        logic [numWays-1:0]   lookup_match;

        logic                 init_done_q;
        logic [setW:0]        init_cnt_q;

        logic                 lookup_valid, insert_valid;

        //  Address decode
        assign aw_set[s]   = aw_remove_addr_i[s][offW +: setW];
        assign aw_tag[s]   = aw_remove_addr_i[s][offW+setW +: tagW];
        assign aw_track[s] = in_range(aw_remove_addr_i[s]);

        assign ins_set[s]   = insert_addr_i[s][offW +: setW];
        assign ins_tag[s]   = insert_addr_i[s][offW+setW +: tagW];
        assign ins_track[s] = in_range(insert_addr_i[s]);

        //  An untracked line is dropped rather than stalling its transaction
        assign insert_ready_o[s] = ins_track[s] ? ins_gnt[s] : 1'b1;

        //  Snoop-response removals first; the choice is locked once presented
        logic rem_hold_q, rem_is_cr_q;

        assign rem_is_cr[s] = rem_hold_q ? rem_is_cr_q : cr_fork_valid[s];
        assign rem_valid[s] = cr_fork_valid[s] || (aw_remove_valid_i[s] && aw_track[s]);

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                rem_hold_q  <= 1'b0;
                rem_is_cr_q <= 1'b0;
            end else if (rem_valid[s] && !rem_ready[s]) begin
                rem_hold_q  <= 1'b1;
                rem_is_cr_q <= rem_is_cr[s];
            end else if (rem_ready[s]) begin
                rem_hold_q  <= 1'b0;
            end
        end

        assign rem_set[s]   = rem_is_cr[s] ? cr_set : aw_set[s];
        assign rem_tag[s]   = rem_is_cr[s] ? cr_tag : aw_tag[s];

        //  The port retires one source at a time, so each ready must name its own
        assign cr_fork_ready[s]     = rem_ready[s] && rem_is_cr[s];
        assign aw_remove_ready_o[s] = aw_track[s] ? (rem_ready[s] && !rem_is_cr[s]) : 1'b1;

        assign lookup_valid = lookup_valid_i && lookup_track;
        assign insert_valid = insert_valid_i[s] && ins_track[s];

        //  Tag array: a byte is one way, so an update writes a single way
        tc_sram #(
            .NumWords  (numSets),
            .DataWidth (numWays * entryW),
            .ByteWidth (entryW),
            .NumPorts  (32'd1),
            .Latency   (32'd1)
        ) u_tag_array (
            .clk_i,
            .rst_ni,
            .req_i   (sram_req),
            .we_i    (sram_we),
            .addr_i  (sram_addr),
            .wdata_i (sram_wdata),
            .be_i    (sram_be),
            .rdata_o (sram_rdata)
        );

        //  The array has no content reset, so clear the valid bits before use
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                init_cnt_q  <= '0;
                init_done_q <= 1'b0;
            end else if (!init_done_q) begin
                init_cnt_q  <= init_cnt_q + 1;
                init_done_q <= init_cnt_q == (setW+1)'(numSets - 1);
            end
        end

        assign lookup_grant = init_done_q && lookup_valid;
        assign op_entry     = '{valid: op_insert_q, tag: op_insert_q ? op_tag_q : '0};
        assign op_write     = state_q == WRITE && !lookup_grant;

        always_comb begin : sram_port_comb
            sram_req   = 1'b0;
            sram_we    = 1'b0;
            sram_addr  = '0;
            sram_be    = '0;
            sram_wdata = '0;
            if (!init_done_q) begin
                sram_req   = 1'b1;
                sram_we    = 1'b1;
                sram_addr  = init_cnt_q[setW-1:0];
                sram_be    = '1;
            end else if (lookup_grant) begin
                sram_req   = 1'b1;
                sram_addr  = lookup_set;
            end else if (op_start) begin
                sram_req   = 1'b1;
                sram_addr  = start_remove ? rem_set[s] : ins_set[s];
            end else if (op_write) begin
                sram_req   = 1'b1;
                sram_we    = 1'b1;
                sram_addr  = op_set_q;
                sram_be    = numWays'(1) << op_way_q;
                sram_wdata = {numWays{op_entry}};
            end
        end

        //  Lookup
        for (genvar w = 0; w < numWays; w++) begin : gen_lookup_match
            assign lookup_match[w] = sram_rdata[w].valid && sram_rdata[w].tag == lookup_tag_q;
        end

        assign table_present[s] = lookup_forced_q || |lookup_match;

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                lookup_set_q    <= '0;
                lookup_tag_q    <= '0;
                lookup_forced_q <= 1'b1;
            end else if (lookup_valid) begin
                lookup_set_q    <= lookup_set;
                lookup_tag_q    <= lookup_tag;
                lookup_forced_q <= !init_done_q;
            end
        end

        //  Update
        assign start_remove = rem_valid[s];
        assign op_start     = init_done_q && !lookup_grant && state_q == IDLE &&
                              (rem_valid[s] || insert_valid);

        for (genvar w = 0; w < numWays; w++) begin : gen_way_match
            assign way_free[w]  = !sram_rdata[w].valid;
            assign way_match[w] = sram_rdata[w].valid && sram_rdata[w].tag == op_tag_q;
        end

        //  A remove frees exactly one way; an insert takes a free one
        assign way_sel = op_insert_q ? way_free : way_match;

        lzc #(
            .WIDTH (numWays),
            .MODE  (1'b0)
        ) u_way_lzc (
            .in_i    (way_sel),
            .cnt_o   (way_idx),
            .empty_o (way_none)
        );

        assign insert_hit    = state_q == READ &&  op_insert_q && |way_match;
        assign insert_stuck  = state_q == READ &&  op_insert_q && way_none && !insert_hit;

        always_comb begin : state_comb
            state_d = state_q;
            unique case (state_q)
                IDLE:    if (op_start) state_d = READ;
                //  Hits, stuck inserts and removal misses retire without writing
                READ:    state_d = insert_hit   ? IDLE :
                                   insert_stuck ? IDLE :
                                   way_none     ? IDLE : WRITE;
                WRITE:   if (!lookup_grant) state_d = IDLE;
                default: state_d = IDLE;
            endcase
        end

        assign ins_gnt[s]      = (op_write &&  op_insert_q) || insert_hit;
        assign rem_ready[s]    = (op_write && !op_insert_q) || remove_miss_o[s];
        assign remove_miss_o[s] = state_q == READ && !op_insert_q && way_none;

        assign backinval_valid_o[s] = backinval_q;
        assign backinval_pend_o[s]  = backinval_pend_q;
        assign backinval_addr_o[s]  = backinval_addr_q;

        //  An attempt stands until this set is updated
        assign backinval_done = ins_gnt[s] ||
            (rem_ready[s] && op_set_q == backinval_addr_q[offW +: setW]);

        //  One latched back-invalidation per table; the insert retries
        always_comb begin : backinval_comb
            victim_d          = victim_q;
            backinval_d       = backinval_q;
            backinval_pend_d  = backinval_pend_q;
            backinval_addr_d  = backinval_addr_q;

            if (backinval_q && backinval_ready_i[s]) backinval_d = 1'b0;

            if (backinval_pend_q) begin
                backinval_pend_d = !backinval_done;
            end else if (insert_stuck) begin
                backinval_d      = 1'b1;
                backinval_pend_d = 1'b1;
                backinval_addr_d = addrW'({sram_rdata[victim_q].tag, op_set_q,
                                           {offW{1'b0}}});
                victim_d         = (victim_q == wayW'(numWays - 1)) ? '0 : victim_q + 1;
            end
        end

        always_comb begin : op_comb
            op_insert_d = op_insert_q;
            op_set_d    = op_set_q;
            op_tag_d    = op_tag_q;
            op_way_d    = op_way_q;

            //  Removals go first: they gate the AR path
            if (op_start) begin
                op_insert_d = !start_remove;
                op_set_d    = start_remove ? rem_set[s] : ins_set[s];
                op_tag_d    = start_remove ? rem_tag[s] : ins_tag[s];
            end

            if (state_q == READ) op_way_d = way_idx;
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                state_q         <= IDLE;
                op_insert_q     <= 1'b0;
                op_set_q        <= '0;
                op_tag_q        <= '0;
                op_way_q        <= '0;
                victim_q         <= '0;
                backinval_q      <= 1'b0;
                backinval_pend_q <= 1'b0;
                backinval_addr_q <= '0;
            end else begin
                state_q         <= state_d;
                op_insert_q     <= op_insert_d;
                op_set_q        <= op_set_d;
                op_tag_q        <= op_tag_d;
                op_way_q        <= op_way_d;
                victim_q         <= victim_d;
                backinval_q      <= backinval_d;
                backinval_pend_q <= backinval_pend_d;
                backinval_addr_q <= backinval_addr_d;
            end
        end

        // pragma translate_off
        `ifndef VERILATOR
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            state_q == READ |-> $onehot0(way_match))
            else $error("a set holds the same line twice");

        //  a redundant insert never races a removal of the same line
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            !(insert_hit && rem_valid[s]
              && rem_set[s] == op_set_q && rem_tag[s] == op_tag_q))
            else $error("insert retired as a hit with a removal pending for it");

        //  One attempt at a time, or the arbiter sees a moving payload
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            backinval_q |-> backinval_pend_q)
            else $error("a back-invalidation outlived its attempt");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            !init_done_q |=> table_present[s])
            else $error("lookup answered from an uninitialised tag array");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            insert_valid && !ins_gnt[s] |=>
            insert_valid && $stable({ins_set[s], ins_tag[s]}))
            else $error("insert payload changed before it retired");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            rem_valid[s] && !rem_ready[s] |=>
            rem_valid[s] && $stable({rem_set[s], rem_tag[s]}))
            else $error("remove payload changed before it retired");

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            sram_req && sram_we && init_done_q |-> $onehot(sram_be))
            else $error("an update wrote more than one way");

        //  A lookup between the read and the write re-points the array
        logic op_rdata_q;
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni)              op_rdata_q <= 1'b0;
            else if (lookup_grant)    op_rdata_q <= 1'b0;
            else if (state_q == READ) op_rdata_q <= 1'b1;
        end

        assert property (@(posedge clk_i) disable iff (!rst_ni)
            op_write && op_insert_q && op_rdata_q |->
                !sram_rdata[op_way_q].valid)
            else $error("insert targeted a live way");

        //  a stuck insert eventually makes progress
        localparam int unsigned stuckAssertLimit = 4096;
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            insert_stuck |-> ##[1:stuckAssertLimit] !insert_stuck)
            else $error("insert stuck for %0d cycles: no way was ever freed",
                        stuckAssertLimit);

        `endif
        // pragma translate_on
    end

    assign lookup_present_o = lookup_track_q ? table_present : '1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)             lookup_track_q <= 1'b0;
        else if (lookup_valid_i) lookup_track_q <= lookup_track;
    end

endmodule
