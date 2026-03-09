// Copyright (c) 2014-2018 ETH Zurich, University of Bologna
// Copyright (c) 2022 PlanV GmbH
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


//! ACE Package
/// Contains all necessary type definitions, constants, and generally useful functions.
/// Naming conventions are chosen to align with the ACE specification.
package ace_pkg;

    //////////////
    // Typedefs //
    //////////////

    // Additional types for already existing AXI channels
    typedef logic [3:0] arsnoop_t;
    typedef logic [2:0] awsnoop_t;
    typedef logic [1:0] axbar_t;
    typedef logic [1:0] axdomain_t;
    typedef logic [3:0] rresp_t;
    typedef logic [0:0] awunique_t;

    // Snoop related types
    typedef logic [3:0] acsnoop_t;
    typedef logic [2:0] acprot_t;

    typedef struct packed {
        logic WasUnique;
        logic IsShared;
        logic PassDirty;
        logic Error;
        logic DataTransfer;
    } crresp_t;

    ///////////////
    // Encodings //
    ///////////////

    // AxDOMAIN
    localparam axdomain_t NonShareable = 2'b00;
    localparam axdomain_t InnerShareable = 2'b01;
    localparam axdomain_t OuterShareable = 2'b10;
    localparam axdomain_t System = 2'b11;


    // AxBAR
    localparam axbar_t NormalAccessRespectingBarriers = 2'b00;
    localparam axbar_t MemoryBarrier = 2'b01;
    localparam axbar_t NormalAccessIgnoringBarriers = 2'b10;
    localparam axbar_t SynchronizationBarrier = 2'b11;

    // Uniquely defined here both for ARSNOOP and AWSNOOP
    localparam int unsigned Barrier = 0;

    // ARSNOOP
    localparam arsnoop_t ReadNoSnoop = 4'b0000;
    localparam arsnoop_t ReadOnce = 4'b0000;
    localparam arsnoop_t ReadShared = 4'b0001;
    localparam arsnoop_t ReadClean = 4'b0010;
    localparam arsnoop_t ReadNotSharedDirty = 4'b0011;
    localparam arsnoop_t ReadUnique = 4'b0111;
    localparam arsnoop_t CleanUnique = 4'b1011;
    localparam arsnoop_t MakeUnique = 4'b1100;
    localparam arsnoop_t CleanShared = 4'b1000;
    localparam arsnoop_t CleanInvalid = 4'b1001;
    localparam arsnoop_t MakeInvalid = 4'b1101;
    localparam arsnoop_t DVMComplete = 4'b1110;
    localparam arsnoop_t DVMMessage = 4'b1111;
    /* Barrier is already defined */

    // AWSNOOP
    localparam awsnoop_t WriteNoSnoop = 3'b000;
    localparam awsnoop_t WriteUnique = 3'b000;
    localparam awsnoop_t WriteLineUnique = 3'b001;
    localparam awsnoop_t WriteClean = 3'b010;
    localparam awsnoop_t WriteBack = 3'b011;
    localparam awsnoop_t Evict = 3'b100;
    localparam awsnoop_t WriteEvict = 3'b101;
    /* Barrier is already defined */

    // ACSNOOP
    //
    //  The encoding is shared with ARSNOOP transactions for the following cases:
    //    - ReadOnce
    //    - ReadShared
    //    - ReadClean
    //    - ReadNotSharedDirty
    //    - ReadUnique
    //    - CleanShared
    //    - CleanInvalid
    //    - MakeInvalid
    //    - DVMComplete
    //    - DVMMessage
    //  Cast the parameters to acsnoop_t for consistency (but works anyway)

    // RRESP
    // Bit position for additional ACE-related fields
    localparam int unsigned RESP_IS_DIRTY = 2;
    localparam int unsigned RESP_IS_SHARED = 3;

    ///////////////
    // Functions //
    ///////////////

    // AWSNOOP decoding
    function automatic logic ace_is_write_no_snoop(logic awbar0, axdomain_t awdomain,
                                                   awsnoop_t awsnoop);
        return (
      awbar0 == 1'b0 &&
      awdomain inside {NonShareable, System} &&
      awsnoop == WriteNoSnoop
      );
    endfunction

    function automatic logic ace_is_write_unique(logic awbar0, axdomain_t awdomain,
                                                 awsnoop_t awsnoop);
        return (
      awbar0 == 1'b0 &&
      awdomain inside {InnerShareable, OuterShareable} &&
      awsnoop == WriteUnique
      );
    endfunction

    function automatic logic ace_is_write_line_unique(logic awbar0, axdomain_t awdomain,
                                                      awsnoop_t awsnoop);
        return (
      awbar0 == 1'b0 &&
      awdomain inside {InnerShareable, OuterShareable} &&
      awsnoop == WriteLineUnique
      );
    endfunction

    function automatic logic ace_is_write_clean(logic awbar0, axdomain_t awdomain,
                                                awsnoop_t awsnoop);
        return (
      awbar0 == 1'b0 &&
      awdomain inside {NonShareable, InnerShareable, OuterShareable} &&
      awsnoop == WriteClean
      );
    endfunction

    function automatic logic ace_is_write_back(logic awbar0, axdomain_t awdomain,
                                               awsnoop_t awsnoop);
        return (
      awbar0 == 1'b0 &&
      awdomain inside {NonShareable, InnerShareable, OuterShareable} &&
      awsnoop == WriteBack
      );
    endfunction

    function automatic logic ace_is_evict(logic awbar0, axdomain_t awdomain, awsnoop_t awsnoop);
        return (
      awbar0 == 1'b0 &&
      awdomain inside {InnerShareable, OuterShareable} &&
      awsnoop == Evict
    );
    endfunction

    function automatic logic ace_is_write_evict(logic awbar0, axdomain_t awdomain,
                                                awsnoop_t awsnoop);
        return (
      awbar0 == 1'b0 &&
      awdomain inside {NonShareable, InnerShareable, OuterShareable} &&
      awsnoop == WriteEvict
    );
    endfunction

    // ARSNOOP decoding
    function automatic logic ace_is_read_no_snoop(logic arbar0, axdomain_t ardomain,
                                                  arsnoop_t arsnoop);
        return (arbar0 == 1'b0 && ardomain inside {NonShareable, System} && arsnoop == ReadNoSnoop);
    endfunction

    function automatic logic ace_is_read_once(logic arbar0, axdomain_t ardomain, arsnoop_t arsnoop);
        return (arbar0 == 1'b0 && ardomain inside {InnerShareable, OuterShareable} && arsnoop == ReadOnce);
    endfunction

    function automatic logic ace_is_read_shared(logic arbar0, axdomain_t ardomain,
                                                arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {InnerShareable, OuterShareable} &&
      arsnoop == ReadShared
    );
    endfunction

    function automatic logic ace_is_read_clean(logic arbar0, axdomain_t ardomain,
                                               arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {InnerShareable, OuterShareable} &&
      arsnoop == ReadClean
    );
    endfunction

    function automatic logic ace_is_read_not_shared_dirty(logic arbar0, axdomain_t ardomain,
                                                          arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {InnerShareable, OuterShareable} &&
      arsnoop == ReadNotSharedDirty
    );
    endfunction

    function automatic logic ace_is_read_unique(logic arbar0, axdomain_t ardomain,
                                                arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {InnerShareable, OuterShareable} &&
      arsnoop == ReadUnique
    );
    endfunction

    function automatic logic ace_is_clean_unique(logic arbar0, axdomain_t ardomain,
                                                 arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {InnerShareable, OuterShareable} &&
      arsnoop == CleanUnique
    );
    endfunction

    function automatic logic ace_is_make_unique(logic arbar0, axdomain_t ardomain,
                                                arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {InnerShareable, OuterShareable} &&
      arsnoop == MakeUnique
    );
    endfunction

    function automatic logic ace_is_clean_shared(logic arbar0, axdomain_t ardomain,
                                                 arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {NonShareable, InnerShareable, OuterShareable} &&
      arsnoop == CleanShared
    );
    endfunction

    function automatic logic ace_is_clean_invalid(logic arbar0, axdomain_t ardomain,
                                                  arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {NonShareable, InnerShareable, OuterShareable} &&
      arsnoop == CleanInvalid
    );
    endfunction

    function automatic logic ace_is_make_invalid(logic arbar0, axdomain_t ardomain,
                                                 arsnoop_t arsnoop);
        return (
      arbar0 == 1'b0 &&
      ardomain inside {NonShareable, InnerShareable, OuterShareable} &&
      arsnoop == MakeInvalid
    );
    endfunction

    // Transaction groups

    function automatic logic ace_aw_is_shareable(logic awbar0, axdomain_t awdomain,
                                                 awsnoop_t awsnoop);
        return ace_is_write_unique(awbar0, awdomain, awsnoop) ||
               ace_is_write_line_unique(awbar0, awdomain, awsnoop);
    endfunction

    function automatic logic ace_aw_is_memory_update(logic awbar0, axdomain_t awdomain,
                                                     awsnoop_t awsnoop);
        return ace_is_write_clean(awbar0, awdomain, awsnoop) ||
               ace_is_write_back(awbar0, awdomain, awsnoop)  ||
               ace_is_evict(awbar0, awdomain, awsnoop)       ||
               ace_is_write_evict(awbar0, awdomain, awsnoop);
    endfunction

    function automatic logic ace_aw_is_non_blocking(logic awbar0, axdomain_t awdomain,
                                                    awsnoop_t awsnoop);
        return ace_aw_is_memory_update(awbar0, awdomain, awsnoop) ||
               ace_is_write_no_snoop(awbar0, awdomain, awsnoop);
    endfunction

    function automatic logic ace_ar_is_shareable(logic arbar0, axdomain_t ardomain,
                                                 arsnoop_t arsnoop);
        return ace_is_read_once(arbar0, ardomain, arsnoop)             ||
               ace_is_read_shared(arbar0, ardomain, arsnoop)           ||
               ace_is_read_clean(arbar0, ardomain, arsnoop)            ||
               ace_is_read_not_shared_dirty(arbar0, ardomain, arsnoop) ||
               ace_is_read_unique(arbar0, ardomain, arsnoop)           ||
               ace_is_clean_unique(arbar0, ardomain, arsnoop)          ||
               ace_is_make_unique(arbar0, ardomain, arsnoop);
    endfunction

    function automatic logic ace_ar_is_clean(logic arbar0, axdomain_t ardomain,
                                             arsnoop_t arsnoop);
        return ace_is_clean_unique(arbar0, ardomain, arsnoop)  ||
               ace_is_clean_shared(arbar0, ardomain, arsnoop)  ||
               ace_is_clean_invalid(arbar0, ardomain, arsnoop);
    endfunction

    // Snoop transaction from initiating master transaction
    function automatic acsnoop_t ace_ar_acsnoop_map(logic arbar0, axdomain_t ardomain,
                                                    arsnoop_t arsnoop);
        return ace_is_clean_unique(arbar0, ardomain, arsnoop) ? acsnoop_t'(CleanInvalid) :
               ace_is_make_unique(arbar0, ardomain, arsnoop)  ? acsnoop_t'(MakeInvalid)  :
                                                                acsnoop_t'(arsnoop);
    endfunction

    function automatic acsnoop_t ace_aw_acsnoop_map(logic awbar0, axdomain_t awdomain,
                                                    awsnoop_t awsnoop);
        return ace_is_write_unique(awbar0, awdomain, awsnoop)      ? acsnoop_t'(CleanInvalid) :
               ace_is_write_line_unique(awbar0, awdomain, awsnoop) ? acsnoop_t'(MakeInvalid)  :
                                                                     acsnoop_t'(CleanInvalid);
    endfunction

    function automatic logic ace_ar_accepts_dirty(logic arbar0, axdomain_t ardomain,
                                                  arsnoop_t arsnoop);
        return ace_is_read_not_shared_dirty(arbar0, ardomain, arsnoop) ||
               ace_is_read_shared(arbar0, ardomain, arsnoop)           ||
               ace_is_read_unique(arbar0, ardomain, arsnoop);
    endfunction

    function automatic logic ace_ar_accepts_dirty_shared(logic arbar0, axdomain_t ardomain,
                                                         arsnoop_t arsnoop);
        return ace_is_read_shared(arbar0, ardomain, arsnoop);
    endfunction

    function automatic logic ace_ar_accepts_shared(logic arbar0, axdomain_t ardomain,
                                                   arsnoop_t arsnoop);
        return ace_is_read_not_shared_dirty(arbar0, ardomain, arsnoop) ||
               ace_is_read_shared(arbar0, ardomain, arsnoop)           ||
               ace_is_read_clean(arbar0, ardomain, arsnoop);
    endfunction

    function automatic logic ace_ar_is_exclusive_load(logic arbar0, axdomain_t ardomain,
                                                      arsnoop_t arsnoop, logic arlock);
        return (ace_is_read_shared(arbar0, ardomain, arsnoop) ||
                ace_is_read_clean(arbar0, ardomain, arsnoop)) && arlock;
    endfunction

    function automatic logic ace_ar_is_exclusive_store(logic arbar0, axdomain_t ardomain,
                                                       arsnoop_t arsnoop, logic arlock);
        return (ace_is_clean_unique(arbar0, ardomain, arsnoop)) && arlock;
    endfunction

endpackage
