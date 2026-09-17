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

package ccu_pkg;

    typedef struct packed {
        //  Number of subordinate ports (i.e. coherent managers)
        int unsigned    numSubordinates;
        //  Number of shareable simultaneous inflight transactions
        int unsigned    numShareableTransactions;
        //  ARs admitted but not yet dispatched
        int unsigned    numDispatchQueue;
        //  Number of simultaneous write transactions
        int unsigned    numWriteTransactions;
        //  Number of simultaneous inflight snoop transactions
        int unsigned    numSnoopTransactions;
        //  Address bits hashed to index the write-engine inflight FIFOs
        int unsigned    writeHashWidth;
        //  AXI/ACE parameters
        int unsigned    axiAddressWidth;
        int unsigned    axiDataWidth;
        int unsigned    axiUserWidth;
        int unsigned    axiSubordinateIdWidth;
        //  Cache parameters
        int unsigned    cachelineWidth;
        //  Snoop filter; when off the CCU broadcasts every snoop
        bit             enableSnoopFilter;
        //  Cache geometry the filter mirrors
        int unsigned    subordinateCacheSets;
        int unsigned    subordinateCacheWays;
        //  Address bits the filter tracks; the rest always report present
        int unsigned    snoopFilterAddrWidth;
        //  Subordinate ARID of a manager port holding no snoopable copy, so the
        //  filter never tracks the lines it reads and its ids may repeat
        bit             hasUntrackedArId;
        int unsigned    untrackedArId;
        //  LSB address bit used for hazard checks (inclusive)
        int unsigned    addressCheckLsb;
        //  MSB address bit used for hazard checks (inclusive)
        int unsigned    addressCheckMsb;
        //  Make snoop request FIFOs fall through
        bit             snoopReqFifoFallthrough;
        //  Make snoop response FIFOs fall through
        bit             snoopRespFifoFallthrough;
        //  Instantiate CCU control and status registers
        bit             enableCSRs;
        //  Insert spill registers in the frontend
        bit             frontendPipeAw;
        bit             frontendPipeW;
        bit             frontendPipeB;
        bit             frontendPipeAr;
        bit             frontendPipeR;
    } ccu_user_config_t;

    typedef struct packed {
        //  User parameters
        ccu_user_config_t u;
        //  Derived internal parameters
        //  Manager index width
        int unsigned subordinateIndexWidth;
        //  ID width internal to the CCU
        int unsigned axiCcuIdWidth;
        //  ID width of the manager interface of the CCU
        int unsigned axiManagerIdWidth;
        //  Byte index in cacheline
        int unsigned cachelineByteIndexWidth;
        //  Cacheline address minus offset
        int unsigned numLineWidth;
        //  Write transaction index width
        int unsigned writeTransactionIndexWidth;
        //  Number of transfers for a single cacheline
        int unsigned cachelineAxiTransfers;
        //  Transaction index width
        int unsigned transactionIndexWidth;
        //  Number of write-engine inflight FIFOs (2**writeHashWidth)
        int unsigned numWriteFifos;
        //  AXI data size
        int unsigned axiDataSize;
        //  Address slice width used for hazard checks
        int unsigned addressCheckWidth;
        //  Snoop filter set index width
        int unsigned snoopFilterSetWidth;
        //  Every tracked address bit above the set index
        int unsigned snoopFilterTagWidth;
        //  Snoop filter entry: tag plus a valid bit
        int unsigned snoopFilterEntryWidth;
    } ccu_config_t;

    function automatic ccu_config_t ccu_build_cfg(ccu_user_config_t u);
        ccu_config_t p;

        p.u                          = u;

        p.subordinateIndexWidth      = u.numSubordinates > 1 ? $clog2(u.numSubordinates) : 1;
        p.axiCcuIdWidth              = u.axiSubordinateIdWidth + p.subordinateIndexWidth;
        p.axiManagerIdWidth          = p.axiCcuIdWidth > u.writeHashWidth ?
                                       p.axiCcuIdWidth : u.writeHashWidth;
        p.cachelineByteIndexWidth    = u.cachelineWidth > 8 ? $clog2(u.cachelineWidth / 8) : 1;
        p.numLineWidth               = u.axiAddressWidth - p.cachelineByteIndexWidth;
        p.writeTransactionIndexWidth = u.numWriteTransactions > 1 ? $clog2(u.numWriteTransactions) : 1;
        p.cachelineAxiTransfers      = u.cachelineWidth / u.axiDataWidth;
        p.transactionIndexWidth      = u.numShareableTransactions > 1 ? $clog2(u.numShareableTransactions) : 1;
        p.numWriteFifos              = 2 ** u.writeHashWidth;
        p.axiDataSize                = u.axiDataWidth > 8 ? $clog2(u.axiDataWidth / 8) : 1;
        p.addressCheckWidth          = u.addressCheckMsb - u.addressCheckLsb + 1;
        p.snoopFilterSetWidth        = u.subordinateCacheSets > 1 ?
                                       $clog2(u.subordinateCacheSets) : 1;
        //  The tag spans every tracked bit above the set, so it identifies the
        //  line and two lines never share a way
        p.snoopFilterTagWidth        = u.snoopFilterAddrWidth >
                                       p.cachelineByteIndexWidth + p.snoopFilterSetWidth ?
                                       u.snoopFilterAddrWidth - p.cachelineByteIndexWidth -
                                       p.snoopFilterSetWidth : 1;
        p.snoopFilterEntryWidth      = p.snoopFilterTagWidth + 1;

        return p;
    endfunction

    //  Decoded once at admission and carried with the transaction, so no two
    //  stages can disagree about what an AR is
    typedef struct packed {
        logic              allocates;
        logic              is_no_snoop;
        logic              accepts_dirty;
        logic              accepts_dirty_shared;
        logic              accepts_shared;
        logic              is_clean_or_make;
        logic              is_exclusive_load;
        logic              is_exclusive_store;
        ace_pkg::acsnoop_t acsnoop;
    } ccu_ar_flags_t;

    function automatic ccu_ar_flags_t ccu_ar_decode(logic arbar0, ace_pkg::axdomain_t ardomain,
                                                    ace_pkg::arsnoop_t arsnoop, logic arlock);
        return '{
            //  C10-1 p.C10-280
            allocates           : ace_pkg::ace_is_read_clean(arbar0, ardomain, arsnoop)            ||
                                  ace_pkg::ace_is_read_not_shared_dirty(arbar0, ardomain, arsnoop) ||
                                  ace_pkg::ace_is_read_shared(arbar0, ardomain, arsnoop)           ||
                                  ace_pkg::ace_is_read_unique(arbar0, ardomain, arsnoop)           ||
                                  ace_pkg::ace_is_clean_unique(arbar0, ardomain, arsnoop)          ||
                                  ace_pkg::ace_is_make_unique(arbar0, ardomain, arsnoop),
            is_no_snoop         : ace_pkg::ace_is_read_no_snoop(arbar0, ardomain, arsnoop),
            accepts_dirty       : ace_pkg::ace_ar_accepts_dirty(arbar0, ardomain, arsnoop),
            accepts_dirty_shared: ace_pkg::ace_ar_accepts_dirty_shared(arbar0, ardomain, arsnoop),
            accepts_shared      : ace_pkg::ace_ar_accepts_shared(arbar0, ardomain, arsnoop),
            is_clean_or_make    : ace_pkg::ace_ar_is_clean(arbar0, ardomain, arsnoop) ||
                                  ace_pkg::ace_ar_is_make(arbar0, ardomain, arsnoop),
            is_exclusive_load   : ace_pkg::ace_ar_is_exclusive_load(arbar0, ardomain, arsnoop, arlock),
            is_exclusive_store  : ace_pkg::ace_ar_is_exclusive_store(arbar0, ardomain, arsnoop, arlock),
            acsnoop             : ace_pkg::ace_ar_acsnoop_map(arbar0, ardomain, arsnoop)
        };
    endfunction

    //  Performance events
    typedef struct packed {
        logic snoop_hit;                        // 0x16
        logic snoop_miss;                       // 0x15
        logic stage1_read_no_snoop;             // 0x14
        logic stage1_read_once;                 // 0x13
        logic stage1_read_shared;               // 0x12
        logic stage1_read_clean;                // 0x11
        logic stage1_read_not_shared_dirty;     // 0x10
        logic stage1_read_unique;               // 0x0F
        logic stage1_clean_unique;              // 0x0E
        logic stage1_make_unique;               // 0x0D
        logic stage1_clean_shared;              // 0x0C
        logic stage1_clean_invalid;             // 0x0B
        logic stage1_make_invalid;              // 0x0A
        logic stage0_stall_other;               // 0x09
        logic stage0_stall_scoreboard_hit;      // 0x08
        logic stage0_stall_scoreboard_full;     // 0x07
        logic stage0_stall_ac_fifo_full;        // 0x06
        logic stage0_stall_stage1_fifo_full;    // 0x05
        logic stage1_stall_other;               // 0x04
        logic stage1_stall_cr_not_valid;        // 0x03
        logic stage1_stall_write_engine_busy;   // 0x02
        logic stage1_stall_read_engine_busy;    // 0x01
        logic stage1_stall_cd_engine_busy;      // 0x00
    } ccu_snoop_pipeline_events_t;

endpackage
