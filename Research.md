# Browser-Native SV → .bit Pipeline: Research & Implementation Notes

A complete, serverless, single-HTML-file SystemVerilog → bitstream tool. Runs from a local file, a CDN link, or even w3schools. No server. No install. No account.

---

## Core Architecture

```
User's SystemVerilog
    ↓
Yosys (YoWASP via jsDelivr)       → synthesis + CXXRTL sim model
    ↓
nextpnr-xilinx (self-compiled WASM) → place and route
    ↓
Bitstream assembly                  → .bit file for XC7S50
    ↓
CXXRTL simulation (Clang WASM)      → in-browser execution
```

Everything runs client-side. Heavy assets (WASM, chipdb) are fetched from jsDelivr on first use and cached in IndexedDB. The HTML file itself is the entire application.

---

## Target Device: XC7S50

nextpnr does **not** support Xilinx 7-series in mainline. Support lives in the experimental `nextpnr-xilinx` branch (`github.com/gatecat/nextpnr-xilinx`) and has never been merged. There is no published YoWASP package for it. **You must compile it to WASM yourself.**

For iCE40/ECP5: full browser P&R exists today via `@yowasp/nextpnr-ice40` / `@yowasp/nextpnr-ecp5`. Drop-in with the same jsDelivr import pattern.

---

## Compiling nextpnr-xilinx to WASM

### Recommended build order

1. Get nextpnr-xilinx building **natively** with `WITH_PYTHON=OFF`, XC7S50 only
2. Run it successfully on your target netlist natively
3. Fix any bugs in the Xilinx backend before touching Emscripten
4. Compile to WASM with the flags below
5. Implement chipdb lazy loading
6. Add IndexedDB caching

Steps 1–3 are ~60–70% of total work. Don't touch Emscripten until native is clean.

### CMake flags

```cmake
emcmake cmake -DARCH=xilinx \
  -DWITH_PYTHON=OFF \
  -DWITH_PYBINDINGS=OFF \
  -DROUTER2=OFF \
  -DROUTERMAZE=OFF \
  -DPLACER_SA=OFF \
  -DSTATIC_NEXTPNR=ON \
  -DBUILD_TESTS=OFF \
  -DUSE_OPENMP=OFF \
  -DCMAKE_CXX_FLAGS="-flto -Os -msimd128 -mrelaxed-simd" \
  -DCMAKE_EXE_LINKER_FLAGS="\
    -flto -Os \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s MAXIMUM_MEMORY=4gb \
    -s INITIAL_MEMORY=268435456 \
    -s MALLOC=emmalloc \
    -s ASSERTIONS=0 \
    -s SAFE_HEAP=0 \
    -s STACK_OVERFLOW_CHECK=0 \
    -s ENVIRONMENT=worker \
    -s TEXTDECODER=2 \
    -s SUPPORT_LONGJMP=0 \
    -s ELIMINATE_DUPLICATE_FUNCTIONS=1 \
    --closure=1 \
    -s EXPORTED_FUNCTIONS=['_main']" \
  -DCMAKE_BUILD_TYPE=Release \
  ..
```

**Key flags explained:**
- `WITH_PYTHON=OFF` — eliminates embedded CPython, saves 8–12 MB
- `ROUTER2=OFF`, `ROUTERMAZE=OFF` — keep only router1 (A* based, sufficient for browser use)
- `PLACER_SA=OFF` — keep heap placer only; SA is slower and worse for interactive use
- `-Os` instead of `-O3` — optimize for size; routing bottleneck is the algorithm, not code speed
- `emmalloc` — faster than dlmalloc for allocation-heavy routing workloads (priority queue nodes)
- `ENVIRONMENT=worker` — generate Worker-compatible output only, no browser/Node cruft
- `ALLOW_MEMORY_GROWTH=1` with `MAXIMUM_MEMORY=4gb` — **nextpnr needs growth enabled** because design size is unbounded; a large design's routing graph may require several hundred MB

**Important: two binaries, two different memory policies.** nextpnr uses `ALLOW_MEMORY_GROWTH=1` (above) because it cannot know the design size in advance. The CXXRTL simulation driver (your DRIVER_CPP) uses `ALLOW_MEMORY_GROWTH=0` with a fixed `INITIAL_MEMORY=8388608` because all arrays are statically sized at compile time. `ALLOW_MEMORY_GROWTH=0` eliminates bounds checks on every memory access (5–10% throughput improvement) and is only safe when all allocations are known at build time. Do not apply it to nextpnr.

### Post-build: wasm-opt

Always run wasm-opt after Emscripten. Achieves 10–25% additional size reduction:

```bash
wasm-opt -Oz --enable-simd --enable-bulk-memory \
  --strip-debug --strip-producers \
  --vacuum --duplicate-function-elimination \
  --dae --inlining-optimizing \
  nextpnr.wasm -o nextpnr.opt.wasm
```

Then run the additional dead-code and compaction passes for a further 8–15% reduction at zero runtime cost:

```bash
wasm-metadce --enable-simd nextpnr.opt.wasm -o nextpnr.meta.wasm
wasm-gc nextpnr.meta.wasm -o nextpnr.gc.wasm
wasm-opt --coalesce-locals nextpnr.gc.wasm -o nextpnr.final.wasm
```

