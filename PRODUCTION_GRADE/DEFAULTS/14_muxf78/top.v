// Four LUT6 primitive outputs composed through two MUXF7 and a MUXF8.
module top(input wire clk,output wire [3:0] LED);
reg [25:0] count=0;
reg fail=0,done=0;
(* keep="true" *) wire l0,l1,l2,l3,m01,m23,m;
LUT6 #(.INIT(64'hAAAAAAAAAAAAAAAA)) u0(.O(l0),.I0(count[0]),.I1(count[1]),.I2(count[2]),.I3(count[3]),.I4(count[4]),.I5(count[5]));
LUT6 #(.INIT(64'hCCCCCCCCCCCCCCCC)) u1(.O(l1),.I0(count[0]),.I1(count[1]),.I2(count[2]),.I3(count[3]),.I4(count[4]),.I5(count[5]));
LUT6 #(.INIT(64'hF0F0F0F0F0F0F0F0)) u2(.O(l2),.I0(count[0]),.I1(count[1]),.I2(count[2]),.I3(count[3]),.I4(count[4]),.I5(count[5]));
LUT6 #(.INIT(64'hFF00FF00FF00FF00)) u3(.O(l3),.I0(count[0]),.I1(count[1]),.I2(count[2]),.I3(count[3]),.I4(count[4]),.I5(count[5]));
MUXF7 f0(.O(m01),.I0(l0),.I1(l1),.S(count[6]));
MUXF7 f1(.O(m23),.I0(l2),.I1(l3),.S(count[6]));
MUXF8 f2(.O(m),.I0(m01),.I1(m23),.S(count[7]));
wire expected=count[7]?(count[6]?count[3]:count[2]):(count[6]?count[1]:count[0]);
always @(posedge clk)begin
count<=count+1'b1;
if(m!=expected)fail<=1'b1;
if(count[17])done<=1'b1;
end
assign LED={m,fail,done,count[25]};
endmodule
