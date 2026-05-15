#!/usr/bin/env python3
"""
gen_verilog.py — Verilog template generator for ZeroLabs FPGA fuzzing suite.
Target: Xilinx Spartan-7 XC7S50CSGA324-1 (Urbana board)
Pins: clk=N15, out=C13, out2=C14

Each generator returns (verilog_str, xdc_str).
Anti-pruning strategy: counters/shift registers feed all data inputs;
XOR-reduce bus outputs to single `out`.
"""

import json
import itertools
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _xor_reduce(sig, width):
    """Return a Verilog expression XOR-reducing `sig[width-1:0]`."""
    if width == 1:
        return sig
    return "^" + sig


def _counter_chain(n_bits=32):
    """Return always block + reg declaration for an n-bit free-running counter."""
    return (
        f"    reg [{n_bits-1}:0] cnt = 0;\n"
        f"    always @(posedge clk) cnt <= cnt + 1;\n"
    )


BASE_XDC = """\
set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 10.000 -name sys_clk [get_ports clk]
"""

ISERDES_XDC = """set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN M16 [get_ports din_pad]
set_property IOSTANDARD LVCMOS33 [get_ports din_pad]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 10.000 -name sys_clk [get_ports clk]
"""


def _diff_out_xdc(iostd):
    if "SSTL135" in iostd:
        p_pin, n_pin = "R5", "T4"    # bank 34, 1.35V
    elif "TMDS" in iostd:
        p_pin, n_pin = "U17", "U18"  # HDMI_D0_P/N, bank 33, 3.3V
    else:
        p_pin, n_pin = "F14", "F15"  # JA1_P/N, bank 34, 2.5V
    return f"""\
set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]
set_property PACKAGE_PIN {p_pin} [get_ports out_p]
set_property PACKAGE_PIN {n_pin} [get_ports out_n]
set_property IOSTANDARD {iostd} [get_ports out_p]
set_property IOSTANDARD {iostd} [get_ports out_n]
"""



# ---------------------------------------------------------------------------
# Validity guards
# ---------------------------------------------------------------------------

def _check_vco(mult_f, period, divclk=1):
    vco = mult_f * 1000.0 / (period * divclk)
    if not (600.0 <= vco <= 1200.0):
        raise ValueError(
            f"VCO={vco:.1f} MHz out of range 600-1200 MHz "
            f"(MULT_F={mult_f}, PERIOD={period}, DIVCLK={divclk})"
        )
    return vco


def _check_oserdes_width(data_rate, data_width):
    # UG953 p.507: SDR valid = 2,3,4,5,6,7,8; DDR valid = 4,6,8,10,14
    # Exclude DDR 10/14: require MASTER+SLAVE cascade (separate generator)
    if data_rate == "DDR" and data_width not in (4, 6, 8):
        raise ValueError(
            f"OSERDESE2 DDR MASTER-only requires DATA_WIDTH in {{4,6,8}}, got {data_width}"
        )
    if data_rate == "SDR" and data_width not in (2, 3, 4, 5, 6, 7, 8):
        raise ValueError(
            f"OSERDESE2 SDR requires DATA_WIDTH 2-8, got {data_width}"
        )


def _check_idelay_value(v):
    if not (0 <= int(v) <= 31):
        raise ValueError(f"IDELAY_VALUE must be 0-31, got {v}")


def _check_ramb_widths(primitive, rw_a, ww_a, rw_b, ww_b):
    valid = {1, 2, 4, 9, 18} if "18" in primitive else {1, 2, 4, 9, 18, 36}
    for w in (rw_a, ww_a, rw_b, ww_b):
        if w not in valid:
            raise ValueError(f"{primitive} invalid width {w}, valid={valid}")


def _check_dsp(areg, breg, mreg, use_mult):
    if mreg == 1 and use_mult == "NONE":
        raise ValueError("DSP48E1: MREG=1 requires USE_MULT=MULTIPLY")


# ---------------------------------------------------------------------------
# Clock primitives
# ---------------------------------------------------------------------------

def generate_BUFIO(params):
    """BUFIO — IO clock buffer. Drives ILOGIC/OLOGIC only, not fabric.
    ISERDES must be in same clock region as BUFIO (same IO column)."""

    verilog = """\
module top (
    input  clk,
    input  din,
    output out
);
    wire clk_buf, clkdiv, q;
    BUFIO u_bufio (.I(clk), .O(clk_buf));
    BUFR #(.BUFR_DIVIDE("BYPASS"), .SIM_DEVICE("7SERIES")) u_bufr (.I(clk), .O(clkdiv), .CE(1'b1), .CLR(1'b0));
    (* keep = "true" *)
    ISERDESE2 #(
        .DATA_RATE("SDR"), .DATA_WIDTH(4),
        .INTERFACE_TYPE("NETWORKING"), .NUM_CE(1),
        .IOBDELAY("NONE"), .SERDES_MODE("MASTER"),
        .DYN_CLKDIV_INV_EN("FALSE"), .DYN_CLK_INV_EN("FALSE"),
        .OFB_USED("FALSE"),
        .INIT_Q1(1'b0), .INIT_Q2(1'b0), .INIT_Q3(1'b0), .INIT_Q4(1'b0),
        .SRVAL_Q1(1'b0), .SRVAL_Q2(1'b0), .SRVAL_Q3(1'b0), .SRVAL_Q4(1'b0)
    ) u_iserdes (
        .CLK(clk_buf), .CLKB(~clk_buf), .CLKDIV(clkdiv),
        .OCLK(1'b0), .OCLKB(1'b0),
        .CE1(1'b1), .CE2(1'b1), .RST(1'b0),
        .DYNCLKDIVSEL(1'b0), .DYNCLKSEL(1'b0),
        .D(din), .DDLY(), .OFB(1'b0), .BITSLIP(1'b0),
        .SHIFTIN1(), .SHIFTIN2(),
        .Q1(q), .Q2(), .Q3(), .Q4(), .Q5(), .Q6(), .Q7(), .Q8(),
        .SHIFTOUT1(), .SHIFTOUT2(), .O()
    );
    reg [7:0] cnt = 0;
    always @(posedge clkdiv) cnt <= cnt + q;
    assign out = ^cnt;
endmodule
"""

    xdc = BASE_XDC + """
set_property PACKAGE_PIN P16 [get_ports din]
set_property IOSTANDARD LVCMOS33 [get_ports din]
set_property LOC ILOGIC_X0Y26 [get_cells u_iserdes]
"""
    return verilog, xdc

def generate_BUFR(params):
    divide = params["BUFR_DIVIDE"]
    divide_str = f'"{divide}"'
    verilog = f"""\
module top (
    input  clk,
    output out
);
    wire clk_div;
    BUFR #(
        .BUFR_DIVIDE({divide_str}),
        .SIM_DEVICE("7SERIES")
    ) u_bufr (
        .I(clk),
        .CE(1'b1),
        .CLR(1'b0),
        .O(clk_div)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk_div) cnt <= cnt + 1;
    assign out = ^cnt;
endmodule
"""
    return verilog, BASE_XDC


def generate_BUFG(params):
    """BUFG — global clock buffer. No configuration registers."""
    verilog = """\
module top (
    input  clk,
    output out
);
    wire clk_g;
    BUFG u_bufg (
        .I(clk),
        .O(clk_g)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk_g) cnt <= cnt + 1;
    assign out = ^cnt;
endmodule
"""
    return verilog, BASE_XDC


