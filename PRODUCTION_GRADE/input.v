module zero_soc (
    input clk,          // Wired to Urbana 100MHz pin
    input rst_n,        // Wired to Urbana Reset Button
    output [7:0] hex_seg, // Wired to Hex Segments
    output [7:0] hex_grid // Wired to Hex Digit Select
);
    // 1. The Internal Memory (ROM)
    // Pre-loaded with a tiny RISC-V program that cycles numbers on the HEX
    logic [31:0] ram [0:63]; 
    initial begin
        // Tiny program: li a0, 0; loop: addi a0, a0, 1; sw a0, 0x100(x0); j loop
        ram[0] = 32'h00000513; 
        ram[1] = 32'h00150513;
        ram[2] = 32'h10A02023; 
        ram[3] = 32'hff9ff06f;
    end

    // 2. The CPU Bus Signals (Internal wires now, not top-level ports)
    wire [31:0] ibus_adr, dbus_adr, dbus_dat;
    wire ibus_cyc, dbus_cyc, dbus_we;
    reg ibus_ack, dbus_ack;
    wire [31:0] ibus_rdt = ram[(ibus_adr >> 2) & 6'h3F];
    
    // 3. Simple Hex Peripheral
    reg [15:0] hex_val;
    always @(posedge clk) begin
        if (dbus_cyc && dbus_we && dbus_adr == 32'h00000100)
            hex_val <= dbus_dat[15:0];
    end

    // 4. Instantiate the Brain
    serv_rf_top cpu (
        .clk(clk), .i_rst(~rst_n), .i_timer_irq(1'b0),
        .o_ibus_adr(ibus_adr), .o_ibus_cyc(ibus_cyc), .i_ibus_rdt(ibus_rdt), .i_ibus_ack(ibus_cyc),
        .o_dbus_adr(dbus_adr), .o_dbus_dat(dbus_dat), .o_dbus_sel(),
        .o_dbus_we(dbus_we), .o_dbus_cyc(dbus_cyc), .i_dbus_rdt(32'h0), .i_dbus_ack(dbus_cyc)
    );

    // 5. Connect to physical pins
    assign hex_seg = ~hex_val[7:0]; // Simplified segment drive
    assign hex_grid = 8'hFE;        // Enable only the first digit
endmodule
