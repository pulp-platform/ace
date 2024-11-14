#!/bin/bash
# Copyright (c) 2014-2018 ETH Zurich, University of Bologna
#
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
# - Andreas Kurth <akurth@iis.ee.ethz.ch>
# - Fabian Schuiki <fschuiki@iis.ee.ethz.ch>

set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if test -z ${VSIM+x}; then
    VSIM=vsim
fi

# Seed values for `sv_seed`; can be extended with specific values on a per-TB basis, as well as with
# a random number by passing the `--random` flag.  The default value, 0, is always included to stay
# regression-consistent.
SEEDS=(0)

# $VSIM -do ${ROOT}/scripts/dofile.do -sv_seed $seed "$@" | tee vsim.log 2>&1
# echo "run -all" | $VSIM -sv_seed $seed "$@" | tee vsim.log 2>&1
call_vsim() {
    for seed in ${SEEDS[@]}; do
        #echo "run -all" | $VSIM -sv_seed $seed "$@" | tee vsim.log 2>&1
        if [ -f ${ROOT}/scripts/$1.do ]; then
            $VSIM -do ${ROOT}/scripts/$1.do -sv_seed $seed "$@" | tee vsim.log 2>&1
        else
            $VSIM -sv_seed $seed "$@" | tee vsim.log 2>&1
        fi
        grep "Errors: 0," vsim.log
    done
}

exec_test() {
    if [ ! -e "$ROOT/test/tb_$1.sv" ]; then
        echo "Testbench for '$1' not found!"
        exit 1
    fi
    case "$1" in
        ace_ccu_top)
            call_vsim tb_ace_ccu_top -t 1ns -classdebug -coverage -voptargs="+acc" \
            -gAddrWidth=$ADDR_WIDTH \
            -gDataWidth=$DATA_WIDTH \
            -gWordWidth=$WORD_WIDTH \
            -gCachelineWords=$CACHELINE_WORDS \
            -gWays=$WAYS \
            -gSets=$SETS \
            -gTbNumMst=$NMASTERS \
            -gNoMstGroups=$NGROUPS \
            -gMemDir=$MEM_DIR
            ;;
        ccu_ctrl_r_snoop)
            call_vsim tb_ccu_ctrl_r_snoop -t 1ns -coverage -voptargs="+acc" \
            -gAddrWidth=$ADDR_WIDTH \
            -gDataWidth=$DATA_WIDTH \
            -gWordWidth=$WORD_WIDTH \
            -gCachelineWords=$CACHELINE_WORDS \
            -gWays=$WAYS \
            -gSets=$SETS \
            -gTbNumMst=$NMASTERS \
            -gMemDir=$MEM_DIR
            ;;
        *)
            call_vsim tb_$1 -t 1ns -coverage -voptargs="+acc"
            ;;
    esac
}

# Parse flags.
PARAMS=""
while (( "$#" )); do
    case "$1" in
        --random-seed)
            SEEDS+=(random)
            shift;;
        -*--*) # unsupported flag
            echo "Error: Unsupported flag '$1'." >&2
            exit 1;;
        *) # preserve positional arguments
            PARAMS="$PARAMS $1"
            shift;;
    esac
done
eval set -- "$PARAMS"

if [ "$#" -eq 0 ]; then
    tests=()
    while IFS=  read -r -d $'\0'; do
        tb_name="$(basename -s .sv $REPLY)"
        dut_name="${tb_name#tb_}"
        tests+=("$dut_name")
    done < <(find "$ROOT/test" -name 'tb_*.sv' -a \( ! -name '*_pkg.sv' \) -print0)
else
    tests=("$@")
fi

for t in "${tests[@]}"; do
    exec_test $t
done