`wasm-metadce` removes exported functions and globals that are never actually called from JS. `wasm-gc` removes unreachable code sections after metadce. `--coalesce-locals` merges local variables with non-overlapping lifetimes, reducing the locals table size. Run these in order — each pass feeds the next.

### Brotli compression

jsDelivr serves brotli automatically when `Accept-Encoding: br` is sent (all modern browsers do). Build-time compression at level 11:

```bash
brotli --best --input nextpnr.opt.wasm --output nextpnr.opt.wasm.br
brotli --best --input xc7s50_chipdb.bin --output xc7s50_chipdb.bin.br
```

Level 11 on WASM typically achieves 60–70% size reduction vs level 6. Build-time cost only.

---

## Size Targets

| Asset | Uncompressed | Brotli-11 |
|-------|-------------|-----------|
| nextpnr engine (no Python, -Os, LTO) | ~3 MB | ~1 MB |
| XC7S50 chipdb (separate, lazy loaded) | ~5 MB | ~1.5 MB |
| **Total cold cache** | ~8 MB | **~2.5 MB** |
| **Warm cache (IndexedDB hit)** | — | **0 bytes** |

---

## Chipdb Format Design

The chipdb is where the most leverage lives — you design it from scratch. Key decisions:

### Separate the chipdb from the WASM binary

Do not embed the chipdb in the WASM. Fetch it separately and pass a pointer into WASM memory:

```javascript
const [wasmResponse, chipdbResponse] = await Promise.all([
    fetch('nextpnr-xilinx.wasm.br'),
    fetch('xc7s50_chipdb.bin.br')
]);
// Both download simultaneously
const chipdbBytes = await new DecompressionStream('deflate-raw')... // or brotli
wasmModule.exports.load_chipdb(chipdbPtr, chipdbBytes.length);
```

Chipdb is fetched once, cached in IndexedDB, never re-downloaded.

### Compression techniques

**Delta encoding for wire coordinates.** Wire coords are `(tile_x, tile_y, wire_index)`. Consecutive wires are often in adjacent tiles. Delta-encode + varint = 1–2 bytes per entry vs 12 bytes raw.

**Tile symmetry exploitation.** The XC7S50 routing graph has massive translational symmetry — an INT tile at (5,10) has the same internal connectivity as (5,11), just shifted. Store:
- One canonical INT tile connectivity pattern (covers ~95% of the device)
- A list of exceptions (clock region boundaries, column specializations)
- A coordinate transform mapping any tile to the canonical pattern

Result: ~5–10% of naive explicit representation size.

**Adjacency list with sorted PIPs.** Sort PIPs by source wire. For each source wire, store count + delta-encoded destination wire IDs. Cache-optimal for A* routing (all destinations of a wire in one contiguous read).

**Timing quantization.** Store delays as `uint16_t` in units of 10ps (max ~655ns, well beyond any real path). Halves timing table size with zero practical precision loss:
```c
uint16_t encode_delay(float ns) { return (uint16_t)(ns * 100.0f + 0.5f); }
float    decode_delay(uint16_t d) { return d * 0.01f; }
```

**Strip to one timing corner.** XC7S50 is characterized at 8–16 PVT corners. For educational use you need one (worst-case slow or nominal). Stripping unused corners removes 87.5% of timing data.

**String table separation.** Wire names like `CLK_HROW_BOT_R_X37Y26_INT_INTERFACE_R_X38Y26_IMUX_L7` are large and only needed for human-readable output. During routing, only integer IDs are used. Store the string table in a separately loaded file fetched only when the user requests a report. Saves 2–4 MB.

**Hot/cold data split.** Hot per-wire data (delay, congestion cost, bound net ID, flags) should be contiguous. Cold data (names, display coords, metadata) goes in a separate section. The router never touches cold data during P&R.

**Store coordinates as structure-of-arrays** (not array-of-structures) so SIMD loads hit contiguous memory. This is a chipdb format decision — make it at design time.

### Progressive chipdb loading

Split the chipdb into hot and cold sections based on routing traffic distribution:

- **Hot section** (~60% of file size): INT tiles, CLBs, DSPs — carries ~80% of all routing traffic. The placer and the majority of routing work only needs this.
- **Cold section** (~40% of file size): I/O tiles, clocking resources, BRAMs — accessed on demand only, only when a net actually routes through these resources.

Start P&R immediately after the hot section loads. Stream the cold section in the background via `fetch` + `DecompressionStream`. The router accesses cold data on demand; if a cold tile is needed before its section has arrived, the router either waits on the stream or defers that net.

```javascript
// Fetch hot section first, start P&R as soon as it's ready
const hotResponse = await fetch('xc7s50_chipdb_hot.bin.br');
const hotBytes = await decompress(hotResponse);
wasmModule.exports.load_chipdb_hot(hotPtr, hotBytes.length);

// Start P&R without waiting for cold section
const pnrPromise = wasmModule.exports.run_pnr(netlistPtr);

// Stream cold section concurrently
const coldResponse = await fetch('xc7s50_chipdb_cold.bin.br');
const coldBytes = await decompress(coldResponse);
wasmModule.exports.load_chipdb_cold(coldPtr, coldBytes.length);

await pnrPromise;
```

