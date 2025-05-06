#!/usr/bin/tclsh
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# Constants
# They are all bash variables defined either in setup or in justfile:
# We need to access some of them through child tcl scripts that doesn't
# accept arguments in vivado's project mode

set PROJECT_DIR     $::env(PROJECT_DIR)
set XIL_PART        $::env(XILINX_PART)
set SHELL_VER       $::env(SHELL_VER)
set VIVADO_PRJ_DIR  $PROJECT_DIR/versal/output

# Let's define a maximal number of threads such as it's half of the number of cores
# this value must be between [1:32], therefore on main server we need an hardcoded value
# set MAX_THREADS [expr {[exec nproc] / 2}]
set MAX_THREADS 10

# Initial project setup ---------------------------------------------------------------------------
# Create the project if only we are in standalone shell project:
# if we are not, this means that this scipt is called from a parent project.
if {![info exists SKIP_PRJ_SHELL] || !$SKIP_PRJ_SHELL} {
    puts "Creating project $SHELL_VER at ${VIVADO_PRJ_DIR}/$SHELL_VER"
    create_project prj "${VIVADO_PRJ_DIR}/$SHELL_VER" -part $XIL_PART -force
}

set_property ip_repo_paths "${PROJECT_DIR}/versal/iprepo" [current_project]
update_ip_catalog

# Set parameters
set_param general.maxThreads $MAX_THREADS

# Block design ------------------------------------------------------------------------------------
create_bd_design  ${SHELL_VER}
current_bd_design ${SHELL_VER}

source "${PROJECT_DIR}/versal/scripts/bd/bd_${SHELL_VER}.tcl"

assign_bd_address

validate_bd_design

save_bd_design

# Write the block diagram wrapper and set it as design top
add_files -norecurse [make_wrapper -files [get_files "${SHELL_VER}.bd"] -top]

# Output ------------------------------------------------------------------------------------------
# Generate all output products
generate_target all [get_files "${SHELL_VER}.bd"]

set_property top ${SHELL_VER}_wrapper [current_fileset]
update_compile_order -fileset sources_1
