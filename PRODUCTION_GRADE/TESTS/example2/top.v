// ZeroLabs: LED Binary Counter
// Primitives: BUFG
// LEDs show a binary count — slow enough to watch individual bits flip

module top (
    input  logic        clk,
    output logic [15:0] LED
);
    wire clk_g;
    BUFG u_bufg (.I(clk), .O(clk_g));

    // Divide 100 MHz down to ~3 Hz — fast enough to look alive,
    // slow enough to read individual bit transitions
    logic [24:0] div = 0;
    logic        tick;

    always_ff @(posedge clk_g) begin
        tick <= 0;
        div  <= div + 1;
        if (div == 25'd33_333_332) begin
            div  <= 0;
            tick <= 1;
        end
    end

    logic [15:0] cnt = 0;
    always_ff @(posedge clk_g) begin
        if (tick) cnt <= cnt + 1;
    end

    assign LED = cnt;

endmodule