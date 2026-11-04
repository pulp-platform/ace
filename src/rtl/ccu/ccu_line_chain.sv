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

//! Line chains of the dispatch pool
//
//  Each pool slot waits on the line's previous operation, a pool slot or an issued tid.
module ccu_line_chain #(
    parameter  int unsigned numSlots = 1,
    parameter  int unsigned numTids  = 1,
    localparam int unsigned slotW    = numSlots > 1 ? $clog2(numSlots) : 1,
    localparam int unsigned tidW     = numTids > 1 ? $clog2(numTids) : 1,
    localparam int unsigned predW    = slotW > tidW ? slotW : tidW
) (
    input  logic                clk_i,
    input  logic                rst_ni,

    //  Admission: the live pool slots and the completion-buffer tail of the admitted line
    input  logic                admit_valid_i,
    input  logic [slotW-1:0]    admit_slot_i,
    input  logic                admit_ahead_i,
    input  logic [numSlots-1:0] line_match_i,
    input  logic [numTids-1:0]  cb_link_i,
    output logic [numTids-1:0]  cb_tail_clear_o,

    //  Issue, and the slots issuing now or the next cycle
    input  logic                issue_valid_i,
    input  logic [slotW-1:0]    issue_slot_i,
    input  logic [tidW-1:0]     issue_tid_i,
    input  logic [numSlots-1:0] committed_i,
    output logic                issue_tail_o,

    //  Tids whose successors may go
    input  logic [numTids-1:0]  released_i,
    output logic [numSlots-1:0] waiting_o
);

    typedef struct packed {
        logic             tail;
        logic             pred_valid;
        logic             pred_in_pool;
        logic [predW-1:0] pred_idx;
    } link_t;

    link_t [numSlots-1:0] link_q, link_d;
    link_t                admit_link, head_link;

    logic [numSlots-1:0] pool_link, head;
    logic [slotW-1:0]    pool_tail_idx, head_idx;
    logic [tidW-1:0]     cb_tail_idx;
    logic                ahead, head_pred_issuing;

//  Tails and the first uncommitted entry of the admitted line
//  {{{
    for (genvar s = 0; s < numSlots; s++) begin : gen_head
        assign pool_link[s] = line_match_i[s] && link_q[s].tail;
        assign head[s]      = line_match_i[s] && !committed_i[s] &&
                              !(link_q[s].pred_valid && link_q[s].pred_in_pool &&
                                !committed_i[slotW'(link_q[s].pred_idx)]);
    end

    onehot_to_bin #(
        .ONEHOT_WIDTH (numSlots)
    ) u_pool_tail_onehot_to_bin (
        .onehot (pool_link),
        .bin    (pool_tail_idx)
    );

    onehot_to_bin #(
        .ONEHOT_WIDTH (numTids)
    ) u_cb_tail_onehot_to_bin (
        .onehot (cb_link_i),
        .bin    (cb_tail_idx)
    );

    onehot_to_bin #(
        .ONEHOT_WIDTH (numSlots)
    ) u_head_onehot_to_bin (
        .onehot (head),
        .bin    (head_idx)
    );

    //  Never behind an unissued entry
    assign ahead             = admit_ahead_i && |head;
    assign head_link         = link_q[head_idx];
    assign head_pred_issuing = issue_valid_i && head_link.pred_idx == predW'(issue_slot_i);

    assign cb_tail_clear_o = admit_valid_i && !ahead ? cb_link_i : '0;
    //  A successor admitted in the issue cycle takes the tail from it
    assign issue_tail_o    = link_q[issue_slot_i].tail &&
                             !(admit_valid_i && pool_link[issue_slot_i]);
//  }}}

//  The admitted slot's link
//  {{{
    always_comb begin : admit_link_comb
        admit_link            = '0;
        admit_link.tail       = !ahead;
        admit_link.pred_valid = |pool_link || |cb_link_i;
        if (ahead) begin
            //  Takes the head's predecessor
            admit_link.pred_valid   = head_link.pred_valid && (head_link.pred_in_pool ||
                                      !released_i[tidW'(head_link.pred_idx)]);
            admit_link.pred_in_pool = head_link.pred_in_pool && !head_pred_issuing;
            admit_link.pred_idx     = head_link.pred_in_pool && head_pred_issuing ?
                                      predW'(issue_tid_i) : head_link.pred_idx;
        end else if (|pool_link) begin
            //  A pool predecessor issuing now is already its tid
            admit_link.pred_in_pool = !(issue_valid_i && issue_slot_i == pool_tail_idx);
            admit_link.pred_idx     = admit_link.pred_in_pool ? predW'(pool_tail_idx) :
                                                                predW'(issue_tid_i);
        end else begin
            admit_link.pred_idx     = predW'(cb_tail_idx);
        end
    end
//  }}}

//  Updates
//  {{{
    for (genvar s = 0; s < numSlots; s++) begin : gen_link
        always_comb begin : link_comb
            link_d[s] = link_q[s];

            if (admit_valid_i && !ahead && pool_link[s]) link_d[s].tail = 1'b0;

            //  The predecessor issued: wait on its tid from now on
            if (link_q[s].pred_valid && link_q[s].pred_in_pool && issue_valid_i &&
                link_q[s].pred_idx == predW'(issue_slot_i)) begin
                link_d[s].pred_in_pool = 1'b0;
                link_d[s].pred_idx     = predW'(issue_tid_i);
            end
            //  Released at the predecessor's ACK, not its insert
            if (link_q[s].pred_valid && !link_q[s].pred_in_pool &&
                released_i[tidW'(link_q[s].pred_idx)])
                link_d[s].pred_valid = 1'b0;

            if (admit_valid_i && ahead && head[s]) begin
                link_d[s].pred_valid   = 1'b1;
                link_d[s].pred_in_pool = 1'b1;
                link_d[s].pred_idx     = predW'(admit_slot_i);
            end

            if (issue_valid_i && issue_slot_i == slotW'(s)) link_d[s] = '0;

            if (admit_valid_i && admit_slot_i == slotW'(s)) link_d[s] = admit_link;
        end

        assign waiting_o[s] = link_q[s].pred_valid;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) link_q <= '0;
        else         link_q <= link_d;
    end
//  }}}

//  Assertions
//  {{{
    // pragma translate_off
    `ifndef VERILATOR
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        admit_valid_i |-> $onehot0({pool_link, cb_link_i}))
        else $error("more than one tail for a line");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        admit_valid_i |-> $onehot0(head))
        else $error("more than one waiting head for a line");

    for (genvar s = 0; s < numSlots; s++) begin : gen_link_assert
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            link_q[s].pred_valid && link_q[s].pred_in_pool |->
                link_q[s].pred_idx != predW'(s))
            else $error("pool slot %0d waits on itself", s);
    end
    `endif
    // pragma translate_on
//  }}}
endmodule
