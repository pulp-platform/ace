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
        //  Memory reads in flight; each reserves a cacheline of R buffering
        int unsigned    numMemReadCredits;
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
        //  ARID of a port without a snoopable cache; its reads are not tracked
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
        //  Full tag: every tracked bit above the set index
        p.snoopFilterTagWidth        = u.snoopFilterAddrWidth >
                                       p.cachelineByteIndexWidth + p.snoopFilterSetWidth ?
                                       u.snoopFilterAddrWidth - p.cachelineByteIndexWidth -
                                       p.snoopFilterSetWidth : 1;
        p.snoopFilterEntryWidth      = p.snoopFilterTagWidth + 1;

        return p;
    endfunction

    //  AR decode, done once at admission
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
    //
    //  Counter [i] counts event [i]. An event is a one-cycle pulse, so a count
    //  is a number of cycles. Every unit registers its events at its boundary.
    localparam int unsigned numEvents = 64;

    //  Snoop pipeline
    typedef struct packed {
        logic stage1_stall_other;                   // 0x1E
        logic stage1_stall_cd_engine_busy;          // 0x1D
        logic stage1_stall_write_engine_busy;       // 0x1C
        logic stage1_stall_cr_not_valid;            // 0x1B
        logic stage0_stall_other;                   // 0x1A
        logic stage0_stall_maintenance;             // 0x19
        logic stage0_stall_stage1_fifo_full;        // 0x18
        logic stage0_stall_ac_fifo_full;            // 0x17
        logic ac_pruned;                            // 0x16
        logic ac_stall;                             // 0x15
        logic ac_sent;                              // 0x14
        logic make_unique;                          // 0x13
        logic clean_unique;                         // 0x12
        logic read_unique;                          // 0x11
        logic read_clean;                           // 0x10
        logic read_shared;                          // 0x0F
        logic read_no_snoop;                        // 0x0E
        logic backinval_dirty;                      // 0x0B
        logic snoop_writeback;                      // 0x0A
        logic snoop_miss;                           // 0x09
        logic snoop_hit;                            // 0x08
    } ccu_snoop_pipeline_events_t;

    //  Frontend (Point of Serialization)
    typedef struct packed {
        logic r_stall_rack_fifo_full;               // 0x3D
        logic aw_stall_sf_remove_full;              // 0x3C
        logic ar_stall;                             // 0x3B
        logic aw_stall_pos_full;                    // 0x32
        logic rack_outstanding;                     // 0x04
        logic aw_accepted;                          // 0x03
    } ccu_frontend_events_t;

    //  AR dispatch
    typedef struct packed {
        logic bi_blocked;                           // 0x27
        logic sf_insert_outstanding;                // 0x26
        logic sf_insert_stall;                      // 0x25
        logic dispatch_stall;                       // 0x24
        logic stall_queue_full;                     // 0x23
        logic stall_sb_full;                        // 0x22
        logic queue_pred_wait;                      // 0x21
        logic queue_blocked;                        // 0x20
        logic chained;                              // 0x1F
        logic ar_dispatched;                        // 0x02
        logic ar_admitted;                          // 0x01
    } ccu_ar_dispatch_events_t;

    //  Snoop filter, reduced over the per-subordinate tables
    typedef struct packed {
        logic remove_miss;                          // 0x2F
        logic backinval_issued;                     // 0x2E
        logic insert_stuck;                         // 0x2D
        logic update_blocked_by_lookup;             // 0x2C
        logic port_busy;                            // 0x2B
        logic lookup_present_all;                   // 0x2A
        logic lookup_present_none;                  // 0x29
        logic lookup;                               // 0x28
    } ccu_snoop_filter_events_t;

    //  Write engine
    typedef struct packed {
        logic w_starve;                             // 0x37
        logic w_stall_mem;                          // 0x36
        logic aw_stall_mem;                         // 0x35
        logic aw_stall_hash_full;                   // 0x34
        logic wb_alloc_stall_full;                  // 0x33
        logic aw_writeback;                         // 0x31
        logic aw_issued;                            // 0x30
        logic mem_ar_stall;                         // 0x0C
    } ccu_write_engine_events_t;

    //  Read engine
    typedef struct packed {
        logic r_stall;                              // 0x3A
        logic ar_stall_mem;                         // 0x39
        logic ar_stall_hazard;                      // 0x38
        logic r_beat_sc_fail;                       // 0x07
        logic r_beat_snoop;                         // 0x06
        logic r_beat_mem;                           // 0x05
    } ccu_read_engine_events_t;

    //  Manager port and the window every rate is taken over
    typedef struct packed {
        logic mem_w_beat;                           // 0x3F
        logic mem_r_beat;                           // 0x3E
        logic mem_ar;                               // 0x0D
        logic cycles;                               // 0x00
    } ccu_top_events_t;

    //  The event vector seen by the counters
    typedef struct packed {
        logic mem_w_beat;                           // 0x3F
        logic mem_r_beat;                           // 0x3E
        logic fe_r_stall_rack_fifo_full;            // 0x3D
        logic fe_aw_stall_sf_remove_full;           // 0x3C
        logic fe_ar_stall;                          // 0x3B
        logic re_r_stall;                           // 0x3A
        logic re_ar_stall_mem;                      // 0x39
        logic re_ar_stall_hazard;                   // 0x38
        logic we_w_starve;                          // 0x37
        logic we_w_stall_mem;                       // 0x36
        logic we_aw_stall_mem;                      // 0x35
        logic we_aw_stall_hash_full;                // 0x34
        logic we_wb_alloc_stall_full;               // 0x33
        logic fe_aw_stall_pos_full;                 // 0x32
        logic we_aw_writeback;                      // 0x31
        logic we_aw_issued;                         // 0x30
        logic sf_remove_miss;                       // 0x2F
        logic sf_backinval_issued;                  // 0x2E
        logic sf_insert_stuck;                      // 0x2D
        logic sf_update_blocked_by_lookup;          // 0x2C
        logic sf_port_busy;                         // 0x2B
        logic sf_lookup_present_all;                // 0x2A
        logic sf_lookup_present_none;               // 0x29
        logic sf_lookup;                            // 0x28
        logic ad_bi_blocked;                        // 0x27
        logic ad_sf_insert_outstanding;             // 0x26
        logic ad_sf_insert_stall;                   // 0x25
        logic ad_dispatch_stall;                    // 0x24
        logic ad_stall_queue_full;                  // 0x23
        logic ad_stall_sb_full;                     // 0x22
        logic ad_queue_pred_wait;                   // 0x21
        logic ad_queue_blocked;                     // 0x20
        logic ad_chained;                           // 0x1F
        logic sp_stage1_stall_other;                // 0x1E
        logic sp_stage1_stall_cd_engine_busy;       // 0x1D
        logic sp_stage1_stall_write_engine_busy;    // 0x1C
        logic sp_stage1_stall_cr_not_valid;         // 0x1B
        logic sp_stage0_stall_other;                // 0x1A
        logic sp_stage0_stall_maintenance;          // 0x19
        logic sp_stage0_stall_stage1_fifo_full;     // 0x18
        logic sp_stage0_stall_ac_fifo_full;         // 0x17
        logic sp_ac_pruned;                         // 0x16
        logic sp_ac_stall;                          // 0x15
        logic sp_ac_sent;                           // 0x14
        logic sp_make_unique;                       // 0x13
        logic sp_clean_unique;                      // 0x12
        logic sp_read_unique;                       // 0x11
        logic sp_read_clean;                        // 0x10
        logic sp_read_shared;                       // 0x0F
        logic sp_read_no_snoop;                     // 0x0E
        logic mem_ar;                               // 0x0D
        logic we_mem_ar_stall;                      // 0x0C
        logic sp_backinval_dirty;                   // 0x0B
        logic sp_snoop_writeback;                   // 0x0A
        logic sp_snoop_miss;                        // 0x09
        logic sp_snoop_hit;                         // 0x08
        logic re_r_beat_sc_fail;                    // 0x07
        logic re_r_beat_snoop;                      // 0x06
        logic re_r_beat_mem;                        // 0x05
        logic fe_rack_outstanding;                  // 0x04
        logic fe_aw_accepted;                       // 0x03
        logic ad_ar_dispatched;                     // 0x02
        logic ad_ar_admitted;                       // 0x01
        logic cycles;                               // 0x00
    } ccu_events_t;

endpackage
