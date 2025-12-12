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
        //  Number of subordinate ports (i.e. coherent managers)
        int unsigned numSubordinates;
        //  Number of shareable simultaneous inflight transactions
        int unsigned numShareableTransactions;
        //  Number of simultaneous write transactions
        int unsigned numWriteTransactions;
        //  Number of simultaneous inflight snoop transactions
        int unsigned numSnoopTransactions;
        //  AXI/ACE parameters
        int unsigned axiAddressWidth;
        int unsigned axiDataWidth;
        int unsigned axiUserWidth;
        int unsigned axiSubordinateIdWidth;
        //  Cache parameters
        int unsigned cachelineWidth;
        //  LSB address bit used for hazard checks (inclusive)
        int unsigned addressCheckLsb;
        //  MSB address bit used for hazard checks (inclusive)
        int unsigned addressCheckMsb;
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
        //  AXI data size
        int unsigned axiDataSize;
        //  Address slice width used for hazard checks
        int unsigned addressCheckWidth;
    } ccu_config_t;

    function automatic ccu_config_t ccu_build_cfg(ccu_user_config_t u);
        ccu_config_t p;

        p.u                          = u;

        p.subordinateIndexWidth      = $clog2(u.numSubordinates);
        p.axiCcuIdWidth              = u.axiSubordinateIdWidth + p.subordinateIndexWidth;
        p.axiManagerIdWidth          = p.axiCcuIdWidth + 1;
        p.cachelineByteIndexWidth    = u.cachelineWidth > 8 ? $clog2(u.cachelineWidth / 8) : 1;
        p.numLineWidth               = u.axiAddressWidth - p.cachelineByteIndexWidth;
        p.writeTransactionIndexWidth = u.numWriteTransactions > 1 ? $clog2(u.numWriteTransactions) : 1;
        p.cachelineAxiTransfers      = u.cachelineWidth / u.axiDataWidth;
        p.transactionIndexWidth      = u.numShareableTransactions > 1 ? $clog2(u.numShareableTransactions) : 1;
        p.axiDataSize                = u.axiDataWidth > 8 ? $clog2(u.axiDataWidth / 8) : 1;
        p.addressCheckWidth          = u.addressCheckMsb - u.addressCheckLsb + 1;

        return p;
    endfunction

endpackage
