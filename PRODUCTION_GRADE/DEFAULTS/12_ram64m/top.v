// Inferred RAM64M distributed RAM with dynamic write.
module top(input wire clk,output wire [3:0] LED);
(* ram_style = "distributed" *) reg [3:0] mem [0:63];
integer i;
initial for(i=0;i<64;i=i+1) mem[i]=i^(i>>3)^4'ha;
reg [5:0] addr=0;
reg [25:0] count=0;
reg fail=0,done=0;
wire [3:0] rd=mem[addr];
wire [3:0] expected=addr^(addr>>3)^4'ha;
always @(posedge clk) begin
count<=count+1'b1;
addr<=addr+1'b1;
if(count[15:0]==16'h1234) mem[count[21:16]]<=count[21:16]^(count[21:16]>>3)^4'ha;
if(count[15:0]!=16'h1234 && rd != expected)fail<=1'b1;
if(count[17])done<=1'b1;
end
assign LED={rd[0],fail,done,count[25]};
endmodule
