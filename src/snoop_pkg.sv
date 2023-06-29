// Copyright (c) 2014-2018 ETH Zurich, University of Bologna
// Copyright (c) 2022 PlanV GmbH
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
package snoop_pkg;

  // CRRESP
  typedef struct packed {
    logic        wasUnique;
    logic        isShared;
    logic        passDirty;
    logic        error;
    logic        dataTransfer;
  } crresp_t;

   /// Support for snoop channels
   typedef logic [3:0] acsnoop_t;
   typedef logic [2:0] acprot_t;

  // AC snoop encoding
  localparam READ_ONCE = 4'b0000;
  localparam READ_SHARED = 4'b0001;
  localparam READ_CLEAN = 4'b0010;
  localparam READ_NOT_SHARED_DIRTY = 4'b0011;
  localparam READ_UNIQUE = 4'b0111;
  localparam CLEAN_SHARED = 4'b1000;
  localparam CLEAN_INVALID = 4'b1001;
  localparam CLEAN_UNIQUE = 4'b1011;
  localparam MAKE_INVALID = 4'b1101;
  localparam DVM_COMPLETE = 4'b1110;
  localparam DVM_MESSAGE = 4'b1111;

endpackage