def generate_BUFGCE(params):
    sim_dev = params.get("SIM_DEVICE", "7SERIES")
    verilog = f"""\
module top (
    input  clk,
    output out
);
    wire clk_g;
    (* clkbuf_inhibit *) wire clk_in;
    assign clk_in = clk;

    reg ce = 1;
    always @(posedge clk) ce <= ~ce;

    BUFGCE #(
        .SIM_DEVICE("{sim_dev}")
    ) u_bufgce (
        .I(clk_in),
        .CE(ce),
        .O(clk_g)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk_g) cnt <= cnt + 1;
    assign out = ^cnt;
endmodule
"""
    
    bufgce_xdc = BASE_XDC + "set_property LOC BUFGCTRL_X0Y1 [get_cells u_bufgce]\n"
    return verilog, bufgce_xdc

def generate_BUFH(params):
    """BUFH — horizontal clock buffer. No configuration registers."""
    verilog = """\
module top (
    input  clk,
    output out
);
    wire clk_h;
    BUFH u_bufh (
        .I(clk),
        .O(clk_h)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk_h) cnt <= cnt + 1;
    assign out = ^cnt;
endmodule
"""
    return verilog, BASE_XDC


def generate_BUFHCE(params):
    """BUFHCE — horizontal clock buffer with clock enable."""
    ce_type = params.get("CE_TYPE", "SYNC")
    init_out = params.get("INIT_OUT", 0)
    verilog = f"""\
module top (
    input  clk,
    input  ce,
    output out
);
    wire clk_h;
    BUFHCE #(
        .CE_TYPE("{ce_type}"),
        .INIT_OUT({init_out})
    ) u_bufhce (
        .I(clk),
        .CE(ce),
        .O(clk_h)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk_h) cnt <= cnt + 1;
    assign out = ^cnt;
endmodule
"""
    xdc = BASE_XDC + """
set_property PACKAGE_PIN D10 [get_ports ce]
set_property IOSTANDARD LVCMOS33 [get_ports ce]
"""
    return verilog, xdc
# -------------------------------------------


# ---------------------------------------------------------------------------
# IO primitives
# ---------------------------------------------------------------------------

def generate_OSERDESE2(params):
    data_rate = params["DATA_RATE_OQ"]
    data_width = int(params["DATA_WIDTH"])
    serdes_mode = params.get("SERDES_MODE", "MASTER")
    data_rate_tq = params.get("DATA_RATE_TQ", "BUF")

    _check_oserdes_width(data_rate, data_width)

    # Build D port connections from shift register
    d_ports = "\n".join(
        f"        .D{i}(sr[{i-1}])," for i in range(1, 9)
    )

    verilog = f"""\
module top (
    input  clk,
    output out
);
    // Parallel data shift register — prevents synthesis pruning
    reg [7:0] sr = 8'hA5;
    always @(posedge clk) sr <= {{sr[6:0], sr[7]}};

    // Serial output
    wire oq;

    // TRISTATE_WIDTH: UG953 p.507 — must be 1 when DATA_RATE_TQ=BUF or SDR; 4 only for DDR
    OSERDESE2 #(
        .DATA_RATE_OQ("{data_rate}"),
        .DATA_RATE_TQ("{data_rate_tq}"),
        .DATA_WIDTH({data_width}),
        .SERDES_MODE("{serdes_mode}"),
        .TRISTATE_WIDTH(1),
        .TBYTE_CTL("FALSE"),
        .TBYTE_SRC("FALSE"),
        .INIT_OQ(1'b0),
        .INIT_TQ(1'b0),
        .SRVAL_OQ(1'b0),
        .SRVAL_TQ(1'b0)
    ) u_oserdes (
        .CLK(clk),
        .CLKDIV(clk),   // Same clock — fuzzing config bits, not timing
        .RST(1'b0),
        .OCE(1'b1),
        .TCE(1'b0),
{d_ports}
        .T1(1'b0),
        .T2(1'b0),
        .T3(1'b0),
        .T4(1'b0),
        .SHIFTIN1(),
        .SHIFTIN2(),
        .TBYTEIN(),
        .OQ(oq),
        .TQ(),
        .OFB(),
        .TFB(),
        .SHIFTOUT1(),
        .SHIFTOUT2(),
        .TBYTEOUT()
    );

    assign out = oq;
endmodule
"""
    return verilog, BASE_XDC


def generate_OSERDESE2_cascade(params):
    """
    10-bit DDR OSERDESE2 requires MASTER+SLAVE cascade.
    SHIFTOUT1/2 from SLAVE connect to SHIFTIN1/2 of MASTER.
    Both must be placed in same IO column.
    """
    data_rate = "DDR"
    data_width = 10

    d_ports_master = "\n".join(
        f"        .D{i}(sr[{i-1}])," for i in range(1, 7)  # D1-D6 for master
    )
    d_ports_slave = "\n".join(
        f"        .D{i}(sr[{i-1}])," for i in range(1, 7)
    )

    verilog = f"""\
module top (
    input  clk,
    output out
);
    reg [9:0] sr = 10'hA5;
    always @(posedge clk) sr <= {{sr[8:0], sr[9]}};

    wire oq, shift1, shift2;

    // Slave — processes bits 7-10
    OSERDESE2 #(
        .DATA_RATE_OQ("{data_rate}"),
        .DATA_RATE_TQ("BUF"),
        .DATA_WIDTH({data_width}),
        .SERDES_MODE("SLAVE"),
        .TRISTATE_WIDTH(1),
        .TBYTE_CTL("FALSE"),
        .TBYTE_SRC("FALSE")
    ) u_slave (
        .CLK(clk),
        .CLKDIV(clk),
        .RST(1'b0),
        .OCE(1'b1),
        .TCE(1'b0),
{d_ports_slave}
        .D7(1'b0),
        .D8(1'b0),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
        .SHIFTIN1(),
        .SHIFTIN2(),
        .TBYTEIN(),
        .SHIFTOUT1(shift1),
        .SHIFTOUT2(shift2),
        .OQ(),
        .TQ(), .OFB(), .TFB(), .TBYTEOUT()
    );

    // Master — receives shift chain from slave
    OSERDESE2 #(
        .DATA_RATE_OQ("{data_rate}"),
        .DATA_RATE_TQ("BUF"),
        .DATA_WIDTH({data_width}),
        .SERDES_MODE("MASTER"),
        .TRISTATE_WIDTH(1),
        .TBYTE_CTL("FALSE"),
        .TBYTE_SRC("FALSE")
    ) u_master (
        .CLK(clk),
        .CLKDIV(clk),
        .RST(1'b0),
        .OCE(1'b1),
        .TCE(1'b0),
{d_ports_master}
        .D7(1'b0),
        .D8(1'b0),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
        .SHIFTIN1(shift1),
        .SHIFTIN2(shift2),
        .TBYTEIN(),
        .OQ(oq),
        .TQ(), .OFB(), .TFB(), .SHIFTOUT1(), .SHIFTOUT2(), .TBYTEOUT()
    );

    assign out = oq;
endmodule
"""
    return verilog, BASE_XDC


