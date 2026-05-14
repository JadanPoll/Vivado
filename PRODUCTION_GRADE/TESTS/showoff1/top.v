// =============================================================================
// NIBBLE TO HEX
// =============================================================================
module nibble_to_hex (
    input  logic [3:0] nibble,
    output logic [7:0] hex
);
    always_comb begin
        case (nibble)
            4'b0000 : hex = 8'b00111111; // '0'
            4'b0001 : hex = 8'b00000110; // '1'
            4'b0010 : hex = 8'b01011011; // '2'
            4'b0011 : hex = 8'b01001111; // '3'
            4'b0100 : hex = 8'b01100110; // '4'
            4'b0101 : hex = 8'b01101101; // '5'
            4'b0110 : hex = 8'b01111101; // '6'
            4'b0111 : hex = 8'b00000111; // '7'
            4'b1000 : hex = 8'b01111111; // '8'
            4'b1001 : hex = 8'b01101111; // '9'
            4'b1010 : hex = 8'b01110111; // 'A'
            4'b1011 : hex = 8'b01111100; // 'b'
            4'b1100 : hex = 8'b00111001; // 'C'
            4'b1101 : hex = 8'b01011110; // 'd'
            4'b1110 : hex = 8'b01111001; // 'E'
            4'b1111 : hex = 8'b01110001; // 'F'
        endcase
    end
endmodule


// =============================================================================
// HEX DRIVER
// =============================================================================
module hex_driver (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] in,
    output logic [7:0]  hex_seg,
    output logic [3:0]  hex_grid
);

    logic [7:0] hex [4];

    // Yosys/nextpnr fix: Unrolled generate block to avoid $scopeinfo crashes
    nibble_to_hex nibble_to_hex_0 (.nibble(in[ 3: 0]), .hex(hex[0]));
    nibble_to_hex nibble_to_hex_1 (.nibble(in[ 7: 4]), .hex(hex[1]));
    nibble_to_hex nibble_to_hex_2 (.nibble(in[11: 8]), .hex(hex[2]));
    nibble_to_hex nibble_to_hex_3 (.nibble(in[15:12]), .hex(hex[3]));

    logic [16:0] counter;

    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= '0;
        end else begin
            counter <= counter + 1;
        end
    end

    always_comb begin
        if (reset) begin
            hex_grid = '1;
            hex_seg  = '1;
        end else begin
            case (counter[16:15])
                2'b00: begin
                    hex_seg  = ~hex[0];
                    hex_grid = 4'b1110;
                end
                2'b01: begin
                    hex_seg  = ~hex[1];
                    hex_grid = 4'b1101;
                end
                2'b10: begin
                    hex_seg  = ~hex[2];
                    hex_grid = 4'b1011;
                end
                2'b11: begin
                    hex_seg  = ~hex[3];
                    hex_grid = 4'b0111;
                end
            endcase
        end
    end

endmodule