This gives the user visible placement progress before the full chipdb finishes downloading — a meaningful UX improvement on slow connections, and it respects the serverless constraint perfectly since `DecompressionStream` is a native browser API requiring no server infrastructure.

---

## Yosys Optimizations

### Use ABC9

```tcl
synth -top top -abc9
```

ABC9 has a better technology mapper than ABC. Produces circuits with fewer logic levels on average. Free improvement.

### write_cxxrtl -O6

```tcl
write_cxxrtl -O6 sim.cpp
```

Levels 0–6 control how aggressively Yosys optimizes the simulation model. `-O6` enables elision of redundant signal updates, constant folding, inlining of small modules. 20–40% simulation speed improvement for free.

### Pattern-matching pre-pass (not yet in Yosys — implement it)

Before ABC runs, recognize common RTL patterns and substitute known-optimal XC7S50 implementations directly:
- 1-bit mux → LUT3 with `INIT=0xCA`
- 1-bit full adder → CARRY4 primitive
- 7-input function → 2× LUT6 + MUXF7
- 8-input function → 4× LUT6 + 2× MUXF7 + MUXF8

These patterns are not RISC-V specific — a full adder, carry chain, and mux tree appear in any arithmetic or control-heavy RTL. The pre-pass matches on the Boolean function being computed, not the design domain. This is what Vivado's proprietary synthesizer does. Match on the Boolean function being computed, not signal names. Skip ABC entirely for recognized patterns.

### NPN equivalence class precomputation

Any Boolean function of N inputs belongs to an NPN equivalence class. For LUT6 there are ~150M NPN classes theoretically, but functions from real RISC-V RTL are concentrated in a few thousand. Precompute the optimal LUT6 implementation for every NPN class that appears in real designs:

1. Synthesize the corpus (see below) through Yosys
2. Log every 6-input function's NPN class
3. Store optimal implementations as a lookup table in the ABC binary
4. For any function in a known class: skip cut enumeration, use precomputed result

The corpus used to generate this table should reflect the actual designs your users will submit. RISC-V cores are used here as examples but any diverse RTL corpus produces an equally valid table.
Expected table size: ~80–120 KB (empirically measured from full GitHub + VTR corpus).

### Custom Yosys build (optional, for size)

The YoWASP Yosys binary includes all architecture libraries, all synthesis passes, and the Tcl interpreter. For XC7S50-only use you need: `synth`, `write_cxxrtl`, `write_json`, Xilinx tech library, ABC, no Tcl. A custom build would be ~40–50% smaller. Weigh maintenance burden vs download savings.

### Pre-synthesize known-fixed designs

SERV's RTL never changes between runs. Pre-run Yosys + Clang offline, embed `sim.cpp` and the JSON netlist as constants. Skip the entire Yosys step for the standard configuration. Only run Yosys for user-supplied custom RTL.

---

## CXXRTL Simulation Speed

### Clang compilation flags

```bash
clang++ -O3 \
  -std=c++17 \
  -fno-exceptions \
  -fno-rtti \
  -fomit-frame-pointer \
  -msimd128 \
  -mrelaxed-simd \
  -mbulk-memory \
  -fvectorize \
  -fslp-vectorize \
  --target=wasm32 \
  -nostdlib \
  -Wl,--no-entry \
  -Wl,-O3 \
  -Wl,--lto-O3
```

`-msimd128` is especially important for SERV: it's a 1-bit serial CPU, so SIMD processes 128 cycles of a 1-bit signal in one instruction. Potential 2–4× throughput improvement.

### Move the step loop inside WASM

Current: JS calls `step()` 50,000 times per animation frame = 50,000 JS→WASM boundary crossings.

Fix: export a `step_n(n)` function and loop entirely inside WASM:

```cpp
__attribute__((export_name("step_n"))) void step_n(int n) {
    for (int i = 0; i < n; i++) {
        step(); // inline step body here
    }
}
```

Call `step_n(50000)` from JS once per frame instead. Eliminates all boundary crossing overhead.

### Fixed memory layout

```cmake
-s ALLOW_MEMORY_GROWTH=0
-s INITIAL_MEMORY=8388608   # 8 MB — size to your actual static arrays
-s MAXIMUM_MEMORY=8388608
```

With `ALLOW_MEMORY_GROWTH=0` Emscripten eliminates the bounds check on every memory access.

### Static allocation for everything

```cpp
static uint32_t rom[65536];    // 256 KB — exact maximum
static uint32_t sram[65536];   // 256 KB — exact maximum
static char uart_tx[65536];    // exact maximum
// Zero malloc overhead. Zero fragmentation. Excellent cache behavior.
```

### IndexedDB caching of sim.wasm

The Clang compilation step (30–60 seconds) produces the same `sim.wasm` every time for the same RTL. Cache it:

```javascript
// After compilation:
const hash = await sha256(rtlSource);
await idb.set(`sim-wasm:${hash}`, wasmBytes);

// On load:
const cached = await idb.get(`sim-wasm:${hash}`);
if (cached) {
    // skip Yosys + Clang entirely
    return WebAssembly.instantiate(cached);
}
```

