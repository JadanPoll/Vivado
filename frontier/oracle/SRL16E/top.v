module top (
    input  clk,
    input  d,
    output out
);
    wire q;
    SRL16E #(.INIT(16'h0000)) u_srl (
        .CLK(clk), .CE(1'b1), .D(d),
        .A0(1'b1), .A1(1'b1), .A2(1'b1), .A3(1'b1),
        .Q(q)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + q;
    assign out = ^cnt;
endmodule
