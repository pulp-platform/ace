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

`define ACE_DECLARE_DOMAIN_MAP_T(__num_subordinates) \
    struct packed { \
        logic [__num_subordinates-1:0] initiator; \
        logic [__num_subordinates-1:0] inner;     \
        logic [__num_subordinates-1:0] outer;     \
    }

`define ACE_TYPEDEF_DOMAIN_TYPEDEF_MAP_T(__num_subordinates, __map_t) \
    typedef `ACE_DECLARE_DOMAIN_MAP_T(__num_subordinates) __map_t;

`endif // ACE_DOMAIN_SVH_
