// pulse_gen.sv - Fixed for Urbana Board Diagnostic Build
module pulse_gen #( 
    parameter CNTR_WIDTH = 16
)(
input logic clk,
    input  logic [3:0]  BTN,      // BTN[0] is Reset, BTN[1] is Start
    input  logic [15:0] SW,       // SW is the max counter value
    output logic [2:0]  RGB0,     // RGB0[0]=pulse, RGB0[1]=strobe, RGB0[2]=unused
    output logic [2:0]  RGB1      // RGB1[0]=busy
);

    // --- Internal Signal Mapping ---
    logic nrst;
    assign nrst = ~BTN[0];         // Note: Urbana buttons are Active High 

    logic start;
    assign start = BTN[1];

    logic [CNTR_WIDTH-1:0] cntr_max;
    assign cntr_max = SW;

    logic [CNTR_WIDTH-1:0] cntr_low;
    assign cntr_low = 16'd5;      // Example: Pulse width of 5 cycles

    // Internal Logic Signals
    logic pulse_out;
    logic start_strobe;
    logic busy;

    // --- Core Logic ---
    logic [CNTR_WIDTH-1:0] seq_cntr = '0;
    logic seq_cntr_0;
    assign seq_cntr_0 = (seq_cntr == '0);

    // Drive the board LEDs
    assign RGB0[0] = pulse_out;
    assign RGB0[1] = start_strobe;
    assign RGB1[0] = busy;
logic [CNTR_WIDTH-1:0] seq_cntr = '0;

logic seq_cntr_0;
assign seq_cntr_0 = (seq_cntr[CNTR_WIDTH-1:0] == '0);

// delayed one cycle
logic seq_cntr_0_d1;
always_ff @(posedge clk) begin
  if( ~nrst) begin
    seq_cntr_0_d1 <= 0;
  end else begin
    seq_cntr_0_d1 <= seq_cntr_0;
  end
end

// first seq_cntr_0 cycle time belongs to pulse period
// second and further seq_cntr_0 cycles are idle
assign busy = ~(seq_cntr_0 && seq_cntr_0_d1);


// buffering cntr_low untill pulse period is over to allow continiously
//  changing inputs
logic [CNTR_WIDTH-1:0] cntr_low_buf = '0;
always_ff @(posedge clk) begin
  if( ~nrst ) begin
    seq_cntr[CNTR_WIDTH-1:0] <= '0;
    cntr_low_buf[CNTR_WIDTH-1:0] <= '0;
    start_strobe <= 1'b0;
  end else begin
    if( seq_cntr_0 ) begin
      // don`t start if cntr_max[] is illegal value
      if( start && (cntr_max[CNTR_WIDTH-1:0]!='0) ) begin
        seq_cntr[CNTR_WIDTH-1:0] <= cntr_max[CNTR_WIDTH-1:0];
        cntr_low_buf[CNTR_WIDTH-1:0] <= cntr_low[CNTR_WIDTH-1:0];
        start_strobe <= 1'b1;
      end else begin
        start_strobe <= 1'b0;
      end
    end else begin
      seq_cntr[CNTR_WIDTH-1:0] <= seq_cntr[CNTR_WIDTH-1:0] - 1'b1;
      start_strobe <= 1'b0;
    end
  end // ~nrst
end

always_comb begin
  if( ~nrst ) begin
    pulse_out <= 1'b0;
  end else begin
    // busy condition guarantees LOW output when idle
    if( busy &&
        (seq_cntr[CNTR_WIDTH-1:0] >= cntr_low_buf[CNTR_WIDTH-1:0]) ) begin
      pulse_out <= 1'b1;
    end else begin
      pulse_out <= 1'b0;
    end
  end // ~nrst
end


endmodule

