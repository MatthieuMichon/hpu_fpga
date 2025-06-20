# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Contains procedure to generate block designs that handle
# the base logic in the PL
# ==============================================================================================

################################################################
# create_hier_cell_base_logic
################################################################
# Hierarchical cell: base_logic
proc create_hier_cell_base_logic { parentCell nameHier } {
  set parentObj [check_parent_hier $parentCell $nameHier]
  if { $parentObj == "" } { return }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_pcie_mgmt_slr0

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_rpu

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_pcie_mgmt_pdi_reset

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M01_AXI_0

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M02_AXI

  # Create pins
  create_bd_pin -dir I -type clk clk_pl
  create_bd_pin -dir I -type clk hpu_clk
  create_bd_pin -dir I -type rst resetn_pl_periph
  create_bd_pin -dir I -type rst resetn_pl_ic
  create_bd_pin -dir O -type intr irq_gcq_m2r

  # Create instance: pcie_slr0_mgmt_sc, and set properties
  set pcie_slr0_mgmt_sc [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 pcie_slr0_mgmt_sc ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI {3} \
    CONFIG.NUM_SI {1} \
  ] $pcie_slr0_mgmt_sc

  # Create instance: rpu_sc, and set properties
  # S00_AXI:M00_AXI:M01_AXI are on aclk
  # M02_AXI is on aclk1
  set rpu_sc [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 rpu_sc ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_MI {3} \
    CONFIG.NUM_SI {1} \
  ] $rpu_sc

  # Create instance: uuid_rom, and set properties
  set uuid_rom [ create_bd_cell -type ip -vlnv xilinx.com:ip:shell_utils_uuid_rom:2.0 uuid_rom ]
  set_property CONFIG.C_INITIAL_UUID {00000000000000000000000000000000} $uuid_rom

  # Create instance: gcq_m2r, and set properties
  set gcq_m2r [ create_bd_cell -type ip -vlnv xilinx.com:ip:cmd_queue:2.0 gcq_m2r ]

  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins rpu_sc/M01_AXI] [get_bd_intf_pins M01_AXI_0]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins rpu_sc/M02_AXI] [get_bd_intf_pins M02_AXI]
  connect_bd_intf_net -intf_net pcie_slr0_mgmt_sc_M00_AXI [get_bd_intf_pins pcie_slr0_mgmt_sc/M00_AXI] [get_bd_intf_pins uuid_rom/S_AXI]
  connect_bd_intf_net -intf_net pcie_slr0_mgmt_sc_M01_AXI [get_bd_intf_pins pcie_slr0_mgmt_sc/M01_AXI] [get_bd_intf_pins gcq_m2r/S00_AXI]
  connect_bd_intf_net -intf_net pcie_slr0_mgmt_sc_M02_AXI [get_bd_intf_pins pcie_slr0_mgmt_sc/M02_AXI] [get_bd_intf_pins m_axi_pcie_mgmt_pdi_reset]
  connect_bd_intf_net -intf_net rpu_sc_M00_AXI [get_bd_intf_pins rpu_sc/M00_AXI] [get_bd_intf_pins gcq_m2r/S01_AXI]
  connect_bd_intf_net -intf_net s_axi_pcie_mgmt_slr0_1 [get_bd_intf_pins s_axi_pcie_mgmt_slr0] [get_bd_intf_pins pcie_slr0_mgmt_sc/S00_AXI]
  connect_bd_intf_net -intf_net s_axi_rpu_1 [get_bd_intf_pins s_axi_rpu] [get_bd_intf_pins rpu_sc/S00_AXI]

  # Create port connections
  connect_bd_net -net clk_pl_1 [get_bd_pins clk_pl] [get_bd_pins pcie_slr0_mgmt_sc/aclk] [get_bd_pins rpu_sc/aclk] [get_bd_pins uuid_rom/S_AXI_ACLK] [get_bd_pins gcq_m2r/aclk]
  connect_bd_net -net hpu_clk [get_bd_pins hpu_clk] [get_bd_pins rpu_sc/aclk1]
  connect_bd_net -net gcq_m2r_irq_sq [get_bd_pins gcq_m2r/irq_sq] [get_bd_pins irq_gcq_m2r]
  connect_bd_net -net resetn_pl_ic_1 [get_bd_pins resetn_pl_ic] [get_bd_pins pcie_slr0_mgmt_sc/aresetn] [get_bd_pins rpu_sc/aresetn]
  connect_bd_net -net resetn_pl_periph_1 [get_bd_pins resetn_pl_periph] [get_bd_pins uuid_rom/S_AXI_ARESETN] [get_bd_pins gcq_m2r/aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}
