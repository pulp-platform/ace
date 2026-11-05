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

package ccu_pkg;

    typedef struct packed {
        //  Number of subordinate ports (i.e. coherent managers)
        int unsigned    numSubordinates;
        //  Snoop-dependent operations in flight, one tid each
        int unsigned    numShareableTransactions;
        //  Snoop-dependent operations waiting to issue, one dispatch-pool slot each
        int unsigned    numDispatchSlots;
        //  Snoops one port may have between AC and CR
        int unsigned    numSnoopTransactions;
        //  Cachelines of CD each port takes before its snoop is routed; 0 holds CD at the manager
        int unsigned    numCdBufferLines;
        //  AXI/ACE parameters
        int unsigned    axiAddressWidth;
        int unsigned    axiDataWidth;
        int unsigned    axiUserWidth;
        int unsigned    axiSubordinateIdWidth;
        //  ARID of a requester without a snoopable cache; its reads never enter the filter
        bit             hasUntrackedArId;
        int unsigned    untrackedArId;
        //  Cache parameters
        int unsigned    cachelineWidth;
        //  Snoop filter; when off the CCU broadcasts every snoop
        bit             enableSnoopFilter;
        //  Cache geometry the filter mirrors
        int unsigned    subordinateCacheSets;
        int unsigned    subordinateCacheWays;
        //  Address bits the filter tracks; the rest always report present
        int unsigned    snoopFilterAddrWidth;
        //  Instantiate CCU control and status registers
        bit             enableCSRs;
        //  R reassembly slots per port, one per outstanding read
        int unsigned    numRSlots;
        //  Write-lane slots for the managers' non-blocking writes
        int unsigned    numPortSlots;
        //  Write-lane slots for the CCU's own snoop writebacks
        int unsigned    numWritebackSlots;
        //  Tids reserved for back-invalidations, shared by the filter tables; at least one
        int unsigned    numBackInvalSlots;
        //  R buffer and write-lane data in flops; a 2-port tc_sram otherwise
        bit             flopBuffers;
        //  Filter tag arrays on one port, shared by fixed phases; two ports otherwise
        bit             singlePortFilter;
        //  Register cuts, one bit per channel; see the Cut* indices
        logic [9:0]     cutSubordinate;
        logic [4:0]     cutManager;
        logic [1:0]     cutInternal;
    } ccu_user_config_t;

    typedef struct packed {
        //  User parameters
        ccu_user_config_t u;
        //  Derived internal parameters
        //  Manager index width
        int unsigned subordinateIndexWidth;
        //  Byte index in cacheline
        int unsigned cachelineByteIndexWidth;
        //  Cacheline address minus offset
        int unsigned numLineWidth;
        //  Number of transfers for a single cacheline
        int unsigned cachelineAxiTransfers;
        //  AXI data size
        int unsigned axiDataSize;
        //  Snoop filter set index width
        int unsigned snoopFilterSetWidth;
        //  Every tracked address bit above the set index
        int unsigned snoopFilterTagWidth;
        //  Snoop filter entry: tag plus a valid bit
        int unsigned snoopFilterEntryWidth;
        //  Transaction table: reads plus the reserved back-invalidation tids
        int unsigned numTids;
        int unsigned tidWidth;
        int unsigned rSlotWidth;
        //  Write lane: port slots, then writeback slots
        int unsigned numWSlots;
        int unsigned wSlotWidth;
        //  Writes a port may have between AW and B
        int unsigned numBSlots;
        int unsigned bSlotWidth;
        //  Beat within a cacheline
        int unsigned beatIndexWidth;
        //  Manager ID: the wider of a tid (AR) and a chain ID (AW)
        int unsigned managerIdWidth;
    } ccu_config_t;

    function automatic ccu_config_t ccu_build_cfg(ccu_user_config_t u);
        ccu_config_t p;

        p.u                          = u;

        p.subordinateIndexWidth      = u.numSubordinates > 1 ? $clog2(u.numSubordinates) : 1;
        p.cachelineByteIndexWidth    = u.cachelineWidth > 8 ? $clog2(u.cachelineWidth / 8) : 1;
        p.numLineWidth               = u.axiAddressWidth - p.cachelineByteIndexWidth;
        p.cachelineAxiTransfers      = u.cachelineWidth / u.axiDataWidth;
        p.axiDataSize                = u.axiDataWidth > 8 ? $clog2(u.axiDataWidth / 8) : 1;
        p.snoopFilterSetWidth        = u.subordinateCacheSets > 1 ?
                                       $clog2(u.subordinateCacheSets) : 1;
        //  Full tag: every tracked bit above the set index
        p.snoopFilterTagWidth        = u.snoopFilterAddrWidth >
                                       p.cachelineByteIndexWidth + p.snoopFilterSetWidth ?
                                       u.snoopFilterAddrWidth - p.cachelineByteIndexWidth -
                                       p.snoopFilterSetWidth : 1;
        p.snoopFilterEntryWidth      = p.snoopFilterTagWidth + 1;

        p.numTids                    = u.numShareableTransactions + u.numBackInvalSlots;
        p.tidWidth                   = p.numTids > 1 ? $clog2(p.numTids) : 1;
        p.rSlotWidth                 = u.numRSlots > 1 ? $clog2(u.numRSlots) : 1;
        p.numWSlots                  = u.numPortSlots + u.numWritebackSlots;
        p.wSlotWidth                 = p.numWSlots > 1 ? $clog2(p.numWSlots) : 1;
        p.numBSlots                  = u.numPortSlots + 2;
        p.bSlotWidth                 = p.numBSlots > 1 ? $clog2(p.numBSlots) : 1;
        p.beatIndexWidth             = p.cachelineAxiTransfers > 1 ?
                                       $clog2(p.cachelineAxiTransfers) : 1;
        p.managerIdWidth             = p.tidWidth > p.wSlotWidth ? p.tidWidth : p.wSlotWidth;

        return p;
    endfunction

    //  Bit of each channel in cutSubordinate and cutManager
    localparam int unsigned CutAr   = 0;
    localparam int unsigned CutAw   = 1;
    localparam int unsigned CutW    = 2;
    localparam int unsigned CutR    = 3;
    localparam int unsigned CutB    = 4;
    localparam int unsigned CutAc   = 5;
    localparam int unsigned CutCr   = 6;
    localparam int unsigned CutCd   = 7;
    localparam int unsigned CutRack = 8;
    localparam int unsigned CutWack = 9;

    //  Bit of each direction of the port-slice networks in cutInternal
    localparam int unsigned CutToSlice = 0;
    localparam int unsigned CutToPort  = 1;

    //  Operations, actions and events
    //  {{{
    //  Performance events, one-cycle pulses; per-port events are ORed over the ports

    //  Port adapters
    typedef struct packed {
        logic cd_wait_resolve;      // CD held at a port until its tid resolves
        logic b_beat;
        logic r_stall;              // R held by the manager
        logic r_beat;
        logic w_wait_map;           // W held until its AW reached the write lane
        logic aw_stall;
        logic aw_accept;
        logic ar_stall_r_slot;      // AR held for an R slot
        logic ar_accept;
    } ccu_port_events_t;

    //  Transaction table
    typedef struct packed {
        logic issue_stall_tid;         // a ready pool slot held for a free tid
        logic insert_owed;             // some entry owes the filter an insert
        logic resolve_stall_memory;    // resolve held for the memory-token FIFO
        logic resolve_stall_writeback; // resolve held for a writeback slot
        logic resolve;
        logic snoop_stall_ac_full;     // an ordered entry held for a full AC FIFO
        logic snoop_token;
        logic chained;                 // admitted behind a same-line entry
        logic admit_stall_full;        // a read held for a free pool slot
        logic admit_back_inval;
        logic admit_read;
    } ccu_tt_events_t;

    //  Snoop engine
    typedef struct packed {
        logic cr;
        logic ac_stall;
        logic ac_sent;
    } ccu_snoop_events_t;

    //  Memory engine
    typedef struct packed {
        logic r_beat;
        logic ar_stall_hazard;      // memory AR held by a same-line pending write
        logic ar_stall_memory;
        logic ar_issued;
    } ccu_mem_events_t;

    //  Write lane
    typedef struct packed {
        logic b;
        logic w_stall_memory;
        logic w_beat;
        logic aw_stall_memory;
        logic aw_issued;
        logic writeback_alloc;
        logic port_stall_full;      // a non-blocking AW held for a port slot
        logic port_alloc;
    } ccu_lane_events_t;

    //  Snoop filter, ORed over its tables
    typedef struct packed {
        logic remove_miss;
        logic back_inval;
        logic insert_stuck;
        logic update_busy;
        logic lookup_present_all;
        logic lookup_present_none;
        logic lookup;
    } ccu_filter_events_t;

    //  Manager port
    typedef struct packed {
        logic mem_b;
        logic mem_w_beat;
        logic mem_aw;
        logic mem_r_beat;
        logic mem_ar;
        logic cycles;
    } ccu_port_mem_events_t;

    //  The vector the counters select from, event 0 is the cycle count
    typedef struct packed {
        ccu_filter_events_t   filter;
        ccu_lane_events_t     lane;
        ccu_mem_events_t      mem;
        ccu_snoop_events_t    snoop;
        ccu_tt_events_t       tt;
        ccu_port_events_t     port;
        ccu_port_mem_events_t top;
    } ccu_events_t;
    //  What a snoop-dependent operation is, decoded once at admission
    typedef enum logic [3:0] {
        OpReadNoSnoop,
        OpReadOnce,
        OpReadClean,
        OpReadNotSharedDirty,
        OpReadShared,
        OpReadUnique,
        OpCleanUnique,
        OpMakeUnique,
        OpCleanShared,
        OpCleanInvalid,
        OpMakeInvalid,
        OpWriteUnique,
        OpWriteLineUnique,
        OpBackInval,
        OpInvalid
    } ccu_op_e;

    //  What an entry does once its snoops are resolved
    typedef struct packed {
        logic stub_fail;
        logic resp_b;
        logic mem_wr;
        logic ack_r;
        logic cd_wb;
        logic cd_r;
        logic mem_rd;
    } ccu_actions_t;

    //  The exclusive monitor's answer for an exclusive load or store
    typedef struct packed {
        logic pass;
        logic fail;
    } ccu_excl_t;

    typedef struct packed {
        ccu_actions_t actions;
        logic         is_shared;
        logic         pass_dirty;
    } ccu_outcome_t;

    function automatic ccu_op_e ccu_op_decode(logic bar0, ace_pkg::axdomain_t domain,
                                              ace_pkg::arsnoop_t snoop);
        unique case (1'b1)
            ace_pkg::ace_is_read_no_snoop        (bar0, domain, snoop): return OpReadNoSnoop;
            ace_pkg::ace_is_read_once            (bar0, domain, snoop): return OpReadOnce;
            ace_pkg::ace_is_read_clean           (bar0, domain, snoop): return OpReadClean;
            ace_pkg::ace_is_read_not_shared_dirty(bar0, domain, snoop): return OpReadNotSharedDirty;
            ace_pkg::ace_is_read_shared          (bar0, domain, snoop): return OpReadShared;
            ace_pkg::ace_is_read_unique          (bar0, domain, snoop): return OpReadUnique;
            ace_pkg::ace_is_clean_unique         (bar0, domain, snoop): return OpCleanUnique;
            ace_pkg::ace_is_make_unique          (bar0, domain, snoop): return OpMakeUnique;
            ace_pkg::ace_is_clean_shared         (bar0, domain, snoop): return OpCleanShared;
            ace_pkg::ace_is_clean_invalid        (bar0, domain, snoop): return OpCleanInvalid;
            ace_pkg::ace_is_make_invalid         (bar0, domain, snoop): return OpMakeInvalid;
            default:                                                    return OpInvalid;
        endcase
    endfunction

    //  The snoop an operation sends
    function automatic ace_pkg::acsnoop_t ccu_op_acsnoop(ccu_op_e op);
        unique case (op)
            OpReadOnce:           return ace_pkg::acsnoop_t'(ace_pkg::ReadOnce);
            OpReadClean:          return ace_pkg::acsnoop_t'(ace_pkg::ReadClean);
            OpReadNotSharedDirty: return ace_pkg::acsnoop_t'(ace_pkg::ReadNotSharedDirty);
            OpReadShared:         return ace_pkg::acsnoop_t'(ace_pkg::ReadShared);
            OpReadUnique:         return ace_pkg::acsnoop_t'(ace_pkg::ReadUnique);
            OpCleanShared:        return ace_pkg::acsnoop_t'(ace_pkg::CleanShared);
            OpMakeUnique,
            OpMakeInvalid,
            OpWriteLineUnique:    return ace_pkg::acsnoop_t'(ace_pkg::MakeInvalid);
            default:              return ace_pkg::acsnoop_t'(ace_pkg::CleanInvalid);
        endcase
    endfunction

    //  The requester keeps the line, so the snoop filter must learn it holds it
    function automatic logic ccu_op_allocates(ccu_op_e op);
        return op inside {OpReadClean, OpReadNotSharedDirty, OpReadShared, OpReadUnique,
                          OpCleanUnique, OpMakeUnique};
    endfunction

    //  The IsShared answer is the interconnect's to give: any snooped copy left behind
    function automatic logic ccu_op_reports_shared(ccu_op_e op);
        return op inside {OpReadOnce, OpReadClean, OpReadNotSharedDirty, OpReadShared,
                          OpCleanShared};
    endfunction

    function automatic logic ccu_op_accepts_dirty(ccu_op_e op);
        return op inside {OpReadNotSharedDirty, OpReadShared, OpReadUnique};
    endfunction

    function automatic logic ccu_op_accepts_dirty_shared(ccu_op_e op);
        return op == OpReadShared;
    endfunction

    //  What resolving an entry's snoops leaves it to do, from the ORed CR bits
    function automatic ccu_outcome_t ccu_resolve(ccu_op_e op, ccu_excl_t excl,
                                                 ace_pkg::crresp_t cr);
        ccu_outcome_t o;

        o = '0;

        //  A failed store-conditional is answered at once, with nobody snooped
        if (excl.fail) begin
            o.actions.ack_r = 1'b1;
            return o;
        end

        unique case (op)
            OpReadNoSnoop:
                o.actions.mem_rd = 1'b1;
            OpReadOnce, OpReadClean, OpReadNotSharedDirty, OpReadShared, OpReadUnique: begin
                o.is_shared = cr.IsShared && ccu_op_reports_shared(op);
                if (!cr.DataTransfer) begin
                    o.actions.mem_rd = 1'b1;
                end else begin
                    o.actions.cd_r = 1'b1;
                    o.pass_dirty   = cr.PassDirty &&
                                     (o.is_shared ? ccu_op_accepts_dirty_shared(op) :
                                                    ccu_op_accepts_dirty(op));
                    //  Dirt the requester cannot take goes to memory
                    o.actions.cd_wb = cr.PassDirty && !o.pass_dirty;
                end
            end
            OpCleanUnique, OpCleanShared, OpCleanInvalid: begin
                o.actions.ack_r = 1'b1;
                o.actions.cd_wb = cr.DataTransfer && cr.PassDirty;
                o.is_shared     = cr.IsShared && ccu_op_reports_shared(op);
            end
            OpMakeUnique, OpMakeInvalid:
                o.actions.ack_r = 1'b1;
            OpBackInval:
                o.actions.cd_wb = cr.DataTransfer && cr.PassDirty;
            OpWriteUnique, OpWriteLineUnique:
                o.actions.stub_fail = 1'b1;
            default: ;
        endcase

        return o;
    endfunction
    //  }}}

endpackage