def generate_ISERDESE2(params):
    data_rate = params["DATA_RATE"]
    data_width = int(params["DATA_WIDTH"])
    iface = params.get("INTERFACE_TYPE", "NETWORKING")
    num_ce = int(params.get("NUM_CE", 1))

    # UG953 p.439: SDR 2-8, DDR 4/6/8/10/14 (exclude 10/14 — cascade)
    if data_rate == "DDR" and data_width not in (4, 6, 8):
        raise ValueError(
            f"ISERDESE2 DDR requires DATA_WIDTH in {{4,6,8}} for MASTER-only, got {data_width}"
        )
    if data_rate == "SDR" and data_width not in (2, 3, 4, 5, 6, 7, 8):
        raise ValueError(
            f"ISERDESE2 SDR requires DATA_WIDTH 2-8, got {data_width}"
        )

    # UG953 p.438: INTERFACE_TYPE=NETWORKING → OCLK must tie to GND
    oclk_tie = "1'b0"  # GND for NETWORKING; MEMORY would need a real clock

    q_ports = "\n".join(
        f"        .Q{i}(q{i})," for i in range(1, 9)
    )

    verilog = f"""\
module top (
    input  clk,
    input  din_pad,
    output out
);
    wire q1, q2, q3, q4, q5, q6, q7, q8;
    wire din_buf;
    IBUF u_ibuf (.I(din_pad), .O(din_buf));

    ISERDESE2 #(
        .DATA_RATE("{data_rate}"),
        .DATA_WIDTH({data_width}),
        .INTERFACE_TYPE("{iface}"),
        .NUM_CE({num_ce}),
        .IOBDELAY("NONE"),
        .SERDES_MODE("MASTER"),
        .DYN_CLKDIV_INV_EN("FALSE"),
        .DYN_CLK_INV_EN("FALSE"),
        .OFB_USED("FALSE"),
        .INIT_Q1(1'b0), .INIT_Q2(1'b0), .INIT_Q3(1'b0), .INIT_Q4(1'b0),
        .SRVAL_Q1(1'b0), .SRVAL_Q2(1'b0), .SRVAL_Q3(1'b0), .SRVAL_Q4(1'b0)
    ) u_iserdes (
        .CLK(clk),
        .CLKB(~clk),      // UG953: invert CLK for all non-QDR modes
        .CLKDIV(clk),
        .CLKDIVP(),   // UG953 p.437: tie GND except in MIG MEMORY_DDR3
        .RST(1'b0),
        .CE1(1'b1),
        .CE2(1'b1),
        .D(din_buf),
        .DDLY(),
        .OFB(1'b0),
        .OCLK({oclk_tie}),   // UG953: GND when INTERFACE_TYPE=NETWORKING
        .OCLKB({oclk_tie}),
        .DYNCLKDIVSEL(),
        .DYNCLKSEL(),
        .BITSLIP(1'b0),
        .SHIFTIN1(),
        .SHIFTIN2(),
{q_ports}
        .O(),
        .SHIFTOUT1(),
        .SHIFTOUT2()
    );

    assign out = q1 ^ q2 ^ q3 ^ q4 ^ q5 ^ q6 ^ q7 ^ q8;
endmodule
"""
    return verilog, ISERDES_XDC


def generate_IDELAYE2(params):
    idelay_type = params["IDELAY_TYPE"]
    idelay_value = int(params["IDELAY_VALUE"])
    high_perf = params.get("HIGH_PERFORMANCE_MODE", "FALSE")
    signal_pat = params.get("SIGNAL_PATTERN", "DATA")

    _check_idelay_value(idelay_value)

    # IDELAYCTRL must share the same bank — instantiate alongside IDELAYE2
    verilog = f"""\
module top (
    input  clk,
    input  din_pad,
    output out
);
    wire delayed;
    wire rdy;

    // UG953 p.399: IDELAYCTRL required in same bank as IDELAYE2
    // REFCLK must be 200 MHz for guaranteed tap accuracy; fuzzer uses clk for config bit testing
    // Both must share the same IODELAY_GROUP attribute in real designs
    (* IODELAY_GROUP = "fuzz_grp" *)
    IDELAYCTRL u_idelayctrl (
        .REFCLK(clk),
        .RST(1'b0),
        .RDY(rdy)
    );

    reg rdy_r = 0;
    reg [7:0] cnt = 0;
    always @(posedge clk) begin
        rdy_r <= rdy;
        cnt <= cnt + 1;
    end

    wire din_buf;
    IBUF u_din_ibuf (.I(din_pad), .O(din_buf));

    (* IODELAY_GROUP = "fuzz_grp" *)
    IDELAYE2 #(
        .IDELAY_TYPE("{idelay_type}"),
        .IDELAY_VALUE({idelay_value}),
        .HIGH_PERFORMANCE_MODE("{high_perf}"),
        .SIGNAL_PATTERN("{signal_pat}"),
        .REFCLK_FREQUENCY(200.0),    // UG953 p.403: 190-210 or 290-310 MHz
        .CINVCTRL_SEL("FALSE"),
        .PIPE_SEL("FALSE"),
        .DELAY_SRC("IDATAIN")
    ) u_idelay (
        .IDATAIN(din_buf),
        .DATAOUT(delayed),
        .C(clk),
        .CE(1'b0),
        .INC(1'b0),
        .CINVCTRL(),
        .CNTVALUEIN(5'b0),           // UG953 p.401: CNTVALUEIN is 5 bits [4:0]
        .CNTVALUEOUT(),
        .LD(1'b0),
        .LDPIPEEN(1'b0),
        .REGRST(1'b0),
        .DATAIN(cnt[7])              // Fed by counter to prevent IS_DATAIN_INVERTED artifact
    );

    assign out = delayed ^ rdy_r ^ cnt[7];
endmodule
"""
    return verilog, ISERDES_XDC


def generate_OBUFDS(params):
    iostd = params["IOSTANDARD"]
    slew = params.get("SLEW", "SLOW")

    verilog = f"""\
module top (
    input  clk,
    output out_p,
    output out_n
);
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    wire sig = ^cnt;

    OBUFDS #(
        .IOSTANDARD("{iostd}"),
        .SLEW("{slew}")
    ) u_obufds (
        .I(sig),
        .O(out_p),
        .OB(out_n)
    );
endmodule
"""



    # LOC uses the IOB33M site of the P-side pin — the correct Vivado constraint
    # for OBUFDS/OBUFTDSE2. Confirmed by Vivado TCL: get_sites -filter {SITE_TYPE==IOB33M}
    # -of [get_tiles -of [get_sites -of [get_package_pins <pin>]]].
    # Forces Vivado free placement to match nextpnr, eliminating UNCONSTRAINED status.
    # SSTL135: R5 -> IOB_X1Y8; TMDS_33: U17 -> IOB_X0Y20; LVDS_25: F14 -> IOB_X0Y74.

    if "SSTL135" in iostd:
        obufds_loc = "IOB_X1Y8"
    elif "TMDS" in iostd:
        obufds_loc = "IOB_X0Y20"
    else:
        obufds_loc = "IOB_X0Y74"
    xdc = _diff_out_xdc(iostd) + f"set_property LOC {obufds_loc} [get_cells u_obufds]\n"
    return verilog, xdc




def generate_IBUFDS(params):
    iostd = params["IOSTANDARD"]
    diff_term = params.get("DIFF_TERM", "FALSE")
    drive = params.get("DRIVE", 12)

    # Dynamic pin swapping to satisfy Vivado DRC
    p_pin, n_pin = ("K1", "L1") if "SSTL135" in iostd else ("F14", "F15")




