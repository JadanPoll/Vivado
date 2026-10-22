# RealDigital Urbana XC7S50. Pin map from PRODUCTION_GRADE/serv.xdc.
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {clk}]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {LED}]
create_clock -period 10.000 -name sys_clk [get_ports {clk}]
