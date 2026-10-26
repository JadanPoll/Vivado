// Direct SRLC32E compared against a sequential reference.
module top(input wire clk,output wire [3:0] LED);
reg [25:0] clocks=0;
wire shift_en=(clocks[17:0]==18'd0);
reg input_bit=0;
reg [31:0] reference=32'h3c5a7e91;
reg [7:0] shifts=0;
reg done=0,fail=0;
wire srl_q;
SRLC32E #(.INIT(32'h3c5a7e91)) srl(.Q(srl_q),.Q31(),.A(5'd31),.CE(shift_en),.CLK(clk),.D(input_bit));
always @(posedge clk) begin
clocks<=clocks+1'b1;
if(shift_en) begin
input_bit<=~input_bit;
reference<={reference[30:0],input_bit};
shifts<=shifts+1'b1;
if(shifts>=8'd33)begin
done<=1'b1;
if(srl_q!=reference[31])fail<=1'b1;
end end end
assign LED={srl_q,fail,done,clocks[25]};
endmodule
