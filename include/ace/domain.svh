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


`ifndef ACE_DOMAIN_SVH_
`define ACE_DOMAIN_SVH_

  //////////////////
  // Domain types //
  //////////////////

`define DOMAIN_BV_T(__width) \
    logic [__width-1:0]

`define DOMAIN_RULE_T(__bv_t) \
    struct packed { \
        __bv_t initiator; \
        __bv_t inner;     \
        __bv_t outer;     \
    }

`define DOMAIN_TYPEDEF_BV_T(__width, __bv_t) \
    typedef logic [__width-1:0] __bv_t;

`define DOMAIN_TYPEDEF_RULE_T(__bv_t, __set_t) \
    typedef struct packed { \
        __bv_t initiator; \
        __bv_t inner;     \
        __bv_t outer;     \
    } __set_t;

`define DOMAIN_TYPEDEF_ALL(__width, __bv_t, __set_t) \
    `DOMAIN_TYPEDEF_BV_T(__width, __bv_t) \
    `DOMAIN_TYPEDEF_RULE_T(__bv_t, __set_t)

`endif // ACE_DOMAIN_SVH_