# LOC uses the IOB33M site of the P-side pin — the correct Vivado constraint
    # for IBUFDS/IBUFDSE2. Confirmed by Vivado TCL: get_sites -filter {SITE_TYPE==IOB33M}
    # -of [get_tiles -of [get_sites -of [get_package_pins <pin>]]].
    # Forces Vivado free placement to match nextpnr, eliminating UNCONSTRAINED status.
    # F14 (LVDS_25, TMDS_33) -> IOB_X0Y74; K1 (DIFF_SSTL135) -> IOB_X1Y44.
    ibufds_loc = "IOB_X1Y44" if "SSTL135" in iostd else "IOB_X0Y74"
    ibufds_xdc = f"""\
set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN {p_pin} [get_ports din_p]
set_property PACKAGE_PIN {n_pin} [get_ports din_n]
set_property IOSTANDARD {iostd} [get_ports din_p]
set_property IOSTANDARD {iostd} [get_ports din_n]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 10.000 -name sys_clk [get_ports clk]
set_property LOC {ibufds_loc} [get_cells u_ibufds]
"""

    
    verilog = f"""\
module top (
    input  clk,
    input  din_p,
    input  din_n,
    output out
);
    wire ibuf_out;

    IBUFDS #(
        .IOSTANDARD("{iostd}"),
        .DIFF_TERM("{diff_term}")
    ) u_ibufds (
        .I(din_p),
        .IB(din_n),
        .O(ibuf_out)
    );

    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    assign out = ibuf_out ^ (^cnt);
endmodule
"""
    return verilog, ibufds_xdc


def generate_IOBUF(params):
    """IOBUF — bidirectional IO buffer. IO must connect to actual pad."""
    verilog = """\
module top (
    input  clk,
    inout  io_pad,
    output out
);
    wire buf_out;
    reg buf_t = 0;
    reg buf_i = 0;
    always @(posedge clk) begin
        buf_t <= ~buf_t;
        buf_i <= ~buf_i;
    end
    IOBUF #(
        .IOSTANDARD("LVCMOS33"),
        .SLEW("SLOW"),
        .DRIVE(12)
    ) u_iobuf (
        .IO(io_pad),
        .I(buf_i),
        .T(buf_t),
        .O(buf_out)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    assign out = buf_out ^ (^cnt);
endmodule
"""
    xdc = BASE_XDC + """
set_property PACKAGE_PIN D10 [get_ports io_pad]
set_property IOSTANDARD LVCMOS33 [get_ports io_pad]
"""
    return verilog, xdc

def generate_IOBUFDS(params):
    iostd = params["IOSTANDARD"]
    slew = params.get("SLEW", "SLOW")

    verilog = f"""\
module top (
    input  clk,
    inout  out_p,
    inout  out_n,
    output out
);
    wire buf_out;
    reg  buf_t = 0;   // Toggle tristate each cycle
    reg  buf_i = 0;   // Toggle input data
    
    always @(posedge clk) begin
        buf_t <= ~buf_t;
        buf_i <= ~buf_i;
    end

    IOBUFDS #(
        .IOSTANDARD("{iostd}"),
        .SLEW("{slew}")
    ) u_iobufds (
        .IO(out_p),
        .IOB(out_n),
        .I(buf_i),
        .T(buf_t),
        .O(buf_out)
    );

    // Anti-pruning
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    assign out = buf_out ^ (^cnt);
endmodule
"""
    # _diff_out_xdc handles clk, out_p, and out_n. Append the 'out' pin constraint.
    xdc = _diff_out_xdc(iostd) + (
        "set_property PACKAGE_PIN C13 [get_ports out]\n"
        "set_property IOSTANDARD LVCMOS33 [get_ports out]\n"
    )

    return verilog, xdc

# ---------------------------------------------------------------------------
# Memory primitives
# ---------------------------------------------------------------------------

def generate_RAMB18E1(params):
    rw_a = int(params["READ_WIDTH_A"])
    ww_a = int(params["WRITE_WIDTH_A"])
    rw_b = int(params["READ_WIDTH_B"])
    ww_b = int(params["WRITE_WIDTH_B"])
    doa_reg = int(params.get("DOA_REG", 0))
    dob_reg = int(params.get("DOB_REG", 0))
    ram_mode = params.get("RAM_MODE", "TDP")

    _check_ramb_widths("RAMB18E1", rw_a, ww_a, rw_b, ww_b)

    # Address widths depend on data width:
    # width 1->14, 2->13, 4->12, 9->11, 18->10 (for 18Kb)
    _aw = {1: 14, 2: 13, 4: 12, 9: 11, 18: 10}
    # Data width for port (strip parity)
    _dw = {1: 1, 2: 2, 4: 4, 9: 8, 18: 16}
    _pw = {1: 0, 2: 0, 4: 0, 9: 1, 18: 2}

    aw_a = _aw.get(ww_a, 14)
    aw_b = _aw.get(ww_b, 14)
    dw_a = _dw.get(rw_a, 1)
    dw_b = _dw.get(rw_b, 1)
    pw_a = _pw.get(rw_a, 0)
    pw_b = _pw.get(rw_b, 0)

    verilog = f"""\
module top (
    input  clk,
    output out
);
    reg [{aw_a-1}:0] addr_a = 0;
    reg [{aw_b-1}:0] addr_b = 0;
    reg [{dw_a-1}:0] din_a  = 0;
    reg [{dw_b-1}:0] din_b  = 0;
    // UG953 p.567: DOADO/DOBDO are always 16 bits wide; read lower dw_a bits
    wire [15:0] dout_a;
    wire [15:0] dout_b;

    always @(posedge clk) begin
        addr_a <= addr_a + 1;
        addr_b <= addr_b + 1;
        din_a  <= addr_a[{min(dw_a-1, aw_a-1)}:0];
        din_b  <= addr_b[{min(dw_b-1, aw_b-1)}:0];
    end

    RAMB18E1 #(
        .RAM_MODE("{ram_mode}"),
        .READ_WIDTH_A({rw_a}),
        .WRITE_WIDTH_A({ww_a}),
        .READ_WIDTH_B({rw_b}),
        .WRITE_WIDTH_B({ww_b}),
        .DOA_REG({doa_reg}),
        .DOB_REG({dob_reg}),
        .WRITE_MODE_A("WRITE_FIRST"),
        .WRITE_MODE_B("WRITE_FIRST"),
        .RDADDR_COLLISION_HWCONFIG("DELAYED_WRITE"),
        .SIM_COLLISION_CHECK("ALL"),
        .SIM_DEVICE("7SERIES"),
        .INIT_A(18'h0),
        .INIT_B(18'h0),
        .SRVAL_A(18'h0),
        .SRVAL_B(18'h0)
    ) u_ramb18 (
        // Port A — address is always 14 bits to the primitive
        .CLKARDCLK(clk),
        .ADDRARDADDR({{{{(14-{aw_a}){{1'b0}}}}, addr_a}}),
        .DIADI({{{{(16-{dw_a}){{1'b0}}}}, din_a}}),
        .DIPADIP(2'b0),
        .WEA(2'b11),
        .ENARDEN(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTREGARSTREG(1'b0),
        .REGCEAREGCE(1'b1),
        .DOADO(dout_a),
        .DOPADOP(),             // Port A parity output
        // Port B
        .CLKBWRCLK(clk),
        .ADDRBWRADDR({{{{(14-{aw_b}){{1'b0}}}}, addr_b}}),
        .DIBDI({{{{(16-{dw_b}){{1'b0}}}}, din_b}}),
        .DIPBDIP(2'b0),
        .WEBWE(4'b1111),
        .ENBWREN(1'b1),
        .RSTRAMB(1'b0),
        .RSTREGB(1'b0),
        .REGCEB(1'b1),
        .DOBDO(dout_b),
        .DOPBDOP()              // Port B parity output
    );

    assign out = (^dout_a[{dw_a-1}:0]) ^ (^dout_b[{dw_b-1}:0]);
endmodule
"""
    return verilog, BASE_XDC


