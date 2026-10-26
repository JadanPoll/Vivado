// Inferred RAMB36E1; LED[1] sweep complete, LED[2] mismatch.
module top(input wire clk, output wire [3:0] LED);
(* ram_style = "block" *) reg [7:0] mem [0:4095];
integer i;
initial for (i=0;i<4096;i=i+1) mem[i] = (i*37) ^ (i>>4) ^ 8'h5a;
reg [11:0] addr=0;
reg [7:0] rd=0, expected=0;
reg valid=0,done=0,fail=0;
reg [25:0] heartbeat=0;
always @(posedge clk) begin
heartbeat<=heartbeat+1'b1;
addr<=addr+1'b1;
rd<=mem[addr];
expected <= (addr*8'd37) ^ (addr>>4) ^ 8'h5a;
valid<=1'b1;
if(valid && rd != expected) fail<=1'b1;
if(valid && addr==12'hfff)done<=1'b1;
end
assign LED={rd[0],fail,done,heartbeat[25]};
endmodule
