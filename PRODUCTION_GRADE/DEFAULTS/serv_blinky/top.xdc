# RealDigital Urbana XC7S50 pin assignments for SERV executable blinky.
# clk: 100 MHz oscillator; BTN[0] requests CPU reset, LED[0] is CPU GPIO output.
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {clk}]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports {BTN}]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {LED}]
create_clock -period 10.000 -name sys_clk [get_ports {clk}]
