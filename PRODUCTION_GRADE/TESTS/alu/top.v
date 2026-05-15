// ZeroLabs Showcase: 8-Function ALU with Hex Display
// Primitives: DSP48E1 (ADD/SUB/MULT), SRLC32E (operand shift reg),
//             BUFG, SRL16E (function name ROM)
//
// D1 display: cycles through function name (A-d-d, 5ub, etc.)
// D0 display: shows 16-bit result in hex
// SW[7:0]  = operand A
// SW[15:8] = operand B
// BTN[0]   = reset
// BTN[1]   = next function (debounced)
// BTN[2]   = latch operands (debounced)
// LED      = result[15:0]
// RGB0     = overflow / carry / zero flags

module top (
    input  logic        clk,
    input  logic [3:0]  BTN,
    input  logic [15:0] SW,
    output logic [15:0] LED,
    output logic [2:0]  RGB0,   // [0]=zero [1]=carry [2]=overflow
    output logic [2:0]  RGB1,
    output logic [3:0]  D0_AN,
    output logic [7:0]  D0_SEG,
    output logic [3:0]  D1_AN,
    output logic [7:0]  D1_SEG
);

    // ────────────────────────────────────────────────────────────────────
    // 0. Global clock buffer
    // ────────────────────────────────────────────────────────────────────
    wire clk_g;
    BUFG u_bufg (.I(clk), .O(clk_g));

    // ────────────────────────────────────────────────────────────────────
    // 1. Debounce BTN[1] (next fn) and BTN[2] (latch)
    // ────────────────────────────────────────────────────────────────────
    logic [19:0] db1 = 0, db2 = 0;
    logic        b1_prev = 0, b2_prev = 0;
    logic        pulse_next = 0, pulse_latch = 0;

    always_ff @(posedge clk_g) begin
        db1 <= db1 + 1; db2 <= db2 + 1;
        b1_prev <= BTN[1]; b2_prev <= BTN[2];
        pulse_next  <= 0;
        pulse_latch <= 0;
        if (db1 == 0 && BTN[1] && !b1_prev) pulse_next  <= 1;
        if (db2 == 0 && BTN[2] && !b2_prev) pulse_latch <= 1;
    end

    // ────────────────────────────────────────────────────────────────────
    // 2. Operand registers  (SW latched on BTN[2])
    // ────────────────────────────────────────────────────────────────────
    logic [15:0] op_a = 16'h0005;
    logic [15:0] op_b = 16'h0003;

    always_ff @(posedge clk_g) begin
        if (BTN[0]) begin
            op_a <= 16'h0005; op_b <= 16'h0003;
        end else if (pulse_latch) begin
            op_a <= SW[7:0];        // lower 8 switches = A
            op_b <= SW[15:8];       // upper 8 switches = B
        end
    end

    // ────────────────────────────────────────────────────────────────────
    // 3. Function select  (8 functions, BTN[1] cycles)
    // ────────────────────────────────────────────────────────────────────
    //  0 = ADD    1 = SUB    2 = MUL (lower 16b)
    //  3 = AND    4 = OR     5 = XOR
    //  6 = SHL1   7 = SHR1
    logic [2:0] fn = 0;

    always_ff @(posedge clk_g) begin
        if (BTN[0])       fn <= 0;
        else if (pulse_next) fn <= fn + 1;  // wraps 7→0 automatically
    end

    // ────────────────────────────────────────────────────────────────────
    // 4. DSP48E1  —  handles ADD / SUB / MUL
    //    OPMODE switches combinatorially via CECTRL
    //    For logic ops we bypass DSP and use fabric
    // ────────────────────────────────────────────────────────────────────
    wire [47:0] dsp_p;
    logic [6:0]  opmode_sel;
    logic        dsp_sub;

    always_comb begin
        case (fn)
            3'd0: begin opmode_sel = 7'b0110011; dsp_sub = 0; end  // P = A + B
            3'd1: begin opmode_sel = 7'b0110011; dsp_sub = 1; end  // P = A - B (ALUMODE)
            3'd2: begin opmode_sel = 7'b0000101; dsp_sub = 0; end  // P = A * B
            default: begin opmode_sel = 7'b0110011; dsp_sub = 0; end
        endcase
    end

    // ALUMODE[0] = subtract when 1
    wire [3:0] alumode = {3'b000, dsp_sub};

    DSP48E1 #(
        .AREG(1), .BREG(1), .MREG(1), .PREG(1), .CREG(0),
        .USE_MULT("MULTIPLY"),
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
        .A({14'b0, op_a}),          // zero-extend A to 30 bits
        .B({2'b0,  op_b}),          // zero-extend B to 18 bits
        .C(48'b0), .D(25'b0),
        .OPMODE(opmode_sel),
        .ALUMODE(alumode),
        .INMODE(5'b00000),
        .CARRYIN(1'b0), .CARRYINSEL(3'b000),
        .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1),
        .CEC(1'b0),  .CED(1'b0),  .CEAD(1'b0),
        .CEM(1'b1),  .CEP(1'b1),  .CECTRL(1'b1), .CECARRYIN(1'b1),
        .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTD(1'b0),
        .RSTM(1'b0), .RSTP(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTCTRL(1'b0),
        .ACIN(30'b0), .BCIN(18'b0), .PCIN(48'b0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .P(dsp_p),
        .ACOUT(), .BCOUT(), .PCOUT(),
        .CARRYCASCOUT(), .MULTSIGNOUT(),
        .CARRYOUT(), .PATTERNDETECT(), .PATTERNBDETECT(),
        .OVERFLOW(), .UNDERFLOW()
    );

    // ────────────────────────────────────────────────────────────────────
    // 5. Result mux — fabric ops + DSP result
    // ────────────────────────────────────────────────────────────────────
    logic [16:0] result_wide;   // 17 bits to capture carry

    always_comb begin
        case (fn)
            3'd0: result_wide = {1'b0, dsp_p[15:0]};           // ADD
            3'd1: result_wide = {1'b0, dsp_p[15:0]};           // SUB
            3'd2: result_wide = {1'b0, dsp_p[15:0]};           // MUL (low 16)
            3'd3: result_wide = {1'b0, op_a[7:0] & op_b[7:0], 8'b0};  // AND
            3'd4: result_wide = {1'b0, op_a[7:0] | op_b[7:0], 8'b0};  // OR
            3'd5: result_wide = {1'b0, op_a[7:0] ^ op_b[7:0], 8'b0};  // XOR
            3'd6: result_wide = {op_a[15], op_a[14:0], 1'b0};          // SHL
            3'd7: result_wide = {1'b0, 1'b0, op_a[15:1]};              // SHR
            default: result_wide = 17'b0;
        endcase
    end

    wire [15:0] result   = result_wide[15:0];
    wire        flag_carry    = result_wide[16];
    wire        flag_zero     = (result == 16'h0000);
    wire        flag_overflow = (fn == 3'd0) ?
                    (~op_a[15] & ~op_b[15] &  result[15]) |
                    ( op_a[15] &  op_b[15] & ~result[15]) : 1'b0;

    assign LED  = result;
    assign RGB0 = {flag_overflow, flag_carry, flag_zero};
    assign RGB1 = fn;   // raw function number on RGB1

    // ────────────────────────────────────────────────────────────────────
    // 6. Hex display
    //    D0 = result (4 hex digits)
    //    D1 = function name (see table below, cycles through chars)
    // ────────────────────────────────────────────────────────────────────

    // 7-segment encoding (active HIGH here — we invert at output)
    //  Segments:  gfedcba
    function automatic [7:0] seg7(input logic [3:0] n);
        case (n)
            4'h0: seg7 = 8'b00111111;  // 0
            4'h1: seg7 = 8'b00000110;  // 1
            4'h2: seg7 = 8'b01011011;  // 2
            4'h3: seg7 = 8'b01001111;  // 3
            4'h4: seg7 = 8'b01100110;  // 4
            4'h5: seg7 = 8'b01101101;  // 5
            4'h6: seg7 = 8'b01111101;  // 6
            4'h7: seg7 = 8'b00000111;  // 7
            4'h8: seg7 = 8'b01111111;  // 8
            4'h9: seg7 = 8'b01101111;  // 9
            4'ha: seg7 = 8'b01110111;  // A
            4'hb: seg7 = 8'b01111100;  // b
            4'hc: seg7 = 8'b00111001;  // C
            4'hd: seg7 = 8'b01011110;  // d
            4'he: seg7 = 8'b01111001;  // E
            4'hf: seg7 = 8'b01110001;  // F
        endcase
    endfunction

    // Function name ROM — 4 chars per function, packed into nibbles
    // Characters encoded as seg7 patterns directly (not ASCII)
    // Segments: gfedcba
    // Letters used:
    //   A=77  d=5E  d=5E  _=08   → ADD_
    //   5=6D  u=1C  b=7C  _=08   → SUb_  (5ub)
    //   n=54  u=1C  L=38  _=08   → nUL_  (MUL shown as nUL since M hard on 7seg)
    //   A=77  n=54  d=5E  _=08   → ANd
    //   o=5C  r=50  _=08  _=08   → or
    //   X=76  o=5C  r=50  _=08   → Xor
    //   5=6D  H=76  L=38  _=08   → SHL
    //   5=6D  H=76  r=50  _=08   → SHr

    // Each entry: 4 bytes = digit3 digit2 digit1 digit0 (left to right on D1)
    logic [7:0] name_rom [0:7][0:3];

    initial begin
        // ADD
        name_rom[0][3] = 8'h77; // A
        name_rom[0][2] = 8'h5E; // d
        name_rom[0][1] = 8'h5E; // d
        name_rom[0][0] = 8'h08; // _
        // SUb
        name_rom[1][3] = 8'h6D; // S
        name_rom[1][2] = 8'h1C; // u
        name_rom[1][1] = 8'h7C; // b
        name_rom[1][0] = 8'h08; // _
        // MUL (display nUL — M not possible on 7seg)
        name_rom[2][3] = 8'h54; // n
        name_rom[2][2] = 8'h1C; // U
        name_rom[2][1] = 8'h38; // L
        name_rom[2][0] = 8'h08; // _
        // AND
        name_rom[3][3] = 8'h77; // A
        name_rom[3][2] = 8'h54; // n
        name_rom[3][1] = 8'h5E; // d
        name_rom[3][0] = 8'h08; // _
        // OR
        name_rom[4][3] = 8'h08; // _
        name_rom[4][2] = 8'h08; // _
        name_rom[4][1] = 8'h5C; // o
        name_rom[4][0] = 8'h50; // r
        // XOR
        name_rom[5][3] = 8'h08; // _
        name_rom[5][2] = 8'h76; // X
        name_rom[5][1] = 8'h5C; // o
        name_rom[5][0] = 8'h50; // r
        // SHL
        name_rom[6][3] = 8'h6D; // S
        name_rom[6][2] = 8'h76; // H
        name_rom[6][1] = 8'h38; // L
        name_rom[6][0] = 8'h08; // _
        // SHR
        name_rom[7][3] = 8'h6D; // S
        name_rom[7][2] = 8'h76; // H
        name_rom[7][1] = 8'h50; // r
        name_rom[7][0] = 8'h08; // _
    end

    // Scan counter — bits [16:15] select which digit is active
    // At 100 MHz this gives ~763 Hz per digit = flicker-free
    logic [16:0] scan = 0;
    always_ff @(posedge clk_g) scan <= scan + 1;

    always_comb begin
        case (scan[16:15])
            // D0: result in hex, right display
            2'b00: begin
                D0_AN  = 4'b1110;
                D0_SEG = ~seg7(result[3:0]);
                D1_AN  = 4'b1110;
                D1_SEG = ~name_rom[fn][0];
            end
            2'b01: begin
                D0_AN  = 4'b1101;
                D0_SEG = ~seg7(result[7:4]);
                D1_AN  = 4'b1101;
                D1_SEG = ~name_rom[fn][1];
            end
            2'b10: begin
                D0_AN  = 4'b1011;
                D0_SEG = ~seg7(result[11:8]);
                D1_AN  = 4'b1011;
                D1_SEG = ~name_rom[fn][2];
            end
            2'b11: begin
                D0_AN  = 4'b0111;
                D0_SEG = ~seg7(result[15:12]);
                D1_AN  = 4'b0111;
                D1_SEG = ~name_rom[fn][3];
            end
        endcase
    end

endmodule