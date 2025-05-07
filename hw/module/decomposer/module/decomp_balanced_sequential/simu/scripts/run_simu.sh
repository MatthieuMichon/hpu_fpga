#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity

run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

module="tb_decomp_balanced_sequential"

###################################################################################################
# Usage
###################################################################################################
function usage () {
echo "Usage : run_simu.sh runs all the simulations for ${module}."
echo "./run_simu.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-- <run_edalize options> : run_edalize options."
}


###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize your own variables here:
while getopts "h" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
  esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift
args=$@


###################################################################################################
# Run simulation
###################################################################################################
# Write simulation command lines here
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
mkdir -p ${PROJECT_DIR}/hw/output
SEED_FILE="${PROJECT_DIR}/hw/output/${module}.seed"
CMD_FILE="${PROJECT_DIR}/hw/output/${module}.cmd.log"
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._tmp"
echo -n "" > $SEED_FILE
echo -n "" > $TMP_FILE
echo -n "" > $CMD_FILE

R=2

for i in {1..5}; do

    PSI=$((1+$RANDOM % 3))
    S=$(($PSI+1+$RANDOM % 6))

    PSI=$((2**$PSI))

    GLWE_K=$((1+$RANDOM % 3))
    PBS_L=$((1+$RANDOM % 3))
    PBS_B_W=$((1+$RANDOM % 10))

    MOD_Q_W=$(($PBS_L*$PBS_B_W + 1 +$RANDOM % 10))
    CHUNK_NB=$((1+$RANDOM % $PBS_L))


    cmd="${SCRIPT_DIR}/run.sh \
        -C \
        -S $S \
        -R $R \
        -P $PSI \
        -g $GLWE_K \
        -l $PBS_L \
        -b $PBS_B_W \
        -W $MOD_Q_W \
        -- \
        -P CHUNK_NB int $CHUNK_NB \
        $args"
    echo "==========================================================="
    echo "INFO> Running : $cmd"
    echo "==========================================================="
    echo $cmd >> $CMD_FILE
    $cmd | tee >(grep "Seed" | head -1 >> $SEED_FILE) |  grep -c "> SUCCEED !" > $TMP_FILE
    exit_status=$?
    succeed_cnt=$(cat $TMP_FILE)
    rm -f $TMP_FILE
    if [ $exit_status -gt 0 ] || [ $succeed_cnt -ne 1 ] ; then
      echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
      exit $exit_status
    else
      echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
    fi
done
