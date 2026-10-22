// Button BTN0 directly controls LED0 (polarity follows hardware).
module top(input wire [0:0] BTN, output wire [0:0] LED);
  assign LED[0] = BTN[0];
endmodule
