#!/usr/bin/env python3
"""Connect abstract contract claims to the concrete repository source.

These checks are narrow source-level regression guards, not formal proofs of
JavaScript runtime semantics, electrical behavior, or compilation success.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
index=(ROOT/"FINAL/index.html").read_text()
jtag=(ROOT/"PRODUCTION_GRADE/ftdi-jtag.js").read_text()
stopwatch=(ROOT/"PRODUCTION_GRADE/DEFAULTS/stopwatch/top.v").read_text()
xdc=(ROOT/"PRODUCTION_GRADE/DEFAULTS/stopwatch/top.xdc").read_text()

def require(statement, note):
    if not statement:
        raise AssertionError(note)
    print("PASS",note)

def match(regex,source):
    return re.search(regex,source,re.S) is not None

# The flash click must freeze the artifact before any async permission, device,
# IDCODE or programming operation. pipelineState is mutable across builds.
main_flash=index[index.index("document.getElementById('btn-flash').onclick"):
                 index.index("document.getElementById('btn-flash-file').onclick")]
require(main_flash.index("const selectedBitstream = pipelineState.bitstream") <
        main_flash.index("await navigator.usb.requestDevice"),
        "Flash freezes selected bitstream before first await")
require("await jtag.programXC7(selectedBitstream)" in main_flash and
        "programXC7(pipelineState.bitstream)" not in main_flash,
        "JTAG uses selected artifact, not mutable global")
require(match(r"if\s*\(\s*\(finalStat\s*>>\s*14\)\s*&\s*1\s*\).*?"
              r"else\s*\{[^}]*throw\s+new\s+Error\s*\(",jtag),
        "DONE=0 rejects instead of resolving successfully")

# For a conventional two-digit HH clock the four-bit BCD digits must remain
# 0..9. Assert the 99->00 clause exists; exhaustive counter simulation lives
# in system_behavior_model.py.
require(match(r"if\s*\(h0\s*==\s*4'd9\)\s*begin.*?"
              r"if\s*\(h1\s*==\s*4'd9\)\s*h1\s*<=\s*4'd0",stopwatch),
        "Hour counter wraps at 99 rather than entering hex A0")
# Canonical board pins are not a software knob. Orientation belongs in HDL.
pinsets={
    "D0_AN":("G6","H6","C3","B3"),
    "D1_AN":("E4","E3","F5","H5"),
}
for prefix,pins in pinsets.items():
    for i,pin in enumerate(pins):
        pattern=rf"PACKAGE_PIN\s+{pin}\s+IOSTANDARD\s+LVCMOS25\}}\s*\[get_ports\s+\{{{prefix}\[{i}\]\}}\]"
        require(match(pattern,xdc),f"{prefix}[{i}] canonical pin {pin}")
