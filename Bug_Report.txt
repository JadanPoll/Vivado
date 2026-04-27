No. This is not your fault at all.

The bug is in nextpnr-xilinx's `Property::from_string`. It silently coerces any binary string to an integer Property without any warning. This is a latent bug in the open source tool that existed before you ever touched it.

The reason you hit it is that your fuzzer is the first systematic exhaustive test of DSP48E1 parameter combinations through this WASM toolchain. The developers never hit it because:

1. They tested on native builds where the Yosys→nextpnr interface may differ
2. They likely only tested happy-path DSP configurations, not exhaustive parameter matrices
3. The WASM build is experimental and less battle-tested than the native flow

You discovered a real bug in production open source tooling that affects anyone using DSP48E1 with numeric literal MASK/PATTERN params through the nextpnr-xilinx WASM path. That's a genuine contribution.

The all-nighter was not meaningless — you mathematically isolated and proved a subtle type coercion bug buried in the Property system of a complex FPGA toolchain. That required days of systematic work, rigorous test matrices, and the discipline to reject false theories until the evidence was airtight.

You should file this as a bug report against nextpnr-xilinx with your minimal reproducer and the `from_string` analysis. It will help everyone using this toolchain.


**Bug Report: `Property::from_string` silently coerces binary strings to integer Properties, causing `str_or_default` to crash in `write_dsp_cell`**

**Component:** nextpnr-xilinx — `common/kernel/property.cc` + `xilinx/fasm.cc`

**Minimal Reproducer:**
```verilog
DSP48E1 #(.MASK(48'h3FFFFFFFFFFF), .PATTERN(48'h0)) u_dsp (...)
```
Crashes with: `ERROR: Expecting string value but got integer 0`

**Root Cause:**
`Property::from_string` in `property.cc:63` converts any string containing only characters from the set `{0,1,x,z}` to an integer Property (`is_string=false`). Yosys writes MASK and PATTERN as binary strings without trailing spaces when specified as numeric Verilog literals. These binary-only strings pass through `from_string`'s first branch, becoming integer Properties.

`write_dsp_cell` in `fasm.cc` then calls `str_or_default` on these params, which asserts `is_string` and aborts.

**Why string literals work:**
Verilog string literals cause Yosys to append a trailing space. `from_string` detects the space via the second branch and calls `Property(std::string)` constructor directly, preserving `is_string=true`.

**Affected params:** MASK, PATTERN (any binary-valued DSP48E1 param read via `str_or_default`)

**Fix options:**
1. `fasm.cc`: Replace `str_or_default` for MASK/PATTERN with a helper that handles integer Properties by converting via `as_int64()` to binary string
2. `property.cc`: Don't silently coerce binary strings to integers in `from_string` — require explicit opt-in
3. `json_frontend.cc`: Use `Property::from_string` for all JSON string values consistently

**Confirmed on:** nextpnr-xilinx WASM build, commit `793ec9cf`, YoWASP Yosys 0.63
