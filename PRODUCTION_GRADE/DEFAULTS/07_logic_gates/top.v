// Two switch inputs show AND, OR, XOR, and NOT on four LEDs.
module top(input wire [1:0] SW, output wire [3:0] LED);
  assign LED[0] = SW[0] & SW[1];
  assign LED[1] = SW[0] | SW[1];
  assign LED[2] = SW[0] ^ SW[1];
  assign LED[3] = ~SW[0];
endmodule
