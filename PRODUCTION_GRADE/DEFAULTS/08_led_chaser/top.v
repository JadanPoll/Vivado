// One illuminated LED advances through eight positions.
module top(input wire clk, output wire [7:0] LED);
  reg [25:0] count = 0;
  reg [2:0] pos = 0;
  always @(posedge clk) begin
    if (count == 26'd12499999) begin
      count <= 0;
      pos <= pos + 1'b1;
    end else count <= count + 1'b1;
  end
  assign LED = 8'b1 << pos;
endmodule