// =============================================================================
// TOP LEVEL
// =============================================================================
module top (
    input  logic        clk,
    input  logic [3:0]  BTN,
    output logic [15:0] LED,
    output logic [2:0]  RGB0,
    output logic [2:0]  RGB1,
    output logic [3:0]  D0_AN,
    output logic [7:0]  D0_SEG,
    output logic [3:0]  D1_AN,
    output logic [7:0]  D1_SEG
);

    // BTN[0] = reset, BTN[1] = start/stop
    logic reset;
    logic run;
    assign reset = BTN[0];
    assign run   = BTN[1];  // high = running (hold or toggle as needed)

    // =========================================================================
    // 1. MASTER CLOCK DIVIDERS (100MHz base)
    // =========================================================================

    // 100 Hz tick  (period = 1,000,000 cycles)
    logic [19:0] cnt_100Hz;
    logic        tick_100Hz;

    always_ff @(posedge clk) begin
        if (reset) begin
            cnt_100Hz  <= '0;
            tick_100Hz <= 1'b0;
        end else if (cnt_100Hz == 20'd999_999) begin
            cnt_100Hz  <= '0;
            tick_100Hz <= 1'b1;
        end else begin
            cnt_100Hz  <= cnt_100Hz + 1;
            tick_100Hz <= 1'b0;
        end
    end

    // 50 Hz tick  (period = 2,000,000 cycles)
    logic [20:0] cnt_50Hz;
    logic        tick_50Hz;

    always_ff @(posedge clk) begin
        if (reset) begin
            cnt_50Hz  <= '0;
            tick_50Hz <= 1'b0;
        end else if (cnt_50Hz == 21'd1_999_999) begin
            cnt_50Hz  <= '0;
            tick_50Hz <= 1'b1;
        end else begin
            cnt_50Hz  <= cnt_50Hz + 1;
            tick_50Hz <= 1'b0;
        end
    end

    // =========================================================================
    // 2. STOPWATCH BCD COUNTERS (HH:MM:SS.cs)
    //    Only advances when run=1 (BTN[1] held high).
    // =========================================================================
    logic [3:0] cs0, cs1, s0, s1, m0, m1, h0, h1;

    always_ff @(posedge clk) begin
        if (reset) begin
            cs0 <= 4'd0; cs1 <= 4'd0;
            s0  <= 4'd0; s1  <= 4'd0;
            m0  <= 4'd0; m1  <= 4'd0;
            h0  <= 4'd0; h1  <= 4'd0;
        end else if (tick_100Hz && run) begin
            // centiseconds units
            if (cs0 == 4'd9) begin
                cs0 <= 4'd0;
                // centiseconds tens
                if (cs1 == 4'd9) begin
                    cs1 <= 4'd0;
                    // seconds units
                    if (s0 == 4'd9) begin
                        s0 <= 4'd0;
                        // seconds tens (0-5)
                        if (s1 == 4'd5) begin
                            s1 <= 4'd0;
                            // minutes units
                            if (m0 == 4'd9) begin
                                m0 <= 4'd0;
                                // minutes tens (0-5)
                                if (m1 == 4'd5) begin
                                    m1 <= 4'd0;
                                    // hours units
                                    if (h0 == 4'd9) begin
                                        h0 <= 4'd0;
                                        // hours tens (unconstrained — wraps at 16 naturally)
                                        h1 <= h1 + 4'd1;
                                    end else begin
                                        h0 <= h0 + 4'd1;
                                    end
                                end else begin
                                    m1 <= m1 + 4'd1;
                                end
                            end else begin
                                m0 <= m0 + 4'd1;
                            end
                        end else begin
                            s1 <= s1 + 4'd1;
                        end
                    end else begin
                        s0 <= s0 + 4'd1;
                    end
                end else begin
                    cs1 <= cs1 + 4'd1;
                end
            end else begin
                cs0 <= cs0 + 4'd1;
            end
        end
    end

    // =========================================================================
    // 3. HEX DISPLAY DRIVERS
    // =========================================================================

    // Display 0: SS.cs  (digit order: s1, s0, cs1, cs0)
    logic [15:0] d0_in;
    assign d0_in = {s1, s0, cs1, cs0};

    hex_driver disp0 (
        .clk     (clk),
        .reset   (reset),
        .in      (d0_in),
        .hex_seg (D0_SEG),
        .hex_grid(D0_AN)
    );

    // Display 1: HH:MM  (digit order: h1, h0, m1, m0)
    logic [15:0] d1_in;
    assign d1_in = {h1, h0, m1, m0};

    hex_driver disp1 (
        .clk     (clk),
        .reset   (reset),
        .in      (d1_in),
        .hex_seg (D1_SEG),
        .hex_grid(D1_AN)
    );

    // =========================================================================
    // 4. CYLON SCANNER
    // =========================================================================
    logic [15:0] shift_reg;
    logic        scan_dir;

    always_ff @(posedge clk) begin
        if (reset) begin
            shift_reg <= 16'h0001;
            scan_dir  <= 1'b0;
        end else if (tick_50Hz) begin
            if (scan_dir == 1'b0) begin
                // Shifting left
                if (shift_reg == 16'h8000) begin
                    scan_dir  <= 1'b1;
                    shift_reg <= shift_reg >> 1;
                end else begin
                    shift_reg <= shift_reg << 1;
                end
            end else begin
                // Shifting right
                if (shift_reg == 16'h0001) begin
                    scan_dir  <= 1'b0;
                    shift_reg <= shift_reg << 1;
                end else begin
                    shift_reg <= shift_reg >> 1;
                end
            end
        end
    end

    assign LED = shift_reg;

    // =========================================================================
    // 5. BREATHING RGB (PWM)
    // =========================================================================
    logic [7:0]  pwm_counter;
    logic [7:0]  brightness;
    logic        breathe_dir;
    logic [15:0] breathe_tick;

    always_ff @(posedge clk) begin
        if (reset) begin
            pwm_counter  <= 8'd0;
            brightness   <= 8'd0;
            breathe_dir  <= 1'b0;
            breathe_tick <= 16'd0;
        end else begin
            pwm_counter  <= pwm_counter + 8'd1;
            breathe_tick <= breathe_tick + 16'd1;

            if (breathe_tick == 16'hFFFF) begin
                if (breathe_dir == 1'b0) begin
                    brightness <= brightness + 8'd1;
                    if (brightness == 8'd254) breathe_dir <= 1'b1;
                end else begin
                    brightness <= brightness - 8'd1;
                    if (brightness == 8'd1) breathe_dir <= 1'b0;
                end
            end
        end
    end

    // RGB0: breathes Blue
    assign RGB0[0] = 1'b0;
    assign RGB0[1] = 1'b0;
    assign RGB0[2] = (pwm_counter < brightness) ? 1'b1 : 1'b0;

    // RGB1: breathes Pink/Purple (Red + Blue)
    assign RGB1[0] = (pwm_counter < brightness) ? 1'b1 : 1'b0;
    assign RGB1[1] = 1'b0;
    assign RGB1[2] = (pwm_counter < brightness) ? 1'b1 : 1'b0;

endmodule