def generate_RAMB36E1(params):
    rw_a = int(params["READ_WIDTH_A"])
    ww_a = int(params["WRITE_WIDTH_A"])
    rw_b = int(params["READ_WIDTH_B"])
    ww_b = int(params["WRITE_WIDTH_B"])
    doa_reg = int(params.get("DOA_REG", 0))
    dob_reg = int(params.get("DOB_REG", 0))
    ram_mode = params.get("RAM_MODE", "TDP")

    _check_ramb_widths("RAMB36E1", rw_a, ww_a, rw_b, ww_b)

    # For RAMB36, 36=max (32+4 parity). Width 36 on both ports is DRC violation.
    if rw_a == 36 and rw_b == 36:
        raise ValueError("RAMB36E1: READ_WIDTH_A=36 and READ_WIDTH_B=36 simultaneously is invalid TDP")

    _aw = {1: 15, 2: 14, 4: 13, 9: 12, 18: 11, 36: 10}
    _dw = {1: 1, 2: 2, 4: 4, 9: 8, 18: 16, 36: 32}
    _pw = {1: 0, 2: 0, 4: 0, 9: 1, 18: 2, 36: 4}

    aw_a = _aw.get(ww_a, 15)
    aw_b = _aw.get(ww_b, 15)
    dw_a = _dw.get(rw_a, 1)
    dw_b = _dw.get(rw_b, 1)

    verilog = f"""\
module top (
    input  clk,
    output out
);
    reg [{aw_a-1}:0] addr_a = 0;
    reg [{aw_b-1}:0] addr_b = 0;
    reg [{dw_a-1}:0] din_a  = 0;
    reg [{dw_b-1}:0] din_b  = 0;
    wire [{dw_a-1}:0] dout_a;
    wire [{dw_b-1}:0] dout_b;

    always @(posedge clk) begin
        addr_a <= addr_a + 1;
        addr_b <= addr_b + 1;
        din_a  <= addr_a[{min(dw_a-1, aw_a-1)}:0];
        din_b  <= addr_b[{min(dw_b-1, aw_b-1)}:0];
    end

    RAMB36E1 #(
        .RAM_MODE("{ram_mode}"),
        .READ_WIDTH_A({rw_a}),
        .WRITE_WIDTH_A({ww_a}),
        .READ_WIDTH_B({rw_b}),
        .WRITE_WIDTH_B({ww_b}),
        .DOA_REG({doa_reg}),
        .DOB_REG({dob_reg}),
        .WRITE_MODE_A("WRITE_FIRST"),
        .WRITE_MODE_B("WRITE_FIRST"),
        .RDADDR_COLLISION_HWCONFIG("DELAYED_WRITE"),
        .SIM_COLLISION_CHECK("ALL"),
        .RAM_EXTENSION_A("NONE"),
        .RAM_EXTENSION_B("NONE"),
        .EN_ECC_READ("FALSE"),
        .EN_ECC_WRITE("FALSE")
    ) u_ramb36 (
        .CLKARDCLK(clk),
        .ADDRARDADDR({{{{(15-{aw_a}){{1'b0}}}}, addr_a}}),
        .DIADI({{{{(32-{dw_a}){{1'b0}}}}, din_a}}),
        .DIPADIP(4'b0),
        .WEA(4'b1111),
        .ENARDEN(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTREGARSTREG(1'b0),
        .REGCEAREGCE(1'b1),
        .DOADO(dout_a),
        .DOPADOP(),
        .CLKBWRCLK(clk),
        .ADDRBWRADDR({{{{(15-{aw_b}){{1'b0}}}}, addr_b}}),
        .DIBDI({{{{(32-{dw_b}){{1'b0}}}}, din_b}}),
        .DIPBDIP(4'b0),
        .WEBWE(8'b11111111),
        .ENBWREN(1'b1),
        .RSTRAMB(1'b0),
        .RSTREGB(1'b0),
        .REGCEB(1'b1),
        .DOBDO(dout_b),
        .DOPBDOP(),
        .CASCADEINA(),
        .CASCADEINB(),
        .CASCADEOUTA(),
        .CASCADEOUTB(),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .DBITERR(),
        .ECCPARITY(),
        .RDADDRECC(),
        .SBITERR()
    );

    assign out = (^dout_a) ^ (^dout_b);
endmodule
"""

    return verilog, BASE_XDC


def generate_FIFO18E1(params):
    data_width = int(params["DATA_WIDTH"])
    fifo_mode = params.get("FIFO_MODE", "FIFO18")
    do_reg = int(params.get("DO_REG", 0))
    fwft = params.get("FIRST_WORD_FALL_THROUGH", "FALSE")

    _dw = {4: 4, 9: 8, 18: 16}
    dw = _dw.get(data_width, 4)

    # UG953 p.351: FWFT incompatible with DO_REG=1
    if fwft == "TRUE":
        raise ValueError("FIFO18E1: FIRST_WORD_FALL_THROUGH=TRUE incompatible with EN_SYN=TRUE (fuzzer uses EN_SYN=TRUE for single-clock operation)")

    # UG953 p.352: DO_REG must be 1 when EN_SYN=FALSE; we use EN_SYN=TRUE for simplicity
    # to avoid the DO_REG=1 mandatory constraint when fuzzing DO_REG=0
    en_syn = "TRUE"

    verilog = f"""\
module top (
    input  clk,
    output out
);
    wire empty, full, almost_empty, almost_full;
    // UG953 p.351: DO is always 32 bits wide (data+parity mux), DI is 32 bits
    wire [31:0] dout;
    reg  [{dw-1}:0] din = 0;
    reg  wr_en = 0, rd_en = 0;

    reg [3:0] phase = 0;
    reg rst_sync = 1;
    always @(posedge clk) begin
        phase  <= phase + 1;
        din    <= din + 1;
        wr_en  <= (phase < 8) & ~full;
        rd_en  <= (phase >= 8) & ~empty;
        rst_sync <= 1;   // Always high — satisfies REQP-34 non-constant requirement
    end

    FIFO18E1 #(
        .DATA_WIDTH({data_width}),
        .FIFO_MODE("{fifo_mode}"),
        .DO_REG({do_reg}),
        .EN_SYN("{en_syn}"),
        .FIRST_WORD_FALL_THROUGH("{fwft}"),
        .INIT(36'h0),
        .SRVAL(36'h0),
        .SIM_DEVICE("7SERIES"),
        .ALMOST_EMPTY_OFFSET(13'h0080),
        .ALMOST_FULL_OFFSET(13'h0080)
    ) u_fifo (
        .RDCLK(clk),
        .WRCLK(clk),
        .RST(rst_sync),   // DRC REQP-34: RST must be driven by non-constant net
        .RSTREG(1'b0),
        .REGCE(1'b1),
        .DI({{{{(32-{dw}){{1'b0}}}}, din}}),
        .DIP(2'b0),
        .WREN(wr_en),
        .RDEN(rd_en),
        .DO(dout),
        .DOP(),
        .EMPTY(empty),
        .FULL(full),
        .ALMOSTEMPTY(almost_empty),
        .ALMOSTFULL(almost_full),
        .RDCOUNT(),
        .WRCOUNT(),
        .RDERR(),
        .WRERR()
    );

    assign out = (^dout[{dw-1}:0]) ^ empty ^ almost_empty;
endmodule
"""
    return verilog, BASE_XDC


