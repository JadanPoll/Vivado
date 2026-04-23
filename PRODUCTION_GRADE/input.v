module zero_soc (
    input clk,
    input rst_n,           // We will use this to toggle all segments
    input [15:0] sw,       // Slide switches
    output [15:0] led,     // On-board LEDs
    output [7:0] hex_seg,  // Hex Segments
    output [3:0] hex_grid  // Digit Select
);
    // Wire the first 16 switches directly to the 16 LEDs
    assign led = sw;

    // Use the Reset button to test segments
    // On Urbana, segments are Active LOW. 
    // If rst_n (BTN0) is pressed, all segments turn ON.
    assign hex_seg = rst_n ? 8'hFF : 8'h00; 

    // Enable all 4 digits of the first hex display (Active LOW)
    assign hex_grid = 4'b0000; 
endmodule
