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

ROOT     := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RDL_DIR  := $(ROOT)/src/rdl
RTL_DIR  := $(ROOT)/src/rtl
LINT_DIR := $(ROOT)/lint

BENDER ?= bender
UV     ?= uv

PEAKRDL        ?= $(UV) run --frozen peakrdl
VERIBLE_LINT   ?= $(UV) run --frozen verible-cli verible-verilog-lint

.PHONY: help

help:
	@echo ""
	@echo "regs:    regenerate the CCU register file from its SystemRDL source"
	@echo "lint:    check the RTL against the Verible style rules"
	@echo ""

include $(RDL_DIR)/rdl.mk
include $(LINT_DIR)/lint.mk
