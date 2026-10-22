// 100 MHz clock; toggle every 50,000,000 cycles (1 Hz blink).
module top(input wire clk, output reg [0:0] LED = 0);
  reg [25:0] count = 0;
  always @(posedge clk) begin
    if (count == 26'd49999999) begin
      count <= 0;
      LED[0] <= ~LED[0];
    end else count <= count + 1'b1;
  end
endmodule