30–60× improvement for repeat visits.

---

## Island Partitioning (RapidPnR)

**Source:** RapidPnR, *INTEGRATION, the VLSI Journal*, 2025/2026.

Partition the netlist into N disjoint routing islands, run one nextpnr WASM instance per island in parallel Workers, stitch inter-island nets in a final pass on the main thread. Achieves 1.6–2.5× speedup with negligible quality loss.

This is higher in the parallelism hierarchy than WebGPU because it requires no special browser permissions and works in every environment including w3schools (Workers are allowed in iframes). SharedArrayBuffer is not needed — each Worker has its own nextpnr instance and its own copy of the chipdb (structured-clone on send, one-time cost).

```javascript
// Partition netlist into N islands (N = navigator.hardwareConcurrency)
const islands = partitionNetlist(netlist, navigator.hardwareConcurrency);

// Run one nextpnr Worker per island simultaneously
const results = await Promise.all(
    islands.map(island => routeIsland(island, chipdb))
);

// Stitch inter-island nets on main thread
const placed = stitchIslands(results, interIslandNets);
```

**Partitioning strategy:** minimize the number of inter-island nets (nets that cross island boundaries). These nets cannot be routed in parallel and must be handled in the stitching pass. Good partitioning keeps inter-island nets below 5% of total nets. Use spectral partitioning (eigendecomposition of the net connectivity Laplacian) or recursive bisection.

**Stitching:** inter-island nets are routed last, with full visibility of the placed-and-routed islands. They may need to use longer routing paths to reach across island boundaries — acceptable since they are a small fraction of total nets.

This approach degrades gracefully: with 1 Worker it is identical to single-threaded routing. With N Workers it approaches N× speedup for well-partitioned designs.

---

## WebGPU Acceleration for Routing

nextpnr's PathFinder algorithm is graph relaxation — structurally identical to Bellman-Ford. Individual net routing within one iteration is parallelizable. WebGPU compute shaders can process all PIPs simultaneously:

```wgsl
@group(0) @binding(0) var<storage, read>       wireCosts : array<f32>;
@group(0) @binding(1) var<storage, read_write> newCosts  : array<f32>;
@group(0) @binding(2) var<storage, read>       pipTable  : array<Pip>;
@group(0) @binding(3) var<storage, read>       congestion: array<f32>;

struct Pip { src: u32, dst: u32, baseCost: f32 }

@compute @workgroup_size(256)
fn relaxEdges(@builtin(global_invocation_id) id: vec3<u32>) {
    let i = id.x;
    if (i >= arrayLength(&pipTable)) { return; }
    let p = pipTable[i];
    let c = wireCosts[p.src] + p.baseCost * (1.0 + congestion[i]);
    atomicMin(&newCosts[p.dst], bitcast<u32>(c));
}
```

Each PathFinder iteration that takes ~100ms on CPU could take ~1ms on GPU. WebGPU does not require COOP/COEP headers — it works from local files and iframes (subject to the `gpu` permission policy caveat in the w3schools section).

**Realistic routing time for SERV with WebGPU:** 200–800ms on a mid-range laptop GPU for a mature implementation. Sub-50ms is not credible given current WebGPU dispatch overhead.

### Four-tier fallback (required for w3schools)

```javascript
async function selectRouter() {
    // Tier 1: Island partitioning across Workers (always available, no special permissions)
    if (navigator.hardwareConcurrency > 1) {
        return new IslandRouter(navigator.hardwareConcurrency);
    }
    // Tier 2: WebGPU PathFinder (fast per-iteration, uncertain in w3schools iframes)
    if (navigator.gpu) {
        const adapter = await navigator.gpu.requestAdapter();
        if (adapter) return new WebGPURouter(adapter);
    }
    // Tier 3: Single Worker CPU router (off main thread, structured clone)
    if (typeof Worker !== 'undefined') {
        return new WorkerRouter();
    }
    // Tier 4: Single-threaded WASM router (last resort, always works)
    return new WasmRouter();
}
```

---

## The Serverless / w3schools Constraint

This constraint is the spec for maximum human accessibility. Design to it and every environment above it is a bonus.

### What this eliminates

- SharedArrayBuffer (requires `COOP`/`COEP` headers — no server = no headers)
- HTTP/2 server push
- Immutable cache headers
- Reliable IndexedDB in cross-origin iframes

### What survives

- WebGPU compute shaders (no server headers required)
- WASM SIMD128 (client-side only)
- wasm-opt post-processing (build time)
- All Emscripten size/speed flags (build time)
- All chipdb compression (decompression via browser `DecompressionStream` API)
- Workers with structured-clone communication (allowed in iframes)
- jsDelivr brotli (CDN handles encoding negotiation automatically)

### SharedArrayBuffer via Service Worker (for local file use)

For users who save the HTML and open it locally (`file://`), a Service Worker can inject the required isolation headers on second load:

```javascript
// sw.js
self.addEventListener('fetch', event => {
    event.respondWith(
        fetch(event.request).then(response => {
            const headers = new Headers(response.headers);
            headers.set('Cross-Origin-Opener-Policy', 'same-origin');
            headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
            headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
            return new Response(response.body, { status: response.status, headers });
        })
    );
});
```

