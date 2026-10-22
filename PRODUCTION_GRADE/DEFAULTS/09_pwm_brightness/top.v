// SW[3:0] sets the duty cycle of LED0 (16 steps).
module top(input wire clk, input wire [3:0] SW, output wire [0:0] LED);
  reg [3:0] pwm = 0;
  always @(posedge clk) pwm <= pwm + 1'b1;
  assign LED[0] = pwm < SW;
endmodule
