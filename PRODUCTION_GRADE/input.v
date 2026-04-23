module zero_soc (
    input clk,
    output [15:0] led
);
    // 1. Physical Heartbeat (Blinky)
    reg [26:0] counter;
    always @(posedge clk) counter <= counter + 1;
    assign led[0] = counter[26]; // Toggles roughly every 0.6 seconds
    assign led[15:1] = 14'h0;

    // 2. The JTAG Loopback Probe
    // Connects internal logic to JTAG USER1 register (Chain 1)
    wire drck, sel, shift, tdi, tdo;
    BSCANE2 #(.JTAG_CHAIN(1)) bscan_inst (
        .DRCK(drck),   // Gated TCK for Chain 1
        .SEL(sel),     // High when USER1 is active
        .SHIFT(shift), // High during Shift-DR state
        .TDI(tdi),     // Serial input from external JTAG
        .TDO(tdo),     // Serial output to external JTAG
        .CAPTURE(), .RESET(), .UPDATE(), .TMS()
    );

    // Shift register to hold and move the magic number
    reg [31:0] test_reg = 32'hDEADBEEF;
    always @(posedge drck) begin
        if (sel && shift) test_reg <= {tdi, test_reg[31:1]};
    end
    assign tdo = test_reg[0];
endmodule
