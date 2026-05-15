// ZeroLabs: UART ↔ BLE Loopback
// UART_TXD  = B16  (IN  — USB-UART chip transmits, FPGA receives)
// UART_RXD  = A16  (OUT — USB-UART chip receives, FPGA transmits)
// BLE_UART_TXD = E13 (IN  — BLE chip transmits, FPGA receives)
// BLE_UART_RXD = G15 (OUT — BLE chip receives, FPGA transmits)

module top (
    input  logic clk,
    input  logic UART_TXD,      // B16 — from PC
    output logic UART_RXD,      // A16 — to PC
    input  logic BLE_UART_TXD,  // E13 — from BLE
    output logic BLE_UART_RXD,  // G15 — to BLE
    output logic [15:0] LED
);
    // Wired-AND: either pulling low = low on both outputs
    assign UART_RXD     = UART_TXD & BLE_UART_TXD;
    assign BLE_UART_RXD = UART_TXD & BLE_UART_TXD;

    logic [23:0] act_cnt = 0;
    wire activity = ~UART_TXD | ~BLE_UART_TXD;

    always_ff @(posedge clk) begin
        if (activity)
            act_cnt <= 24'hFFFFFF;
        else if (act_cnt > 0)
            act_cnt <= act_cnt - 1;
    end

    assign LED[0]    = act_cnt[23];
    assign LED[1]    = ~UART_TXD;
    assign LED[2]    = ~BLE_UART_TXD;
    assign LED[15:3] = 0;
endmodule