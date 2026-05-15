// ZeroLabs: LED Ring + Clocking Showcase
// Primitives: BUFG, BUFR, BUFGCE
// BTN[0] = reset
// BTN[1] = cycle mode (ring / chase / binary / bounce)
// SW[0]  = freeze (BUFGCE gate)
// SW[1]  = speed select

module top (
    input  logic        clk,
    input  logic [3:0]  BTN,
    input  logic [15:0] SW,
    output logic [15:0] LED,
    output logic [2:0]  RGB0,
    output logic [2:0]  RGB1
);

    // ────────────────────────────────────────────────────────────────────
    // 1. Clocking — BUFG → BUFGCE (gateable) → BUFR (divided)
    // ────────────────────────────────────────────────────────────────────

    wire clk_g;
    BUFG u_bufg (.I(clk), .O(clk_g));

    // BUFGCE: SW[0] freezes all animation
    wire clk_gce;
    BUFGCE #(.SIM_DEVICE("7SERIES")) u_bufgce (
        .I(clk_g), .CE(~SW[0]), .O(clk_gce)
    );

    // BUFR: divide by 8 for a slow independent clock domain
    wire clk_slow;
    BUFR #(.BUFR_DIVIDE("8"), .SIM_DEVICE("7SERIES")) u_bufr (
        .I(clk_g), .CE(1'b1), .CLR(1'b0), .O(clk_slow)
    );

    // ────────────────────────────────────────────────────────────────────
    // 2. Tick generators — fast and slow rates, SW[1] selects
    // ────────────────────────────────────────────────────────────────────

    logic [24:0] div = 0;
    logic        tick_fast, tick_slow;

    always_ff @(posedge clk_gce) begin
        div       <= div + 1;
        tick_fast <= (div == 25'd1_562_499);   // 64 Hz
        tick_slow <= (div == 25'd12_499_999);  // 8 Hz
        if (div == 25'd12_499_999) div <= 0;
    end

    wire tick = SW[1] ? tick_fast : tick_slow;

    // ────────────────────────────────────────────────────────────────────
    // 3. Mode select — BTN[1] cycles 0→1→2→3→0
    // ────────────────────────────────────────────────────────────────────

    logic [19:0] db = 0;
    logic        b1_prev = 0, pulse_mode = 0;

    always_ff @(posedge clk_g) begin
        db     <= db + 1;
        b1_prev <= BTN[1];
        pulse_mode <= 0;
        if (db == 0 && BTN[1] && !b1_prev) pulse_mode <= 1;
    end

    logic [1:0] mode = 0;
    always_ff @(posedge clk_g) begin
        if (BTN[0])         mode <= 0;
        else if (pulse_mode) mode <= mode + 1;
    end

    // ────────────────────────────────────────────────────────────────────
    // 4. LED patterns
    // ────────────────────────────────────────────────────────────────────

    // mode 0: single rotating ring (one hot)
    logic [15:0] ring = 16'h0001;
    always_ff @(posedge clk_gce) begin
        if (BTN[0])   ring <= 16'h0001;
        else if (tick) ring <= {ring[14:0], ring[15]};
    end

    // mode 1: chase — 4-wide window rotating
    logic [15:0] chase = 16'h000F;
    always_ff @(posedge clk_gce) begin
        if (BTN[0])    chase <= 16'h000F;
        else if (tick)  chase <= {chase[14:0], chase[15]};
    end

    // mode 2: binary counter on LEDs (clk_slow domain via BUFR)
    logic [15:0] bincount = 0;
    always_ff @(posedge clk_slow) begin
        if (BTN[0]) bincount <= 0;
        else        bincount <= bincount + 1;
    end

    // mode 3: bounce — ping-pong single LED
    logic [3:0] pos = 0;
    logic       dir = 0;
    always_ff @(posedge clk_gce) begin
        if (BTN[0]) begin
            pos <= 0; dir <= 0;
        end else if (tick) begin
            if (!dir) begin
                if (pos == 15) begin dir <= 1; pos <= pos - 1; end
                else pos <= pos + 1;
            end else begin
                if (pos == 0)  begin dir <= 0; pos <= pos + 1; end
                else pos <= pos - 1;
            end
        end
    end

    logic [15:0] bounce;
    always_comb begin
        bounce = 0;
        bounce[pos] = 1;
    end

    // ────────────────────────────────────────────────────────────────────
    // 5. Output mux
    // ────────────────────────────────────────────────────────────────────

    always_comb begin
        case (mode)
            2'd0: LED = ring;
            2'd1: LED = chase;
            2'd2: LED = bincount;
            2'd3: LED = bounce;
        endcase
    end

    // RGB0 = mode indicator, RGB1 = freeze/speed status
    assign RGB0 = {1'b0, mode};
    assign RGB1 = {1'b0, SW[1], SW[0]};

endmodule