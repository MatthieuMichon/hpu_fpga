# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing constraints for an out-of-context (OOC) synthesis
# ----------------------------------------------------------------------------------------------
#
# This file contains:
#    - the clock definition
#    - constraints on input and output ports
# ----------------------------------------------------------------------------------------------
# Create clock
# ==============================================================================================

set CLK_PERIOD 2.500
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

# In Vivado 2024.2 (or v80, not sure), input and output delays no longer inherit the clock's
# insertion delay in the path calculation. So, build a generated clock from a cell's clock pin to
# inherite the propagation delay and set all io constraints relatively to this new clock.
set i_insertion_pin {pep_ks_mult/gen_node_x_loop[2].gen_node_y_loop[18].gen_not_last_y.pep_ks_mult_node/s0_fifo_element/loop_gen[0].type1_gen.fifo_element/no_reset_data_gen.data_reg[22]/C}
create_generated_clock -name i_clk -source [get_port clk] -combinational [get_pin $i_insertion_pin]

set o_insertion_pin {pep_ks_mult/gen_node_x_loop[2].gen_node_y_loop[30].gen_not_last_y.pep_ks_mult_node/s0_fifo_element/loop_gen[0].type1_gen.fifo_element/no_reset_data_gen.data_reg[36]/C}
create_generated_clock -name o_clk -source [get_port clk] -combinational [get_pin $o_insertion_pin]

# Set delay on input and output ports. These are extremely small to eat in some of the bogus clock
# tree insertion delay that is created in out of context synthesis.
set_input_delay [expr [get_property PERIOD [get_clocks CLK]] * 1 / 3] -clock i_clk -max [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_input_delay [expr [get_property PERIOD [get_clocks CLK]] * 1 / 6] -clock i_clk -min [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] * 1 / 3] -clock o_clk -max [all_outputs]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] * 1 / 6] -clock o_clk -min [all_outputs]
