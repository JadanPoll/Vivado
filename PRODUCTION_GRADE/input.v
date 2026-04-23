module zero_soc(
  input clk, rst_n, timer_irq,
  output [31:0] ibus_adr, output ibus_cyc, input [31:0] ibus_rdt, input ibus_ack,
  output [31:0] dbus_adr, output [31:0] dbus_dat, output [3:0] dbus_sel,
  output dbus_we, output dbus_cyc, input [31:0] dbus_rdt, input dbus_ack);
  serv_rf_top cpu(
    .clk(clk),.i_rst(~rst_n),.i_timer_irq(timer_irq),
    .o_ibus_adr(ibus_adr),.o_ibus_cyc(ibus_cyc),.i_ibus_rdt(ibus_rdt),.i_ibus_ack(ibus_ack),
    .o_dbus_adr(dbus_adr),.o_dbus_dat(dbus_dat),.o_dbus_sel(dbus_sel),
    .o_dbus_we(dbus_we),.o_dbus_cyc(dbus_cyc),.i_dbus_rdt(dbus_rdt),.i_dbus_ack(dbus_ack));
endmodule