# Copyright and related rights are licensed under the Solderpad Hardware
# License, Version 0.51 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
# or agreed to in writing, software, hardware and materials distributed under
# this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# Authors:
# - Thomas Benz <tbenz@iis.ee.ethz.ch>

# select IIS-internal tool commands if we run on IIS machines
ifneq (,$(wildcard /etc/iis.version))
	VSIM        ?= questa-2022.3 vsim
	SYNOPSYS_DC ?= synopsys-2022.03 dcnxt_shell
else
	VSIM        ?= vsim
	SYNOPSYS_DC ?= dc_shell
endif

TBS         ?= ace_ccu_top \
               ace_ccu_top_sanity

SIM_TARGETS := $(addsuffix .log,$(addprefix sim-,$(TBS)))

####### Simulation parameters #######
# Address width
ADDR_WIDTH 			?= 32
# AXI/ACE data width
DATA_WIDTH 			?= 64
# Cache line word width
WORD_WIDTH 			?= 64
# Number of words in a cache line
CACHELINE_WORDS ?= 4
# Number of ways in the cache model
WAYS 						?= 2
# Number of sets in the cache model
SETS 						?= 16
# Number of cached masters
NMASTERS 				?= 4
# Number of master groups
NGROUPS 				?= 2
# Number of transactions to be generated per master
NTRANSACTIONS 	?= 100
# Location of the generated files
MEM_DIR 				?= $(PWD)/build/mem
# Seed for initial state generation. If empty, no seed
SEED						?= 10
# Run coherency check after simulation
CHECK 					?= 0
# Debug mode for coherency checking
DEBUG 					?= 1

export ADDR_WIDTH
export DATA_WIDTH
export WORD_WIDTH
export CACHELINE_WORDS
export WAYS
export SETS
export NMASTERS
export NGROUPS
export NTRANSACTIONS
export MEM_DIR

.SHELL: bash

.PHONY: help all sim_all clean


help:
	@echo ""
	@echo "elab.log:     elaborates all files using Synopsys DC"
	@echo "compile.log:  compile files using Questasim"
	@echo "sim-#TB#.log: simulates a given testbench, available TBs are:"
	@echo "$(addprefix ###############-#,$(TBS))" | sed -e 's/ /\n/g' | sed -e 's/#/ /g'
	@echo "sim_all:      simulates all available testbenches"
	@echo ""
	@echo "clean:        cleans generated files"
	@echo ""


all: compile.log elab.log sim_all


sim_all: $(SIM_TARGETS)


build:
	mkdir -p $@

build/mem: build
	mkdir -p $@

init_mem: build/mem
	python3 test/vip/python/cache_coherency_test.py \
	--addr_width ${ADDR_WIDTH} \
	--data_width ${DATA_WIDTH} \
	--word_width ${WORD_WIDTH} \
	--cacheline_words ${CACHELINE_WORDS} \
	--ways ${WAYS} \
	--sets ${SETS} \
	--n_caches ${NMASTERS} \
	--n_transactions ${NTRANSACTIONS} \
	--target_dir $(MEM_DIR) \
	--seed $(SEED) \
	$(if $(filter 1, $(CHECK)),--check) \
	$(if $(filter 1, $(DEBUG)),--debug)


elab.log: Bender.yml | build
	export SYNOPSYS_DC="$(SYNOPSYS_DC)"; cd build && ../scripts/synth.sh | tee ../$@
	(! grep -n "Error:" $@)


compile.log: Bender.yml | build
	export VSIM="$(VSIM)"; cd build && ../scripts/compile_vsim.sh | tee ../$@
	(! grep -n "Error:" $@)


sim-%.log: compile.log
	export VSIM="$(VSIM)"; cd build && ../scripts/run_vsim.sh --random-seed $* | tee ../$@
	(! grep -n "Error:" $@)
	(! grep -n "Fatal:" $@)


clean:
	rm -rf build
	rm -f  *.log
