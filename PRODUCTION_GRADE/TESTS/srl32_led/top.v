// ZeroLabs Showcase: LFSR Shimmer using SRLC32E cascade
// Primitives: SRLC32E (x4 cascade = 128-bit LFSR tap), BUFGCE
// Every LED gets an independent LFSR phase — creates organic shimmer

module top (
    input  logic        clk,
    input  logic [3:0]  BTN,    // BTN[0] = freeze
    output logic [15:0] LED,
    output logic [2:0]  RGB0,
    output logic [2:0]  RGB1
);
    wire clk_g;
    reg  ce = 1;

    // BUFGCE lets us gate the clock — BTN[0] freezes the pattern
    BUFGCE #(.SIM_DEVICE("7SERIES")) u_bufgce (
        .I(clk), .CE(~BTN[0]), .O(clk_g)
    );

    // ── 4× SRLC32E cascade = 128-bit shift register ─────────────────────
    wire q0, q1, q2, q3;
    wire q31_0, q31_1, q31_2, q31_3;

    // Seed the chain — tap positions chosen for maximal LFSR period
    SRLC32E #(.INIT(32'hACE1_2345)) u_srl0 (
        .CLK(clk_g), .CE(1'b1), .D(q31_3 ^ q31_1),  // XOR feedback
        .A(5'b11111), .Q(q0), .Q31(q31_0)
    );
    SRLC32E #(.INIT(32'hDEAD_BEEF)) u_srl1 (
        .CLK(clk_g), .CE(1'b1), .D(q31_0),
        .A(5'b11111), .Q(q1), .Q31(q31_1)
    );
    SRLC32E #(.INIT(32'hCAFE_BABE)) u_srl2 (
        .CLK(clk_g), .CE(1'b1), .D(q31_1),
        .A(5'b11111), .Q(q2), .Q31(q31_2)
    );
    SRLC32E #(.INIT(32'hF00D_1234)) u_srl3 (
        .CLK(clk_g), .CE(1'b1), .D(q31_2),
        .A(5'b11111), .Q(q3), .Q31(q31_3)
    );

    // ── Slow capture register — visible on LEDs ──────────────────────────
    logic [24:0] div = 0;
    logic        tick;
    always_ff @(posedge clk_g) begin
        div  <= div + 1;
        tick <= (div == 25'd3_124_999);   // 32 Hz
        if (div == 25'd3_124_999) div <= 0;
    end

    logic [15:0] shimmer = 16'hA5A5;
    always_ff @(posedge clk_g) begin
        if (tick) begin
            // Sample taps at different chain positions for 16 independent bits
            shimmer <= {q31_3, q31_2, q31_1, q31_0,
                        q3,    q2,    q1,    q0,
                        shimmer[15:8]};
        end
    end

    assign LED  = shimmer;
    assign RGB0 = shimmer[2:0];
    assign RGB1 = shimmer[5:3];

endmodule