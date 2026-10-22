// Display a fixed zero on digit 0; segments and anodes are active LOW.
module top(output wire [3:0] D0_AN, output wire [7:0] D0_SEG);
  assign D0_AN = 4'b1110;
  // {decimal point, g, f, e, d, c, b, a}; bit 0 is segment a.
  assign D0_SEG = 8'b11000000;
endmodule
