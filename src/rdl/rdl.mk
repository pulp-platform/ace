# Copyright (c) 2026 ETH Zurich, University of Bologna
#
# Copyright and related rights are licensed under the Solderpad Hardware
# License, Version 0.51 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
# or agreed to in writing, software, hardware and materials distributed under
# this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.

.PHONY: regs

# CCU control and status registers
# {{{
CCU_CSR_RDL    := $(RDL_DIR)/ccu/ccu_csr.rdl
CCU_CSR_DIR    := $(RTL_DIR)/ccu/generated
CCU_CSR_SV     := $(CCU_CSR_DIR)/ccu_csr.sv
CCU_CSR_PKG_SV := $(CCU_CSR_DIR)/ccu_csr_pkg.sv

regs: $(CCU_CSR_SV) $(CCU_CSR_PKG_SV)

$(CCU_CSR_SV): $(CCU_CSR_RDL)
	$(PEAKRDL) regblock $< \
	  -o $(CCU_CSR_DIR) \
	  --cpuif apb4-flat \
	  --default-reset arst_n

#  One peakrdl run emits both files
$(CCU_CSR_PKG_SV): $(CCU_CSR_SV) ;
# }}}
