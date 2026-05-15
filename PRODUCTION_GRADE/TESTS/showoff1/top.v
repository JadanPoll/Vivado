// =============================================================================
// HEX DRIVER
// nibble_to_hex is inlined as a function to avoid Yosys $scopeinfo injection.
// Any named sub-module instance inside a hierarchy causes nextpnr-xilinx to
// crash with "no BELs remaining for $scopeinfo" — inlining eliminates the issue
// entirely without needing the 'flatten' workaround in the Yosys script.
// =============================================================================
module hex_driver (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] in,       // packed: in[15:12]=d3, [11:8]=d2, [7:4]=d1, [3:0]=d0
    output logic [7:0]  hex_seg,
    output logic [3:0]  hex_grid
);

    // Inline nibble->7-segment decode (was nibble_to_hex module)
    function automatic [7:0] nibble_to_seg(input logic [3:0] n);
        case (n)
            4'h0: nibble_to_seg = 8'b00111111;
            4'h1: nibble_to_seg = 8'b00000110;
            4'h2: nibble_to_seg = 8'b01011011;
            4'h3: nibble_to_seg = 8'b01001111;
            4'h4: nibble_to_seg = 8'b01100110;
            4'h5: nibble_to_seg = 8'b01101101;
            4'h6: nibble_to_seg = 8'b01111101;
            4'h7: nibble_to_seg = 8'b00000111;
            4'h8: nibble_to_seg = 8'b01111111;
            4'h9: nibble_to_seg = 8'b01101111;
            4'ha: nibble_to_seg = 8'b01110111;
            4'hb: nibble_to_seg = 8'b01111100;
            4'hc: nibble_to_seg = 8'b00111001;
            4'hd: nibble_to_seg = 8'b01011110;
            4'he: nibble_to_seg = 8'b01111001;
            4'hf: nibble_to_seg = 8'b01110001;
        endcase
    endfunction

    logic [16:0] counter;

    always_ff @(posedge clk) begin
        if (reset) counter <= '0;
        else       counter <= counter + 1;
    end

    always_comb begin
        if (reset) begin
            hex_grid = '1;
            hex_seg  = '1;
        end else begin
            case (counter[16:15])
                2'b00: begin hex_seg = ~nibble_to_seg(in[ 3: 0]); hex_grid = 4'b1110; end
                2'b01: begin hex_seg = ~nibble_to_seg(in[ 7: 4]); hex_grid = 4'b1101; end
                2'b10: begin hex_seg = ~nibble_to_seg(in[11: 8]); hex_grid = 4'b1011; end
                2'b11: begin hex_seg = ~nibble_to_seg(in[15:12]); hex_grid = 4'b0111; end
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
    logic reset, run;
    assign reset = BTN[0];
    assign run   = BTN[1];

    // =========================================================================
    // 1. CLOCK DIVIDERS
    // =========================================================================

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
    // =========================================================================
    logic [3:0] cs0, cs1, s0, s1, m0, m1, h0, h1;

    always_ff @(posedge clk) begin
        if (reset) begin
            cs0 <= 4'd0; cs1 <= 4'd0;
            s0  <= 4'd0; s1  <= 4'd0;
            m0  <= 4'd0; m1  <= 4'd0;
            h0  <= 4'd0; h1  <= 4'd0;
        end else if (tick_100Hz && run) begin
            if (cs0 == 4'd9) begin cs0 <= 4'd0;
                if (cs1 == 4'd9) begin cs1 <= 4'd0;
                    if (s0 == 4'd9) begin s0 <= 4'd0;
                        if (s1 == 4'd5) begin s1 <= 4'd0;
                            if (m0 == 4'd9) begin m0 <= 4'd0;
                                if (m1 == 4'd5) begin m1 <= 4'd0;
                                    if (h0 == 4'd9) begin h0 <= 4'd0; h1 <= h1 + 4'd1;
                                    end else h0 <= h0 + 4'd1;
                                end else m1 <= m1 + 4'd1;
                            end else m0 <= m0 + 4'd1;
                        end else s1 <= s1 + 4'd1;
                    end else s0 <= s0 + 4'd1;
                end else cs1 <= cs1 + 4'd1;
            end else cs0 <= cs0 + 4'd1;
        end
    end

    // =========================================================================
    // 3. HEX DISPLAY DRIVERS
    // =========================================================================

    hex_driver disp0 (
        .clk(clk), .reset(reset),
        .in({s1, s0, cs1, cs0}),
        .hex_seg(D0_SEG), .hex_grid(D0_AN)
    );

    hex_driver disp1 (
        .clk(clk), .reset(reset),
        .in({h1, h0, m1, m0}),
        .hex_seg(D1_SEG), .hex_grid(D1_AN)
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
                if (shift_reg == 16'h8000) begin scan_dir <= 1'b1; shift_reg <= shift_reg >> 1;
                end else shift_reg <= shift_reg << 1;
            end else begin
                if (shift_reg == 16'h0001) begin scan_dir <= 1'b0; shift_reg <= shift_reg << 1;
                end else shift_reg <= shift_reg >> 1;
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

    assign RGB0[0] = 1'b0;
    assign RGB0[1] = 1'b0;
    assign RGB0[2] = (pwm_counter < brightness) ? 1'b1 : 1'b0;

    assign RGB1[0] = (pwm_counter < brightness) ? 1'b1 : 1'b0;
    assign RGB1[1] = 1'b0;
    assign RGB1[2] = (pwm_counter < brightness) ? 1'b1 : 1'b0;

endmodule