// SW0 directly controls LED0.
module top(input wire [0:0] SW, output wire [0:0] LED);
  assign LED[0] = SW[0];
endmodule
