// ZeroLabs Showcase: 8-Function ALU with Hex Display
// Primitives: DSP48E1 (ADD/SUB/MUL), BUFG
// D1 = function name, D0 = result in hex
// SW[7:0]=A  SW[15:8]=B  BTN[0]=reset  BTN[1]=next fn  BTN[2]=latch operands
// LED=result  RGB0=[overflow,carry,zero]

module top (
    input  logic        clk,
    input  logic [3:0]  BTN,
    input  logic [15:0] SW,
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

    logic [19:0] db1 = 0, db2 = 0;
    logic        b1_prev = 0, b2_prev = 0;
    logic        pulse_next = 0, pulse_latch = 0;

    always_ff @(posedge clk_g) begin
        db1 <= db1 + 1;
        db2 <= db2 + 1;
        b1_prev <= BTN[1];
        b2_prev <= BTN[2];
        pulse_next  <= 0;
        pulse_latch <= 0;
        if (db1 == 0 && BTN[1] && !b1_prev) pulse_next  <= 1;
        if (db2 == 0 && BTN[2] && !b2_prev) pulse_latch <= 1;
    end

    logic [15:0] op_a = 16'h0005;
    logic [15:0] op_b = 16'h0003;

    always_ff @(posedge clk_g) begin
        if (BTN[0]) begin
            op_a <= 16'h0005;
            op_b <= 16'h0003;
        end else if (pulse_latch) begin
            op_a <= {8'b0, SW[7:0]};
            op_b <= {8'b0, SW[15:8]};
        end
    end

    logic [2:0] fn = 0;

    always_ff @(posedge clk_g) begin
        if (BTN[0])          fn <= 0;
        else if (pulse_next) fn <= fn + 1;
    end

    logic [2:0] fn_d1 = 0, fn_d2 = 0, fn_d3 = 0;
    always_ff @(posedge clk_g) begin
        fn_d1 <= fn;
        fn_d2 <= fn_d1;
        fn_d3 <= fn_d2;
    end

    logic [6:0] opmode_sel;
    logic       dsp_sub;

    always_comb begin
        case (fn)
            3'd0: begin opmode_sel = 7'b0110011; dsp_sub = 0; end
            3'd1: begin opmode_sel = 7'b0110011; dsp_sub = 1; end
            3'd2: begin opmode_sel = 7'b0000101; dsp_sub = 0; end
            default: begin opmode_sel = 7'b0110011; dsp_sub = 0; end
        endcase
    end

    wire [3:0]  alumode = {3'b000, dsp_sub};
    wire [47:0] dsp_p;

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
        .A({14'b0, op_a}),
        .B({2'b0,  op_b}),
        .C(48'b0), .D(25'b0),
        .OPMODE(opmode_sel),
        .ALUMODE(alumode),
        .INMODE(5'b00000),
        .CARRYIN(1'b0), .CARRYINSEL(3'b000),
        .CEA1(1'b1), .CEA2(1'b1),
        .CEB1(1'b1), .CEB2(1'b1),
        .CEC(1'b0),  .CED(1'b0), .CEAD(1'b0),
        .CEM(1'b1),  .CEP(1'b1), .CECTRL(1'b1), .CECARRYIN(1'b1),
        .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTD(1'b0),
        .RSTM(1'b0), .RSTP(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTCTRL(1'b0),
        .ACIN(30'b0), .BCIN(18'b0), .PCIN(48'b0),
        .CARRYCASCIN(),
        .P(dsp_p),
        .ACOUT(), .BCOUT(), .PCOUT(),
        .CARRYCASCOUT(), .MULTSIGNOUT(),
        .CARRYOUT(), .PATTERNDETECT(), .PATTERNBDETECT(),
        .OVERFLOW(), .UNDERFLOW()
    );

    logic [16:0] result_wide;

    always_comb begin
        case (fn_d3)
            3'd0: result_wide = {1'b0,  dsp_p[15:0]};
            3'd1: result_wide = {1'b0,  dsp_p[15:0]};
            3'd2: result_wide = {1'b0,  dsp_p[15:0]};
            3'd3: result_wide = {9'b0,  op_a[7:0] & op_b[7:0]};
            3'd4: result_wide = {9'b0,  op_a[7:0] | op_b[7:0]};
            3'd5: result_wide = {9'b0,  op_a[7:0] ^ op_b[7:0]};
            3'd6: result_wide = {op_a[15], op_a[14:0], 1'b0};
            3'd7: result_wide = {2'b0,  op_a[15:1]};
            default: result_wide = 17'b0;
        endcase
    end

    wire [15:0] result        = result_wide[15:0];
    wire        flag_carry    = result_wide[16];
    wire        flag_zero     = (result == 16'h0000);
    wire        flag_overflow = (fn_d3 == 3'd0) ?
                    (~op_a[15] & ~op_b[15] &  result[15]) |
                    ( op_a[15] &  op_b[15] & ~result[15]) : 1'b0;

    assign LED  = result;
    assign RGB0 = {flag_overflow, flag_carry, flag_zero};
    assign RGB1 = fn_d3[2:0];

    function automatic [7:0] seg7(input logic [3:0] n);
        case (n)
            4'h0: seg7 = 8'b00111111;
            4'h1: seg7 = 8'b00000110;
            4'h2: seg7 = 8'b01011011;
            4'h3: seg7 = 8'b01001111;
            4'h4: seg7 = 8'b01100110;
            4'h5: seg7 = 8'b01101101;
            4'h6: seg7 = 8'b01111101;
            4'h7: seg7 = 8'b00000111;
            4'h8: seg7 = 8'b01111111;
            4'h9: seg7 = 8'b01101111;
            4'ha: seg7 = 8'b01110111;
            4'hb: seg7 = 8'b01111100;
            4'hc: seg7 = 8'b00111001;
            4'hd: seg7 = 8'b01011110;
            4'he: seg7 = 8'b01111001;
            4'hf: seg7 = 8'b01110001;
        endcase
    endfunction

    // Flat ROM — Yosys-safe, no 2D arrays
    // Index: fn*4 + digit   digit0=rightmost digit3=leftmost
    // fn0 ADD_  fn1 SUb_  fn2 nUL_  fn3 ANd_
    // fn4 __or  fn5 _Xor  fn6 SHL_  fn7 SHr_
    logic [7:0] name_rom [0:31];

    initial begin
        name_rom[ 0]=8'h08; name_rom[ 1]=8'h5E;
        name_rom[ 2]=8'h5E; name_rom[ 3]=8'h77;

        name_rom[ 4]=8'h08; name_rom[ 5]=8'h7C;
        name_rom[ 6]=8'h1C; name_rom[ 7]=8'h6D;

        name_rom[ 8]=8'h08; name_rom[ 9]=8'h38;
        name_rom[10]=8'h1C; name_rom[11]=8'h54;

        name_rom[12]=8'h08; name_rom[13]=8'h5E;
        name_rom[14]=8'h54; name_rom[15]=8'h77;

        name_rom[16]=8'h50; name_rom[17]=8'h5C;
        name_rom[18]=8'h08; name_rom[19]=8'h08;

        name_rom[20]=8'h50; name_rom[21]=8'h5C;
        name_rom[22]=8'h76; name_rom[23]=8'h08;

        name_rom[24]=8'h08; name_rom[25]=8'h38;
        name_rom[26]=8'h76; name_rom[27]=8'h6D;

        name_rom[28]=8'h08; name_rom[29]=8'h50;
        name_rom[30]=8'h76; name_rom[31]=8'h6D;
    end

    logic [16:0] scan = 0;
    always_ff @(posedge clk_g) scan <= scan + 1;

    always_comb begin
        case (scan[16:15])
            2'b00: begin
                D0_AN  = 4'b1110;
                D0_SEG = ~seg7(result[ 3:0]);
                D1_AN  = 4'b1110;
                D1_SEG = ~name_rom[{fn_d3, 2'b00}];
            end
            2'b01: begin
                D0_AN  = 4'b1101;
                D0_SEG = ~seg7(result[ 7:4]);
                D1_AN  = 4'b1101;
                D1_SEG = ~name_rom[{fn_d3, 2'b01}];
            end
            2'b10: begin
                D0_AN  = 4'b1011;
                D0_SEG = ~seg7(result[11:8]);
                D1_AN  = 4'b1011;
                D1_SEG = ~name_rom[{fn_d3, 2'b10}];
            end
            2'b11: begin
                D0_AN  = 4'b0111;
                D0_SEG = ~seg7(result[15:12]);
                D1_AN  = 4'b0111;
                D1_SEG = ~name_rom[{fn_d3, 2'b11}];
            end
        endcase
    end

endmodule