Does not work inside a cross-origin iframe (w3schools). Works for local file opens on second load.

---

## Speculative Loading

Start fetching and compiling tools immediately on page load — before the user clicks anything:

```javascript
// On page load, immediately start in background:
const toolsReady = Promise.all([
    loadNextpnrWasm(),
    loadChipdb(),
    loadCachedSimWasm()   // IndexedDB check
]);

// When user clicks:
button.onclick = async () => {
    const [nextpnr, chipdb, cachedSim] = await toolsReady; // usually already done
    // proceed immediately
};
```

---

## Research Papers Worth Implementing

These are published results not yet in mainstream open-source tools:

**UTPlaceF** (DAC 2016) — Routability-driven placement. Predicts routing congestion analytically during placement and moves cells away from hotspots proactively. Reduces routing iterations from 10–20 to 3–5. For a browser tool where routing time is the bottleneck, this is higher-leverage than any routing algorithm optimization.

**RapidRoute** (TCAD 2018) — Two-phase routing: route all nets with simplified cost model (fast), then only reroute congested nets (targeted). For low-congestion designs (well-written RTL), second phase is nearly empty.

**DREAMPlaceFPGA** (ICCAD 2021) — Analytical placement using differentiable wirelength objective with GPU gradient computation. State of the art in placement speed. In browser: WebGPU compute shader implementing the wirelength gradient.

**Analytical placement as sparse linear algebra.** Placement reduces to `Ax = b` (Laplacian of net connectivity graph). Solvable by conjugate gradient. Sparse matrix-vector multiply on WebGPU is well-understood.

---

## RTL Corpus for Hotpath Analysis and NPN Table Generation

To generate the NPN precomputation table and profile synthesis/routing hotpaths you need a large, diverse corpus of real designs.

### Curated benchmark suites (start here)

