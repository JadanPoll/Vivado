// SW0 directly controls LED0.
module top(input wire SW, output wire LED);
  assign LED = SW;
endmodule
