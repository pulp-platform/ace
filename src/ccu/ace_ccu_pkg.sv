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

package ace_ccu_pkg;

    typedef struct packed {
        // Number of slv ports
        int unsigned SlvPorts;
        // Maximum blocking inflight transactions
        int unsigned MaxTransactions;
        // Shareable W channel buffer size
        int unsigned ShareableWFifoDepth;
        // Instantiate replay table
        bit          ReplayEn;
        // Address bits to be used during conflict checking
        int unsigned NLineWidth;
        // AXI/ACE parameters
        int unsigned AxiAddrWidth;
        int unsigned AxiDataWidth;
        int unsigned AxiUserWidth;
        int unsigned AxiSlvIdWidth;
        // Unique IDs are passed to frontend demux
        bit          AxiUniqueIds;
        // Lookup bits in frontend demux
        int unsigned AxiIdLookupBits;
        // Cache parameters
        int unsigned CachelineWidth;
        // I/O cuts
        bit          CutSlvReq;
        bit          CutSlvResp;
        bit          CutMstReq;
        bit          CutMstResp;
        bit          CutSnoopReq;
        bit          CutSnoopResp;
    } ace_ccu_user_cfg_t;

    typedef struct packed {
        // User parameters
        ace_ccu_user_cfg_t u;
        // Derived parameters
        int unsigned       SlvPortIdxWidth;
        int unsigned       TransactionIdxWidth;
        int unsigned       CachelineBytes;
        int unsigned       CachelineBytesIdxWidth;
        int unsigned       CachelineAddrWidth;
        int unsigned       CachelineAxiTransfers;
        int unsigned       CachelineAxiTransfersIdxWidth;
        int unsigned       AxiMidendIdWidth;
        int unsigned       AxiBackendIdWidth;
        int unsigned       AxiDataBytes;
        int unsigned       AxiDataBytesIdxWidth;
        int unsigned       AxiStrbWidth;
        int unsigned       AxiMstIdWidth;
        int unsigned       ArIdCounters;
    } ace_ccu_cfg_t;

    function automatic ace_ccu_cfg_t ace_ccu_build_cfg(ace_ccu_user_cfg_t u);
        ace_ccu_cfg_t p;

        p.u                             = u;

        p.SlvPortIdxWidth               = $clog2(u.SlvPorts);
        p.TransactionIdxWidth           = $clog2(u.MaxTransactions);
        p.CachelineBytes                = u.CachelineWidth / 8;
        p.CachelineBytesIdxWidth        = $clog2(p.CachelineBytes);
        p.CachelineAddrWidth            = u.AxiAddrWidth - p.CachelineBytesIdxWidth;
        p.CachelineAxiTransfers         = u.CachelineWidth / u.AxiDataWidth;
        p.CachelineAxiTransfersIdxWidth = $clog2(p.CachelineAxiTransfers);
        p.AxiDataBytes                  = u.AxiDataWidth / 8;
        p.AxiDataBytesIdxWidth          = $clog2(p.AxiDataBytes);
        p.AxiStrbWidth                  = u.AxiDataWidth / 8;
        p.AxiMidendIdWidth              = u.AxiSlvIdWidth + p.SlvPortIdxWidth;
        p.AxiBackendIdWidth             = p.AxiMidendIdWidth + 1;
        p.AxiMstIdWidth                 = p.AxiBackendIdWidth + 1;

        return p;
    endfunction

    // Typedefs

    // CD ctrl structure
    typedef struct packed {
        logic read;
        logic write;
        logic drop;
    } cd_sel_t;

endpackage
