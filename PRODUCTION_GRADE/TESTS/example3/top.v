// ZeroLabs: Hex Display Showcase — Scrolling Message + Counter
// Primitives: BUFG
// D1 = scrolling "ZEro LABS" message
// D0 = live millisecond timer (resets at 9999)
// BTN[0] = reset timer
// BTN[1] = pause scroll

module top (
    input  logic        clk,
    input  logic [3:0]  BTN,
    output logic [3:0]  D0_AN,
    output logic [7:0]  D0_SEG,
    output logic [3:0]  D1_AN,
    output logic [7:0]  D1_SEG,
    output logic [15:0] LED
);
    wire clk_g;
    BUFG u_bufg (.I(clk), .O(clk_g));

    // ────────────────────────────────────────────────────────────────────
    // Segment encoding — active HIGH (inverted at output)
    // Standard 7-seg: segment order = gfedcba
    //
    //  Verified codes:
    //   0=3F  1=06  2=5B  3=4F  4=66  5=6D  6=7D  7=07
    //   8=7F  9=6F  A=77  b=7C  C=39  d=5E  E=79  F=71
    //   L=38  o=5C  r=50  H=76  Z=6B  S=6D  _=08  -=40
    //   blank=00
    // ────────────────────────────────────────────────────────────────────

    function automatic [7:0] seg7(input logic [3:0] n);
        case (n)
            4'h0: seg7 = 8'h3F;
            4'h1: seg7 = 8'h06;
            4'h2: seg7 = 8'h5B;
            4'h3: seg7 = 8'h4F;
            4'h4: seg7 = 8'h66;
            4'h5: seg7 = 8'h6D;
            4'h6: seg7 = 8'h7D;
            4'h7: seg7 = 8'h07;
            4'h8: seg7 = 8'h7F;
            4'h9: seg7 = 8'h6F;
            4'ha: seg7 = 8'h77;
            4'hb: seg7 = 8'h7C;
            4'hc: seg7 = 8'h39;
            4'hd: seg7 = 8'h5E;
            4'he: seg7 = 8'h79;
            4'hf: seg7 = 8'h71;
        endcase
    endfunction

    // ────────────────────────────────────────────────────────────────────
    // Scrolling message ROM
    // Message: " ZEro LABS " (with leading/trailing blanks for clean scroll)
    // Each entry is a raw segment byte
    //
    //  Z=6B  E=79  r=50  o=5C  blank=00
    //  L=38  A=77  b=7C  S=6D
    // ────────────────────────────────────────────────────────────────────

    localparam MSG_LEN = 12;
    logic [7:0] msg [0:MSG_LEN-1];

    initial begin
        msg[ 0] = 8'h00; // blank
        msg[ 1] = 8'h6B; // Z
        msg[ 2] = 8'h79; // E
        msg[ 3] = 8'h50; // r
        msg[ 4] = 8'h5C; // o
        msg[ 5] = 8'h00; // blank
        msg[ 6] = 8'h38; // L
        msg[ 7] = 8'h77; // A
        msg[ 8] = 8'h7C; // b
        msg[ 9] = 8'h6D; // S
        msg[10] = 8'h00; // blank
        msg[11] = 8'h00; // blank
    end

    // ────────────────────────────────────────────────────────────────────
    // Scroll tick — shifts message every ~200ms
    // ────────────────────────────────────────────────────────────────────

    logic [23:0] scroll_div = 0;
    logic        scroll_tick;
    logic [3:0]  scroll_pos = 0;

    // Debounce BTN[1] pause
    logic [19:0] db1 = 0;
    logic        b1_prev = 0, paused = 0;

    always_ff @(posedge clk_g) begin
        db1    <= db1 + 1;
        b1_prev <= BTN[1];
        if (db1 == 0 && BTN[1] && !b1_prev)
            paused <= ~paused;
    end

    always_ff @(posedge clk_g) begin
        scroll_tick <= 0;
        if (!paused) begin
            scroll_div <= scroll_div + 1;
            if (scroll_div == 24'd19_999_999) begin  // 5 Hz scroll
                scroll_div  <= 0;
                scroll_tick <= 1;
            end
        end
    end

    always_ff @(posedge clk_g) begin
        if (BTN[0])         scroll_pos <= 0;
        else if (scroll_tick) begin
            if (scroll_pos == MSG_LEN - 1) scroll_pos <= 0;
            else                           scroll_pos <= scroll_pos + 1;
        end
    end

    // 4 visible digits — window into message ring
    function automatic [3:0] wrap(input logic [3:0] base, input int offset);
        wrap = (base + offset) % MSG_LEN;
    endfunction

    wire [7:0] d1_dig3 = msg[wrap(scroll_pos, 0)];
    wire [7:0] d1_dig2 = msg[wrap(scroll_pos, 1)];
    wire [7:0] d1_dig1 = msg[wrap(scroll_pos, 2)];
    wire [7:0] d1_dig0 = msg[wrap(scroll_pos, 3)];

    // ────────────────────────────────────────────────────────────────────
    // Millisecond timer on D0 — BCD, resets at 9999
    // ────────────────────────────────────────────────────────────────────

    logic [16:0] ms_div = 0;
    logic        ms_tick;

    always_ff @(posedge clk_g) begin
        ms_tick <= 0;
        ms_div  <= ms_div + 1;
        if (ms_div == 17'd99_999) begin  // 1 kHz
            ms_div  <= 0;
            ms_tick <= 1;
        end
    end

    // BCD digits
    logic [3:0] ms0 = 0, ms1 = 0, ms2 = 0, ms3 = 0;

    always_ff @(posedge clk_g) begin
        if (BTN[0]) begin
            ms0 <= 0; ms1 <= 0; ms2 <= 0; ms3 <= 0;
        end else if (ms_tick) begin
            if (ms0 == 9) begin ms0 <= 0;
                if (ms1 == 9) begin ms1 <= 0;
                    if (ms2 == 9) begin ms2 <= 0;
                        if (ms3 == 9) ms3 <= 0;
                        else          ms3 <= ms3 + 1;
                    end else ms2 <= ms2 + 1;
                end else ms1 <= ms1 + 1;
            end else ms0 <= ms0 + 1;
        end
    end

    assign LED = {ms3, ms2, ms1, ms0};

    // ────────────────────────────────────────────────────────────────────
    // Multiplexed scan — both displays, same counter
    // scan[16:15] → ~763 Hz per digit
    // ────────────────────────────────────────────────────────────────────

    logic [16:0] scan = 0;
    always_ff @(posedge clk_g) scan <= scan + 1;

    always_comb begin
        case (scan[16:15])
            2'b00: begin
                D0_AN  = 4'b1110; D0_SEG = ~seg7(ms0);
                D1_AN  = 4'b1110; D1_SEG = ~d1_dig0;
            end
            2'b01: begin
                D0_AN  = 4'b1101; D0_SEG = ~seg7(ms1);
                D1_AN  = 4'b1101; D1_SEG = ~d1_dig1;
            end
            2'b10: begin
                D0_AN  = 4'b1011; D0_SEG = ~seg7(ms2);
                D1_AN  = 4'b1011; D1_SEG = ~d1_dig2;
            end
            2'b11: begin
                D0_AN  = 4'b0111; D0_SEG = ~seg7(ms3);
                D1_AN  = 4'b0111; D1_SEG = ~d1_dig3;
            end
        endcase
    end

endmodule