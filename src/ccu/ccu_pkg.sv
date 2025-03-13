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

  package ccu_pkg;

  typedef struct packed {
    int unsigned DcacheLineWidth;
    int unsigned AxiAddrWidth;
    int unsigned AxiDataWidth;
    int unsigned AxiUserWidth;
    int unsigned AxiSlvIdWidth;
    int unsigned NoSlvPorts;
    int unsigned NoSlvPerGroup;
    bit          AmoHotfix;
  } ccu_cfg_t;

  function automatic int unsigned CcuAxiMstIdWidth (ccu_cfg_t ccu_cfg);
      int unsigned NoGroups = ccu_cfg.NoSlvPorts / ccu_cfg.NoSlvPerGroup;
      return (ccu_cfg.AxiSlvIdWidth         + // Initial ID width
              $clog2(ccu_cfg.NoSlvPerGroup) + // Internal MUX additional bits
              $clog2(3*NoGroups)            + // Final MUX additional bits
              1);                             // AMO support
  endfunction

  endpackage
