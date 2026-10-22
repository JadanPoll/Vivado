// Eight switches mirrored onto eight LEDs.
module top(input wire [7:0] SW, output wire [7:0] LED);
  assign LED = SW;
endmodule
