// ZeroLabs: UART ↔ BLE Loopback
// UART_RXD  = B16  (data coming IN to FPGA from USB-UART chip TX)
// UART_TXD  = A16  (data going OUT from FPGA to USB-UART chip RX)
// BLE_UART_RXD = E13 (data coming IN to FPGA from BLE chip TX)
// BLE_UART_TXD = G15 (data going OUT from FPGA to BLE chip RX)
//
// Topology:
//   UART_TXD  = UART_RXD & BLE_RXD   (wired-AND = open-drain: either pulls low)
//   BLE_TXD   = UART_RXD & BLE_RXD   (same — both see everything)
//
// So: whatever the PC sends arrives at BLE, whatever BLE sends arrives at PC.
// The FPGA is purely a wire with an AND gate.

module top (
    input  logic clk,           // N15 — not needed but avoids undriven warnings
    input  logic UART_RXD,      // B16 — from PC
    output logic UART_TXD,      // A16 — to PC
    input  logic BLE_UART_RXD,  // E13 — from BLE chip
    output logic BLE_UART_TXD,  // G15 — to BLE chip
    output logic [15:0] LED     // heartbeat so we can see activity
);
    // Wired-AND: either side pulling low = low on both
    assign UART_TXD   = UART_RXD & BLE_UART_RXD;
    assign BLE_UART_TXD = UART_RXD & BLE_UART_RXD;

    // Activity LED — blink when line is pulled low (data flying)
    logic [23:0] act_cnt = 0;
    wire         activity = ~UART_RXD | ~BLE_UART_RXD;

    always_ff @(posedge clk) begin
        if (activity)
            act_cnt <= 24'hFFFFFF;   // hold bright
        else if (act_cnt > 0)
            act_cnt <= act_cnt - 1;  // fade out
    end

    assign LED[0]    = act_cnt[23];   // activity on LED0
    assign LED[1]    = ~UART_RXD;     // PC line live
    assign LED[2]    = ~BLE_UART_RXD; // BLE line live
    assign LED[15:3] = 0;

endmodule