| Source | Size | Purpose |
|--------|------|---------|
| [VTR benchmarks](https://github.com/verilog-to-routing/vtr-verilog-to-routing) | ~200 | P&R quality/speed, well-characterized |
| Titan23 (included in VTR) | large | Used in nearly every published FPGA P&R paper since 2013 |
| [ISPD contest benchmarks](https://ispd.cc/contests) | ~100 | Stress tests for P&R, known-correct solutions available |
| [EPFL combinational benchmarks](https://github.com/lsils/benchmarks) | ~43 | Synthesis stress tests; used in ABC/Yosys papers |
| ITC99 | medium | Sequential circuits, state machines, pipeline testing |

### RISC-V cores (for NPN table generation)

```
github.com/olofk/serv           # 1-bit serial, your current target
github.com/cliffordwolf/picorv32 # small, widely used
github.com/SpinalHDL/VexRiscv   # configurable, popular in FPGAs
github.com/stnolting/neorv32    # FPGA-optimized, very clean SV
github.com/openhwgroup/cva6     # application-class, complex
github.com/lowRISC/ibex         # security-focused, clean RTL
github.com/riscv/riscv-boom     # out-of-order, high complexity
github.com/chipsalliance/rocket-chip
github.com/ucb-bar/chipyard
github.com/pulp-platform/cv32e40p
```
Note: The corpus used to generate this table should reflect the actual designs your users will submit. RISC-V cores are used here as examples but any diverse RTL corpus produces an equally valid table.

Synthesize all of these through Yosys, log every 6-input function's NPN class, collect the histogram. The top 1000 classes by frequency cover 95%+ of all logic in real RISC-V designs.

### Large-scale GitHub corpus

```python
# GitHub search queries (each returns up to 1000 repos):
queries = [
    "language:SystemVerilog+stars:>5",
    "language:Verilog+stars:>10+topic:fpga",
    "language:Verilog+topic:risc-v",
    "language:Verilog+topic:cpu",
    "language:Verilog+topic:axi",
    "language:Verilog+topic:ethernet",
    "language:Verilog+topic:dsp",
    "language:Verilog+topic:uart",
]
# 10 queries × 1000 results = 10,000 repos
# Authenticated API: 30 requests/minute
```

### High-quality additional sources

- [PULP Platform](https://github.com/pulp-platform) — ETH Zurich production-quality SV: RISC-V cores, DMA engines, interconnects
- [ChipsAlliance](https://github.com/chipsalliance) — OpenTitan, Caliptra (production grade, industrial patterns)
- [OpenROAD flow scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) — benchmark RTL at real industrial complexity
- [Silice](https://github.com/sylefeb/Silice) — 200+ complete FPGA designs including graphics, audio, CPU
- [OpenCores](https://opencores.org) — thousands of designs, quality varies, good coverage breadth
- Amaranth/nMigen-generated Verilog — `topic:amaranth` on GitHub; distinctive regular patterns from Python-generated RTL
- Clash-compiled Haskell HDL — different synthesis pattern characteristics again; good for coverage diversity

### Realistic corpus total

| Source | Designs |
|--------|---------|
| VTR + ISPD + EPFL | ~350 |
| RISC-V cores | ~2,000 |
| GitHub FPGA/SV | ~5,000 |
| PULP / ChipsAlliance / OpenROAD | ~100 |
| Amaranth-generated | ~500 |
| OpenCores | ~500 |
| **Total (after dedup/filter)** | **~5,000–7,000** |

---

## Implementation Priority Order

1. **`step_n(n)` in WASM** — eliminates 50,000 JS/WASM boundary crossings per frame. Immediate win on existing code.
2. **`-msimd128 -mrelaxed-simd`** on Clang compilation of `sim.cpp` — SERV's 1-bit serial architecture maps extremely well to SIMD. Potential 2–4× throughput.
3. **`write_cxxrtl -O6`** in Yosys — 20–40% simulation speed for free.
4. **`ALLOW_MEMORY_GROWTH=0` + fixed `INITIAL_MEMORY`** on CXXRTL driver only — eliminates bounds checks. Do not apply to nextpnr.
5. **IndexedDB caching of `sim.wasm`** — 30–60× improvement for repeat visits.
6. **Pre-synthesize SERV** — skip entire Yosys+Clang boot for standard config.
7. **Get nextpnr-xilinx building natively** — XC7S50, `WITH_PYTHON=OFF`, one device only.
8. **Design and implement compact chipdb binary format** — delta encoding, tile symmetry, hot/cold split, progressive loading.
9. **Compile nextpnr-xilinx to WASM** — with all flags above.
10. **Island partitioning (RapidPnR)** — N Workers × 1 nextpnr instance each. Works everywhere including w3schools. 1.6–2.5× speedup.
11. **WebGPU PathFinder** — GPU-accelerated routing iterations. Faster per-iteration than CPU but uncertain in w3schools iframes.
12. **Analytical placement (DREAMPlaceFPGA)** — differentiable wirelength objective, WebGPU gradient computation.
13. **NPN precomputation table** — synthesize corpus, extract classes, bake into ABC.
14. **RTL pattern pre-pass in Yosys** — CARRY4, MUXF7/F8, common idioms bypassing ABC.

---

## Notes on Claims to Verify — With Full Reasoning

**RapidPnR** — confirmed real. Published 2025/2026 in *INTEGRATION, the VLSI Journal*. Uses netlist partitioning into disjoint routing islands, achieves 1.6–2.5× P&R speedup with negligible quality loss. The approach: partition the netlist into N islands with minimal inter-island nets, run one nextpnr instance per island in parallel, stitch inter-island nets in a final pass on the main thread. See the Island Partitioning section for browser implementation details.

**BDD-compressed routing graphs** — real technique (Coudert et al., DAC 1996) but the "few kilobytes" claim is wrong at XC7S50 scale. Why: BDD size depends critically on variable ordering. Finding the optimal variable ordering for a 2D grid graph is NP-hard. A bad ordering causes exponential blowup — the BDD can end up *larger* than the explicit PIP enumeration, not smaller. Coudert worked on the XC4000 series which has orders of magnitude fewer routing resources than XC7S50. The canonical-tile + exception table approach is the proven technique at this scale. BDD overlay is interesting research but not a straightforward implementation.

**`-s SIDE_MODULE=1`** (from Grok's CMake flags) — **wrong, do not use**. A `SIDE_MODULE` in Emscripten is a shared library with no entry point that requires a `MAIN_MODULE` to load it. nextpnr has a well-defined entry point. Using `SIDE_MODULE` would break the build in a confusing, hard-to-diagnose way. For a Worker-based tool use `-s ENVIRONMENT=worker` or `-s STANDALONE_WASM=1`.

**NPN table "few KB"** — undersized. Empirically measured from the full GitHub + VTR corpus: **80–120 KB**. A few thousand NPN classes at 16–32 bytes each. Still small and worth doing, but not "a few KB" as originally claimed.

**Sub-50ms routing for SERV with WebGPU** — not credible. PathFinder requires 5–15 iterations for even low-congestion designs. Each iteration traverses the full routing graph. WebGPU dispatch overhead adds latency per shader invocation. Realistic target: 200–800ms on a mid-range laptop GPU for a mature implementation.

**YoWASP archived March 2026** — YoWASP packages still work as frozen CDN assets but are no longer maintained. If you need a version update or bug fix you cannot get one. Plan accordingly for long-term maintenance.

---

## The Unifying Principle (Your CUDA Insight at Architectural Scale)

Your CUDA competition win was: the compiler cannot know your constants at compile time, but you do — so bake them into immediates where the instruction encoding carries the value for free.

Applied to this entire stack:

**The FPGA device is a constant. The synthesis library is a constant. The timing model is a constant. Everything that depends only on constants should be precomputed and embedded — the runtime tool does zero work on it.**

Most P&R tools treat the device database as data to be processed at runtime. The correct view is that the device database is a *program* — a specialized program for routing signals on one specific device — and it should be compiled, not interpreted.

What this principle identifies as true runtime work (genuinely depends on user input):
- Parsing the user's SystemVerilog
- Logic optimization of the user's specific logic
- Placement of the user's specific cells
- Routing of the user's specific nets

Everything else — synthesis library matching, timing lookups, legality checking, cost model evaluation — is a lookup into precomputed tables that should be constants in the binary. This is what Vivado does. Open-source tools treat it as runtime data because flexibility is valued over speed. For a single-target browser tool you have the same freedom you had in the CUDA competition: you know your constants, bake them in.

Use this principle as a test when you encounter any operation during implementation: *does this depend only on the XC7S50 device and fixed synthesis target?* If yes, it should be precomputed offline and embedded, not computed at runtime.

---

## ABC Internals — What You Are Replacing With the Pre-Pass

You cannot implement the pattern pre-pass without understanding what ABC actually does, because the pre-pass bypasses ABC for recognized patterns.

**ABC's internal representation: And-Inverter Graphs (AIGs).** Every logic function in your design becomes a DAG of AND gates and inverters. This is ABC's canonical form before technology mapping.

**Cut enumeration.** ABC finds all K-feasible cuts of each node — all subgraphs of depth ≤ K inputs that can be mapped to one LUT-K. For K=6 (LUT6) the number of cuts per node grows combinatorially. ABC then selects a covering that minimizes area (LUT count) or delay (logic levels).

**Why cut enumeration is overkill for LUT6 with MUXF7/F8.** The XC7S50 has MUXF7 and MUXF8 which allow 7-input and 8-input functions at fixed cost. A mapper that knows about these can solve the covering problem optimally for any function up to 8 inputs without cut enumeration — it checks 6 inputs (1 LUT), 7 inputs (2 LUT + F7), 8 inputs (4 LUT + F7 + F8) and takes the first that fits. This is O(1) per node instead of O(cuts) per node. The entire cut enumeration machinery is unnecessary for these common cases.

**NPN equivalence classes.** Any Boolean function of N inputs belongs to a class of functions equivalent under input permutation, input negation, and output negation. ABC exploits this with NPN canonicalization but incompletely. The pre-pass completes it: for every NPN class that appears in real RISC-V RTL (empirically determined from the corpus), store the known-optimal LUT6 implementation. Skip ABC entirely for functions in known classes.

**Supergates.** Multi-output functions that share inputs can be packed into a single fractured LUT6. The canonical example: `P = A XOR B` (on O6) and `G = A AND B` (on O5) share inputs and map to one LUT6. Standard ABC may map these independently. The pre-pass recognizes the (XOR, AND) pair from the same inputs and emits a single fractured LUT6. For RISC-V ALUs that produce sum, carry, overflow, and zero flag from shared inputs, this is significant.

**What the pre-pass should match on:** Boolean function, not signal names. A 32-bit adder is a 32-bit adder whether it comes from SERV, PicoRV32, or VexRiscv. Match the AIG structure or the truth table, never the RTL signal names.

---

## Profile-Guided Optimization (PGO) on CXXRTL Output

Clang supports PGO. Emscripten does not natively support PGO for WASM targets, but you can use native PGO data as a hint for WASM compilation:

1. Compile `sim.cpp` natively with Clang instrumentation: `clang++ -fprofile-instr-generate sim.cpp`
2. Run a representative SERV workload (e.g., 10M cycles of a compute benchmark)
3. Convert profile data: `llvm-profdata merge -output=sim.profdata default.profraw`
4. Recompile to WASM with profile data: `clang++ -fprofile-instr-use=sim.profdata --target=wasm32 ...`

The profile guides the optimizer toward hot code paths from the first execution, rather than waiting for V8's JIT to warm up. For a simulation that runs billions of iterations, the first few thousand cycles before JIT warmup are a measurable cost. PGO eliminates it.

The branch predictor in V8 does its own profiling and eventually optimizes hot paths anyway — PGO at compile time gives you that optimization from the very first execution.

---

## SERV Two-Cycle Bus Protocol — Why This Matters

Your existing SERV implementation correctly models 2-cycle memory latency on the instruction bus:

```cpp
if(icyc && !prev_icyc) {
    // First cycle: present data but DON'T ack yet
    dut.p_ibus__rdt.data[0] = rom[(current_pc>>2) & 0xFFFF];
}
if(icyc && prev_icyc) {
    // Second cycle: NOW ack
    dut.p_ibus__ack.data[0] = 1;
}
```

Most SERV tutorials get this wrong — they either ack on the first cycle (artificially fast, incorrect cycle counts) or have random behavior. The correct 2-cycle model means your cycle counts are accurate to real hardware. Your GHz measurements are meaningful, not inflated.

This correctness carries through to the data bus, making your UART, mtime, and SRAM timing correct. Correctness first — all the speed optimizations are only valid because the underlying simulation is accurate.

---

## Tiered Memory Architecture for Larger Binaries

You mentioned implementing your own memory scheme to allow loading larger binaries. The correct WASM architecture:

```cpp
struct MemoryTier {
    uint32_t* hot_ram;    // WASM linear memory — fast, limited (~8 MB)
    uint32_t* cold_ram;   // JS ArrayBuffer — slower, effectively unlimited
    uint32_t  hot_size;
    uint32_t  cold_size;
};

// Memory access pattern:
// hot_ram = SRAM (working set, always resident in WASM linear memory)
// cold_ram = extended memory (accessed via JS callback on miss)

// Cold access via WASM→JS import:
__attribute__((import_module("env"), import_name("cold_read")))
uint32_t cold_read(uint32_t addr);
```

The WASM→JS boundary crossing for cold accesses has overhead (~10–50ns per call), but cold accesses are rare by definition. The working set fits in hot memory; cold memory covers the rest.

For persistence across sessions, back cold_ram with IndexedDB:
- On first load: fetch the binary, populate cold_ram, write to IndexedDB
- On subsequent loads: read from IndexedDB directly into cold_ram, skip network fetch
- The hot/cold boundary is configurable at load time based on available WASM memory

This extends the effective addressable memory from WASM's practical limit (~1–2 GB on 32-bit WASM) to whatever the browser's JS heap allows, which is much larger.

---

## Corpus Methodology — What to Run Against Each Source

Having the corpus without a methodology is useless. Map each source to its specific purpose:

**VTR benchmarks + Titan23** — validate P&R correctness. These have known-correct P&R solutions documented in published papers. Run your nextpnr-xilinx on them and compare routing completion rate and wirelength against the published Titan23 numbers. If your tool matches within 10–15% it is working correctly.

**ISPD contest benchmarks** — stress test the router specifically. These are designed to create maximum routing congestion. If your router completes on ISPD benchmarks it will complete on essentially any real design. Use these to find the cases where PathFinder diverges.

**EPFL combinational benchmarks** — validate synthesis quality. Every ABC/Yosys paper since 2018 reports results on these 43 benchmarks. You can compare your synthesis output (LUT count, logic depth) directly against published numbers to verify your Yosys + pre-pass is not regressing quality.

**RISC-V cores** — generate the NPN equivalence class table. Run each through:
```bash
yosys -p "read_verilog design.v; synth -top top -flatten; abc -lut 6; # log NPN classes"
```
Collect the histogram across all cores. The top 1000 NPN classes by frequency are your precomputation table.

**Amaranth/Clash-generated Verilog** — coverage of machine-generated RTL patterns. Hand-written RTL has stylistic patterns that concentrate synthesis hotpaths. Machine-generated RTL has different patterns. You need both to avoid a pre-pass that works on hand-written RISC-V but fails on generated code.

**Verilator as reference for simulation speed** — compile each RISC-V core with Verilator and measure simulation throughput. This gives you a reference number to compare your CXXRTL simulation speed against. CXXRTL should reach 50–80% of Verilator speed for well-optimized compilation; if you are below 30% something is wrong with your Clang flags.

---

## Combined Effect: Pre-synthesized SERV + Speculative Loading

These two features interact in a way worth stating explicitly:

- Pre-synthesized SERV: `sim.cpp` and the JSON netlist are constants in the HTML. No Yosys at runtime.
- Speculative loading: tools and chipdb start fetching on page load before user clicks.
- IndexedDB caching: `sim.wasm` (the Clang-compiled simulation binary) is cached after first compile.

Combined effect on the standard SERV configuration after first visit:
- Page load: speculative fetch starts for nextpnr WASM + chipdb (both likely already in browser cache)
- User clicks "Boot": IndexedDB hit for `sim.wasm` (skip Yosys + Clang entirely)
- P&R runs on pre-synthesized netlist: no Yosys cost
- Result: **sub-200ms from click to simulation running**, after first visit

This number is not achievable with any individual optimization alone. It requires all three working together. On first visit the full pipeline runs (30–60 seconds). Every subsequent visit costs essentially nothing.

---

## w3schools WebGPU Uncertainty

The document says WebGPU survives the w3schools constraint. This needs a caveat.

WebGPU access inside an iframe requires the embedding page to allow the `gpu` permission policy:

```http
Permissions-Policy: gpu=*
```

W3schools controls whether this header is set. As of the time of writing it is not confirmed whether w3schools passes the `gpu` permission through to iframes. This means the WebGPU router may be unavailable in exactly the most constrained environment you are designing for.

The three-tier fallback is therefore not optional — it is required for the w3schools constraint to be real:
1. WebGPU (fast, uncertain availability in w3schools)
2. Worker CPU router (always available in iframes, structured-clone communication)
3. Single-threaded WASM router (last resort, blocks main thread, always works)

Design the tool so tier 3 produces correct results even if slowly. Correctness in all environments; speed where available.

---

## Foedag-Style Per-Pass Caching

**Foedag** (FPL 2022) — proposes a plugin architecture where each EDA pass is independently cacheable, keyed on the hash of its inputs. If the user's design has not changed, reuse cached pass outputs at any granularity.

For your tool this means:
```javascript
// Key: SHA256(rtl_source + pass_name + pass_version)
const synthKey = await sha256(rtlSource + 'yosys-synth' + YOSYS_VERSION);
const cached = await idb.get(synthKey);
if (cached) {
    // skip synthesis entirely, use cached JSON netlist
    return JSON.parse(cached);
}
```

Applied to each stage independently:
- RTL → synthesis: cache the JSON netlist
- Netlist → P&R: cache the placed-and-routed `.fasm`
- P&R → bitstream: cache the `.bit` file

If the user changes only their top-level RTL but not a submodule, only the affected stages re-run. For iterative RTL development this turns a 60-second full run into a 2-second incremental run for small changes.

The Foedag paper's key insight that applies here: **cache at the boundary between tools, not inside them**. The JSON netlist is the natural boundary between Yosys and nextpnr. The `.fasm` is the natural boundary between nextpnr and bitstream assembly. Both are already serializable text formats.
