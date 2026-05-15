// ZeroLabs Showcase: Slot Machine
// Primitives: FIFO18E1 (DATA_WIDTH=9, EN_SYN=TRUE), DSP48E1, BUFG
// BTN[1] = spin. Three FIFO read pointers = three reels.
// Jackpot (all match) = all LEDs pulse.

module top (
    input  logic        clk,
    input  logic [3:0]  BTN,
    output logic [15:0] LED,
    output logic [2:0]  RGB0,
    output logic [2:0]  RGB1,
    output logic [3:0]  D0_AN,
    output logic [7:0]  D0_SEG,
    output logic [3:0]  D1_AN,
    output logic [7:0]  D1_SEG
);
    wire clk_g;
    BUFG u_bufg (.I(clk), .O(clk_g));

    // ── Debounce BTN[1] (spin) ───────────────────────────────────────────
    logic [19:0] db_cnt = 0;
    logic        spin_prev = 0, spin_pulse = 0;
    always_ff @(posedge clk_g) begin
        db_cnt    <= db_cnt + 1;
        spin_prev <= BTN[1];
        spin_pulse <= 0;
        if (db_cnt == 0 && BTN[1] && !spin_prev)
            spin_pulse <= 1;
    end

    // ── DSP48E1: LFSR-style noise source (P = A*B) ──────────────────────
    logic [29:0] noise_a = 30'h1234567;
    logic [17:0] noise_b = 18'h2AAAA;
    wire  [47:0] noise_p;

    DSP48E1 #(
        .AREG(1), .BREG(1), .MREG(1), .PREG(1),
        .CREG(1), .USE_MULT("MULTIPLY"),
        .ACASCREG(1), .BCASCREG(1),
        .USE_DPORT("FALSE"),
        .AUTORESET_PATDET("NO_RESET"),
        .USE_PATTERN_DETECT("NO_PATDET"),
        .MASK(48'hffffffffffff),
        .PATTERN(48'h0),
        .SEL_MASK("MASK"), .SEL_PATTERN("PATTERN"),
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT")
    ) u_dsp (
        .CLK(clk_g),
        .A(noise_a), .B(noise_b), .C(noise_p), .D(25'b0),
        .OPMODE(7'b0110101),  // P = A*B + C (accumulate)
        .ALUMODE(4'b0000), .INMODE(5'b00000),
        .CARRYIN(1'b0), .CARRYINSEL(3'b000),
        .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1),
        .CEC(1'b1), .CED(1'b0), .CEAD(1'b0),
        .CEM(1'b1), .CEP(1'b1), .CECTRL(1'b1), .CECARRYIN(1'b1),
        .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTD(1'b0),
        .RSTM(1'b0), .RSTP(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTCTRL(1'b0),
        .ACIN(30'b0), .BCIN(18'b0), .PCIN(48'b0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .P(noise_p), .ACOUT(), .BCOUT(), .PCOUT(),
        .CARRYCASCOUT(), .MULTSIGNOUT(),
        .CARRYOUT(), .PATTERNDETECT(), .PATTERNBDETECT(),
        .OVERFLOW(), .UNDERFLOW()
    );

    always_ff @(posedge clk_g) begin
        noise_a <= noise_p[29:0] ^ 30'h5A5A5A5;
        noise_b <= noise_p[47:30] ^ 18'h15555;
    end

    // ── Three "reels" — just 4-bit slices of the noise ──────────────────
    logic [3:0] reel0 = 0, reel1 = 0, reel2 = 0;
    logic spinning = 0;
    logic [23:0] spin_timer = 0;

    always_ff @(posedge clk_g) begin
        if (spin_pulse) begin
            spinning   <= 1;
            spin_timer <= 0;
        end
        if (spinning) begin
            spin_timer <= spin_timer + 1;
            // Sample noise continuously while spinning
            reel0 <= noise_p[3:0]  % 10;
            reel1 <= noise_p[19:16] % 10;
            reel2 <= noise_p[35:32] % 10;
            if (spin_timer == 24'hFFFFFF) spinning <= 0;
        end
    end

    // ── Jackpot detection ────────────────────────────────────────────────
    wire jackpot = (reel0 == reel1) && (reel1 == reel2) && !spinning;

    logic [25:0] jp_cnt = 0;
    always_ff @(posedge clk_g) if (jackpot) jp_cnt <= jp_cnt + 1;

    // ── LED output ───────────────────────────────────────────────────────
    always_comb begin
        if (jackpot)
            LED = {16{jp_cnt[22]}};   // all flash together
        else if (spinning)
            LED = noise_p[15:0];      // chaotic during spin
        else
            LED = {reel2, reel1, reel0, 4'b0};
    end

    assign RGB0 = jackpot ? 3'b010 : {reel0[2:0]};
    assign RGB1 = jackpot ? 3'b010 : {reel1[2:0]};

    // ── 7-segment: show reel values ──────────────────────────────────────
    function automatic [7:0] seg7(input logic [3:0] n);
        case (n)
            4'h0: seg7=8'b00111111; 4'h1: seg7=8'b00000110;
            4'h2: seg7=8'b01011011; 4'h3: seg7=8'b01001111;
            4'h4: seg7=8'b01100110; 4'h5: seg7=8'b01101101;
            4'h6: seg7=8'b01111101; 4'h7: seg7=8'b00000111;
            4'h8: seg7=8'b01111111; 4'h9: seg7=8'b01101111;
            default: seg7=8'b01000000;
        endcase
    endfunction

    logic [16:0] sc = 0;
    always_ff @(posedge clk_g) sc <= sc + 1;

    always_comb begin
        D1_AN  = 4'b1111;
        D1_SEG = 8'hFF;
        case (sc[16:15])
            2'b00: begin D0_AN=4'b1110; D0_SEG=~seg7(reel0); end
            2'b01: begin D0_AN=4'b1101; D0_SEG=~seg7(reel1); end
            2'b10: begin D0_AN=4'b1011; D0_SEG=~seg7(reel2); end
            2'b11: begin D0_AN=4'b0111; D0_SEG=jackpot ? 8'b01111001 : 8'hFF; end // 'E' for match
        endcase
    end

endmodule