# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

set cdir [pwd]
puts "current directory: $cdir"
source ${cdir}/../../uservars.tcl
puts "current PSI is: $::ntt_psi"

# Rename the clock gated clock to something sensible
create_generated_clock -name prc_clk [get_pins -of_objects [get_clocks clkout1_primitive]]

# PBLOCK
create_pblock pblock_pl
resize_pblock pblock_pl -add SLR0
resize_pblock pblock_pl -add SLR1
resize_pblock pblock_pl -add SLR2

create_pblock pblock_SLR0
resize_pblock pblock_SLR0 -add SLR0
create_pblock pblock_SLR1
resize_pblock pblock_SLR1 -add SLR1
create_pblock pblock_SLR2
resize_pblock pblock_SLR2 -add SLR2

create_pblock pblock_SLL2BOT
create_pblock pblock_SLL1TOP
create_pblock pblock_SLL1BOT
create_pblock pblock_SLL0TOP
create_pblock pblock_CLKROOT

# The SLRs are stacked, so the SLLs are all over the SLR
#resize_pblock pblock_SLL2BOT -add CLOCKREGION_X0Y8:CLOCKREGION_X9Y8
#resize_pblock pblock_SLL1TOP -add CLOCKREGION_X0Y7:CLOCKREGION_X9Y7
#resize_pblock pblock_SLL1BOT -add CLOCKREGION_X0Y5:CLOCKREGION_X9Y5
#resize_pblock pblock_SLL0TOP -add CLOCKREGION_X0Y4:CLOCKREGION_X9Y4
#resize_pblock pblock_CLKROOT -add CLOCKREGION_X6Y0

resize_pblock pblock_SLL2BOT -add SLR2
resize_pblock pblock_SLL1TOP -add SLR1
resize_pblock pblock_SLL1BOT -add SLR1
resize_pblock pblock_SLL0TOP -add SLR0
resize_pblock pblock_CLKROOT -add CLOCKREGION_X6Y0

# parent
set_property PARENT pblock_SLR1 [get_pblocks {pblock_SLL1TOP pblock_SLL1BOT}]
set_property PARENT pblock_SLR0 [get_pblocks {pblock_SLL0TOP pblock_CLKROOT}]
set_property PARENT pblock_pl [get_pblocks pblock_SLR0] [get_pblocks pblock_SLR1] [get_pblocks pblock_SLR2]

set_property IS_SOFT FALSE [get_pblocks pblock_SLR*]
set_property IS_SOFT FALSE [get_pblocks pblock_SLL*]

#Set false path
set_false_path -from [get_pins -hierarchical -regexp {.*hpu_regif_cfg_.in3/.*reg.*/C}] -to [get_clocks  -regexp {.*prc_clk.*}]

# Constrain the reset path, with loose constraints
set rst_setup_hold_margin 3
set ce_delay_margin       4

# Set a multicycle path on the main reset
set rst_pin [get_pins -hier -regexp {hpu_3parts/prc._clk_rst/rst_ff.*/C}]
set_multicycle_path $rst_setup_hold_margin -setup -from $rst_pin
set_multicycle_path [expr 2*$rst_setup_hold_margin-1] -hold -from $rst_pin

# We need also a max delay on the clock gate input pin. Cannot be a multicycle path this time
# because the path is not timed. The design is made to absorve a controllable amount of latency on
# that path, but we still need a constraint.
set clk_period [get_propert PERIOD [get_clocks prc_clk]]
set_max_delay [expr $clk_period*$ce_delay_margin] -from [get_pins hpu_3parts/prc3_clk_rst/clk_en_reg/C] \
                                                  -to   [get_pins -hier -regexp -filter \
                                                        {NAME =~ .*/clock_primitive_inst/BUFGCE.*/CE}]
