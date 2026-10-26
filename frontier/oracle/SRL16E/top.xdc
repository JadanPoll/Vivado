set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 10.000 -name sys_clk [get_ports clk]

set_property PACKAGE_PIN D10 [get_ports d]
set_property IOSTANDARD LVCMOS33 [get_ports d]
