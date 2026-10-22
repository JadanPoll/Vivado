// Button BTN0 directly controls LED0 (polarity follows hardware).
module top(input wire BTN, output wire LED);
  assign LED = BTN;
endmodule
