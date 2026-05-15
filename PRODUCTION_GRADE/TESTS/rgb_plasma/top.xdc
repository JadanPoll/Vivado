# URBANA BOARD — RGB Breathing Plasma
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports out]

set_property -dict {PACKAGE_PIN C9  IOSTANDARD LVCMOS33} [get_ports {RGB0[0]}]
set_property -dict {PACKAGE_PIN A9  IOSTANDARD LVCMOS33} [get_ports {RGB0[1]}]
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS33} [get_ports {RGB0[2]}]
set_property -dict {PACKAGE_PIN A11 IOSTANDARD LVCMOS33} [get_ports {RGB1[0]}]
set_property -dict {PACKAGE_PIN C10 IOSTANDARD LVCMOS33} [get_ports {RGB1[1]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports {RGB1[2]}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]