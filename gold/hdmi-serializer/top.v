module top #(
    parameter integer DATA_WIDTH = 8,
    parameter integer BUFR_DIVIDE = 1,
    parameter DATA_RATE_TQ = "DDR",
    parameter integer USE_HDMI_MMCM = 0
) (
    input  wire clk,
    output wire hdmi_p,
    output wire hdmi_n
);
    localparam BUF_DIV = BUFR_DIVIDE == 1 ? "BYPASS" :
                         BUFR_DIVIDE == 2 ? "2" :
                         BUFR_DIVIDE == 3 ? "3" :
                         BUFR_DIVIDE == 4 ? "4" :
                         BUFR_DIVIDE == 5 ? "5" :
                         BUFR_DIVIDE == 6 ? "6" :
                         BUFR_DIVIDE == 7 ? "7" : "8";
    wire clk_fast, clk_io, clk_div, serial;
    wire mmcm_fb;
    reg [9:0] pattern = 10'b1101010100;
    wire shift1, shift2;

    generate if (USE_HDMI_MMCM) begin : g_mmcm
        // One real HDMI-rate witness: 100 MHz * 10 / 8 = 125 MHz,
        // followed by BUFR / 5 = 25 MHz for 10-bit DDR serialization.
        MMCME2_ADV #(
            .BANDWIDTH("OPTIMIZED"), .COMPENSATION("INTERNAL"),
            .CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1),
            .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(8.0)
        ) u_mmcm (
            .CLKIN1(clk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
            .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb), .CLKOUT0(clk_fast),
            .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0),
            .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0),
            .PWRDWN(1'b0), .RST(1'b0)
        );
    end else begin : g_direct_clock
        assign clk_fast = clk;
    end endgenerate

    BUFIO u_bufio (.I(clk_fast), .O(clk_io));
    BUFR #(.BUFR_DIVIDE(BUF_DIV), .SIM_DEVICE("7SERIES"))
        u_bufr (.I(clk), .CE(1'b1), .CLR(1'b0), .O(clk_div));

    always @(posedge clk_div)
        pattern <= {pattern[8:0], pattern[9] ^ pattern[6]};

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"), .DATA_RATE_TQ(DATA_RATE_TQ),
        .DATA_WIDTH(DATA_WIDTH), .SERDES_MODE("MASTER"),
        .TRISTATE_WIDTH(1)
    ) u_master (
        .OQ(serial), .CLK(clk_io), .CLKDIV(clk_div),
        .D1(pattern[0]), .D2(pattern[1]), .D3(pattern[2]), .D4(pattern[3]),
        .D5(pattern[4]), .D6(pattern[5]), .D7(pattern[6]), .D8(pattern[7]),
        .OCE(1'b1), .RST(1'b0),
        .SHIFTIN1(DATA_WIDTH == 10 ? shift1 : 1'b0),
        .SHIFTIN2(DATA_WIDTH == 10 ? shift2 : 1'b0),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
        .TBYTEIN(1'b0), .TCE(1'b0)
    );

    generate if (DATA_WIDTH == 10) begin : g_slave
        OSERDESE2 #(
            .DATA_RATE_OQ("DDR"), .DATA_RATE_TQ(DATA_RATE_TQ),
            .DATA_WIDTH(10), .SERDES_MODE("SLAVE"), .TRISTATE_WIDTH(1)
        ) u_slave (
            .CLK(clk_io), .CLKDIV(clk_div),
            .D1(1'b0), .D2(1'b0), .D3(pattern[8]), .D4(pattern[9]),
            .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
            .OCE(1'b1), .RST(1'b0), .SHIFTIN1(1'b0), .SHIFTIN2(1'b0),
            .SHIFTOUT1(shift1), .SHIFTOUT2(shift2),
            .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
            .TBYTEIN(1'b0), .TCE(1'b0)
        );
    end endgenerate

    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST"))
        u_out (.I(serial), .O(hdmi_p), .OB(hdmi_n));
endmodule
