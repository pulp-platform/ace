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
    int unsigned CmAddrBase;
    int unsigned CmAddrWidth;
    bit          CutSnoopReq;
    bit          CutSnoopResp;
    bit          CutSlvAx;
    bit          CutSlvReq;
    bit          CutSlvResp;
    bit          CutMstAx;
    bit          CutMstReq;
    bit          CutMstResp;
  } ccu_user_cfg_t;

  typedef struct packed {
    // User defined
    int unsigned DcacheLineWidth;
    int unsigned AxiAddrWidth;
    int unsigned AxiDataWidth;
    int unsigned AxiUserWidth;
    int unsigned AxiSlvIdWidth;
    int unsigned NoSlvPorts;
    int unsigned NoSlvPerGroup;
    bit          AmoHotfix;
    int unsigned CmAddrBase;
    int unsigned CmAddrWidth;
    bit          CutSnoopReq;
    bit          CutSnoopResp;
    bit          CutSlvAx;
    bit          CutSlvReq;
    bit          CutSlvResp;
    bit          CutMstAx;
    bit          CutMstReq;
    bit          CutMstResp;
    // Computed
    int unsigned NoGroups;
    int unsigned NoSnoopPorts;
    int unsigned NoMemPorts;
    int unsigned AxiMstIdWidth;
    int unsigned NoSnoopPortsPerGroup;
    int unsigned NoMemPortsPerGroup;
  } ccu_cfg_t;

  function automatic ccu_cfg_t ccu_build_cfg (ccu_user_cfg_t ccu_user_cfg);
    int unsigned NO_SNOOP_PORTS_PER_GROUP = 2; // read, write
    int unsigned NO_MEM_PORTS_PER_GROUP   = 2; // nosnooping, snooping
    int unsigned NO_GROUPS                = ccu_user_cfg.NoSlvPorts / ccu_user_cfg.NoSlvPerGroup;
    int unsigned NO_SNOOP_PORTS           = NO_SNOOP_PORTS_PER_GROUP * ccu_user_cfg.NoSlvPerGroup;
    int unsigned NO_MEM_PORTS             = NO_MEM_PORTS_PER_GROUP * NO_GROUPS;
    int unsigned AXI_MST_ID_WIDTH         =
      ccu_user_cfg.AxiSlvIdWidth         + // Initial ID width
      $clog2(ccu_user_cfg.NoSlvPerGroup) + // Internal MUX additional bits
      $clog2(NO_MEM_PORTS)               + // Final MUX additional bits
      2;                                   // AMO support

    ccu_cfg_t ccu_cfg = '{default: '0};

    ccu_cfg.DcacheLineWidth      = ccu_user_cfg.DcacheLineWidth;
    ccu_cfg.AxiAddrWidth         = ccu_user_cfg.AxiAddrWidth;
    ccu_cfg.AxiDataWidth         = ccu_user_cfg.AxiDataWidth;
    ccu_cfg.AxiUserWidth         = ccu_user_cfg.AxiUserWidth;
    ccu_cfg.AxiSlvIdWidth        = ccu_user_cfg.AxiSlvIdWidth;
    ccu_cfg.NoSlvPorts           = ccu_user_cfg.NoSlvPorts;
    ccu_cfg.NoSlvPerGroup        = ccu_user_cfg.NoSlvPerGroup;
    ccu_cfg.AmoHotfix            = ccu_user_cfg.AmoHotfix;
    ccu_cfg.CmAddrBase           = ccu_user_cfg.CmAddrBase;
    ccu_cfg.CmAddrWidth          = ccu_user_cfg.CmAddrWidth;
    ccu_cfg.CutSnoopReq          = ccu_user_cfg.CutSnoopReq;
    ccu_cfg.CutSnoopResp         = ccu_user_cfg.CutSnoopResp;
    ccu_cfg.CutSlvAx             = ccu_user_cfg.CutSlvAx;
    ccu_cfg.CutSlvReq            = ccu_user_cfg.CutSlvReq;
    ccu_cfg.CutSlvResp           = ccu_user_cfg.CutSlvResp;
    ccu_cfg.CutMstAx             = ccu_user_cfg.CutMstAx;
    ccu_cfg.CutMstReq            = ccu_user_cfg.CutMstReq;
    ccu_cfg.CutMstResp           = ccu_user_cfg.CutMstResp;
    ccu_cfg.NoGroups             = NO_GROUPS;
    ccu_cfg.NoSnoopPorts         = NO_SNOOP_PORTS;
    ccu_cfg.NoMemPorts           = NO_MEM_PORTS;
    ccu_cfg.AxiMstIdWidth        = AXI_MST_ID_WIDTH;
    ccu_cfg.NoSnoopPortsPerGroup = NO_SNOOP_PORTS_PER_GROUP;
    ccu_cfg.NoMemPortsPerGroup   = NO_MEM_PORTS_PER_GROUP;

    return ccu_cfg;

  endfunction

  endpackage
