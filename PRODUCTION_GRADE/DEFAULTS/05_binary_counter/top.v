// Display upper 8 bits of a free-running binary counter.
module top(input wire clk, output wire [7:0] LED);
  reg [31:0] count = 0;
  always @(posedge clk) count <= count + 1'b1;
  assign LED = count[31:24];
endmodule
