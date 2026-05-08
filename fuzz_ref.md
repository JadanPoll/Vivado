# ZeroLabs FPGA Fuzzing Suite — Hyper-Detailed LLM Reference

> **Purpose**: Exhaustive, atom-level index for debugging, navigating, and understanding every script, function, primitive, constraint, data-flow, and behavioral rule in the ZeroLabs Spartan-7 FPGA fuzzing suite. Every file, parameter, validity guard, path, magic number, and protocol is catalogued here.

---

## TABLE OF CONTENTS

1. [System Identity & Hardware Target](#1-system-identity--hardware-target)
2. [File Map](#2-file-map)
3. [Pipeline Architecture (End-to-End)](#3-pipeline-architecture-end-to-end)
4. [fuzz.sh — Orchestrator](#4-fuzzsh--orchestrator)
5. [fuzz_one.sh — Single-Test Worker](#5-fuzz_onesh--single-test-worker)
6. [gen_verilog.py — Verilog Generator](#6-gen_verilogpy--verilog-generator)
7. [Primitive Generators — Complete Reference](#7-primitive-generators--complete-reference)
8. [Params JSON Files — All Primitives](#8-params-json-files--all-primitives)
9. [compare_bits.py — Bitstream Comparison](#9-compare_bitspy--bitstream-comparison)
10. [headless_pnr.mjs — WASM P&R Pipeline](#10-headless_pnrmjs--wasm-pr-pipeline)
11. [headless_pnr_native.mjs — Native P&R Pipeline](#11-headless_pnr_nativemjs--native-pr-pipeline)
12. [find_nodes.sh — Cluster Node Discovery](#12-find_nodessh--cluster-node-discovery)
13. [cleanup.sh — Stale Lock Removal](#13-cleanupsh--stale-lock-removal)
14. [health_check.sh — Pre-Flight Verification](#14-health_checksh--pre-flight-verification)
15. [status.sh — Progress Dashboard](#15-statussh--progress-dashboard)
16. [Lock Protocol & Self-Healing](#16-lock-protocol--self-healing)
17. [Caching & Hash System](#17-caching--hash-system)
18. [XDC Templates](#18-xdc-templates)
19. [Validity Guards (All Primitives)](#19-validity-guards-all-primitives)
20. [FASM Filter System (compare_bits.py)](#20-fasm-filter-system-compare_bitspy)
21. [Result JSON Schema](#21-result-json-schema)
22. [Environment Variables](#22-environment-variables)
23. [Filesystem Paths — Complete Reference](#23-filesystem-paths--complete-reference)
24. [Key Constants & Magic Numbers](#24-key-constants--magic-numbers)
25. [Error Taxonomy](#25-error-taxonomy)
26. [Anti-Pruning Strategies](#26-anti-pruning-strategies)
27. [Known Hardware Constraints (Spartan-7 XC7S50)](#27-known-hardware-constraints-spartan-7-xc7s50)
28. [Cross-Reference: PRIM_FILTERS vs EXCLUDE Logic](#28-cross-reference-prim_filters-vs-exclude-logic)
29. [Cluster Architecture & Node Selection](#29-cluster-architecture--node-selection)
30. [Auto-Scaling Logic](#30-auto-scaling-logic)

---

## 1. SYSTEM IDENTITY & HARDWARE TARGET

| Property | Value |
|---|---|
| Project name | ZeroLabs FPGA Fuzzing Suite |
| Purpose | Validate nextpnr-xilinx bitstream correctness against Vivado ground-truth for Xilinx primitives |
| Target device | `xc7s50csga324-1` (Xilinx Spartan-7, 50K LUT) |
| Board name | Urbana board |
| Clock pin | `N15` |
| Primary output pin | `C13` |
| Secondary output pin | `C14` (differential negative) |
| Differential pair pins | `F14` (din_p / JA1_P) and `F15` (din_n / JA1_N), Bank 34 HR |
| Default IO standard | `LVCMOS33` |
| Default clock period | `10.000 ns` (100 MHz) |
| Vivado version | `xilinx/2025.1` (module load) |
| Node JS version | `v20.20.0` (nvm) |
| Cluster prefix | `fastx3-{01..39}.ews.illinois.edu` |
| Cluster count | 39 nodes |

---

## 2. FILE MAP

| File | Location | Role |
|---|---|---|
| `fuzz.sh` | `~/fpga_scripts/fuzz/fuzz.sh` | Orchestrator: expands param combos, dispatches local or remote |
| `fuzz_one.sh` | `~/fpga_scripts/fuzz/fuzz_one.sh` | Single-test worker: generates, synthesizes, compares one combo |
| `gen_verilog.py` | `~/fpga_scripts/fuzz/gen_verilog.py` | Verilog + XDC generator for all supported primitives |
| `compare_bits.py` | `~/fpga_scripts/fuzz/compare_bits.py` | Runs bit2fasm on both bitstreams, diffs FASM, writes result.json |
| `headless_pnr.mjs` | `~/fpga_scripts/fuzz/headless_pnr.mjs` | WASM-based nextpnr pipeline: YoWASP synth → WASM P&R → WASM frames2bit |
| `headless_pnr_native.mjs` | `~/fpga_scripts/fuzz/headless_pnr_native.mjs` | YoWASP synth → native nextpnr → WASM frames2bit |
| `find_nodes.sh` | `~/fpga_scripts/fuzz/find_nodes.sh` | SSH probe cluster nodes, select by load average |
| `cleanup.sh` | `~/fpga_scripts/fuzz/cleanup.sh` | Removes stale `running.lock` files |
| `health_check.sh` | `~/fpga_scripts/fuzz/health_check.sh` | Pre-flight: disk, bit2fasm sanity, compare_bits sanity, smoke test |
| `status.sh` | `~/fpga_scripts/fuzz/status.sh` | Summary dashboard: PASS/FAIL/ERROR counts, active locks |
| `run_fuzz_vivado.tcl` | `~/fpga_scripts/fuzz/run_fuzz_vivado.tcl` | Vivado TCL: synthesize + implement → bitstream |
| `params/*.json` | `~/fpga_scripts/fuzz/params/{primitive_lowercase}.json` | Parameter sweep definitions per primitive |
| `chipdb` | `~/nextpnr-xilinx/xilinx/xc7s50.bin` | Native nextpnr Spartan-7 chipdb |
| `chipdb (WASM)` | `~/fpga_assets/xc7s50.bin.br` | Brotli-compressed chipdb for WASM pipeline |
| `fasm_map` | `~/fpga_assets/xc7s50_fasm_map_v4.json.br` | Brotli-compressed FASM feature→frame mapping |
| `part.yaml` | `~/fpga_assets/part.yaml` | xc7frames2bit part definition |
| `prjxray DB` | `~/nextpnr-xilinx/xilinx/external/prjxray-db/spartan7` | Bit→FASM database |
| `bitread` | `~/prjxray/build/tools/bitread` | prjxray bitstream reader binary |
| `bit2fasm.py` | `~/prjxray/utils/bit2fasm.py` | Converts .bit → FASM text |
| `fasm2frames.py` | `~/prjxray/utils/fasm2frames.py` | Converts FASM → frames |
| `xc7frames2bit` | `~/prjxray/build/tools/xc7frames2bit` | Converts frames → .bit |
| `nextpnr-xilinx` | `~/nextpnr-xilinx/build/nextpnr-xilinx` | Native nextpnr binary |
| `dispatch.log` | `~/fuzz_results/dispatch.log` | Remote dispatch audit log |
| `node_*.log` | `~/fuzz_results/node_{node}.log` | Per-node execution log |

---

## 3. PIPELINE ARCHITECTURE (END-TO-END)

### 3.1 Full Pipeline Flow

```
fuzz.sh
  └── [for each param combo]
        └── fuzz_one.sh PRIMITIVE params.json
              ├── [Step 0]  Check result.json cache → skip if exists
              ├── [Step 1]  Acquire running.lock (with self-healing)
              ├── [Step 2]  gen_verilog.py → top.v + top.xdc  (local SSD /tmp/$USER/fuzz_{HASH})
              ├── [Step 3]  vivado -mode batch … → vivado_out.bit  (30 min timeout)
              ├── [Step 4a] headless_pnr.mjs (synthesis only: writes synth.json)
              ├── [Step 4b] nextpnr-xilinx → out.fasm
              ├── [Step 4c] fasm2frames.py → out.frames
              ├── [Step 4d] xc7frames2bit → nextpnr_out.bit
              └── [Step 5]  compare_bits.py → result.json
```

### 3.2 Data Flow Summary

| Stage | Input | Output | Tool |
|---|---|---|---|
| Verilog generation | params JSON | `top.v`, `top.xdc` | `gen_verilog.py` |
| Vivado implementation | `top.v`, `top.xdc` | `vivado_out.bit` | `vivado -mode batch` |
| Synthesis (nextpnr path) | `top.v`, `top.xdc` | `synth.json` | YoWASP Yosys (WASM) |
| Place & Route | `synth.json`, `top.xdc` | `out.fasm` | native `nextpnr-xilinx` |
| FASM → frames | `out.fasm` | `out.frames` | `fasm2frames.py` |
| Frames → bit | `out.frames`, `part.yaml` | `nextpnr_out.bit` | `xc7frames2bit` |
| Comparison | `vivado_out.bit`, `nextpnr_out.bit` | `result.json` | `compare_bits.py` |

---

## 4. FUZZ.SH — ORCHESTRATOR

**Location**: `~/fpga_scripts/fuzz/fuzz.sh`

### 4.1 Argument Parsing

| Argument | Default | Meaning |
|---|---|---|
| Positional `$1` | `MMCME2_ADV` | Primitive name to fuzz |
| `--jobs N` | Auto-scaled | Parallel jobs per node |
| `--nodes N` | `0` (local) | Number of remote nodes to use |

Flag `JOBS_EXPLICIT=1` is set when `--jobs` is passed; prevents auto-scaling from overriding.

### 4.2 GEN_HASH Computation

```bash
GEN_HASH=$(md5sum ~/fpga_scripts/fuzz/gen_verilog.py | cut -c1-8)
```

- Computed once per fuzz.sh invocation.
- Used to namespace results: `~/fuzz_results/{PRIMITIVE}/gen_{GEN_HASH}/`.
- **Stale cache invalidation**: All directories under `~/fuzz_results/{PRIMITIVE}/` that do **not** match `gen_{GEN_HASH}` are deleted with `rm -rf`.

### 4.3 Combo Expansion

Python one-liner inside fuzz.sh expands all parameter combinations from `params/{primitive,,}.json`:
```python
import json, itertools
with open(PARAM_FILE) as f: d = json.load(f)
keys = [k for k in d if k not in ['primitive', 'constraints']]
for combo in itertools.product(*[d[k] for k in keys]):
    print(json.dumps(dict(zip(keys, combo))))
```
Each line written to `$COMBOS_FILE` is one JSON object, one combo per line.

### 4.4 Local Dispatch

```bash
while IFS= read -r line; do
    TEMP_PARAM_FILE=$(mktemp /tmp/fuzz_param_XXXXXX.json)
    echo "$line" > "$TEMP_PARAM_FILE"
    echo "$TEMP_PARAM_FILE"
done < "$COMBOS_FILE" | xargs -P "$JOBS" -I{} env GEN_HASH=$GEN_HASH bash ~/fpga_scripts/fuzz/fuzz_one.sh "$PRIMITIVE" {}
```

`xargs -P $JOBS` controls parallelism. `GEN_HASH` is exported as an env var.

### 4.5 Remote Dispatch

```bash
ssh -f -n -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
    $node.ews.illinois.edu \
    "bash -l -c 'module load xilinx/2025.1; GEN_HASH=$GEN_HASH ~/fpga_scripts/fuzz/fuzz.sh $PRIMITIVE --jobs $JOBS >> ~/fuzz_results/node_${node}.log 2>&1'"
```

- `-f` sends SSH to background immediately.
- `bash -l` loads login shell (needed for `module load`).
- Remote node runs its own `fuzz.sh` in local mode (`--nodes 0`).
- Dispatch logged to `~/fuzz_results/dispatch.log`.

---

## 5. FUZZ_ONE.SH — SINGLE-TEST WORKER

**Location**: `~/fpga_scripts/fuzz/fuzz_one.sh`

### 5.1 Hash Computation

```bash
HASH=$(echo "$PARAMS$PRIMITIVE" | md5sum | awk '{print $1}')
```

- `$PARAMS` = full JSON content of param file (not just filename).
- `$PRIMITIVE` = uppercase primitive name.
- Produces 32-character hex hash → `test_{HASH}` directory name.

### 5.2 Cache Check

```bash
if [ -f "$TEST_DIR/result.json" ]; then
    echo "⏭ Skipping $HASH (cached)"
    rm -f "$PARAM_FILE"
    exit 0
fi
```

Early exit if result already exists. Param temp file is cleaned up.

### 5.3 Lock Acquisition & Self-Healing

Lock file: `$TEST_DIR/running.lock`
Lock content: `$$:$(hostname)` (PID:hostname)

**Self-healing logic** (before writing lock):
1. If lock file exists, read PID and HOST.
2. If HOST == local hostname: check `kill -0 $L_PID` — if alive, exit (another instance running); if dead, steal lock.
3. If HOST != local hostname: SSH to host, `kill -0 $L_PID` — if alive, exit; if dead (SSH fails or kill -0 fails), steal lock.
4. Print `"🔓 Stealing dead lock for $HASH from $CONTENT"` when stealing.

**Heartbeat**: Background process touches lock file every 60 seconds to prevent age-based cleanup.
```bash
(while [ -f "$LOCK" ]; do touch "$LOCK"; sleep 60; done) &
HEARTBEAT_PID=$!
```

**Trap on exit**:
```bash
trap 'kill $HEARTBEAT_PID 2>/dev/null; rm -f "$LOCK" "$PARAM_FILE"; rm -rf "$LOCAL_TMP"' EXIT
```

### 5.4 Local SSD Workspace

```bash
LOCAL_TMP="/tmp/$USER/fuzz_${HASH}"
mkdir -p "$LOCAL_TMP"
```

All Vivado and nextpnr I/O runs on local `/tmp` SSD (not NFS). Results are copied to NFS `$TEST_DIR` only when complete. Rationale: Vivado performance is dramatically worse on NFS.

### 5.5 Vivado Invocation

```bash
timeout 30m vivado -mode batch \
    -source ~/fpga_scripts/fuzz/run_fuzz_vivado.tcl \
    -tclargs "$LOCAL_TMP/top.v" "$LOCAL_TMP/top.xdc" "$LOCAL_TMP/vivado_out.bit" \
    > "$TEST_DIR/vivado.log" 2>&1
VIV_EXIT=$?
```

Exit code handling:
- `124` → `"TIMEOUT"` in result.json
- Non-zero (not 124) → `"VIVADO_CRASH_{VIV_EXIT}"` in result.json

### 5.6 nextpnr Pipeline (Native)

```bash
# Step 1: Synthesis via headless_pnr.mjs (output_bit=/dev/null → only writes synth.json)
node ~/fpga_scripts/fuzz/headless_pnr.mjs \
    "$LOCAL_TMP/top.v" "$LOCAL_TMP/top.xdc" \
    /dev/null top >> "$TEST_DIR/nextpnr.log" 2>&1 || true

# Step 2: Native nextpnr P&R
LD_LIBRARY_PATH=$BOOST_LIBS:$XILINX_LIBS $NATIVE_PNR \
    --chipdb "$CHIPDB" \
    --json "$LOCAL_TMP/synth.json" \
    --xdc "$LOCAL_TMP/top.xdc" \
    --fasm "$LOCAL_TMP/out.fasm"

# Step 3: FASM → frames
python3 "$FASM2FRAMES" --db-root "$PRJXRAY_DB" --part "$PART" \
    "$LOCAL_TMP/out.fasm" "$LOCAL_TMP/out.frames"

# Step 4: frames → bit
"$XC7FRAMES2BIT" --part_file "$PART_YAML" \
    --frm_file "$LOCAL_TMP/out.frames" \
    --output_file "$LOCAL_TMP/nextpnr_out.bit"
```

**BOOST_LIBS**: `$HOME/boost_libs:/software/xilinx-2025.1/2025.1/Model_Composer/lib/lnx64.o`

### 5.7 Comparison & Result

```bash
if [ -f "$LOCAL_TMP/vivado_out.bit" ] && [ -f "$LOCAL_TMP/nextpnr_out.bit" ]; then
    python3 ~/fpga_scripts/fuzz/compare_bits.py \
        "$LOCAL_TMP/vivado_out.bit" "$LOCAL_TMP/nextpnr_out.bit" \
        "$PRIMITIVE" "$PARAMS" "$TEST_DIR/result.json"
else
    echo '{"status":"ERROR","reason":"MISSING_BITSTREAM",...}' > "$TEST_DIR/result.json"
fi
```

---

## 6. GEN_VERILOG.PY — VERILOG GENERATOR

**Location**: `~/fpga_scripts/fuzz/gen_verilog.py`

### 6.1 Module Structure

| Component | Purpose |
|---|---|
| `GENERATORS` dict | Maps uppercase primitive name → generator function |
| `generate_<PRIMITIVE>(params)` | Returns `(verilog_str, xdc_str)` tuple |
| `expand_params(param_file)` | Yields all `{key: value}` dicts from a params JSON |
| `main()` | CLI entry point |

### 6.2 CLI Interface

```
gen_verilog.py <primitive> [params_json] [--out-dir DIR] [--all]
```

| Argument | Meaning |
|---|---|
| `primitive` | Uppercase primitive name (e.g., `RAMB18E1`) |
| `params_json` | Single-combo JSON file (output from fuzz.sh pipeline) |
| `--out-dir DIR` | Output directory (default: `.`) |
| `--all` | Expand all combos from `params/{primitive.lower()}.json` |

Output files: `top.v` (or `top_{i:04d}.v` for multi-combo) and matching `.xdc`.

### 6.3 Validity Guards (Called Inside Generators)

| Function | Checks |
|---|---|
| `_check_vco(mult_f, period, divclk=1)` | `600 ≤ VCO ≤ 1200 MHz`; raises `ValueError` with formula if violated |
| `_check_oserdes_width(data_rate, data_width)` | SDR: width ∈ {2,3,4,5,6,7,8}; DDR: width ∈ {4,6,8} (10/14 require cascade, excluded) |
| `_check_idelay_value(v)` | `0 ≤ v ≤ 31` |
| `_check_ramb_widths(primitive, rw_a, ww_a, rw_b, ww_b)` | RAMB18E1: valid ∈ {1,2,4,9,18}; RAMB36E1: valid ∈ {1,2,4,9,18,36} |
| `_check_dsp(areg, breg, mreg, use_mult)` | `MREG=1` requires `USE_MULT=MULTIPLY` |

### 6.4 Helper Functions

| Function | Returns |
|---|---|
| `_xor_reduce(sig, width)` | Verilog XOR-reduce expression; `^sig` for width>1, bare `sig` for width=1 |
| `_counter_chain(n_bits=32)` | Verilog `reg` + `always @(posedge clk)` counter block string |

---

## 7. PRIMITIVE GENERATORS — COMPLETE REFERENCE

### 7.1 Generator Dispatch Table

| Key | Function | Category |
|---|---|---|
| `MMCME2_ADV` | `generate_MMCME2_ADV` | Clock |
| `PLLE2_ADV` | `generate_PLLE2_ADV` | Clock |
| `BUFIO` | `generate_BUFIO` | Clock |
| `BUFR` | `generate_BUFR` | Clock |
| `BUFG` | `generate_BUFG` | Clock |
| `BUFGCE` | `generate_BUFGCE` | Clock |
| `BUFH` | `generate_BUFH` | Clock |
| `OSERDESE2` | `generate_OSERDESE2` | IO |
| `OSERDESE2_CASCADE` | `generate_OSERDESE2_cascade` | IO |
| `ISERDESE2` | `generate_ISERDESE2` | IO |
| `IDELAYE2` | `generate_IDELAYE2` | IO |
| `OBUFDS` | `generate_OBUFDS` | IO |
| `IBUFDS` | `generate_IBUFDS` | IO |
| `IOBUF` | `generate_IOBUF` | IO |
| `RAMB18E1` | `generate_RAMB18E1` | Memory |
| `RAMB36E1` | `generate_RAMB36E1` | Memory |
| `FIFO18E1` | `generate_FIFO18E1` | Memory |
| `FIFO36E1` | `generate_FIFO36E1` | Memory |
| `DSP48E1` | `generate_DSP48E1` | Arithmetic |
| `STARTUPE2` | `generate_STARTUPE2` | Config |

---

### 7.2 Clock Primitives

#### BUFIO
- **Params**: none
- **Ports**: `clk` (input), `out` (output)
- **Topology**: `clk → BUFIO.I → BUFIO.O → 8-bit counter → ^cnt → out`
- **Notes**: No configuration registers. Routing test only. Counter forces IO-region placement.

#### BUFR
- **Params**: `BUFR_DIVIDE` (string)
- **Ports**: `clk` (input), `out` (output)
- **Topology**: `clk → BUFR(CE=1,CLR=0) → 8-bit counter → ^cnt → out`
- **XDC**: `BASE_XDC`
- **Instantiation params**: `BUFR_DIVIDE` (quoted string), `SIM_DEVICE("7SERIES")`

#### BUFG
- **Params**: none
- **Ports**: `clk` (input), `out` (output)
- **Topology**: `clk → BUFG → 8-bit counter → ^cnt → out`
- **XDC**: `BASE_XDC`

#### BUFGCE
- **Params**: `SIM_DEVICE`
- **Ports**: `clk` (input), `out` (output)
- **Topology**: Toggle CE each cycle → `BUFGCE(CE=ce) → counter → out`
- **XDC**: `BASE_XDC` + `set_property LOC BUFGCTRL_X0Y0 [get_cells u_bufgce]`
- **Special**: CE is toggled every cycle to exercise the enable path

#### BUFH
- **Params**: none
- **Ports**: `clk` (input), `out` (output)
- **Topology**: `clk → BUFH → 8-bit counter → ^cnt → out`

#### MMCME2_ADV
- **Params**: `CLKFBOUT_MULT_F`, `CLKIN1_PERIOD`, `DIVCLK_DIVIDE`, `CLKOUT0_DIVIDE_F`
- **Ports**: `clk` (input), `out` (output)
- **Topology**: `CLKIN1=clk, CLKFBIN=clkfb, CLKFBOUT=clkfb → CLKOUT0=out`
- **XDC**: `BASE_XDC`
- **VCO check**: `_check_vco(CLKFBOUT_MULT_F, CLKIN1_PERIOD, DIVCLK_DIVIDE)` (600–1200 MHz)

#### PLLE2_ADV
- **Params**: `CLKFBOUT_MULT`, `CLKIN1_PERIOD`, `DIVCLK_DIVIDE`, `CLKOUT0_DIVIDE`
- **Ports**: `clk` (input), `out` (output)
- **Topology**: same feedback loop as MMCME2_ADV
- **XDC**: `BASE_XDC`
- **VCO check**: (uses integer MULT, not MULT_F)

---

### 7.3 IO Primitives

#### OSERDESE2
- **Params**: `DATA_RATE_OQ`, `DATA_WIDTH`, `SERDES_MODE`, `DATA_RATE_TQ`
- **Ports**: `clk` (input), `out` (output, connected to OQ)
- **Topology**: 8-bit circular shift register `sr` feeds D1..D8; OQ → out
- **Validity**: `_check_oserdes_width(DATA_RATE_OQ, DATA_WIDTH)`
- **Hardcoded params**: `TRISTATE_WIDTH=1`, `TBYTE_CTL="FALSE"`, `TBYTE_SRC="FALSE"`, all INIT/SRVAL = 0
- **CLK=CLKDIV=clk** (same clock, fuzzing config bits not timing)
- **XDC**: `BASE_XDC`

#### OSERDESE2_CASCADE (10-bit DDR)
- **No params** (hardcoded DDR, DATA_WIDTH=10)
- **Topology**: SLAVE (SERDES_MODE="SLAVE") → SHIFTOUT1/2 → MASTER.SHIFTIN1/2; 10-bit shift register
- **Master D7/D8 = 1'b0** (slave fills higher bits via shift chain)
- **XDC**: `BASE_XDC`

#### ISERDESE2
- **Params**: `DATA_RATE`, `DATA_WIDTH`, `INTERFACE_TYPE`, `IOBDELAY`, `NUM_CE`
- **Ports**: `clk`, `din_pad` (inputs); `out` (XOR of Q1..Q8)
- **Topology**: `din_pad → IBUF → ISERDESE2.D`; Q1..Q8 XORed to `out`
- **Validity**: DDR: DATA_WIDTH ∈ {4,6,8}; SDR: ∈ {2,3,4,5,6,7,8}
- **Hardcoded**: `CLKB=~clk` (inverted CLK per UG953 for non-QDR), `OCLK/OCLKB=1'b0` (NETWORKING mode), `IOBDELAY="NONE"`, `SERDES_MODE="MASTER"`
- **XDC**: `ISERDES_XDC` (adds M16 for `din_pad`)

#### IDELAYE2
- **Params**: `IDELAY_TYPE`, `IDELAY_VALUE`, `HIGH_PERFORMANCE_MODE`, `SIGNAL_PATTERN`
- **Ports**: `clk`, `din_pad` (inputs); `out` (delayed ^ rdy_r)
- **Topology**: `din_pad → IBUF → IDELAYE2.IDATAIN → delayed`; IDELAYCTRL also instantiated
- **Validity**: `_check_idelay_value(IDELAY_VALUE)` (0–31)
- **Required companion**: `IDELAYCTRL` with `IODELAY_GROUP="fuzz_grp"` attribute
- **Hardcoded**: `REFCLK_FREQUENCY=200.0`, `CINVCTRL_SEL="FALSE"`, `PIPE_SEL="FALSE"`, `DELAY_SRC="IDATAIN"`, `CNTVALUEIN=5'b0`
- **XDC**: `ISERDES_XDC`

#### OBUFDS
- **Params**: `IOSTANDARD`, `SLEW`
- **Ports**: `clk` (input), `out_p`, `out_n` (outputs)
- **Topology**: 8-bit counter → `^cnt` → `OBUFDS.I`; differential outputs
- **XDC**: `DIFF_OUT_XDC` (uses C14/C13 for out_p/out_n)

#### IBUFDS
- **Params**: `IOSTANDARD`, `DIFF_TERM`
- **Ports**: `clk`, `din_p`, `din_n` (inputs); `out` (ibuf_out XOR ^cnt)
- **Topology**: `din_p/din_n → IBUFDS → ibuf_out`; counter XORed with ibuf_out
- **Pin assignment**: F14 (din_p), F15 (din_n) — JA1_P/JA1_N, Bank 34
- **Critical constraint**: `clk` cannot fan to both `IBUFDS.I` and fabric (Vivado Synth 8-5535), so dedicated diff-pair pins are used
- **Hardware note**: `DIFF_TERM=TRUE` excluded — XC7S50 has HR banks only; internal termination requires HP banks
- **XDC**: Custom (defines F14/F15, C13 for out)

#### IOBUF
- **Params**: `IOSTANDARD`
- **Ports**: `clk` (input), `out` (output)
- **Topology**: Toggling T/I fed to `IOBUF`; `IO` wire tied to `io_wire`; `out = buf_out ^ ^cnt ^ io_wire`
- **Hardcoded**: `SLEW="SLOW"`, `DRIVE=12`
- **XDC**: `BASE_XDC`

---

### 7.4 Memory Primitives

#### RAMB18E1

**Address/data width tables** (used internally in generator):

| Width param | Address bits (aw) | Data bits (dw) | Parity bits (pw) |
|---|---|---|---|
| 1 | 14 | 1 | 0 |
| 2 | 13 | 2 | 0 |
| 4 | 12 | 4 | 0 |
| 9 | 11 | 8 | 1 |
| 18 | 10 | 16 | 2 |

- **Params**: `READ_WIDTH_A`, `WRITE_WIDTH_A`, `READ_WIDTH_B`, `WRITE_WIDTH_B`, `DOA_REG`, `DOB_REG`, `RAM_MODE`
- **Ports**: `clk` (input), `out` (^dout_a[dw_a-1:0] ^ ^dout_b[dw_b-1:0])
- **Topology**: Incrementing address/data counters feed both ports; XOR of read outputs drives `out`
- **Validity**: `_check_ramb_widths("RAMB18E1", ...)` — valid set {1,2,4,9,18}
- **Hardcoded params**: `WRITE_MODE_A/B="WRITE_FIRST"`, `RDADDR_COLLISION_HWCONFIG="DELAYED_WRITE"`, `SIM_COLLISION_CHECK="ALL"`, `SIM_DEVICE="7SERIES"`
- **Port bus widths**: DOADO/DOBDO are always 16-bit wide (UG953 p.567); address always padded to 14 bits
- **XDC**: `BASE_XDC`

#### RAMB36E1

**Address/data width tables**:

| Width param | Address bits (aw) | Data bits (dw) | Parity bits (pw) |
|---|---|---|---|
| 1 | 15 | 1 | 0 |
| 2 | 14 | 2 | 0 |
| 4 | 13 | 4 | 0 |
| 9 | 12 | 8 | 1 |
| 18 | 11 | 16 | 2 |
| 36 | 10 | 32 | 4 |

- **Params**: same as RAMB18E1 plus DOA_REG/DOB_REG
- **Additional validity**: `READ_WIDTH_A=36 AND READ_WIDTH_B=36` simultaneously is invalid TDP
- **XDC**: `BASE_XDC`

#### FIFO18E1
- **Params**: `DATA_WIDTH`, `FIFO_MODE`, `DO_REG`, `FIRST_WORD_FALL_THROUGH`
- **Data width map**: `{4:4, 9:8, 18:16}` (dw = actual data bits)
- **FWFT restriction**: `FIRST_WORD_FALL_THROUGH="TRUE"` → raises `ValueError` (incompatible with `EN_SYN="TRUE"`)
- **Hardcoded**: `EN_SYN="TRUE"` (single-clock operation; avoids DO_REG=1 mandatory constraint)
- **Topology**: Phase counter 0..15; write phase 0..7, read phase 8..15; `rst_sync=1` (satisfies DRC REQP-34 non-constant requirement)
- **DRC note**: `RST` must be driven by non-constant net (REQP-34)
- **XDC**: `BASE_XDC`
- **DO bus width**: Always 32 bits (DI/DO buses are always 32-bit per UG953 p.351)

#### FIFO36E1
- **Params**: `DATA_WIDTH`, `DO_REG`, `FIRST_WORD_FALL_THROUGH`
- **Data width map**: `{4:4, 9:8, 18:16, 36:32}`
- **FWFT restriction**: same `ValueError` as FIFO18E1
- **Hardcoded**: `FIFO_MODE="FIFO36"`, `EN_SYN="TRUE"`, `EN_ECC_READ/WRITE="FALSE"`
- **DO bus width**: Always 64 bits (DI/DO buses are always 64-bit per UG953 p.356)
- **Bug note**: `RST` references `rst_sync` but `rst_sync` is not declared; this is a known limitation in generator
- **XDC**: `BASE_XDC`

---

### 7.5 Arithmetic Primitives

#### DSP48E1
- **Params**: `AREG`, `BREG`, `CREG`, `PREG`, `MREG`, `USE_MULT`
- **Validity**: `_check_dsp(areg, breg, mreg, use_mult)` — `MREG=1` requires `USE_MULT=MULTIPLY`
- **Port widths**: A = 30 bits, B = 18 bits, C = 48 bits, P = 48 bits
- **Topology**: `a_reg - 1`, `b_reg + 1` each cycle; `c_reg ← p_out` (feedback prevents pruning; implements accumulator)
- **Hardcoded OPMODE**: `7'b0110101` (P = A*B + C, multiply-accumulate)
- **Hardcoded ALUMODE**: `4'b0000`
- **XDC**: `BASE_XDC` + `set_property LOC DSP48_X0Y0 [get_cells u_dsp]`
- **ACASCREG/BCASCREG**: Set to `areg if areg > 0 else 0`

---

### 7.6 Configuration Primitives

#### STARTUPE2
- **Params**: `PROG_USR`, `SIM_CCLK_FREQ`
- **Ports**: `clk` (input), `out` (eos ^ cfgmclk ^ ^cnt)
- **Topology**: Minimal; captures CFGCLK, CFGMCLK, EOS, PREQ outputs; XORs into `out`
- **Hardcoded**: `GSR=0`, `GTS=0`, `KEYCLEARB=1`, `PACK=0`, `USRCCLKTS=1`, `USRDONEO=1`, `USRDONETS=1`
- **XDC**: `BASE_XDC`

---

## 8. PARAMS JSON FILES — ALL PRIMITIVES

### 8.1 JSON Structure

```json
{
  "primitive": "PRIMITIVE_NAME",
  "PARAM_KEY": [value1, value2, ...],
  "constraints": "human-readable constraint notes"
}
```

Keys `"primitive"` and `"constraints"` are excluded from parameter expansion (filtered in `expand_params`).

### 8.2 Complete Parameter Tables

#### MMCME2_ADV (`mmcme2_adv.json`)
| Param | Values |
|---|---|
| `CLKFBOUT_MULT_F` | `[6.0, 8.0, 10.0, 12.0]` |
| `CLKIN1_PERIOD` | `[10.0]` |
| `DIVCLK_DIVIDE` | `[1]` |
| `CLKOUT0_DIVIDE_F` | `[4.0, 6.0, 8.0]` |

**Constraint**: VCO = MULT_F × 1000 / PERIOD must be 600–1200 MHz.
**Total combos**: 4 × 1 × 1 × 3 = **12**

#### PLLE2_ADV (`plle2_adv.json`)
| Param | Values |
|---|---|
| `CLKFBOUT_MULT` | `[8, 10, 12, 16]` |
| `CLKIN1_PERIOD` | `[10.0]` |
| `CLKOUT0_DIVIDE` | `[4, 6, 8]` |
| `DIVCLK_DIVIDE` | `[1]` |

**Constraint**: VCO = MULT × 1000 / PERIOD must be 800–1600 MHz.
**Total combos**: **12**

#### BUFGCE (`bufgce.json`)
| Param | Values |
|---|---|
| `SIM_DEVICE` | `["7SERIES"]` |

**Total combos**: **1**

#### BUFR (`bufr.json`)
| Param | Values |
|---|---|
| `BUFR_DIVIDE` | `["BYPASS", "1", "2", "3", "4", "5", "6", "7", "8"]` |

**Total combos**: **9**

#### OSERDESE2 (`oserdese2.json`)
| Param | Values |
|---|---|
| `DATA_RATE_OQ` | `["SDR", "DDR"]` |
| `DATA_WIDTH` | `[4, 6, 8]` |
| `SERDES_MODE` | `["MASTER"]` |
| `DATA_RATE_TQ` | `["BUF"]` |
| `TRISTATE_WIDTH` | `[1]` |

**Total combos**: 2 × 3 × 1 × 1 × 1 = **6**

#### ISERDESE2 (`iserdese2.json`)
| Param | Values |
|---|---|
| `DATA_RATE` | `["SDR", "DDR"]` |
| `DATA_WIDTH` | `[4, 6, 8]` |
| `INTERFACE_TYPE` | `["NETWORKING"]` |
| `IOBDELAY` | `["NONE"]` |
| `NUM_CE` | `[1]` |

**Total combos**: **6**

#### IDELAYE2 (`idelaye2.json`)
| Param | Values |
|---|---|
| `IDELAY_TYPE` | `["FIXED", "VARIABLE"]` |
| `IDELAY_VALUE` | `[0, 8, 16, 24, 31]` |
| `HIGH_PERFORMANCE_MODE` | `["FALSE", "TRUE"]` |
| `SIGNAL_PATTERN` | `["DATA", "CLOCK"]` |

**Total combos**: 2 × 5 × 2 × 2 = **40**

#### IBUFDS (`ibufds.json`)
| Param | Values |
|---|---|
| `IOSTANDARD` | `["LVDS_25"]` |
| `DIFF_TERM` | `["FALSE"]` |

**Constraint**: `DIFF_TERM=TRUE` excluded — requires HP bank; XC7S50 has HR banks only.
**Total combos**: **1**

#### OBUFDS (`obufds.json`)
| Param | Values |
|---|---|
| `IOSTANDARD` | `["LVDS_25", "TMDS_33", "DIFF_SSTL18_I"]` |
| `SLEW` | `["SLOW", "FAST"]` |

**Total combos**: **6**

#### RAMB18E1 (`ramb18e1.json`)
| Param | Values |
|---|---|
| `READ_WIDTH_A` | `[1, 2, 4, 9, 18]` |
| `WRITE_WIDTH_A` | `[1, 2, 4, 9, 18]` |
| `READ_WIDTH_B` | `[1, 2, 4, 9, 18]` |
| `WRITE_WIDTH_B` | `[1, 2, 4, 9, 18]` |
| `RAM_MODE` | `["TDP"]` |
| `DOA_REG` | `[0, 1]` |
| `DOB_REG` | `[0, 1]` |

**Total combos**: 5⁴ × 1 × 2 × 2 = **2500**

#### RAMB36E1 (`ramb36e1.json`)
| Param | Values |
|---|---|
| `READ_WIDTH_A` | `[1, 2, 4, 9, 18, 36]` |
| `WRITE_WIDTH_A` | `[1, 2, 4, 9, 18, 36]` |
| `READ_WIDTH_B` | `[1, 2, 4, 9, 18, 36]` |
| `WRITE_WIDTH_B` | `[1, 2, 4, 9, 18, 36]` |
| `RAM_MODE` | `["TDP"]` |
| `DOA_REG` | `[0, 1]` |
| `DOB_REG` | `[0, 1]` |

**Constraint**: `READ_WIDTH_A=36 AND READ_WIDTH_B=36` simultaneously invalid.
**Total combos**: 6⁴ × 1 × 2 × 2 ≈ **5184** (minus invalid combos)

#### FIFO18E1 (`fifo18e1.json`)
| Param | Values |
|---|---|
| `DATA_WIDTH` | `[4, 9, 18]` |
| `FIFO_MODE` | `["FIFO18"]` |
| `DO_REG` | `[0, 1]` |
| `FIRST_WORD_FALL_THROUGH` | `["FALSE", "TRUE"]` |

**Runtime filter**: `FIRST_WORD_FALL_THROUGH="TRUE"` → raises `ValueError` → skipped.
**Effective combos**: 3 × 1 × 2 × 1 = **6** (FWFT=TRUE skipped)

#### FIFO36E1 (`fifo36e1.json`)
| Param | Values |
|---|---|
| `DATA_WIDTH` | `[4, 9, 18, 36]` |
| `DO_REG` | `[0, 1]` |
| `FIRST_WORD_FALL_THROUGH` | `["FALSE", "TRUE"]` |

**Effective combos**: 4 × 2 × 1 = **8** (FWFT=TRUE skipped)

#### DSP48E1 (`dsp48e1.json`)
| Param | Values |
|---|---|
| `AREG` | `[0, 1, 2]` |
| `BREG` | `[0, 1, 2]` |
| `CREG` | `[0, 1]` |
| `PREG` | `[0, 1]` |
| `MREG` | `[0, 1]` |
| `USE_MULT` | `["MULTIPLY", "NONE"]` |
| `AUTORESET_PATDET` | `["NO_RESET"]` |
| `USE_PATTERN_DETECT` | `["NO_PATDET"]` |

**Runtime filter**: `MREG=1, USE_MULT="NONE"` → `ValueError` → skipped.
**Total combos**: 3 × 3 × 2 × 2 × 2 × 2 × 1 × 1 = **144** (minus MREG=1+NONE combos)

---

## 9. COMPARE_BITS.PY — BITSTREAM COMPARISON

**Location**: `~/fpga_scripts/fuzz/compare_bits.py`

### 9.1 Invocation

```bash
python3 compare_bits.py <vivado.bit> <nextpnr.bit> <PRIMITIVE> '<params_json>' <out.json>
```

Arguments are positional via `sys.argv[1:6]`.

### 9.2 Constants

```python
PRJXRAY_DB = os.path.expanduser("~/nextpnr-xilinx/xilinx/external/prjxray-db/spartan7")
PART = "xc7s50csga324-1"
BIT2FASM = os.path.expanduser("~/prjxray/utils/bit2fasm.py")
BITREAD = os.path.expanduser("~/prjxray/build/tools/bitread")
```

### 9.3 PRIM_FILTERS — Primitive-to-Keyword Map

| Primitive | Filter Keywords |
|---|---|
| `MMCME2_ADV` | `["MMCME2", "HCLK_CMT", "CLK_FREQ"]` |
| `PLLE2_ADV` | `["PLLE2", "HCLK_CMT", "CLK_FREQ"]` |
| `OSERDESE2` | `["OLOGIC", "OSERDES"]` |
| `ISERDESE2` | `["ILOGIC", "ISERDES"]` |
| `IDELAYE2` | `["IDELAY", "IODELAY"]` |
| `BUFIO` | `["BUFIO", "HCLK_IOI"]` |
| `BUFR` | `["BUFR", "HCLK_IOI"]` |
| `BUFG` | `["BUFG", "BUFGCTRL"]` |
| `BUFGCE` | `["BUFG", "BUFGCTRL"]` |
| `OBUFDS` | `["IOB", "OBUFTDS"]` |
| `IBUFDS` | `["IOB", "IBUFDSE2"]` |
| `RAMB18E1` | `["RAMB18", "BRAM"]` |
| `RAMB36E1` | `["RAMB36", "BRAM"]` |
| `FIFO18E1` | `["RAMB18", "BRAM"]` |
| `FIFO36E1` | `["RAMB36", "BRAM"]` |
| `DSP48E1` | `["DSP48"]` |

**Fallback**: If primitive not in `PRIM_FILTERS`, uses `[primitive.upper()]` as the single keyword.

### 9.4 EXCLUDE List (Always Filtered Out)

`["INT_L", "INT_R", "CLBLL", "CLBLM", "SLICEL", "SLICEM"]`

These are pure routing/logic tiles — excluded from all comparisons regardless of primitive.

### 9.5 filter_lines() Logic

```python
def filter_lines(out_str, primitive):
    keywords = PRIM_FILTERS.get(primitive.upper(), [primitive.upper()])
    lines = set()
    for line in out_str.splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        if any(ex in line for ex in EXCLUDE): continue
        if any(kw in line for kw in keywords):
            lines.add(line)
    return lines  # returns a Python set (deduplicates)
```

### 9.6 bit2fasm Invocation

```python
def bit2fasm_proc(bit_file):
    cmd = ["python3", BIT2FASM, "--bitread", BITREAD, "--db-root", PRJXRAY_DB, "--part", PART, bit_file]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
```

Both Vivado and nextpnr bitstreams are processed in parallel (two `Popen` calls before either `.communicate()`).

### 9.7 Diff Computation

```python
v = filter_lines(out_v, primitive)   # Vivado FASM set
n = filter_lines(out_n, primitive)   # nextpnr FASM set
missing = sorted(v - n)              # in Vivado but not nextpnr
extra   = sorted(n - v)              # in nextpnr but not Vivado
status  = "PASS" if not missing and not extra else "FAIL"
```

---

## 10. HEADLESS_PNR.MJS — WASM P&R PIPELINE

**Location**: `~/fpga_scripts/fuzz/headless_pnr.mjs`

### 10.1 WASM Asset Paths

| Asset | Path |
|---|---|
| `nextpnr-xilinx.wasm` | `~/fpga_assets/nextpnr-xilinx.wasm` |
| `nextpnr-xilinx.js` | `~/fpga_assets/nextpnr-xilinx.js` |
| `xc7s50.bin.br` | `~/fpga_assets/xc7s50.bin.br` (Brotli) |
| `xc7s50_fasm_map_v4.json.br` | `~/fpga_assets/xc7s50_fasm_map_v4.json.br` (Brotli) |
| `xc7frames2bit.wasm` | `~/fpga_assets/xc7frames2bit.wasm` |
| `xc7frames2bit.js` | `~/fpga_assets/xc7frames2bit.js` |
| `part.yaml` | `~/fpga_assets/part.yaml` |

**Alternate workspace**: `FPGA_ASSETS` env var or `/workspaces/Vivado/PRODUCTION_GRADE` (if exists).

### 10.2 Brotli Cache

```javascript
function readBrotliSync(filePath) {
    const cachePath = '/tmp/' + path.basename(filePath) + '_cache.bin';
    // Returns cached decompressed data if mtime >= original file mtime
    // Else decompresses and writes cache
}
```

Cache key: `/tmp/{basename}_cache.bin`. Invalidated if original file is newer than cache.

### 10.3 Pipeline Steps

**Step 1 — YoWASP Yosys Synthesis**:
```javascript
const { runYosys } = await import('/home/nathan37/.nvm/versions/node/v20.20.0/lib/node_modules/@yowasp/yosys/gen/bundle.js');
result = await runYosys(
    ['-p', `synth_xilinx -flatten -abc9 -arch xc7 -top ${topModule}; write_json synth.json`, topVerilogBasename],
    { [topVerilogBasename]: verilogCode }
);
```
Output: `synth.json` written to CWD.

**Step 2 — XDC Filtering**:
Filters XDC before passing to nextpnr:
- Strips trailing `;`
- Strips inline comments `#`
- **Dropped directives**: `get_iobanks`, `get_iobank`, `current_instance`, `current_design`, `INTERNAL_VREF`, `IO_BUFFER_TYPE`, `CFGBS`, `CFGBVS`, `CONFIG_VOLTAGE`, `SPI_buswidth`, `UNUSEDPIN`, `COMPRESS`
- **Dropped ports**: Any `get_ports` reference where the port name is not in the netlist's `validPorts` set

**Step 3 — nextpnr WASM P&R**:
```javascript
global.Module.arguments = [
    '--chipdb', '/chipdb.bin',
    '--json', '/design.json',
    '--xdc', '/design.xdc',
    '--fasm', '/out.fasm',
    '--timing-allow-fail',
    '--top', topModule
];
```

**Step 4 — FASM Fixup**:
Removes `DRIVE`/`SLEW` attributes from tiles that have `IN_ONLY` set (these are input-only IOBs; drive/slew are meaningless and cause DRC errors).

**Step 5 — Custom FASM→Frames**:
`generateFramesSync(fasmStr, fasmMap)` — JavaScript implementation of FASM-to-frame conversion using `xc7s50_fasm_map_v4.json` lookup table.

**Step 6 — xc7frames2bit WASM**:
```javascript
// Injects global.f2bFS = FS before createWasm() fires
f2bCode = f2bCode.replace('createWasm();', 'global.f2bFS = FS; createWasm();');
vm.runInThisContext('(function(Module){\n' + f2bCode + '\n})(global.Module)');
```

**Global timeout**: 5 minutes (`setTimeout(() => process.exit(1), 5 * 60 * 1000)`).

---

## 11. HEADLESS_PNR_NATIVE.MJS — NATIVE P&R PIPELINE

**Location**: `~/fpga_scripts/fuzz/headless_pnr_native.mjs`

### 11.1 Key Paths

| Asset | Path |
|---|---|
| `nextpnr-xilinx` binary | `~/nextpnr-xilinx/build/nextpnr-xilinx` |
| chipdb | `~/nextpnr-xilinx/xilinx/xc7s50.bin` |
| boost libs | `~/boost_libs` |

### 11.2 Pipeline Steps

**Step 1 — Synthesis**: Spawns `headless_pnr.mjs` as a subprocess with `outputBit=/dev/null`. This writes `synth.json` to CWD (working directory at call time).

**Step 2 — Native nextpnr P&R**:
```javascript
spawnSync(NEXTPNR_BIN, [
    '--chipdb', CHIPDB, '--json', 'synth.json',
    '--xdc', xdcFile, '--fasm', 'out.fasm'
], {
    env: { ...process.env, LD_LIBRARY_PATH: `${BOOST_LIBS}:...` },
    timeout: 300000  // 5 minutes
})
```

**Steps 3–4** (frames2bit): Reuses WASM frames2bit from `headless_pnr.mjs` assets.

---

## 12. FIND_NODES.SH — CLUSTER NODE DISCOVERY

**Location**: `~/fpga_scripts/fuzz/find_nodes.sh`

### 12.1 Invocation

```bash
~/fpga_scripts/fuzz/find_nodes.sh [WANTED_NODES=4] [MIN_FREE_FACTOR=1]
```

Outputs one hostname per line (without `.ews.illinois.edu` suffix).

### 12.2 Lock File (Node Reservation)

- **Path**: `/tmp/fuzz_node_lock_${USER}`
- **Format**: One `node timestamp` per line
- **TTL**: `LOCK_TTL=45` seconds (enough for Vivado to spin up)
- **Cleanup**: `awk -v now="$now" -v ttl="$LOCK_TTL" '$2 + ttl > now'` filters on read
- **Purpose**: Prevents dispatching multiple jobs to same node in rapid succession

### 12.3 Node Cache

- **Path**: `/tmp/fuzz_node_cache_${USER}`
- **Format**: `node load_avg timestamp` per line
- **TTL**: `CACHE_TTL=30` seconds
- **Purpose**: Avoids re-probing recently checked nodes

### 12.4 SSH Probe

```bash
for i in {01..39}; do
    ssh -n -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o PasswordAuthentication=no \
        fastx3-$i.ews.illinois.edu \
        "load=\$(awk '{print \$1}' /proc/loadavg); echo \"fastx3-$i \$load\"" >> "$TMP_OUT" 2>/dev/null &
done
```

- All 39 nodes probed in parallel background jobs.
- Early exit: checks every 1s, 1s, 0.5s for enough good nodes before all probes finish.
- Good node threshold: `load < 6.0`

### 12.5 Node Selection

```bash
sort -k2 -n "$TMP_OUT" | awk 'NR<=10' | shuf
```

Sorts by load, takes top 10 lowest-load, shuffles (avoids hotspot clustering). Iterates selecting nodes not in excluded set until `FOUND >= WANTED_NODES`.

---

## 13. CLEANUP.SH — STALE LOCK REMOVAL

**Location**: `~/fpga_scripts/fuzz/cleanup.sh`

### 13.1 Stale Lock Criteria (any one triggers removal)

| Criterion | Check |
|---|---|
| Age > 2 hours | `AGE=$((NOW - LAST_MOD)) > 7200` |
| Local PID dead | `HOST == $(hostname) AND kill -0 $PID` fails |
| Remote PID dead | `ssh $HOST "kill -0 $PID"` fails or SSH unreachable |

### 13.2 Lock Content Format

`{PID}:{hostname}` — e.g., `12345:fastx3-07`

SSH options used for liveness check: `-o ConnectTimeout=2 -o StrictHostKeyChecking=no -o PasswordAuthentication=no`

---

## 14. HEALTH_CHECK.SH — PRE-FLIGHT VERIFICATION

**Location**: `~/fpga_scripts/fuzz/health_check.sh`

### 14.1 Checks (in order)

| Check | Method | Failure Condition |
|---|---|---|
| Disk quota | `df -h ~ \| awk 'NR==2 {print $5}'` | `> 95%` → CRITICAL exit; `> 85%` → WARNING |
| bitread binary exists | `[ -f "$BITREAD" ]` | Not found → exit 1 |
| Reference bitstream exists | `[ -f "$REF_BIT" ]` | Not found → exit 1 |
| bit2fasm pipeline live | Run on reference `.bit`, count output lines | `== 0` → CRITICAL exit |
| compare_bits.py sanity | Run on identical bitstreams | `matching == 0` → CRITICAL exit (false positive detection) |
| Stale locks | `cleanup.sh` | Cleans but does not fail |
| Node availability | `find_nodes.sh 1 4` | No nodes → CRITICAL exit |

### 14.2 Quick Mode

```bash
health_check.sh --quick
```

Skips smoke test (Steps 6+). Runs only checks 1–5.

### 14.3 Smoke Test

Uses first combo from `params/mmcme2_adv.json`. Runs full `fuzz_one.sh MMCME2_ADV`. Checks:
- `result.json` exists
- `status == "PASS"` AND `matching > 0`

If `status == "PASS"` but `matching == 0` → **false positive detected** → CRITICAL failure.

### 14.4 Reference Files

| File | Path |
|---|---|
| Reference bitstream | `~/prjxray/lib/test_data/configuration_test.bit` |

---

## 15. STATUS.SH — PROGRESS DASHBOARD

**Location**: `~/fpga_scripts/fuzz/status.sh`

### 15.1 Invocation

```bash
status.sh [PRIMITIVE=MMCME2_ADV]
```

Scans: `~/fuzz_results/$PRIMITIVE/gen_{GEN_HASH}/`

### 15.2 Output Fields

| Field | Method |
|---|---|
| PASS count | `grep -rl "status.*PASS" \| wc -l` |
| FAIL count | `grep -rl "status.*FAIL" \| wc -l` |
| ERROR count | `grep -rl "status.*ERROR" \| wc -l` |
| RUNNING count | `find … -name "running.lock" \| wc -l` |
| DONE total | `find … -name "result.json" \| wc -l` |
| Active nodes | `cat running.lock files \| sort \| uniq -c` |
| Error reasons | `grep -rh '"reason"' \| sort \| uniq -c \| sort -rn \| head -5` |
| Fail details | `python3` inline: prints params + first 2 missing/extra FASM lines per FAIL |

---

## 16. LOCK PROTOCOL & SELF-HEALING

### 16.1 Lock Lifecycle

```
1. Check result.json → skip if cached
2. mkdir -p $TEST_DIR
3. Check existing lock:
   a. If lock exists → read PID:HOST
   b. Same host: kill -0 PID → alive=exit(0), dead=steal
   c. Remote host: ssh kill -0 → alive=exit(0), dead/unreachable=steal
4. Write "$$:$(hostname)" → lock file
5. Start heartbeat (touch every 60s)
6. ... do work ...
7. EXIT TRAP: kill heartbeat, rm lock, rm param file, rm LOCAL_TMP
```

### 16.2 Lock File Paths

| Lock type | Path |
|---|---|
| Job lock | `$TEST_DIR/running.lock` |
| Node reservation | `/tmp/fuzz_node_lock_${USER}` |

### 16.3 Stale Lock Age Threshold

`> 7200 seconds` (2 hours) → always stale regardless of PID liveness.

---

## 17. CACHING & HASH SYSTEM

### 17.1 Two-Level Cache

| Level | Key | Purpose |
|---|---|---|
| GEN_HASH | `md5sum(gen_verilog.py)[0:8]` | Namespace for generator version; invalidates all results when generator changes |
| Test HASH | `md5sum(PARAMS_JSON + PRIMITIVE)` (32 hex chars) | Unique per (primitive, param combo) |

### 17.2 Cache Hit Logic

```bash
TEST_DIR="$HOME/fuzz_results/${PRIMITIVE}/gen_${GEN_HASH}/test_$HASH"
if [ -f "$TEST_DIR/result.json" ]; then
    # skip
fi
```

### 17.3 Uncached Count (Used in Auto-Scaling)

```python
# Python inline in fuzz.sh
for combo in itertools.product(...):
    params = json.dumps(...)
    h = hashlib.md5((params + PRIMITIVE).encode()).hexdigest()
    if not os.path.exists(f'~/fuzz_results/{PRIMITIVE}/gen_{GEN_HASH}/test_{h}/result.json'):
        count += 1
```

---

## 18. XDC TEMPLATES

### 18.1 BASE_XDC

```
set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 10.000 -name sys_clk [get_ports clk]
```

Used by: BUFIO, BUFR, BUFG, BUFGCE, BUFH, OSERDESE2, OSERDESE2_CASCADE, IOBUF, RAMB18E1, RAMB36E1, FIFO18E1, FIFO36E1, MMCME2_ADV, PLLE2_ADV, STARTUPE2, DSP48E1

### 18.2 ISERDES_XDC

```
set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN M16 [get_ports din_pad]
set_property IOSTANDARD LVCMOS33 [get_ports din_pad]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 10.000 -name sys_clk [get_ports clk]
```

Used by: ISERDESE2, IDELAYE2

### 18.3 DIFF_OUT_XDC

```
set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]
set_property PACKAGE_PIN C14 [get_ports out_p]
set_property PACKAGE_PIN C13 [get_ports out_n]
set_property IOSTANDARD {iostd} [get_ports out_p]
set_property IOSTANDARD {iostd} [get_ports out_n]
```

`{iostd}` is substituted with `params["IOSTANDARD"]`. Used by: OBUFDS

### 18.4 IBUFDS Custom XDC

```
set_property PACKAGE_PIN N15 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN F14 [get_ports din_p]
set_property PACKAGE_PIN F15 [get_ports din_n]
set_property IOSTANDARD {iostd} [get_ports din_p]
set_property IOSTANDARD {iostd} [get_ports din_n]
set_property PACKAGE_PIN C13 [get_ports out]
set_property IOSTANDARD LVCMOS33 [get_ports out]
create_clock -period 10.000 -name sys_clk [get_ports clk]
```

### 18.5 BUFGCE XDC Addition

`BASE_XDC` plus: `set_property LOC BUFGCTRL_X0Y0 [get_cells u_bufgce]`

### 18.6 DSP48E1 XDC Addition

`BASE_XDC` plus: `set_property LOC DSP48_X0Y0 [get_cells u_dsp]`

---

## 19. VALIDITY GUARDS (ALL PRIMITIVES)

### 19.1 `_check_vco(mult_f, period, divclk=1)`

```
VCO = mult_f * 1000.0 / (period * divclk)
Valid range: 600.0 ≤ VCO ≤ 1200.0 MHz
Raises: ValueError("VCO={vco:.1f} MHz out of range 600-1200 MHz (MULT_F={mult_f}, PERIOD={period}, DIVCLK={divclk})")
```

### 19.2 `_check_oserdes_width(data_rate, data_width)`

| data_rate | Valid data_width values | Excluded (why) |
|---|---|---|
| `"SDR"` | {2, 3, 4, 5, 6, 7, 8} | — |
| `"DDR"` | {4, 6, 8} | 10, 14: require MASTER+SLAVE cascade (separate generator) |

### 19.3 `_check_idelay_value(v)`

```
Valid: 0 ≤ int(v) ≤ 31
Raises: ValueError(f"IDELAY_VALUE must be 0-31, got {v}")
```

### 19.4 `_check_ramb_widths(primitive, rw_a, ww_a, rw_b, ww_b)`

| Primitive | Valid width set |
|---|---|
| RAMB18E1 | {1, 2, 4, 9, 18} |
| RAMB36E1 | {1, 2, 4, 9, 18, 36} |

Raises `ValueError` for any width not in the valid set.

### 19.5 `_check_dsp(areg, breg, mreg, use_mult)`

```
If mreg == 1 and use_mult == "NONE":
    Raises: ValueError("DSP48E1: MREG=1 requires USE_MULT=MULTIPLY")
```

### 19.6 RAMB36E1 Dual-36 Check (inside generator)

```
If rw_a == 36 and rw_b == 36:
    Raises: ValueError("RAMB36E1: READ_WIDTH_A=36 and READ_WIDTH_B=36 simultaneously is invalid TDP")
```

### 19.7 FIFO FWFT Check (inside generators)

```
If fwft == "TRUE":
    Raises: ValueError("FIFO18E1: FIRST_WORD_FALL_THROUGH=TRUE incompatible with EN_SYN=TRUE")
    # (same message pattern for FIFO36E1)
```

### 19.8 ISERDESE2 Width Check (inside generator)

```
DDR: data_width not in (4, 6, 8) → ValueError
SDR: data_width not in (2, 3, 4, 5, 6, 7, 8) → ValueError
```

---

## 20. FASM FILTER SYSTEM (COMPARE_BITS.PY)

### 20.1 Filter Pipeline

```
bit2fasm output (raw FASM lines)
  → strip blank lines
  → strip comment lines (startswith "#")
  → reject if any EXCLUDE keyword present in line
  → accept if any PRIM_FILTER keyword present in line
  → deduplicate (Python set)
  → sort() for diff output
```

### 20.2 EXCLUDE Keywords (Universal)

All of these appearing anywhere in a FASM line cause it to be discarded:

```python
EXCLUDE = ["INT_L", "INT_R", "CLBLL", "CLBLM", "SLICEL", "SLICEM"]
```

Rationale: These are general fabric routing and LUT/FF slices. Their FASM bits are not relevant to the primitive under test.

### 20.3 Set Operations

| Variable | Meaning |
|---|---|
| `v` | Set of filtered FASM lines from Vivado bitstream |
| `n` | Set of filtered FASM lines from nextpnr bitstream |
| `v - n` = `missing` | Bits Vivado sets that nextpnr does not → bug in nextpnr |
| `n - v` = `extra` | Bits nextpnr sets that Vivado does not → spurious configuration |
| `v & n` | Matching bits (correct) |

---

## 21. RESULT JSON SCHEMA

### 21.1 Success/Fail Result

```json
{
  "primitive": "RAMB18E1",
  "params": {"READ_WIDTH_A": 9, "WRITE_WIDTH_A": 9, ...},
  "status": "PASS" | "FAIL",
  "missing": ["BRAM_L_X6Y10.RAMB18_Y0.DATA_WIDTH_A[02]", ...],
  "extra": [...],
  "matching": 42
}
```

### 21.2 Error Result (from fuzz_one.sh)

```json
{
  "status": "ERROR",
  "reason": "TIMEOUT" | "VIVADO_CRASH_{EXIT_CODE}" | "MISSING_BITSTREAM",
  "primitive": "MMCME2_ADV",
  "params": {...}
}
```

### 21.3 Field Definitions

| Field | Type | Meaning |
|---|---|---|
| `primitive` | string | Uppercase primitive name |
| `params` | object | The exact parameter combo that was tested |
| `status` | `"PASS"` / `"FAIL"` / `"ERROR"` | Test result |
| `missing` | array of strings | FASM lines in Vivado not in nextpnr (sorted) |
| `extra` | array of strings | FASM lines in nextpnr not in Vivado (sorted) |
| `matching` | integer | Count of identical FASM lines in both |
| `reason` | string | Only present for `status == "ERROR"` |

---

## 22. ENVIRONMENT VARIABLES

| Variable | Set By | Used By | Meaning |
|---|---|---|---|
| `GEN_HASH` | `fuzz.sh`, propagated to workers | `fuzz_one.sh`, `status.sh` | 8-char MD5 prefix of `gen_verilog.py` |
| `FPGA_ASSETS` | User (optional) | `headless_pnr.mjs` | Override asset directory (default: `~/fpga_assets`) |
| `LD_LIBRARY_PATH` | `fuzz_one.sh` | nextpnr native binary | Boost + Xilinx libs path |
| `USER` | Shell | `find_nodes.sh`, `cleanup.sh` | For lock file naming |

---

## 23. FILESYSTEM PATHS — COMPLETE REFERENCE

### 23.1 Scripts

```
~/fpga_scripts/fuzz/
  fuzz.sh
  fuzz_one.sh
  gen_verilog.py
  compare_bits.py
  headless_pnr.mjs
  headless_pnr_native.mjs
  find_nodes.sh
  cleanup.sh
  health_check.sh
  status.sh
  run_fuzz_vivado.tcl
  params/
    mmcme2_adv.json
    plle2_adv.json
    bufgce.json
    bufr.json
    oserdese2.json
    iserdese2.json
    idelaye2.json
    ibufds.json
    obufds.json
    ramb18e1.json
    ramb36e1.json
    fifo18e1.json
    fifo36e1.json
    dsp48e1.json
```

### 23.2 Results

```
~/fuzz_results/
  dispatch.log
  node_{nodename}.log
  {PRIMITIVE}/
    gen_{GEN_HASH}/
      test_{HASH}/
        result.json          ← final output
        vivado.log
        nextpnr.log
        synth.json           ← preserved copy
        running.lock         ← deleted on completion
```

### 23.3 Tools

```
~/prjxray/
  build/tools/bitread
  build/tools/xc7frames2bit
  utils/bit2fasm.py
  utils/fasm2frames.py
  lib/test_data/configuration_test.bit   ← health check reference

~/nextpnr-xilinx/
  build/nextpnr-xilinx
  xilinx/xc7s50.bin
  xilinx/external/prjxray-db/spartan7/

~/fpga_assets/
  nextpnr-xilinx.wasm
  nextpnr-xilinx.js
  xc7s50.bin.br
  xc7s50_fasm_map_v4.json.br
  xc7frames2bit.wasm
  xc7frames2bit.js
  part.yaml

~/boost_libs/               ← Boost shared libraries for native nextpnr
```

### 23.4 Temporary (Local SSD)

```
/tmp/{USER}/fuzz_{HASH}/
  params_input.json
  top.v
  top.xdc
  synth.json
  out.fasm
  out.frames
  vivado_out.bit
  nextpnr_out.bit
  [vivado working directory created by run_fuzz_vivado.tcl]

/tmp/fuzz_param_XXXXXX.json     ← per-combo param file (deleted after use)
/tmp/fuzz_node_lock_{USER}      ← node reservation lock
/tmp/fuzz_node_cache_{USER}     ← node load cache
/tmp/{asset_basename}_cache.bin ← Brotli decompression cache
```

---

## 24. KEY CONSTANTS & MAGIC NUMBERS

| Constant | Value | Location | Meaning |
|---|---|---|---|
| `LOCK_TTL` | `45` seconds | `find_nodes.sh` | Node reservation expiry |
| `CACHE_TTL` | `30` seconds | `find_nodes.sh` | Node load cache expiry |
| Stale lock age | `7200` seconds (2 hours) | `cleanup.sh` | Job considered dead if lock older than this |
| Heartbeat interval | `60` seconds | `fuzz_one.sh` | Lock touch frequency |
| Vivado timeout | `30m` (1800 s) | `fuzz_one.sh` | `timeout 30m vivado` |
| nextpnr native timeout | `300000 ms` (5 min) | `headless_pnr_native.mjs` | `spawnSync timeout` |
| WASM global timeout | `5 * 60 * 1000 ms` (5 min) | `headless_pnr.mjs` | Global process exit timeout |
| BFS early exit probes | `1s, 1s, 0.5s` | `find_nodes.sh` | Progressive wait intervals |
| Max BFS nodes (cache) | top 10 | `find_nodes.sh` | `awk 'NR<=10'` after sort |
| Load threshold | `< 6.0` | `find_nodes.sh` | Node considered usable |
| GEN_HASH length | 8 chars | `fuzz.sh` | `cut -c1-8` of MD5 |
| Test HASH length | 32 chars | `fuzz_one.sh` | Full MD5 hex |
| Health check quota WARN | `> 85%` | `health_check.sh` | Warning level |
| Health check quota CRIT | `> 95%` | `health_check.sh` | Fatal level |
| IDELAY_VALUE range | `0..31` | `gen_verilog.py` | 5-bit tap count |
| CNTVALUEIN width | 5 bits | `gen_verilog.py` | IDELAYE2 port (UG953 p.401) |
| REFCLK_FREQUENCY | `200.0` | `gen_verilog.py` | IDELAYCTRL reference (190–210 or 290–310 MHz) |
| VCO range (MMCM) | `600–1200 MHz` | `gen_verilog.py` | Spartan-7 MMCME2_ADV |
| DSP A width | 30 bits | `gen_verilog.py` | `a_reg [29:0]` |
| DSP B width | 18 bits | `gen_verilog.py` | `b_reg [17:0]` |
| DSP C/P width | 48 bits | `gen_verilog.py` | `c_reg/p_out [47:0]` |
| OSERDESE2 shift reg | 8 bits | `gen_verilog.py` | `reg [7:0] sr = 8'hA5` |
| OSERDESE2_CASCADE shift | 10 bits | `gen_verilog.py` | `reg [9:0] sr = 10'hA5` |
| ISERDESE2 Q count | 8 outputs | `gen_verilog.py` | Q1..Q8 |
| RAMB18 DOADO width | 16 bits | `gen_verilog.py` | Always 16 bits (UG953 p.567) |
| FIFO18 DO width | 32 bits | `gen_verilog.py` | Always 32 bits (UG953 p.351) |
| FIFO36 DO width | 64 bits | `gen_verilog.py` | Always 64 bits (UG953 p.356) |
| DSP OPMODE | `7'b0110101` | `gen_verilog.py` | P = A*B + C |
| node probe range | `{01..39}` | `find_nodes.sh` | Zero-padded bash brace expansion |

---

## 25. ERROR TAXONOMY

### 25.1 Pipeline Errors (result.json)

| `reason` value | Trigger | Meaning |
|---|---|---|
| `"TIMEOUT"` | `timeout 30m vivado` exits with code 124 | Vivado took > 30 minutes |
| `"VIVADO_CRASH_{N}"` | Vivado exits non-zero (not 124) | Vivado failed; N = exit code |
| `"MISSING_BITSTREAM"` | One or both `.bit` files missing after pipeline | nextpnr or Vivado produced no output |

### 25.2 Generator Errors (ValueError, → SKIP)

| Error | Condition |
|---|---|
| VCO out of range | MMCM/PLL frequency outside 600–1200 MHz |
| OSERDES width invalid | DDR width ∉ {4,6,8} or SDR width ∉ {2..8} |
| IDELAY_VALUE out of range | Value > 31 |
| RAMB width invalid | Width not in valid set for primitive |
| DSP MREG/USE_MULT conflict | MREG=1 with USE_MULT="NONE" |
| RAMB36 dual-36 | READ_WIDTH_A=36 and READ_WIDTH_B=36 |
| FIFO FWFT | FIRST_WORD_FALL_THROUGH="TRUE" |
| ISERDESE2 width | DDR width ∉ {4,6,8} |

All `ValueError` exceptions in generators are caught by `fuzz.sh` via the `continue` statement after printing `SKIP combo N (params): reason`.

### 25.3 Health Check Failures

| Check | Impact |
|---|---|
| bit2fasm produces 0 lines | All comparisons will false-PASS; pipeline is broken |
| compare_bits matching=0 on identical inputs | false-PASS detection; pipeline broken |
| No nodes available | Cannot run distributed fuzzing |
| Disk > 95% | All jobs would fail; abort immediately |

---

## 26. ANTI-PRUNING STRATEGIES

Synthesis tools (Yosys, Vivado) aggressively prune logic with no observable effect. All generators use explicit strategies to force placement:

### 26.1 Counter Chains

```verilog
reg [7:0] cnt = 0;
always @(posedge clk) cnt <= cnt + 1;
assign out = ^cnt;
```

An 8-bit or 32-bit free-running counter's XOR-reduction drives the output. The synthesizer cannot eliminate the counter because `out` is a primary output.

### 26.2 Shift Registers (OSERDESE2)

```verilog
reg [7:0] sr = 8'hA5;
always @(posedge clk) sr <= {sr[6:0], sr[7]};
```

Circular shift register feeds all D1..D8 ports. Non-trivial data pattern (init 0xA5) prevents constant folding.

### 26.3 Feedback Paths (DSP48E1)

```verilog
always @(posedge clk) begin
    a_reg <= a_reg - 1;
    b_reg <= b_reg + 1;
    c_reg <= p_out;   // P → C feedback
end
```

P→C feedback creates an accumulator loop. Without it, the multiply-accumulate output would be pruned.

### 26.4 IDELAYCTRL Companion

```verilog
(* IODELAY_GROUP = "fuzz_grp" *)
IDELAYCTRL u_idelayctrl (.REFCLK(clk), .RST(1'b0), .RDY(rdy));
reg rdy_r = 0;
always @(posedge clk) rdy_r <= rdy;
assign out = delayed ^ rdy_r;
```

`RDY` is registered and XORed into `out` to prevent IDELAYCTRL pruning.

### 26.5 RAMB Read-Back

```verilog
assign out = (^dout_a[dw_a-1:0]) ^ (^dout_b[dw_b-1:0]);
```

Both ports are read and XOR-reduced. Forces both port A and port B to be active.

### 26.6 FIFO Phase Controller

```verilog
reg [3:0] phase = 0;
always @(posedge clk) begin
    phase  <= phase + 1;
    wr_en  <= (phase < 8) & ~full;
    rd_en  <= (phase >= 8) & ~empty;
end
assign out = (^dout[dw-1:0]) ^ empty ^ almost_empty;
```

Write phase 0–7, read phase 8–15. Status flags feed output to prevent elimination.

### 26.7 IBUFDS Counter Mix

```verilog
reg [7:0] cnt = 0;
always @(posedge clk) cnt <= cnt + 1;
assign out = ibuf_out ^ (^cnt);
```

IBUFDS output XORed with counter prevents the IBUFDS from being trimmed if input is constant.

---

## 27. KNOWN HARDWARE CONSTRAINTS (SPARTAN-7 XC7S50)

### 27.1 Bank Type Restrictions

| Restriction | Reason | Impact |
|---|---|---|
| `DIFF_TERM=FALSE` always for IBUFDS | XC7S50 has HR banks only; internal 100Ω termination requires HP banks | DIFF_TERM excluded from param sweep |
| TMDS_33 valid for OBUFDS | TMDS_33 is supported on HR banks (Spartan-7 compatible) | Included in OBUFDS IOSTANDARD sweep |

### 27.2 Pin Routing Constraints

| Constraint | Details |
|---|---|
| `clk` cannot fan to both IBUFDS.I and fabric | Vivado Synth 8-5535 DRC error; requires dedicated diff-pair pins | IBUFDS uses F14/F15 (JA1_P/JA1_N), not clk pin |
| IDELAYCTRL must be in same bank as IDELAYE2 | UG953 p.399 requirement | `IODELAY_GROUP` attribute added to both |
| REFCLK for IDELAYCTRL | 200 MHz required for guaranteed tap accuracy; fuzzer uses system clk (100 MHz) | Intentional: testing config bits, not timing accuracy |

### 27.3 OSERDESE2 Cascade Requirement

| DATA_RATE | DATA_WIDTH | Cascade Required |
|---|---|---|
| DDR | 10, 14 | Yes (MASTER+SLAVE) |
| DDR | 4, 6, 8 | No |
| SDR | 2–8 | No |

DDR 10/14: `OSERDESE2_CASCADE` generator handles this. Excluded from main `OSERDESE2` sweep.

### 27.4 FIFO DRC Rules

| Rule | ID | Requirement |
|---|---|---|
| RST non-constant | REQP-34 | RST must be driven by a non-constant net; fuzzer uses `rst_sync` register (always=1, but not synthesis-constant) |
| FWFT incompatibility | — | `FIRST_WORD_FALL_THROUGH=TRUE` incompatible with `EN_SYN=TRUE` (single-clock mode used by fuzzer) |

### 27.5 RAMB18E1 Bus Widths

DOADO and DOBDO are always 16 bits wide at the primitive port, regardless of READ_WIDTH setting. Read lower `dw_a` bits.

---

## 28. CROSS-REFERENCE: PRIM_FILTERS VS EXCLUDE LOGIC

### 28.1 Filter Decision Tree

```
For each FASM line L:
  1. Strip blank / comment → discard
  2. Any word from EXCLUDE ∈ L? → discard (routing fabric, not primitive config)
  3. Any keyword from PRIM_FILTERS[primitive] ∈ L? → keep
  4. Else → discard
```

### 28.2 FIFO vs RAMB Filter Overlap

Both `FIFO18E1` and `RAMB18E1` use `["RAMB18", "BRAM"]` keywords. Both `FIFO36E1` and `RAMB36E1` use `["RAMB36", "BRAM"]`. This is intentional: FIFO primitives occupy RAMB sites; their FASM configuration appears under RAMB tile names.

### 28.3 BUFG vs BUFGCE Filter Overlap

Both use `["BUFG", "BUFGCTRL"]`. Intentional: BUFGCE is implemented in a BUFGCTRL site.

---

## 29. CLUSTER ARCHITECTURE & NODE SELECTION

### 29.1 Cluster Topology

```
39 nodes: fastx3-01.ews.illinois.edu … fastx3-39.ews.illinois.edu
All accessible via SSH with StrictHostKeyChecking=no, PasswordAuthentication=no
Load metric: /proc/loadavg field 1 (1-minute average)
Usability threshold: load < 6.0
```

### 29.2 SSH Probe Options

| Option | Value | Reason |
|---|---|---|
| `ConnectTimeout` | `2` | Fast failure for unreachable nodes |
| `StrictHostKeyChecking` | `no` | No interactive prompts |
| `PasswordAuthentication` | `no` | Keys only; no password prompts |

### 29.3 Selection Algorithm

```
1. Expire locked nodes (> LOCK_TTL seconds)
2. Try cached nodes (< CACHE_TTL seconds old) first, sorted by load
3. If still need nodes: probe all 39 in parallel
4. Early exit: check every 1s, 1s, 0.5s for REMAINING_NODES good nodes
5. Kill background SSH jobs
6. Sort remaining probe results by load, take top 10, shuffle
7. Select from shuffled until FOUND >= WANTED_NODES
8. Write selected nodes to lock file with current timestamp
9. Merge fresh results with still-valid cache entries
```

Shuffle in step 6 prevents all dispatchers from choosing the same lowest-load node simultaneously.

---

## 30. AUTO-SCALING LOGIC

**Location**: `fuzz.sh` (lines within `if [ "$NODES" -gt 0 ]` block)

### 30.1 Pressure Calculation

```bash
AVAILABLE_NODES=$(~/fpga_scripts/fuzz/find_nodes.sh 99 1 | wc -l)
UNCACHED=$(python3 -c "... count uncached combos ...")
```

| Condition | AUTO_JOBS | Label |
|---|---|---|
| `UNCACHED ≤ AVAILABLE_NODES` | `1` | Pressure: LOW |
| `UNCACHED ≤ AVAILABLE_NODES × 3` | `2` | Pressure: MEDIUM |
| `UNCACHED > AVAILABLE_NODES × 3` | `2` + warning | Pressure: HIGH |

### 30.2 Explicit Override

If `--jobs N` was passed, `JOBS_EXPLICIT=1` is set and `AUTO_JOBS` is computed but not applied:
```bash
if [ "$JOBS_EXPLICIT" != "1" ]; then
    JOBS=$AUTO_JOBS
fi
```

### 30.3 HIGH Pressure Warning

```
⚠️  Large matrix — consider running in batches
```

Printed when `UNCACHED > AVAILABLE_NODES × 3`. Does not stop execution.

---

*End of reference document. All functions, parameters, paths, constants, protocols, and behavioral rules are indexed above for rapid LLM lookup and cross-referencing.*
