// ZeroLabs Showcase: RGB Breathing Plasma
// Primitives: ODDR, BUFG
// clk=N15, RGB0=C9/A9/A10, RGB1=A11/C10/B11

module top (
    input  logic clk,
    output logic [2:0] RGB0,
    output logic [2:0] RGB1
);
    wire clk_g;
    BUFG u_bufg (.I(clk), .O(clk_g));

    logic [26:0] cnt = 0;
    logic [7:0]  pwm_cnt = 0;
    logic [7:0]  bright  = 0;
    logic        dir     = 0;

    always_ff @(posedge clk_g) begin
        cnt     <= cnt + 1;
        pwm_cnt <= pwm_cnt + 1;

        if (cnt == 27'd100_000_000) begin
            cnt <= 0;
        end

        // Slow breathe tick
        if (cnt[15:0] == 0) begin
            if (!dir) begin
                bright <= bright + 1;
                if (bright == 8'd254) dir <= 1;
            end else begin
                bright <= bright - 1;
                if (bright == 8'd1)   dir <= 0;
            end
        end
    end

    // R channel — full breath
    wire r_pwm = (pwm_cnt < bright);
    // G channel — half-phase offset
    wire g_pwm = (pwm_cnt < (bright >> 1));
    // B channel — quarter breath
    wire b_pwm = (pwm_cnt < (bright >> 2));

    // ODDR drives each color line cleanly
    ODDR #(.DDR_CLK_EDGE("OPPOSITE_EDGE"), .SRTYPE("SYNC"), .INIT(0))
        u_r0 (.C(clk_g), .CE(1'b1), .R(1'b0), .S(1'b0),
              .D1(r_pwm), .D2(r_pwm), .Q(RGB0[0]));
    ODDR #(.DDR_CLK_EDGE("OPPOSITE_EDGE"), .SRTYPE("SYNC"), .INIT(0))
        u_g0 (.C(clk_g), .CE(1'b1), .R(1'b0), .S(1'b0),
              .D1(g_pwm), .D2(g_pwm), .Q(RGB0[1]));
    ODDR #(.DDR_CLK_EDGE("OPPOSITE_EDGE"), .SRTYPE("SYNC"), .INIT(0))
        u_b0 (.C(clk_g), .CE(1'b1), .R(1'b0), .S(1'b0),
              .D1(b_pwm), .D2(b_pwm), .Q(RGB0[2]));

    // RGB1 mirrors with inverted phase
    ODDR #(.DDR_CLK_EDGE("OPPOSITE_EDGE"), .SRTYPE("SYNC"), .INIT(0))
        u_r1 (.C(clk_g), .CE(1'b1), .R(1'b0), .S(1'b0),
              .D1(~r_pwm), .D2(~r_pwm), .Q(RGB1[0]));
    ODDR #(.DDR_CLK_EDGE("OPPOSITE_EDGE"), .SRTYPE("SYNC"), .INIT(0))
        u_g1 (.C(clk_g), .CE(1'b1), .R(1'b0), .S(1'b0),
              .D1(b_pwm),  .D2(b_pwm),  .Q(RGB1[1]));
    ODDR #(.DDR_CLK_EDGE("OPPOSITE_EDGE"), .SRTYPE("SYNC"), .INIT(0))
        u_b1 (.C(clk_g), .CE(1'b1), .R(1'b0), .S(1'b0),
              .D1(g_pwm),  .D2(g_pwm),  .Q(RGB1[2]));

    assign out = cnt[26];
endmodule