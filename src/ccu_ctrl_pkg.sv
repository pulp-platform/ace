// Copyright (c) 2024 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

package ccu_ctrl_pkg;

    typedef enum logic [3:0] {
        SEND_AXI_REQ_R,
        SEND_AXI_REQ_WRITE_BACK_R,
        SEND_AXI_REQ_W,
        SEND_AXI_REQ_WRITE_BACK_W,
        AMO_WAIT_READ,
        AMO_WAIT_WB_R,
        AMO_WAIT_WB_W
    } mu_op_e;

    typedef enum logic {
        READ_SNP_DATA,
        SEND_INVALID_ACK_R
    } su_op_e;

    typedef enum logic { MEMORY_UNIT, SNOOP_UNIT } cd_user_t;

endpackage