def generate_FIFO36E1(params):
    data_width = int(params.get("DATA_WIDTH", 18))
    do_reg = int(params.get("DO_REG", 0))
    fwft = params.get("FIRST_WORD_FALL_THROUGH", "FALSE")

    if fwft == "TRUE":
        raise ValueError("FIFO36E1: FIRST_WORD_FALL_THROUGH=TRUE incompatible with EN_SYN=TRUE (fuzzer uses EN_SYN=TRUE for single-clock operation)")

    # UG953 p.356: DI/DO are 64 bits wide (port bus is always 64-bit)
    _dw = {4: 4, 9: 8, 18: 16, 36: 32}
    dw = _dw.get(data_width, 16)

    verilog = f"""\
module top (
    input  clk,
    output out
);
    wire empty, full, almost_empty;
    wire [63:0] dout;          // UG953: DO is always 64 bits
    reg  [{dw-1}:0] din = 0;
    reg  wr_en = 0, rd_en = 0;
    
    reg [3:0] phase = 0;

    reg rst_sync = 1;
    always @(posedge clk) begin
        phase  <= phase + 1;
        din    <= din + 1;
        wr_en  <= (phase < 8) & ~full;
        rd_en  <= (phase >= 8) & ~empty;
        rst_sync <= 1;
    end

    FIFO36E1 #(
        .DATA_WIDTH({data_width}),
        .DO_REG({do_reg}),
        .FIRST_WORD_FALL_THROUGH("{fwft}"),
        .EN_SYN("TRUE"),
        .FIFO_MODE("FIFO36"),
        .INIT(72'h0),
        .SRVAL(72'h0),
        .SIM_DEVICE("7SERIES"),
        .EN_ECC_READ("FALSE"),
        .EN_ECC_WRITE("FALSE"),
        .ALMOST_EMPTY_OFFSET(13'h0080),
        .ALMOST_FULL_OFFSET(13'h0080)
    ) u_fifo36 (
        .RDCLK(clk),
        .WRCLK(clk),
        .RST(rst_sync),   // DRC REQP-34: RST must be driven by non-constant net
        .RSTREG(1'b0),
        .REGCE(1'b1),
        .DI({{{{(64-{dw}){{1'b0}}}}, din}}),    // UG953: DI is 64 bits
        .DIP(8'b0),
        .WREN(wr_en),
        .RDEN(rd_en),
        .DO(dout),
        .DOP(),
        .EMPTY(empty),
        .FULL(full),
        .ALMOSTEMPTY(almost_empty),
        .ALMOSTFULL(),
        .RDCOUNT(),
        .WRCOUNT(),
        .RDERR(),
        .WRERR(),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .DBITERR(),
        .ECCPARITY(),
        .SBITERR()
    );

    assign out = (^dout[{dw-1}:0]) ^ empty ^ almost_empty;
endmodule
"""
    return verilog, BASE_XDC


# ---------------------------------------------------------------------------
# Arithmetic primitives
# ---------------------------------------------------------------------------

def generate_DSP48E1(params):
    areg = int(params["AREG"])
    breg = int(params["BREG"])
    creg = int(params.get("CREG", 1))
    preg = int(params.get("PREG", 1))
    mreg = int(params.get("MREG", 0))
    use_mult = params.get("USE_MULT", "MULTIPLY")
    _check_dsp(areg, breg, mreg, use_mult)

    verilog = f"""\
module top (
    input  clk,
    output out
);
    // A: 30 bits, B: 18 bits, C: 48 bits
    reg [29:0] a_reg = 30'h3FFFFFFF;
    reg [17:0] b_reg = 18'h2AAAA;
    reg [47:0] c_reg = 48'h0;
    wire [47:0] p_out;

    always @(posedge clk) begin
        a_reg <= a_reg - 1;
        b_reg <= b_reg + 1;
        c_reg <= p_out;   // Feedback P -> C to prevent pruning and create accumulator
    end

    DSP48E1 #(
        .AREG({areg}),
        .BREG({breg}),
        .CREG({creg}),
        .PREG({preg}),
        .MREG({mreg}),
        .ADREG(1),
        .DREG(1),
        .ACASCREG({areg if areg > 0 else 0}),
        .BCASCREG({breg if breg > 0 else 0}),
        .USE_DPORT("FALSE"),
        .AUTORESET_PATDET("NO_RESET"),
        .USE_PATTERN_DETECT("NO_PATDET"),
        .MASK("001111111111111111111111111111111111111111111111"),
        .PATTERN("000000000000000000000000000000000000000000000000"),
        .SEL_MASK("MASK"),
        .SEL_PATTERN("PATTERN"),
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT")
    ) u_dsp (
        .CLK(clk),
        .A(a_reg),
        .B(b_reg),
        .C(c_reg),
        .D(25'b0),
        .OPMODE(7'b0110101),    // P = A*B + C (multiply-accumulate)
        .ALUMODE(4'b0000),
        .INMODE(5'b00000),
        .CARRYIN(1'b0),
        .CARRYINSEL(3'b000),
        .CEA1(1'b1), .CEA2(1'b1),
        .CEB1(1'b1), .CEB2(1'b1),
        .CEC(1'b1),
        .CED(1'b1),
        .CEAD(1'b1),
        .CEM(1'b1),
        .CEP(1'b1),
        .CECTRL(1'b1),
        .CECARRYIN(1'b1),
        .RSTA(1'b0), .RSTB(1'b0),
        .RSTC(1'b0), .RSTD(1'b0),
        .RSTM(1'b0), .RSTP(1'b0),
        .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0),
        .RSTINMODE(1'b0),
        .RSTCTRL(1'b0),
        .ACIN(), .BCIN(), .PCIN(),
        .CARRYCASCIN(), .MULTSIGNIN(),
        .P(p_out),
        .ACOUT(), .BCOUT(), .PCOUT(),
        .CARRYCASCOUT(), .MULTSIGNOUT(),
        .CARRYOUT(), .PATTERNDETECT(), .PATTERNBDETECT(),
        .OVERFLOW(), .UNDERFLOW()
    );

    assign out = ^p_out;
endmodule
"""
    return verilog, BASE_XDC


# ---------------------------------------------------------------------------
# Configuration primitives (low priority — minimal config registers)
# ---------------------------------------------------------------------------

def generate_STARTUPE2(params):
    """STARTUPE2 — startup sequence. Minimal configurable bits."""
    prog_usr = params.get("PROG_USR", "FALSE")
    sim_cclk = params.get("SIM_CCLK_FREQ", "0.0")
    verilog = f"""\
module top (
    input  clk,
    output out
);
    wire cfgclk, cfgmclk, eos, preq;

    STARTUPE2 #(
        .PROG_USR("{prog_usr}"),
        .SIM_CCLK_FREQ({sim_cclk})
    ) u_startup (
        .CLK(clk),
        .GSR(1'b0),
        .GTS(1'b0),
        .KEYCLEARB(1'b1),
        .PACK(1'b0),
        .USRCCLKO(1'b0),
        .USRCCLKTS(1'b1),
        .USRDONEO(1'b1),
        .USRDONETS(1'b1),
        .CFGCLK(cfgclk),
        .CFGMCLK(cfgmclk),
        .EOS(eos),
        .PREQ(preq)
    );

    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    assign out = eos ^ cfgmclk ^ (^cnt);
endmodule
"""
    return verilog, BASE_XDC


# ---------------------------------------------------------------------------
# Dispatch table
# ---------------------------------------------------------------------------

