#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"

###################################################################################################
# This script deals with the testbench run.
# This testbench has specificities that cannot be handled by run_edealize alone.
# They are handled here.
###################################################################################################

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/script/edalize/run_edalize.py

module="tb_ksk_manager"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-g                       : GLWE_K (default 2)"
echo "-R                       : R: Radix (default 2)"
echo "-S                       : S: Number of stages (default 8)"
echo "-r                       : MOD_KSK: modulo (default : 2**32)"
echo "-V                       : MOD_KSK_W: modulo width (default 32)"
echo "-c                       : BATCH_PBS_NB (default : 4)"
echo "-K                       : LWE_K (default : 24)"
echo "-L                       : KS_L (default 2)"
echo "-B                       : KS_B_W (default 16)"
echo "-E                       : KSK_SLOT_NB (default 8)"
echo "-U                       : KSK_CUT_NB (default 1)"
echo "-X                       : LBX: Number of coefficients columns processed in parallel (default 2)"
echo "-Y                       : LBY: Number of coefficients lines processed in parallel (default 24)"
echo "-Z                       : LBZ: Number of coefficients lines processed in parallel (default 2)"
echo "-- <run_edalize options> : run_edalize options."

}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
GEN_STIMULI=1
GLWE_K=2
PBS_L=2
R=2
S=8
MOD_KSK="2**32"
MOD_KSK_W=32
BATCH_PBS_NB=4
LWE_K=24
LBX=2
LBY=24
LBZ=2
KS_L=1
KS_B_W=31
KSK_SLOT_NB=8
KSK_CUT_NB=1
# Initialize your own variables here:
while getopts "hg:R:S:r:V:c:K:X:Y:Z:B:L:E:U:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    g)
      GLWE_K=$OPTARG
      ;;
    R)
      R=$OPTARG
      ;;
    S)
      S=$OPTARG
      ;;
    r)
      MOD_KSK=$OPTARG
      ;;
    V)
      MOD_KSK_W=$OPTARG
      ;;
    c)
      BATCH_PBS_NB=$OPTARG
      ;;
    K)
      LWE_K=$OPTARG
      ;;
    X)
      LBX=$OPTARG
      ;;
    Y)
      LBY=$OPTARG
      ;;
    Z)
      LBZ=$OPTARG
      ;;
    B)
      KS_B_W=$OPTARG
      ;;
    L)
      KS_L=$OPTARG
      ;;
    E)
      KSK_SLOT_NB=$OPTARG
      ;;
    U)
      KSK_CUT_NB=$OPTARG
      ;;
    :)
      echo "$0: Must supply an argument to -$OPTARG." >&2
      exit 1
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

# run_edalize additional arguments
[ "${1:-}" = "--" ] && shift
args=$@

N=$((${R}**${S}))


###################################################################################################
# Generate package
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR

# Create package
if [ $GEN_STIMULI -eq 1 ] ; then
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_tfhe_definition_pkg.py -f \
                  -N $N -g $GLWE_K -K $LWE_K -r $MOD_KSK -V $MOD_KSK_W -L $KS_L -B $KS_B_W \
                  -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> N=${N}, GLWE_K=${GLWE_K} MOD_KSK=${MOD_KSK} MOD_KSK_W=${MOD_KSK_W} LWE_K=${LWE_K} KS_L=${KS_L} KS_B_W=${KS_B_W}"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pe_pbs/module/pep_common/scripts/gen_pep_batch_definition_pkg.py\
          -f -c $BATCH_PBS_NB -o ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> BATCH_PBS_NB=$BATCH_PBS_NB"
  echo "INFO> pep_batch_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pep_key_switch/module/pep_ks_common/scripts/gen_pep_ks_common_definition_pkg.py\
          -f -lbx $LBX -lby $LBY -lbz $LBZ -o ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
  echo "INFO> LBX=$LBX LBY=$LBY LBZ=$LBZ"
  echo "INFO> pep_ks_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/ksk/module/ksk_manager/module/ksk_mgr_common/scripts/gen_ksk_mgr_common_cut_definition_pkg.py\
          -f -ksk_cut $KSK_CUT_NB -o ${RTL_DIR}/ksk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> KSK_CUT_NB=$KSK_CUT_NB"
  echo "INFO> ksk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/ksk/module/ksk_manager/module/ksk_mgr_common/scripts/gen_ksk_mgr_common_slot_definition_pkg.py\
          -f -ksk_slot $KSK_SLOT_NB -o ${RTL_DIR}/ksk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> KSK_SLOT_NB=$KSK_SLOT_NB"
  echo "INFO> ksk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/script/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R pep_batch_definition_pkg.sv simu 0 1 \
                -R pep_ks_common_definition_pkg.sv simu 0 1 \
                -R ksk_mgr_common_cut_definition_pkg.sv simu 0 1 \
                -R ksk_mgr_common_slot_definition_pkg.sv simu 0 1 \
                -F pep_ks_common_definition_pkg.sv KSLB KSLB_x${LBX}y${LBY}z${LBZ} \
                -F ksk_mgr_common_cut_definition_pkg.sv KSK_CUT KSK_CUT_${KSK_CUT_NB} \
                -F ksk_mgr_common_slot_definition_pkg.sv KSK_SLOT KSK_SLOT_${KSK_SLOT_NB} \
                -F pep_batch_definition_pkg.sv PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB} \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu"
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ksk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ksk_mgr_common_slot_definition_pkg.sv"
fi

###################################################################################################
# Process
###################################################################################################
mkdir -p ${PROJECT_DIR}/hw/output
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

#################################################
# Config phase : create directory + scripts
#################################################

eda_args="$eda_args -F PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB} \
                    -F APPLICATION APPLI_simu \
                    -F KSLB KSLB_x${LBX}y${LBY}z${LBZ} \
                    -F KSK_CUT KSK_CUT_${KSK_CUT_NB} \
                    -F KSK_SLOT KSK_SLOT_${KSK_SLOT_NB}"

# Get current working directory
cmd="$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
    $eda_args \
    $args"
echo "Info> Running : $cmd"
$cmd | tee >(grep "Work directory :" >> $TMP_FILE)
sync
>&2 echo "INFO> Reading from $TMP_FILE: $(ls -l $TMP_FILE)"
work_dir=$(cat $TMP_FILE | sed 's/Work directory : *//')
>&2 echo "INFO> Extracted work_dir : ${work_dir}"

# Delete TMP_FILE
rm -f $TMP_FILE

# log command line
echo $cli > ${work_dir}/cli.log

#################################################
# Run phase : simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

