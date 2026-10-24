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
    // Preserve the Urbana USB-UART <-> BLE bridge while the stopwatch runs.
    input  logic        UART_TXD,
    output logic        UART_RXD,
    input  logic        BLE_UART_TXD,
    output logic        BLE_UART_RXD,
    output logic [15:0] LED,
    output logic [2:0]  RGB0,
    output logic [2:0]  RGB1,
    output logic [3:0]  D0_AN,
    output logic [7:0]  D0_SEG,
    output logic [3:0]  D1_AN,
    output logic [7:0]  D1_SEG
);


    // BLE module: 115200 baud, 8N1; newline commits a wireless packet.
    // USB terminal continues to receive data arriving from Bluetooth.
    assign UART_RXD=BLE_UART_TXD;
    localparam integer BIT_CLOCKS=868; // 100 MHz / 115200 rounded
    (* ASYNC_REG="TRUE" *) reg rx_meta=1,rx_sync=1;
    always @(posedge clk) begin rx_meta<=BLE_UART_TXD;rx_sync<=rx_meta;end
    reg [9:0] rx_timer=0;
    reg [3:0] rx_index=0;
    reg [7:0] rx_data=0,rx_value=0;
    reg rx_active=0,rx_done=0;
    always @(posedge clk) begin
      rx_done<=0;
      if(!rx_active) begin
        if(!rx_sync) begin rx_active<=1;rx_timer<=BIT_CLOCKS/2-1;rx_index<=0;end
      end else if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
      else begin
        rx_timer<=BIT_CLOCKS-1;
        if(rx_index==0) begin
          if(rx_sync) rx_active<=0;
          else rx_index<=1;
        end else if(rx_index<=8) begin
          rx_data[rx_index-1'b1]<=rx_sync;rx_index<=rx_index+1'b1;
        end else begin
          rx_active<=0;
          if(rx_sync) begin rx_value<=rx_data;rx_done<=1;end
        end
      end
    end

    // First character determines command; CR ignored, LF executes.
    // BTN[1] toggles run; UART s/p/r commands override physical button.
    reg [7:0] command_first=0;
    reg command_pending=0;
    reg start_pulse=0,pause_pulse=0,reset_pulse=0;
    reg running=0,button_prev=0;
    reg [2:0] request=0;
    reg [95:0] time_snapshot = "00:00:00.00\n";
    wire reset=BTN[0] | reset_pulse;
    wire run=running;
    always @(posedge clk) begin
      start_pulse<=0;pause_pulse<=0;reset_pulse<=0;request<=0;
      button_prev<=BTN[1];
      if(BTN[0] || reset_pulse || pause_pulse) running<=0;
      else if(start_pulse) running<=1;
      else if(BTN[1] && !button_prev) running<=~running;
      if(rx_done) begin
        if(rx_value==8'h0a) begin
          if(command_pending) begin
            case(command_first)
              "s","S":begin start_pulse<=1;request<=1;end
              "p","P":begin pause_pulse<=1;request<=2;end
              "r","R":begin reset_pulse<=1;request<=3;end
              "h","H","?":request<=4;
              "t","T": begin
                time_snapshot <= {8'h30+h1,8'h30+h0,8'h3a,8'h30+m1,8'h30+m0,8'h3a,8'h30+s1,8'h30+s0,8'h2e,8'h30+cs1,8'h30+cs0,8'h0a};
                request<=6;
              end
              default:request<=5;
            endcase
          end
          command_pending<=0;
        end else if(rx_value!=8'h0d && !command_pending) begin
          command_first<=rx_value;command_pending<=1;
        end
      end
    end

    localparam [71:0] MSG1 = "OK START\n";
    localparam [71:0] MSG2 = "OK PAUSE\n";
    localparam [71:0] MSG3 = "OK RESET\n";
    localparam [303:0] MSG4 = "s start p pause r reset h help t time\n";
    localparam [63:0] MSG5 = "UNKNOWN\n";
    function automatic [7:0] reply_byte(input [2:0] kind,input [5:0] pos);
      begin case(kind)
        1: reply_byte=MSG1[8*(9-pos)-1 -: 8];
        2: reply_byte=MSG2[8*(9-pos)-1 -: 8];
        3: reply_byte=MSG3[8*(9-pos)-1 -: 8];
        4: reply_byte=MSG4[8*(38-pos)-1 -: 8];
        6: reply_byte=time_snapshot[8*(12-pos)-1 -: 8];
        5: reply_byte=MSG5[8*(8-pos)-1 -: 8];
        default:reply_byte=8'h0a;
      endcase end
    endfunction
    function automatic [5:0] reply_len(input [2:0] kind);
      begin case(kind)
        1: reply_len=9;
        2: reply_len=9;
        3: reply_len=9;
        4: reply_len=38;
        6: reply_len=12;
        5: reply_len=8;
        default:reply_len=0;
      endcase end
    endfunction
    // Direct UART transmitter; response overrides USB->BLE passthrough.
    reg [2:0] response=0;
    reg [5:0] response_pos=0;
    reg [9:0] tx_shift=10'h3ff,tx_timer=0;
    reg [3:0] tx_bits=0;
    reg tx_active=0,tx_pin=1;
    assign BLE_UART_RXD=(response!=0 || tx_active)?tx_pin:UART_TXD;
    always @(posedge clk) begin
      if(request!=0 && response==0 && !tx_active) begin
        response<=request;response_pos<=0;
      end
      if(tx_active) begin
        if(tx_timer!=0) tx_timer<=tx_timer-1'b1;
        else begin
          tx_timer<=BIT_CLOCKS-1;
          if(tx_bits==1) begin
            tx_bits<=0;tx_active<=0;tx_pin<=1;
          end else begin
            tx_bits<=tx_bits-1'b1;
            tx_shift<={1'b1,tx_shift[9:1]};
            tx_pin<=tx_shift[1];
          end
        end
      end else if(response!=0) begin
        if(response_pos==reply_len(response)) begin response<=0;tx_pin<=1;end
        else begin
          tx_shift<={1'b1,reply_byte(response,response_pos),1'b0};
          tx_pin<=0;tx_timer<=BIT_CLOCKS-1;tx_bits<=10;
          tx_active<=1;response_pos<=response_pos+1'b1;
        end
      end
    end

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
                                    if (h0 == 4'd9) begin
                                        h0 <= 4'd0;
                                        // The external HH display and UART time response
                                        // both contain decimal digits, so roll 99 -> 00.
                                        if (h1 == 4'd9) h1 <= 4'd0;
                                        else h1 <= h1 + 4'd1;
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
        .in({h1, h0, m1, m0}),
        .hex_seg(D0_SEG), .hex_grid(D0_AN)
    );

    hex_driver disp1 (
        .clk(clk), .reset(reset),
        .in({s1, s0, cs1, cs0}),
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