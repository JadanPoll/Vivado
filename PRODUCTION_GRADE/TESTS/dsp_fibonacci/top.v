// ZeroLabs Showcase: DSP48E1 Fibonacci on 7-Segment
// Primitives: DSP48E1 (AREG=1 BREG=1 PREG=1), BUFG
// Computes Fib(n) mod 10000 and displays on D0 display

module top (
    input  logic        clk,
    input  logic [3:0]  BTN,     // BTN[0] = reset, BTN[1] = step
    output logic [3:0]  D0_AN,
    output logic [7:0]  D0_SEG,
    output logic [15:0] LED
);
    wire clk_g;
    BUFG u_bufg (.I(clk), .O(clk_g));

    // ── Tick divider — 4 Hz step rate ───────────────────────────────────
    logic [24:0] div = 0;
    logic        tick;
    always_ff @(posedge clk_g) begin
        div  <= div + 1;
        tick <= (div == 25'd24_999_999);
        if (div == 25'd24_999_999) div <= 0;
    end

    // ── DSP48E1 as adder: P = A + B (Fib recurrence) ────────────────────
    // We feed A=fib_a, B=fib_b, read P=fib_a+fib_b
    logic [29:0] fib_a = 30'd0;
    logic [17:0] fib_b = 18'd1;
    logic [47:0] fib_p;

    DSP48E1 #(
        .AREG(1), .BREG(1), .CREG(0), .PREG(1),
        .MREG(0), .USE_MULT("NONE"),
        .ACASCREG(1), .BCASCREG(1),
        .USE_DPORT("FALSE"),
        .AUTORESET_PATDET("NO_RESET"),
        .USE_PATTERN_DETECT("NO_PATDET"),
        .MASK(48'hffffffffffff),
        .PATTERN(48'h0),
        .SEL_MASK("MASK"),
        .SEL_PATTERN("PATTERN"),
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT")
    ) u_dsp (
        .CLK(clk_g),
        .A(fib_a), .B(fib_b), .C(48'b0), .D(25'b0),
        .OPMODE(7'b0110011),   // P = A + B
        .ALUMODE(4'b0000),
        .INMODE(5'b00000),
        .CARRYIN(1'b0), .CARRYINSEL(3'b000),
        .CEA1(1'b1), .CEA2(1'b1),
        .CEB1(1'b1), .CEB2(1'b1),
        .CEC(1'b0), .CED(1'b0), .CEAD(1'b0),
        .CEM(1'b0), .CEP(1'b1), .CECTRL(1'b1), .CECARRYIN(1'b1),
        .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTD(1'b0),
        .RSTM(1'b0), .RSTP(1'b0),
        .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0),
        .RSTINMODE(1'b0), .RSTCTRL(1'b0),
        .ACIN(30'b0), .BCIN(18'b0), .PCIN(48'b0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .P(fib_p),
        .ACOUT(), .BCOUT(), .PCOUT(),
        .CARRYCASCOUT(), .MULTSIGNOUT(),
        .CARRYOUT(), .PATTERNDETECT(), .PATTERNBDETECT(),
        .OVERFLOW(), .UNDERFLOW()
    );

    // ── Fibonacci state machine ──────────────────────────────────────────
    logic [15:0] display_val = 0;

    always_ff @(posedge clk_g) begin
        if (BTN[0]) begin
            fib_a <= 30'd0;
            fib_b <= 18'd1;
            display_val <= 0;
        end else if (tick) begin
            // Shift: a=b, b=p mod 65536
            fib_a <= {12'b0, fib_b};
            fib_b <= fib_p[17:0];
            display_val <= fib_p[15:0];
        end
    end

    assign LED = display_val;

    // ── 4-digit hex display driver ───────────────────────────────────────
    function automatic [7:0] seg7(input logic [3:0] n);
        case (n)
            4'h0: seg7 = 8'b00111111; 4'h1: seg7 = 8'b00000110;
            4'h2: seg7 = 8'b01011011; 4'h3: seg7 = 8'b01001111;
            4'h4: seg7 = 8'b01100110; 4'h5: seg7 = 8'b01101101;
            4'h6: seg7 = 8'b01111101; 4'h7: seg7 = 8'b00000111;
            4'h8: seg7 = 8'b01111111; 4'h9: seg7 = 8'b01101111;
            4'ha: seg7 = 8'b01110111; 4'hb: seg7 = 8'b01111100;
            4'hc: seg7 = 8'b00111001; 4'hd: seg7 = 8'b01011110;
            4'he: seg7 = 8'b01111001; 4'hf: seg7 = 8'b01110001;
        endcase
    endfunction

    logic [16:0] scan_cnt = 0;
    always_ff @(posedge clk_g) scan_cnt <= scan_cnt + 1;

    always_comb begin
        case (scan_cnt[16:15])
            2'b00: begin D0_AN = 4'b1110; D0_SEG = ~seg7(display_val[ 3: 0]); end
            2'b01: begin D0_AN = 4'b1101; D0_SEG = ~seg7(display_val[ 7: 4]); end
            2'b10: begin D0_AN = 4'b1011; D0_SEG = ~seg7(display_val[11: 8]); end
            2'b11: begin D0_AN = 4'b0111; D0_SEG = ~seg7(display_val[15:12]); end
        endcase
    end

endmodule