def generate_MMCME2_ADV(params):
    verilog = f"""
module top (input clk, output out);
    wire clkfb;
    MMCME2_ADV #(
        .CLKFBOUT_MULT_F({params.get('CLKFBOUT_MULT_F', 8.0)}),
        .CLKIN1_PERIOD({params.get('CLKIN1_PERIOD', 10.0)}),
        .DIVCLK_DIVIDE({params.get('DIVCLK_DIVIDE', 1)}),
        .CLKOUT0_DIVIDE_F({params.get('CLKOUT0_DIVIDE_F', 8.0)})
    ) mmcm_inst (
        .CLKIN1(clk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(out),
        .RST(1'b0), .PWRDWN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'b0), .DI(16'b0)
    );
endmodule
"""
    return verilog, BASE_XDC

def generate_PLLE2_ADV(params):
    verilog = f"""
module top (input clk, output out);
    wire clkfb;
    PLLE2_ADV #(
        .CLKFBOUT_MULT({params.get('CLKFBOUT_MULT', 8)}),
        .CLKIN1_PERIOD({params.get('CLKIN1_PERIOD', 10.0)}),
        .DIVCLK_DIVIDE({params.get('DIVCLK_DIVIDE', 1)}),
        .CLKOUT0_DIVIDE({params.get('CLKOUT0_DIVIDE', 8)})
    ) pll_inst (
        .CLKIN1(clk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(out),
        .RST(1'b0), .PWRDWN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'b0), .DI(16'b0)
    );
endmodule
"""
    return verilog, BASE_XDC

def generate_IDDR(params):
    """IDDR — DDR input register."""
    ddr_clk_edge = params.get("DDR_CLK_EDGE", "OPPOSITE_EDGE")
    srtype = params.get("SRTYPE", "SYNC")
    init_q1 = params.get("INIT_Q1", 0)
    init_q2 = params.get("INIT_Q2", 0)
    verilog = f"""\
module top (
    input  clk,
    input  din,
    output out
);
    wire q1, q2;
    IDDR #(
        .DDR_CLK_EDGE("{ddr_clk_edge}"),
        .SRTYPE("{srtype}"),
        .INIT_Q1({init_q1}),
        .INIT_Q2({init_q2})
    ) u_iddr (
        .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0),
        .D(din), .Q1(q1), .Q2(q2)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + q1 + q2;
    assign out = ^cnt;
endmodule
"""
    xdc = BASE_XDC + """
set_property PACKAGE_PIN D10 [get_ports din]
set_property IOSTANDARD LVCMOS33 [get_ports din]
set_property PACKAGE_PIN F14 [get_ports q1]
set_property IOSTANDARD LVCMOS33 [get_ports q1]
set_property PACKAGE_PIN F15 [get_ports q2]
set_property IOSTANDARD LVCMOS33 [get_ports q2]
"""
    return verilog, xdc

def generate_ODDR(params):
    """ODDR — DDR output register."""
    ddr_clk_edge = params.get("DDR_CLK_EDGE", "OPPOSITE_EDGE")
    srtype = params.get("SRTYPE", "SYNC")
    init = params.get("INIT", 0)
    verilog = f"""\
module top (
    input  clk,
    output out
);
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    ODDR #(
        .DDR_CLK_EDGE("{ddr_clk_edge}"),
        .SRTYPE("{srtype}"),
        .INIT({init})
    ) u_oddr (
        .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0),
        .D1(cnt[0]), .D2(cnt[1]), .Q(out)
    );
endmodule
"""
    return verilog, BASE_XDC

def generate_IDELAYCTRL(params):
    """IDELAYCTRL — must be accompanied by at least one IDELAYE2."""
    verilog = """\
module top (
    input  refclk,
    input  clk,
    input  din,
    output out
);
    wire rdy, delayed;
    IDELAYCTRL u_idelayctrl (
        .REFCLK(refclk),
        .RST(1'b0),
        .RDY(rdy)
    );
    IDELAYE2 #(
        .IDELAY_TYPE("FIXED"),
        .IDELAY_VALUE(0),
        .DELAY_SRC("IDATAIN"),
        .HIGH_PERFORMANCE_MODE("FALSE"),
        .SIGNAL_PATTERN("DATA"),
        .REFCLK_FREQUENCY(200.0)
    ) u_idelay (
        .IDATAIN(din),
        .DATAOUT(delayed),
        .C(clk), .CE(1'b0), .INC(1'b0),
        .CINVCTRL(1'b0), .CNTVALUEIN(5'b0),
        .DATAIN(1'b0), .LD(1'b0), .LDPIPEEN(1'b0),
        .REGRST(1'b0)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + delayed + rdy;
    assign out = ^cnt;
endmodule
"""
    xdc = """
set_property PACKAGE_PIN N15 [get_ports refclk]
set_property IOSTANDARD LVCMOS33 [get_ports refclk]
set_property PACKAGE_PIN K16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN D10 [get_ports din]
set_property IOSTANDARD LVCMOS33 [get_ports din]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 5.000 -name refclk [get_ports refclk]
create_clock -period 10.000 -name clk [get_ports clk]
"""
    return verilog, xdc

def generate_XADC(params):
    """XADC — analog-to-digital converter. Autonomous mode only."""
    verilog = """\
module top (
    input  clk,
    output out
);
    wire eoc, eos, busy;
    wire [15:0] do_out;
    (* keep = "true" *)
    XADC #(
        .INIT_40(16'h9000),
        .INIT_41(16'h2ef0),
        .INIT_42(16'h0400)
    ) u_xadc (
        .DCLK(clk), .RESET(1'b0), .DEN(1'b0), .DWE(1'b0),
        .DADDR(7'b0), .DI(16'b0),
        .DO(do_out), .DRDY(), .EOC(eoc), .EOS(eos), .BUSY(busy)
    );
    assign out = eoc ^ eos ^ busy ^ (^do_out);
endmodule
"""
    return verilog, BASE_XDC

def generate_SRL16E(params):
    """SRL16E — 16-bit shift register LUT."""
    init = params.get("INIT", "16'h0000")
    verilog = f"""\
module top (
    input  clk,
    input  d,
    output out
);
    wire q;
    SRL16E #(.INIT({init})) u_srl (
        .CLK(clk), .CE(1'b1), .D(d),
        .A0(1'b1), .A1(1'b1), .A2(1'b1), .A3(1'b1),
        .Q(q)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + q;
    assign out = ^cnt;
endmodule
"""
    xdc = BASE_XDC + """
set_property PACKAGE_PIN D10 [get_ports d]
set_property IOSTANDARD LVCMOS33 [get_ports d]
"""
    return verilog, xdc

def generate_SRLC32E(params):
    """SRLC32E — 32-bit shift register LUT with cascade."""
    init = params.get("INIT", "32'h00000000")
    verilog = f"""\
module top (
    input  clk,
    input  d,
    output out
);
    wire q, q31;
    SRLC32E #(.INIT({init})) u_srl (
        .CLK(clk), .CE(1'b1), .D(d),
        .A(5'b11111),
        .Q(q), .Q31(q31)
    );
    reg [7:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + q;
    assign out = ^cnt;
endmodule
"""
    xdc = BASE_XDC + """
set_property PACKAGE_PIN D10 [get_ports d]
set_property IOSTANDARD LVCMOS33 [get_ports d]
"""
    return verilog, xdc


def generate_ISERDESE2_cascade(params):
    """ISERDESE2 CASCADE — MASTER+SLAVE pair for DATA_WIDTH 10 or 14.
    Pack_io_xc7.cc: MASTER SHIFTOUT1/2 -> SLAVE SHIFTIN1/2.
    MASTER receives D from IO. SLAVE placed at Y-1."""
    data_rate = params.get("DATA_RATE", "DDR")
    data_width = int(params.get("DATA_WIDTH", 10))
    master_q = "\n".join(f"        .Q{i}(q{i})," for i in range(1, 9))
    slave_q  = "\n".join(f"        .Q{i}(sq{i})," for i in range(1, 9))
    verilog = f"""\
module top (
    input  clk,
    input  din_pad,
    output out
);
    wire din_buf, clkb;
    wire shift1, shift2;
    wire q1,q2,q3,q4,q5,q6,q7,q8;
    wire sq1,sq2,sq3,sq4,sq5,sq6,sq7,sq8;
    IBUF u_ibuf (.I(din_pad), .O(din_buf));
    assign clkb = ~clk;
    // MASTER — receives data from IO, produces SHIFTOUT to SLAVE
    ISERDESE2 #(
        .DATA_RATE("{data_rate}"),
        .DATA_WIDTH({data_width}),
        .INTERFACE_TYPE("NETWORKING"),
        .NUM_CE(1),
        .IOBDELAY("NONE"),
        .SERDES_MODE("MASTER"),
        .DYN_CLKDIV_INV_EN("FALSE"),
        .DYN_CLK_INV_EN("FALSE"),
        .OFB_USED("FALSE"),
        .INIT_Q1(1'b0), .INIT_Q2(1'b0),
        .INIT_Q3(1'b0), .INIT_Q4(1'b0),
        .SRVAL_Q1(1'b0), .SRVAL_Q2(1'b0),
        .SRVAL_Q3(1'b0), .SRVAL_Q4(1'b0)
    ) u_master (
        .CLK(clk), .CLKB(clkb), .CLKDIV(clk),
        .OCLK(1'b0), .OCLKB(1'b0),
        .CE1(1'b1), .CE2(1'b1),
        .RST(1'b0), .DYNCLKDIVSEL(1'b0), .DYNCLKSEL(1'b0),
        .D(din_buf), .DDLY(1'b0), .OFB(1'b0), .BITSLIP(1'b0),
        .SHIFTIN1(1'b0), .SHIFTIN2(1'b0),
        .SHIFTOUT1(shift1), .SHIFTOUT2(shift2),
{master_q}
        .O()
    );
    // SLAVE — receives SHIFTOUT from MASTER, placed at Y-1
    ISERDESE2 #(
        .DATA_RATE("{data_rate}"),
        .DATA_WIDTH({data_width}),
        .INTERFACE_TYPE("NETWORKING"),
        .NUM_CE(1),
        .IOBDELAY("NONE"),
        .SERDES_MODE("SLAVE"),
        .DYN_CLKDIV_INV_EN("FALSE"),
        .DYN_CLK_INV_EN("FALSE"),
        .OFB_USED("FALSE"),
        .INIT_Q1(1'b0), .INIT_Q2(1'b0),
        .INIT_Q3(1'b0), .INIT_Q4(1'b0),
        .SRVAL_Q1(1'b0), .SRVAL_Q2(1'b0),
        .SRVAL_Q3(1'b0), .SRVAL_Q4(1'b0)
    ) u_slave (
        .CLK(clk), .CLKB(clkb), .CLKDIV(clk),
        .OCLK(1'b0), .OCLKB(1'b0),
        .CE1(1'b1), .CE2(1'b1),
        .RST(1'b0), .DYNCLKDIVSEL(1'b0), .DYNCLKSEL(1'b0),
        .D(), .DDLY(), .OFB(1'b0), .BITSLIP(1'b0),
        .SHIFTIN1(shift1), .SHIFTIN2(shift2),
        .SHIFTOUT1(), .SHIFTOUT2(),
{slave_q}
        .O()
    );
    assign out = q1^q2^q3^q4^q5^q6^q7^q8^sq1^sq2^sq3^sq4^sq5^sq6^sq7^sq8;
endmodule
"""
    xdc = BASE_XDC + """
set_property PACKAGE_PIN D10 [get_ports din_pad]
set_property IOSTANDARD LVCMOS33 [get_ports din_pad]
"""
    return verilog, xdc


GENERATORS = {
    "MMCME2_ADV":     generate_MMCME2_ADV,
    "PLLE2_ADV":      generate_PLLE2_ADV,
    "BUFIO":          generate_BUFIO,
    "BUFR":           generate_BUFR,
    "BUFG":           generate_BUFG,
    "BUFGCE":         generate_BUFGCE,
    "BUFH":           generate_BUFH,
    "OSERDESE2":      generate_OSERDESE2,
    "OSERDESE2_CASCADE": generate_OSERDESE2_cascade,
    "ISERDESE2":      generate_ISERDESE2,
    "ISERDESE2_CASCADE": generate_ISERDESE2_cascade,
    "IDELAYE2":       generate_IDELAYE2,
    "OBUFDS":         generate_OBUFDS,
    "IBUFDS":         generate_IBUFDS,
    "IOBUF":          generate_IOBUF,
    "IOBUFDS":        generate_IOBUFDS,
    "RAMB18E1":       generate_RAMB18E1,
    "RAMB36E1":       generate_RAMB36E1,
    "FIFO18E1":       generate_FIFO18E1,
    "FIFO36E1":       generate_FIFO36E1,
    "DSP48E1":        generate_DSP48E1,
    "STARTUPE2":      generate_STARTUPE2,
    "BUFHCE":         generate_BUFHCE,
    "IDDR":           generate_IDDR,
    "ODDR":           generate_ODDR,
    "IDELAYCTRL":     generate_IDELAYCTRL,
    "XADC":           generate_XADC,
    "SRL16E":         generate_SRL16E,
    "SRLC32E":        generate_SRLC32E,
}



def expand_params(param_file):
    """Yield all parameter combos from a params JSON."""
    with open(param_file) as f:
        d = json.load(f)
    keys = [k for k in d if k not in ("primitive", "constraints")]
    for combo in itertools.product(*[d[k] for k in keys]):
        yield dict(zip(keys, combo))


def main():
    import argparse, sys

    parser = argparse.ArgumentParser(description="Generate Verilog for FPGA fuzzing")
    parser.add_argument("primitive", help="Primitive name (e.g. RAMB18E1)")
    parser.add_argument("params_json", nargs="?",
                        help="Single-combo JSON file (from fuzz.sh pipeline)")
    parser.add_argument("--out-dir", default=".", help="Output directory")
    parser.add_argument("--all", action="store_true",
                        help="Expand all combos from params/<primitive>.json")
    args = parser.parse_args()

    prim = args.primitive.upper()
    gen  = GENERATORS.get(prim)
    if gen is None:
        print(f"ERROR: Unknown primitive {prim}", file=sys.stderr)
        sys.exit(1)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.all:
        param_file = Path("params") / f"{prim.lower()}.json"
        combos = list(expand_params(param_file))
    elif args.params_json:
        try:
            with open(args.params_json) as f:
                combos = [json.load(f)]
        except json.JSONDecodeError:
            print(f"WARNING: {args.params_json} is empty or malformed. Skipping.", file=sys.stderr)
            combos = []

    else:
        # Zero-param primitives (BUFIO, BUFG, BUFH)
        combos = [{}]

    for i, combo in enumerate(combos):
        try:
            verilog, xdc = gen(combo)
        except ValueError as e:
            print(f"SKIP combo {i} ({combo}): {e}", file=sys.stderr)
            continue

        suffix = f"_{i:04d}" if len(combos) > 1 else ""
        vname  = out_dir / f"top{suffix}.v"
        xname  = out_dir / f"top{suffix}.xdc"

        vname.write_text(verilog)
        xname.write_text(xdc)
        print(f"  wrote {vname}  {xname}")


if __name__ == "__main__":
    main()
