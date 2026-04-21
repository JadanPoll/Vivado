# Vivado Developer Reference — Research-Grade Edition
### A Practitioner's Deep Guide to Synthesis Attributes, Hardware Primitives, Toolchain Internals, and Theoretical Foundations

> **Scope:** This document targets practitioners who need to understand not just *what* Vivado's synthesis attributes and 7-Series primitives do, but *why* they work, *how* the toolchain processes them internally, and *when* misusing them leads to subtle, hard-to-diagnose failures. It covers synthesis attribute semantics, primitive architecture, the Vivado compilation pipeline, timing model internals, clock domain crossing theory, and domain-specific applications. Reference manuals: **UG901** (Vivado Synthesis), **UG953** (7-Series Libraries Guide), **UG470** (Configuration), **UG474** (CLB Architecture), **UG479** (DSP48E1), **UG472** (Clocking Resources).

---

## Table of Contents

1. [Vivado Compilation Pipeline — What Actually Happens to Your Code](#1-vivado-compilation-pipeline--what-actually-happens-to-your-code)
2. [Synthesis Attributes — Complete Reference](#2-synthesis-attributes--complete-reference)
3. [The Logic Fabric — LUT, Carry, and Mux Primitives](#3-the-logic-fabric--lut-carry-and-mux-primitives)
4. [Storage Elements — Flip-Flop Primitives](#4-storage-elements--flip-flop-primitives)
5. [Shift Register Primitives — SRL16E and SRLC32E](#5-shift-register-primitives--srl16e-and-srlc32e)
6. [Block RAM — RAMB18E1 and RAMB36E1](#6-block-ram--ramb18e1-and-ramb36e1)
7. [Hardened FIFO — FIFO18E1 and FIFO36E1](#7-hardened-fifo--fifo18e1-and-fifo36e1)
8. [DSP48E1 — Complete Datapath Reference](#8-dsp48e1--complete-datapath-reference)
9. [I/O Primitives — Buffers, Delays, and SERDES](#9-io-primitives--buffers-delays-and-serdes)
10. [Clocking Primitives — BUFG, BUFR, MMCM, PLL](#10-clocking-primitives--bufg-bufr-mmcm-pll)
11. [Configuration and Debug Primitives](#11-configuration-and-debug-primitives)
12. [Clock Domain Crossing — Theory and Implementation](#12-clock-domain-crossing--theory-and-implementation)
13. [Timing Model Internals](#13-timing-model-internals)
14. [XDC Constraints — Complete Reference](#14-xdc-constraints--complete-reference)
15. [Power Architecture and Clock Gating](#15-power-architecture-and-clock-gating)
16. [Quick Reference Decision Trees](#16-quick-reference-decision-trees)

---

## 1. Vivado Compilation Pipeline — What Actually Happens to Your Code

Understanding what Vivado does to your HDL source before it becomes a bitstream is essential context for understanding why synthesis attributes exist and when they are needed. Without this model, attribute usage becomes cargo-cult engineering.

### 1.1 The Full Pipeline

```
HDL Source (VHDL / Verilog / SystemVerilog)
    │
    ▼ Elaboration (xelab)
    │  - Parses HDL syntax and resolves module hierarchy
    │  - Evaluates generate blocks, parameters, and localparams
    │  - Expands arrays of instances
    │  - Produces an elaborated netlist — pure behavioral, no technology mapping
    │  - This is what you see in "Open Elaborated Design" (the RTL schematic)
    │
    ▼ Synthesis (synth_design)
    │  - Technology mapping: maps RTL constructs to 7-Series primitives
    │  - Boolean minimization: reduces logic using Quine-McCluskey / ESPRESSO variants
    │  - LUT inference: maps any Boolean function of ≤6 inputs to a single LUT6
    │  - Register inference: maps always_ff blocks to FDRE/FDCE/FDSE/FDPE
    │  - Memory inference: maps reg arrays to BRAM or distributed RAM
    │  - Arithmetic inference: maps +/- to CARRY4 chains, * to DSP48E1
    │  - FSM extraction: identifies and re-encodes state machines
    │  - Resource sharing: reuses multipliers/adders across multiple operations
    │  - Register retiming (if enabled): moves FFs across logic levels for timing
    │  - Produces: synthesized netlist checkpoint (.dcp)
    │
    ▼ opt_design
    │  - Constant propagation: eliminates logic driven by compile-time constants
    │  - Dead code sweep: removes cells with no path to any primary output
    │  - Remap: re-maps LUT combinations for better packing density
    │  - Retarget: replaces cells with more efficient primitive equivalents
    │  - This is the stage where signals without KEEP get silently deleted
    │
    ▼ place_design
    │  - Global placement: assigns every cell to a physical site (X,Y coordinate)
    │  - Analytical placement: minimizes estimated wirelength (quadratic HPWL model)
    │  - Timing-driven refinement: moves cells to close estimated slack violations
    │  - Legalization: resolves conflicts where two cells claim the same site
    │  - Uses simulated annealing — non-deterministic unless -seed is fixed
    │
    ▼ phys_opt_design (optional but strongly recommended)
    │  - Post-placement physical optimization
    │  - Cell replication: duplicates high-fanout drivers to reduce net delay
    │  - Physical retiming: moves pipeline registers across logic for timing
    │  - Hold fixing: inserts delay buffers (LUT1 pass-throughs) on hold violations
    │
    ▼ route_design
    │  - Global routing: assigns nets to routing channels
    │  - Detailed routing: assigns specific wire segments and PIPs
    │  - Negotiation-based (PathFinder-style): iteratively penalizes overused segments
    │  - Timing-driven: critical paths get first access to best routing resources
    │  - Produces: fully routed design checkpoint (.dcp)
    │
    ▼ write_bitstream
       - Generates configuration frames from placed and routed netlist
       - Computes CRC-32 over frame data
       - Applies AES-256 encryption if enabled
       - Produces: .bit bitstream file
```

### 1.2 Why Attributes Exist

At each stage above, Vivado makes heuristic decisions. It guesses the best encoding for your FSM. It guesses whether a memory should go to BRAM or LUT RAM. It guesses whether a chain of FFs can be merged into an SRL. It guesses which signals are "dead" and can be deleted.

Most of the time these guesses are correct. When they are wrong, synthesis attributes are the mechanism for overriding individual decisions without restructuring the entire design. They are surgical — applying to a single signal, module, or instance — and they are embedded in source code where they travel with the design through version control.

**The hierarchy of override mechanisms, from weakest to strongest:**

| Mechanism | Scope | Overrides |
|---|---|---|
| `(* KEEP *)` | Single net | Synthesis dead-code elimination only |
| `(* SHREG_EXTRACT = "no" *)` | Single array | SRL inference only |
| `(* RAM_STYLE *)` | Single array | Memory type inference only |
| `(* FSM_ENCODING *)` | Single FSM register | FSM encoding only |
| `(* DONT_TOUCH *)` | Net or module | All synthesis + implementation optimization |
| Explicit primitive instantiation | Single instance | Entire inference pipeline — direct hardware control |

Understanding this hierarchy prevents the common mistake of applying `DONT_TOUCH` (the nuclear option) when `KEEP` (a surgical option) would have been sufficient.

### 1.3 How Synthesis Attributes Are Processed

In the HDL parser, `(* attribute = "value" *)` syntax creates an **attribute annotation** attached to the next declaration. These annotations travel with the elaborated netlist object through the entire compilation pipeline.

At synthesis time, Vivado reads each attribute and modifies its optimization behavior accordingly. The attribute is not compiled into logic — it is metadata consumed by the compiler. This means:

- Attributes have no effect on simulation (simulators ignore unknown attributes unless specifically coded to handle them).
- Attributes interact with the Vivado tool version — an attribute valid in Vivado 2019 may have different behavior in Vivado 2023 as the synthesis engine evolves.
- Attribute names are case-insensitive in the parser but conventionally written in ALL_CAPS.
- Attribute values are case-insensitive strings: `"true"` and `"TRUE"` are identical.

---

## 2. Synthesis Attributes — Complete Reference

### 2.1 Preservation and Debug Attributes

---

#### `(* KEEP = "true" *)`

**What it does at the hardware level:**

During `opt_design`, Vivado performs a backward traversal of the netlist DAG (Directed Acyclic Graph) from primary outputs. Any node not reachable from a primary output is classified as dead code and pruned. `KEEP` marks the net as a virtual primary output for the purposes of this traversal, forcing the node to be retained.

**Scope:** Synthesis and `opt_design` only. After placement, the net is a physical wire with a specific route — `KEEP` has no effect on whether the implementation stages modify the routing.

**When the optimizer will delete a signal despite your intentions:**

Without `KEEP`, the following patterns are silently pruned:
- Any `wire` that fans out only to another `wire` that is also deleted (cascading deletion).
- Intermediate pipeline registers that drive only other intermediate registers (if the final output is the only "real" sink and Vivado decides to register-retime the whole chain into one stage).
- Debug assignments of the form `assign debug_out = internal_signal` where `debug_out` is never connected to a port.

```systemverilog
// Without KEEP — Vivado deletes debug_sum entirely:
wire [7:0] debug_sum = alu_a + alu_b;  // never drives a port → pruned

// With KEEP — survives opt_design:
(* KEEP = "true" *) wire [7:0] debug_sum = alu_a + alu_b;
```

**Interaction with `MARK_DEBUG`:**

`MARK_DEBUG` implies `KEEP` — any net tagged for ILA probing is automatically preserved. You do not need both attributes on the same net. However, `KEEP` without `MARK_DEBUG` is appropriate when you want the net in the schematic for inspection during bring-up, without committing to a full ILA deployment.

---

#### `(* DONT_TOUCH = "true" *)`

**Internal behavior:**

`DONT_TOUCH` on a net is equivalent to `KEEP` plus a constraint that prevents Vivado's implementation tools from merging, absorbing, or retiming across the net's driver. On a **module or instance**, it creates an optimization boundary — Vivado treats the boundary as if it were a black box during cross-boundary optimizations.

Specifically, `DONT_TOUCH` on an instance prevents:
- **Logic absorption:** Pulling a LUT from inside the module into a LUT outside the module (and vice versa) for packing efficiency.
- **Register retiming:** Moving a flip-flop from inside the module to outside (or vice versa) to balance pipeline stage delays.
- **Cell replication:** Duplicating a high-fanout cell inside the module to reduce net delays.
- **Physical optimization:** `phys_opt_design` will not restructure anything inside or crossing the boundary.

**The QoR (Quality of Results) cost:**

Placing a `DONT_TOUCH` boundary around a sub-module prevents the surrounding logic from being co-optimized with it. In a design where the critical path runs through the boundary, Vivado cannot balance the path by moving logic across it — so you may pay a timing penalty on paths that enter or exit the module.

**Correct use pattern:**

```systemverilog
// Good: applied to a synchronizer chain that must not be retimed or replicated
(* DONT_TOUCH = "true" *)
module cdc_synchronizer #(parameter WIDTH = 1) (
    input  wire             clk_dst,
    input  wire [WIDTH-1:0] async_in,
    output wire [WIDTH-1:0] sync_out
);
    (* ASYNC_REG = "true" *) reg [WIDTH-1:0] ff1, ff2;
    always_ff @(posedge clk_dst) begin
        ff1 <= async_in;
        ff2 <= ff1;
    end
    assign sync_out = ff2;
endmodule

// Bad: applied globally to a large datapath module because "it's timing-closed"
// — this prevents ALL future optimization including fixing new violations introduced
// by unrelated design changes elsewhere
(* DONT_TOUCH = "true" *)
module my_entire_fft ( ... );  // WRONG — too broad
```

---

#### `(* MARK_DEBUG = "true" *)`

**ILA infrastructure integration:**

When `MARK_DEBUG` is present on a net, Vivado's post-synthesis design analysis pass adds the net to an internal debug net database. When you subsequently run **Set Up Debug** (in the GUI: Flow Navigator → Open Synthesized Design → Set Up Debug, or Tcl: `launch_runs impl_1` with debug enabled), Vivado:

1. Instantiates an `xil_defaultlib/ila_0` IP core (or extends an existing one).
2. Adds a probe port to the ILA for each `MARK_DEBUG` net.
3. Wires the probe ports to the nets by inserting the ILA into the post-synthesis netlist.
4. Places the ILA core during `place_design` using the remaining resources.

This entire process is automated — you do not need to manually instantiate the ILA or connect probe ports in your HDL.

**Resource consumption of the auto-inserted ILA:**

For N total probe bits and a capture depth of D samples:

```
BRAM36 consumption ≈ ceil(N / 36) × ceil(log2(D) / log2(512))
LUT consumption    ≈ 100 + (N × 2)   // trigger comparator logic
FF consumption     ≈ N + 64           // probe capture registers + control
```

For 64 probe bits at 1024-sample depth: approximately 2 BRAM36, ~230 LUTs, ~128 FFs.

**Discipline for production designs:**

In a team setting, define a naming convention for debug nets and gate them behind a compile-time parameter:

```systemverilog
parameter DEBUG_ENABLE = 1;
generate
    if (DEBUG_ENABLE) begin
        (* MARK_DEBUG = "true" *) wire [15:0] rx_data_dbg = rx_data;
        (* MARK_DEBUG = "true" *) wire        rx_valid_dbg = rx_valid;
    end
endgenerate
```

Setting `DEBUG_ENABLE = 0` in the production build eliminates all ILA resources at zero cost.

---

### 2.2 Resource Mapping Attributes

---

#### `(* RAM_STYLE = "block" | "distributed" | "registers" | "ultra" *)`

**How Vivado's memory inference works without this attribute:**

Vivado's synthesizer performs pattern matching on `reg` array declarations followed by synchronous write and read processes. It then applies a cost model based on:

- **Depth × Width:** Memories wider than 16 bits or deeper than 64 entries are generally pushed to BRAM.
- **Read semantics:** Asynchronous reads (combinational `assign` from the array) force distributed RAM — BRAM cannot do zero-latency reads.
- **Port count:** Single-port memories go to RAMB with one port unused. True dual-port memories require RAMB TDP mode.
- **Resource budget:** If the design is already BRAM-limited, Vivado may move borderline memories to distributed RAM.

The heuristic fails most often at the boundary cases — a 128-deep × 8-bit memory could legitimately go either way, and Vivado's choice may not match your intent.

**`"block"` — Physical architecture of RAMB36E1:**

BRAM is synchronous on both read and write. The output is registered, introducing exactly one clock cycle of read latency (two cycles if the optional output register `DOA_REG` is enabled). The read address is sampled on the clock edge, and the data appears at the output one cycle later.

```
Write cycle:  addr → WE=1 → ADDRA sampled → data written to array
Read cycle:   addr → ADDRA sampled → data appears at DOA after 1 cycle
```

The consequence: **you cannot use BRAM for zero-latency lookup tables.** If your design reads a value and immediately uses it in the same combinational path (e.g., a coefficient lookup inside a combinational multiplier tree), BRAM is incorrect and `"distributed"` is required.

**`"distributed"` — LUT RAM in SLICEM:**

Distributed RAM uses the SRAM cells of LUT6 primitives in SliceM tiles as addressable memory. The read path is purely combinational — the address directly selects SRAM cells, and the output is available with LUT propagation delay (~0.5 ns).

Key architectural constraint: distributed RAM consumes SliceM resources. The XC7S50 has 2,400 SliceM tiles, each containing 64 bits of distributed RAM capacity (one 64×1 RAM per LUT, or one 32×2, etc.). Total distributed RAM capacity is approximately `2,400 × 4 × 64 = 614,400 bits ≈ 75 KB`. This pool is shared with all shift register (SRL) usage. Oversubscribing SliceM causes synthesis to fail with a resource overflow error.

**`"registers"` — Plain flip-flops:**

Each bit of storage is a physical FDRE. For a `[7:0] reg [0:15]` array, this maps to 128 flip-flops. Read is combinational (wires from FF outputs); write is synchronous. No inference required — this is simply register file behavior.

Use this only when:
- The array is small enough that FF consumption is acceptable (< ~32 entries × data width).
- You need absolutely deterministic timing (no BRAM or LUT RAM timing uncertainty).
- You need `MARK_DEBUG` on individual elements (BRAM and distributed RAM are atomic — you can't probe individual cells easily).

**`"ultra"` (UltraScale+ only):**

Routes to 288Kb UltraRAM tiles. Not available on any 7-Series device including the XC7S50. Using this attribute on a 7-Series device causes a synthesis error. Documented here because it appears in portable code intended to run on both families.

```systemverilog
// Synthesis automatically picks wrong type at this boundary:
reg [7:0] ambiguous_mem [0:127];   // 128 bytes — could be BRAM or LUT RAM

// Force intent explicitly:
(* RAM_STYLE = "distributed" *) reg [7:0] fast_lut [0:127];   // async reads OK
(* RAM_STYLE = "block" *)       reg [7:0] large_buf [0:1023]; // 1 cycle latency OK
```

---

#### `(* USE_DSP = "yes" | "no" | "simd" *)`

**How arithmetic inference decides without this attribute:**

Vivado's synthesizer recognizes multiply operators (`*`) and multiply-accumulate patterns (`P <= P + A*B`) and maps them to DSP48E1 by default — unless the operands are narrow constants that are cheaper in LUTs (e.g., multiply by a power of 2 becomes a left shift, multiply by 3 becomes `A + (A << 1)`).

The inference can go wrong when:
- A multiply is part of a loop-carried accumulation — Vivado may generate a fabric multiplier and a DSP adder separately.
- Multiple small multiplies could each fit in fabric LUTs but one DSP48E1 could handle them all with pre-adder tricks.
- The design is DSP-limited and you want to explicitly move marginal operations to fabric.

**`"yes"` — DSP48E1 performance advantage:**

The DSP48E1 tile runs at 550+ MHz in -1 speed grade (verified against UG479 Table 2). A fabric 18×18 multiplier built from LUTs typically runs at 150–200 MHz on the same device. On any signal-processing path where a multiply is the critical element, this is a 2.5–3.5× frequency improvement.

Additionally, DSP48E1 cascade ports (`PCIN → PCOUT`) allow chaining multiply-accumulate operations with zero routing delay between stages — the intermediate result never enters the INT routing matrix. A 16-tap FIR filter implemented as a DSP cascade achieves dramatically lower net delay than the same filter built in fabric.

**`"no"` — When to suppress DSP inference:**

DSP48E1 tiles are a finite resource (120 on XC7S50). Common scenarios where `"no"` is correct:
- You have manually instantiated DSP48E1 for a high-performance operation and Vivado is additionally consuming DSPs for secondary low-priority multiplies that don't need the speed.
- A constant-coefficient multiply (e.g., `data * 5`) can be implemented as `(data << 2) + data` — four adder bits from CARRY4, no DSP needed.
- You are implementing a design that must be portable to a device with fewer DSPs and you want to verify it fits without DSP use.

**`"simd"` — Packing two operations into one DSP:**

The DSP48E1 pre-adder operates on 25-bit operands. In SIMD mode, the operand is split into two halves and processed as two independent narrow operations sharing the multiplier pipeline. This halves DSP consumption for narrow-width parallel datapaths at the cost of requiring operand packing/unpacking logic.

```systemverilog
// Force all multiplies in this module to DSP:
(* USE_DSP = "yes" *)
module fir_tap (
    input  wire signed [17:0] coeff, sample,
    input  wire [47:0]        p_in,
    output wire [47:0]        p_out
);
    assign p_out = p_in + coeff * sample;
endmodule
```

---

#### `(* EQUIVALENT_REGISTER_REMOVAL = "no" *)`

**What Vivado does without this attribute:**

During synthesis optimization, Vivado identifies registers whose D inputs are driven by logically identical combinational cones — same function, same input signals. It merges these into a single physical flip-flop, with the single output fanning out to all the original destinations. This is called **register merging** or **equivalent register removal**.

This is correct behavior in most cases — it saves area and reduces routing complexity. It fails when:
- You intentionally want two separate physical FF copies for **fanout reduction** (each copy drives a different half of the load).
- You are implementing **triple modular redundancy (TMR)** for fault tolerance — three copies must remain three separate physical FFs.
- You are doing **timing isolation** — two copies of a register intentionally placed in different areas of the die to give the router flexibility in closing timing to different destination groups.

```systemverilog
// TMR register: three physically separate FFs required
(* EQUIVALENT_REGISTER_REMOVAL = "no" *)
reg [7:0] data_a, data_b, data_c;

always_ff @(posedge clk) begin
    data_a <= data_in;   // these three are logically identical
    data_b <= data_in;   // without the attribute, Vivado collapses to one FF
    data_c <= data_in;   // with it, all three survive as separate physical cells
end

// Voter: take majority
assign data_out = (data_a & data_b) | (data_b & data_c) | (data_a & data_c);
```

---

#### `(* MAX_FANOUT = N *)`

**The fanout problem:**

When one signal drives many loads, the physical net has high capacitance. High capacitance means high net delay (from the RC model: `t = 0.69 × R_driver × C_net`). Additionally, a high-fanout net constrains placement — all loads must be "reachable" within the timing budget from one driver location, which may force suboptimal placement of unrelated logic.

Common high-fanout nets in real designs:
- Global reset (`rst_n`): may fan out to every FF in the design (thousands of loads).
- Clock enables for large datapath stages.
- Configuration registers that control many functional units.

**What `MAX_FANOUT` triggers:**

Setting `MAX_FANOUT = N` on a net (or the register that drives it) tells Vivado to replicate the driving cell as many times as needed so that no single copy drives more than N loads. Each replica is placed near its group of loads, distributing the capacitive load across many local drivers.

The replicas are logically identical — they all compute the same function from the same inputs. The implementation simply creates physical copies with independent routing.

```systemverilog
// Global reset — fan out to thousands of FFs without this would create a
// massive high-delay reset tree that constrains all placement:
(* MAX_FANOUT = 50 *)
reg rst_sync;

// Vivado creates ceil(total_loads / 50) physical copies of rst_sync,
// each driving at most 50 FFs in their local placement area.
```

**Cost:** Each replica is a physical FF or LUT that consumes a BEL site. For a reset driving 5,000 FFs with `MAX_FANOUT = 50`, Vivado creates 100 replica FFs. This is usually a small fraction of total resources but should be accounted for in resource budgets.

---

#### `(* IOB = "true" *)`

**The I/O register path:**

Every IOB (I/O Block) tile contains dedicated registers in its ILOGIC (input side) and OLOGIC (output side) blocks. These registers are physically inside the I/O tile — not in the general fabric CLB array. Placing a flip-flop inside the IOB eliminates an entire routing segment: the path from the pad to a fabric register traverses the IOB → INT routing hierarchy, but a pad → IOB register path uses only internal IOB wiring.

This translates to a measurable timing improvement: typically 0.3–0.7 ns faster setup/hold window on I/O paths, depending on the interface speed and routing congestion.

**When Vivado does this automatically vs. not:**

Vivado automatically places FF into the IOB for simple registered input/output patterns. It does not do so when:
- The FF has additional fanout to other fabric logic (the IOB register output has limited fanout capability).
- There is combinational logic between the pad and the FF.
- The FF is part of a multi-bit shift register that Vivado wants to pack into an SRL.

`(* IOB = "true" *)` forces the placement even in cases where Vivado would otherwise back away from it.

```systemverilog
// Output register explicitly placed in IOB:
(* IOB = "true" *)
always_ff @(posedge clk)
    data_out <= data_internal;   // FF placed in OLOGIC block of IOB tile

// Input register explicitly placed in IOB:
(* IOB = "true" *)
always_ff @(posedge clk)
    data_reg <= data_in_pad;     // FF placed in ILOGIC block of IOB tile
```

---

### 2.3 FSM and State Encoding Attributes

---

#### `(* FSM_ENCODING = "one_hot" | "sequential" | "gray" | "johnson" | "none" *)`

**How Vivado's FSM extractor works:**

The synthesis engine contains a pattern recognizer that identifies sequences of the form:
1. A register whose next-state assignment depends on the current value of that same register (self-referential combinational logic).
2. Outputs that are functions of the current state.

When this pattern is found, Vivado labels it as an FSM and applies encoding-specific optimization. The encoding choice affects:
- **Number of flip-flops consumed** (state register width).
- **Complexity of the next-state logic** (how many LUTs the decoder requires).
- **Critical path** (whether the state decode path or the output decode path is the bottleneck).

**Encoding comparison — formal analysis:**

For an FSM with N states:

| Encoding | FF Count | Next-state logic per LUT | Output logic | Notes |
|---|---|---|---|---|
| Binary | ⌈log₂(N)⌉ | Complex decoder required | Requires decode | Most compact |
| One-hot | N | Single-bit check: `state[i]` | Direct | Fastest; FFs cheap on FPGA |
| Gray | ⌈log₂(N)⌉ | Same as binary | Requires decode | 1-bit transition per cycle |
| Johnson | 2⌈log₂(N)⌉ | Simple shift pattern | Requires decode | Counter-like FSMs only |

On FPGAs, flip-flops are relatively abundant (65,200 on XC7S50). LUT depth (logic levels) is the primary speed constraint. One-hot encoding minimizes LUT depth because each state's decode is a single-bit check — no multi-input decoder is needed. Vivado defaults to one-hot for FSMs with more than 5 states for exactly this reason.

**The `"none"` escape hatch:**

`"none"` disables FSM extraction entirely. Vivado treats the state register as a plain register array with no special optimization. This is useful when:
- Vivado's FSM optimizer is misidentifying a counter or datapath register as an FSM and applying incorrect transformations.
- You need the state bits to remain exactly as written (e.g., the state value is output on a port for external decode).
- You are debugging and need the synthesized netlist to map 1:1 to your source.

```systemverilog
// Gray encoding for a FIFO pointer crossing clock domains:
// Only 1 bit changes per increment → safe for CDC synchronization
(* FSM_ENCODING = "gray" *)
reg [3:0] wr_ptr;   // 4-bit gray counter

// Standard one-hot for a fast protocol controller:
(* FSM_ENCODING = "one_hot" *)
typedef enum logic [5:0] {
    IDLE, ARBITRATE, REQUEST, GRANT, TRANSFER, COMPLETE
} bus_state_t;
```

---

#### `(* SHREG_EXTRACT = "no" *)`

**The SRL inference mechanism:**

When Vivado's synthesizer sees a shift register pattern — a chain of flip-flops where each FF's D input is the Q output of the preceding FF — it recognizes that this can be implemented more efficiently using an SRL (Shift Register LUT) primitive.

An SRL16E or SRLC32E repurposes a LUT6's SRAM array as a 16-bit or 32-bit shift register, with a programmable tap output. What would require 16 or 32 physical flip-flops consumes only one LUT site in a SliceM. This is a dramatic area saving.

The synthesis inference is aggressive — Vivado will extract SRLs from patterns as short as 4 elements.

**When SRL inference is wrong:**

- **Multi-tap access:** SRL primitives expose only one programmable output tap. If your pipeline requires `stage[3]`, `stage[7]`, and `stage[12]` simultaneously (as in a CPU forwarding network), SRL cannot satisfy this — you need individual FFs.
- **Reset semantics:** SRLs cannot be initialized to an arbitrary reset value. They have `INIT` parameter support but no synchronous or asynchronous reset input. If your shift register requires `if (rst) pipe <= '0`, the inferred SRL will silently drop the reset capability, which is a functional bug.
- **Debug visibility:** Individual pipeline stages inside an SRL are not accessible as named nets. `MARK_DEBUG` on an SRL-inferred chain will probe only the final output, not intermediate stages.
- **Timing differences:** SRL read-address inputs have different timing arcs than FF clock-to-Q paths. In a path where the shift register output connects to a DSP or CARRY4, the timing model for the SRL may produce unexpected slack changes.

```systemverilog
// Pipeline delay line — SRL is correct here (no tap access needed):
reg [7:0] delay_line [0:15];
// ... (Vivado will infer SRL16E, which is fine)

// CPU pipeline with forwarding — SRL is WRONG here:
(* SHREG_EXTRACT = "no" *)
reg [31:0] ex_stage, mem_stage, wb_stage;
always_ff @(posedge clk) begin
    ex_stage  <= id_result;    // need access to all three simultaneously
    mem_stage <= ex_stage;
    wb_stage  <= mem_stage;
end
// Forwarding mux accesses all three — SRL cannot provide this
```

---

### 2.4 Placement and Physical Attributes

---

#### `(* ASYNC_REG = "true" *)`

This attribute is covered in detail in Section 12 (Clock Domain Crossing). The placement behavior is described here for completeness.

**Physical effect on placement:**

When `ASYNC_REG` is applied to two FFs in a synchronizer chain, Vivado's placer adds a constraint that the two FFs must be placed in the same **slice** — not merely the same clock region or nearby, but the exact same physical slice with shared routing. This maximizes the resolution time available to the second FF.

The timing constraint added by `ASYNC_REG` is a **false path** on the setup check for the first FF (the metastable stage) combined with a **maximum delay** constraint ensuring the second FF is placed within the same slice. Vivado also adds a `set_bus_skew` constraint to prevent the two bits of a multi-bit synchronizer from drifting apart in placement.

**Critical error pattern:**

```systemverilog
// WRONG — async_reg applied to the SOURCE FF (domain A):
always_ff @(posedge clk_a)
    (* ASYNC_REG = "true" *) src_ff <= data;  // ERROR: wrong domain

// CORRECT — apply only to CATCHING FFs in domain B:
(* ASYNC_REG = "true" *) reg sync_ff1, sync_ff2;
always_ff @(posedge clk_b) begin
    sync_ff1 <= src_ff;   // catches from domain A — may go metastable
    sync_ff2 <= sync_ff1; // resolves metastability
end
```

---

#### `(* PBLOCK = "pblock_name" *)`

**Pblock mechanics:**

A Pblock (Placement Block) is a rectangular region of the device die defined by a set of resource coordinates: `SLICE_X0Y0:SLICE_X15Y49` defines a 16×50 slice rectangle. Pblocks can include multiple resource types: slices, DSPs, BRAMs. An instance tagged with `(* PBLOCK = "name" *)` is constrained to place all its cells within the specified resource set.

**Interaction with routing:**

By default, a Pblock constrains placement only — routing wires can still enter and exit the region freely. The `CONTAIN_ROUTING true` property additionally constrains the router to keep routing for nets whose both endpoints are inside the Pblock within the Pblock's boundary. This reduces interference between the Pblock's logic and surrounding logic but may increase internal routing congestion.

**Use cases requiring Pblocks:**

Partial Reconfiguration is the most critical use case. A Reconfigurable Partition (RP) must have a Pblock that:
- Contains exactly the resources needed by the largest reconfigurable module variant.
- Does not overlap with the static region.
- Has `SNAPPING_MODE ON` to align to clock region boundaries (required by the PR implementation flow).
- Includes all resource types the RP may need: if any RP variant uses BRAM, the Pblock must include BRAM resources even if the current variant does not use them.

```tcl
// XDC:
create_pblock pblock_rp
add_cells_to_pblock [get_pblocks pblock_rp] [get_cells rp_inst]
resize_pblock [get_pblocks pblock_rp] \
    -add {SLICE_X0Y0:SLICE_X15Y49 DSP48_X0Y0:DSP48_X0Y9 RAMB36_X0Y0:RAMB36_X0Y4}
set_property SNAPPING_MODE ON [get_pblocks pblock_rp]
set_property CONTAIN_ROUTING true [get_pblocks pblock_rp]
```

---

#### `(* CLOCK_BUFFER_TYPE = "none" | "BUFG" | "BUFR" | "BUFH" *)`

**Default clock buffer insertion:**

When Vivado sees a port declared with the `CLK` or `clock` naming convention — or identified as a clock by a `create_clock` XDC constraint — it automatically inserts a `BUFG` on the net at synthesis time. This is almost always the correct behavior.

The attribute is needed when:
- A clock enters through a non-standard port name that Vivado correctly does not auto-buffer — you want to force `BUFG` insertion.
- A clock is distributed only within a single clock region — use `"BUFR"` to avoid consuming a global BUFG resource.
- You are implementing a deliberate ungated clock path (e.g., directly connecting an MMCM output to a test register) — use `"none"` to prevent the automatic buffer.

```systemverilog
// Port name does not signal "clock" to Vivado — force BUFG insertion:
(* CLOCK_BUFFER_TYPE = "BUFG" *)
input wire ref_clk_25mhz;

// Regional clock — only drives logic in one bank:
(* CLOCK_BUFFER_TYPE = "BUFR" *)
input wire sensor_clk;
```

---

## 3. The Logic Fabric — LUT, Carry, and Mux Primitives

### 3.1 LUT6 — Internal Architecture

**Physical structure:**

A LUT6 is a 64-bit SRAM array with a 6-bit address bus. The six logic inputs (A1–A6) form the 6-bit address. The SRAM cell at that address drives the output:

```
f(A6, A5, A4, A3, A2, A1) = INIT[ A6×32 + A5×16 + A4×8 + A3×4 + A2×2 + A1 ]
```

At the transistor level, a LUT6 is a balanced binary tree of 63 pass-transistor 2:1 multiplexers, with 64 SRAM cells at the leaves. The signal propagates through 6 levels of multiplexer from leaf to output. Every possible 6-input Boolean function has the same propagation delay through this structure — the INIT content affects which output value emerges, not how long it takes.

**Implication:** This constant-delay property is fundamental to why FPGA timing analysis is tractable. Every LUT6 in the design has the same timing model regardless of the function it implements. In contrast, standard-cell ASIC timing models vary per gate type (NAND2 vs. NOR4 vs. XOR2 have different delays). The FPGA's uniformity makes STA (Static Timing Analysis) much simpler.

**Fractured LUT operation (LUT6 as dual LUT5):**

The same 64-bit SRAM can serve two independent 5-input functions simultaneously. Input A6 is not used as a data input in fractured mode — instead it serves as a path-select signal. The lower 32 bits implement one function on inputs A1–A5 (output O5), and the upper 32 bits implement another function on the same inputs A1–A5 (output O6).

Constraint: **both functions must share the same 5 inputs (A1–A5).** If two logic functions require different input sets, they cannot share a fractured LUT, and Vivado must use two separate LUT sites.

**Why this matters for timing:**

The O5 and O6 outputs of a fractured LUT connect to different downstream BELs within the slice. O5 connects to the lower flip-flop and to F7MUX; O6 connects to the upper flip-flop and to the main fabric routing. When Vivado packs two unrelated signals into a fractured LUT, their routing paths inside the slice may add unexpected hold-time differences. In timing-critical paths, forcing a signal through a fractured LUT occasionally introduces hold violations that are difficult to diagnose without examining the implemented primitive in the device view.

**INIT parameter encoding:**

The INIT is specified as a hex string of 2^N/4 hex digits for a LUTN:

```systemverilog
// LUT2 INIT encoding:
//   Bit 3: O when I1=1, I0=1
//   Bit 2: O when I1=1, I0=0
//   Bit 1: O when I1=0, I0=1
//   Bit 0: O when I1=0, I0=0
//
// XOR: output = I0 ^ I1 → truth table: 0110 → INIT = 4'h6
LUT2 #(.INIT(4'h6)) xor2 (.O(out), .I0(a), .I1(b));

// XNOR: output = ~(I0 ^ I1) → truth table: 1001 → INIT = 4'h9
LUT2 #(.INIT(4'h9)) xnor2 (.O(out), .I0(a), .I1(b));

// LUT6 6-input AND: only all-ones input → 1
// Bit 63 of INIT = 1, all others 0 → INIT = 64'h8000000000000000
LUT6 #(.INIT(64'h8000000000000000)) and6 (
    .O(out), .I0(a), .I1(b), .I2(c), .I3(d), .I4(e), .I5(f)
);
```

**Decoding an INIT from the schematic:**

Vivado's schematic view displays each LUT's INIT value in hex. To reverse-engineer the function:
1. Convert the hex INIT to binary (64 bits for LUT6).
2. For each input combination (0 to 63), the output is the bit at that index.
3. The Boolean expression can be extracted by finding all minterms (indices where the bit is 1).

This is how bitstream reverse engineering tools recover the logic netlist from an unencrypted bitstream — each LUT's INIT value is stored in a defined set of configuration frame bits.

---

### 3.2 MUXF7 and MUXF8

**Hardwired multiplexer hierarchy:**

Within each slice, there is a hardwired 2:1 multiplexer (MUXF7) that combines the O6 outputs of two adjacent LUTs (LUT positions A and B in the slice), controlled by a third signal routed on a dedicated internal wire (not the general INT fabric). Above it, an MUXF8 combines two MUXF7 outputs.

This creates a three-level hierarchy for function extension:
- **LUT6 alone:** any 6-input function
- **LUT6 + MUXF7:** any 7-input function (at the cost of two LUTs + one MUXF7)
- **LUT6 + MUXF7 + MUXF8:** any 8-input function (at the cost of four LUTs + two MUXF7s + one MUXF8)

**Why this matters for wide multiplexers:**

A 256:1 mux with 8-bit select built from standard LUT fabric would require many logic levels and extensive routing through INT tiles. Using the MUXF7/F8 hierarchy, sections of the mux are computed inside slices using internal wiring — bypassing the INT routing matrix entirely for the selection signal. This reduces both latency and routing congestion.

Vivado infers MUXF7/F8 automatically from wide `case` statements and conditional expressions. Direct instantiation is needed only in hand-optimized netlists or when Vivado's inference produces suboptimal packing.

```systemverilog
// Vivado automatically infers MUXF7 from this 7-input expression:
assign y = sel[6] ? f(a[5:0]) : g(a[5:0]);

// Direct instantiation (rarely needed — Vivado inference is reliable):
MUXF7 mux7 (
    .O  (result),
    .I0 (lut_a_out),  // LUT A output (sel=0)
    .I1 (lut_b_out),  // LUT B output (sel=1)
    .S  (select)
);
```

---

### 3.3 CARRY4 — Carry Chain Architecture

**Silicon implementation:**

The CARRY4 primitive implements 4 bits of carry-propagate-generate logic in hardwired silicon wiring — the carry signals are not routed through PIPs (Programmable Interconnect Points) but through a dedicated carry chain that runs strictly North (increasing Y coordinate) through adjacent CLB rows.

**Gate-level semantics:**

```
For each bit position i (0 to 3):
  P[i]  = S[i]            // Propagate signal — from LUT O6 output
  G[i]  = DI[i]           // Generate signal  — from LUT O5 output
  
  O[i]  = P[i] XOR CI[i]  // Sum output
  CO[i] = G[i] OR (P[i] AND CI[i])  // Carry output

  Where CI[0] = CI (external carry-in) or CYINIT
        CI[i] = CO[i-1] for i > 0
```

The LUTs adjacent to a CARRY4 are configured by synthesis to produce the P (propagate) and G (generate) signals. For a binary adder, the LUT computes `P = A XOR B` (on O6) and `G = A AND B` (on O5) — using both outputs of the LUT simultaneously, which is a fractured LUT configuration.

**Chaining constraints:**

A 64-bit adder requires 16 CARRY4 primitives. These must occupy 16 consecutive CLB rows in a **single column** (same X, increasing Y). The physical carry wire has no routing flexibility — it connects CO[3] of one CARRY4 to CI of the next via a hardwired metal connection in the silicon. Any Pblock constraint that prevents vertical stacking will cause Vivado to issue a routing error:

```
[Route 35-39] The following unroutable placement was found ... CARRY4 chain
cannot be routed across a horizontal gap.
```

**Population count example (explicit CARRY4):**

```systemverilog
// 8-bit popcount using CARRY4 chain — a classic example of non-arithmetic CARRY4 use
module popcount8 (
    input  wire [7:0] data,
    output wire [3:0] count
);
    wire [3:0] carry;

    // First stage: sum pairs using LUTs to generate partial sums and carries
    // Then chain with CARRY4 for final accumulation
    // (Full implementation is in UG474 Application Note examples)
endmodule
```

---

## 4. Storage Elements — Flip-Flop Primitives

### 4.1 The FDRE/FDSE/FDCE/FDPE Family

**Physical BEL architecture:**

Each slice contains 8 flip-flop BELs (2 per LUT position: one for the O5 output, one for the O6 output). Every FF BEL is physically identical in silicon — the FDRE/FDSE/FDCE/FDPE distinction is configured by setting bits in the configuration frame that control:
- Whether the reset input is synchronous or asynchronous.
- Whether the reset state is 0 (reset/clear) or 1 (set/preset).
- The initial value (the `INIT` parameter) loaded during configuration.

**Primitive comparison:**

| Primitive | Reset Type | Reset Polarity | Reset State | `INIT` Default |
|---|---|---|---|---|
| `FDRE` | Synchronous | Active-high `R` | `0` | `1'b0` |
| `FDSE` | Synchronous | Active-high `S` | `1` | `1'b1` |
| `FDCE` | Asynchronous | Active-high `CLR` | `0` | `1'b0` |
| `FDPE` | Asynchronous | Active-high `PRE` | `1` | `1'b1` |

**Why synchronous reset (FDRE) is strongly preferred on FPGAs:**

Asynchronous resets (FDCE/FDPE) create a separate reset routing tree. Every FF using async reset must have its CLR/PRE input routed from the reset source — this is a high-fanout signal that may travel long distances. The timing constraint for async reset is the **recovery/removal check** (analogous to setup/hold, but for the reset de-assertion edge relative to the clock edge). If the reset de-assertion is not synchronous with the clock, the recovery/removal check may fail, causing unpredictable behavior during reset release.

Synchronous reset (FDRE) maps the reset condition to the CE and R inputs, keeping all timing analysis within the clock domain. Reset routing is identical to data routing — no special tree required.

**The INIT parameter:**

The `INIT` parameter sets the FF's state immediately after device configuration, before the first clock edge. This is the value the FF holds during the FPGA startup sequence. It differs from the reset value:
- `INIT = 1'b1` means the FF powers up with Q=1 (regardless of whether FDRE or FDSE).
- If `RST` is asserted after configuration, FDRE will clear to 0 regardless of `INIT`.

Use `INIT = 1'b1` when a subsystem should be in an "active" or "enabled" state immediately after power-on, without waiting for the first reset assertion.

```systemverilog
// Standard pipeline register — the most common pattern:
FDRE #(.INIT(1'b0)) pipe_ff (
    .C  (clk),
    .D  (d_in),
    .Q  (q_out),
    .R  (sync_rst),   // synchronous reset — preferred
    .CE (1'b1)        // always enabled — no clock gating
);

// Clock-gated register — CE used for power reduction:
FDRE #(.INIT(1'b0)) gated_ff (
    .C  (clk),
    .D  (d_in),
    .Q  (q_out),
    .R  (sync_rst),
    .CE (data_valid)  // FF only latches when data_valid=1
);
```

**The CE input and power:**

The CE (Clock Enable) input does not gate the clock signal at the FF's clock input. The clock continues to toggle. Instead, CE controls an internal multiplexer that selects between D (new value, CE=1) and Q (current value, CE=0). When CE=0, the FF retains its current value and does not draw dynamic switching power from the data path. The clock tree still dissipates power (the clock input to the FF still toggles).

For gating entire subsystems including their clock tree, use `BUFGCE` (a clock buffer with enable) rather than FF-level CE.

---

## 5. Shift Register Primitives — SRL16E and SRLC32E

### 5.1 Architecture

**SRL as reconfigured LUT:**

In a SliceM, the 64-bit SRAM array of a LUT6 can be reconfigured from a truth-table lookup to a shift register. In SRL mode, the SRAM bits form a shift register of depth 16 (SRL16E) or 32 (SRLC32E). Data is shifted in from DIN on each clock edge. The 4-bit (or 5-bit for 32-deep) address input A selects which tap to read out, making it a programmable delay line.

**SRL16E ports:**

| Port | Description |
|---|---|
| `CLK` | Clock input |
| `CE` | Clock enable |
| `D` | Serial data in |
| `A[3:0]` | Read address (selects tap 0–15) |
| `Q` | Registered output at selected tap |
| `Q15` | Fixed output of the final stage (tap 15) — used for cascading |

**SRLC32E** extends depth to 32 bits and adds `Q31` for cascading two primitives to 64-bit depth.

**Resource efficiency:**

| Implementation | Depth | FFs Used | LUT Sites Used |
|---|---|---|---|
| Plain FFs | 16 | 16 | 0 (uses FF BELs only) |
| SRL16E | 16 | 1 (output reg optional) | 1 SliceM LUT |
| SRLC32E | 32 | 1 | 1 SliceM LUT |

A shift register of depth 32 in a single LUT site (with one FF for the optional output register) versus 32 FF BELs — approximately 32× area improvement.

**Direct instantiation — when and why:**

The primary reason to instantiate SRL primitives directly rather than inferring them is to **set the INIT value**. The `INIT` parameter pre-loads the entire shift register content at configuration time, which is useful for:
- Pre-loading a known delay sequence.
- Implementing a constant coefficient shift-and-add circuit.
- Initializing a PRBS (Pseudorandom Binary Sequence) generator to a known seed.

```systemverilog
// Variable-length delay line (0–15 cycles), tap address set at runtime:
SRLC32E #(.INIT(32'h0)) delay_line (
    .CLK (clk),
    .CE  (1'b1),
    .D   (data_in),
    .A   (delay_count),   // dynamic tap selection
    .Q   (data_out),
    .Q31 ()               // unused cascade output
);

// Cascaded 64-bit shift register:
wire cascade_mid;
SRLC32E #(.INIT(32'h0)) srl_lo (
    .CLK(clk), .CE(1'b1), .D(data_in), .A(5'd31), .Q(), .Q31(cascade_mid)
);
SRLC32E #(.INIT(32'h0)) srl_hi (
    .CLK(clk), .CE(1'b1), .D(cascade_mid), .A(5'd31), .Q(data_out_64), .Q31()
);
```

---

## 6. Block RAM — RAMB18E1 and RAMB36E1

### 6.1 Physical Architecture

**Tile organization:**

The XC7S50 contains 75 RAMB36E1 physical tiles. Each can be configured as:
- One RAMB36E1 (36Kb, True Dual Port or Simple Dual Port)
- Two independent RAMB18E1 (18Kb each), sharing the physical tile but operating independently

Total BRAM capacity: 75 × 36Kb = 2,700Kb = 337.5 KB.

**BRAM cascade placement:**

BRAM tiles occupy dedicated columns in the device floorplan. Like DSP48E1, they have dedicated cascade ports (`CASCADEOUTA`, `CASCADEOUTB`) that connect directly to the adjacent BRAM in the column — bypassing INT routing. This allows wide or deep memory arrays to be built from cascaded BRAMs with no routing delay between tiles.

### 6.2 Port Configurations

**True Dual Port (TDP) mode:**

Both Port A and Port B are fully independent. Each has its own:
- Clock (`CLKA` / `CLKB`)
- Address (`ADDRA` / `ADDRB`)
- Data in/out (`DIA` / `DOA`, `DIB` / `DOB`)
- Write enable (`WEA` / `WEB`)
- Enable (`ENA` / `ENB`)

In TDP mode on RAMB36E1, each port is limited to 18-bit data width (plus 2 parity bits). For 36-bit width, use SDP mode.

**Simple Dual Port (SDP) mode:**

Port A is dedicated write; Port B is dedicated read. This removes the 18-bit width restriction and allows the full 36-bit (plus 4 parity bits) width. Effectively converts the BRAM into a single-clock or dual-clock 36-bit SRAM.

**Asymmetric port widths:**

TDP mode permits each port to have a different data width, as long as both are valid widths (1, 2, 4, 9, 18 for RAMB36E1). This enables patterns like:
- Port A writes 32-bit words; Port B reads individual bytes (4-bit port).
- Port A writes 1-bit serial data; Port B reads 16-bit parallel words.

The address range automatically adjusts — a narrower port has a proportionally larger address space covering the same physical storage.

**Width × Depth configurations (RAMB36E1):**

| Data Width (bits) | Depth (entries) | Parity Bits Included |
|---|---|---|
| 1 | 32,768 | No |
| 2 | 16,384 | No |
| 4 | 8,192 | No |
| 9 | 4,096 | Yes (1 per 8 data bits) |
| 18 | 2,048 | Yes |
| 36 | 1,024 | Yes (SDP mode only) |
| 72 | 512 | Yes (SDP TDP combined) |

### 6.3 Read-Write Collision Behavior

When both ports address the same memory location in the same clock cycle, the behavior is determined by the `WRITE_MODE_A/B` parameter:

**`READ_FIRST`:** The read operation completes first — the old (pre-write) data appears on the read port. The write then commits. This is the safest mode for applications where reads and writes to the same address occur simultaneously and the read result matters.

**`WRITE_FIRST`:** The new (post-write) data immediately appears on the read port of the same port doing the write (write-through behavior). Reads from the other port may see the old value depending on timing. Useful for single-port SRAM-like semantics.

**`NO_CHANGE`:** The read output does not change during a write cycle. The output register holds its previous value. Lowest power consumption — recommended for write-only operations on one port where the read output is irrelevant.

### 6.4 Output Register and Timing

The optional output register (`DOA_REG = 1`) adds a second pipeline stage to the read path:

```
Without output register: CLK → 1 cycle → data at DOA (Fmax limited by BRAM read + output routing)
With output register:    CLK → 2 cycles → data at DOA (Fmax improved; extra latency)
```

The output register is physically inside the BRAM tile, not in fabric. Enabling it increases the achievable Fmax for the memory read path because the critical path is split: the BRAM array access occurs in cycle 1, and the output registers sample the result in cycle 2 with a shorter timing arc to the fabric.

### 6.5 Initialization

BRAM content can be pre-loaded at configuration time using `INIT_xx` parameters (for RAMB18E1: `INIT_00` through `INIT_1F`; for RAMB36E1: `INIT_00` through `INIT_3F`). Each parameter is 256 bits (64 hex digits).

The `INITP_xx` parameters initialize parity bits. For a bootloader or ROM implementation:

```systemverilog
RAMB36E1 #(
    .INIT_00(256'h0000...),   // First 256 bits of content
    .INIT_01(256'h...),
    // ... through INIT_3F
    .WRITE_WIDTH_A(36),
    .READ_WIDTH_B(36),
    .RAM_MODE("SDP"),
    .DOB_REG(0)
) boot_rom (
    .CLKBWRCLK(clk),
    .ADDRARDADDR(14'b0),      // Port A unused (write port in SDP)
    .CLKARDCLK(1'b0),
    .ADDRBRDADDR(addr),       // Port B read address
    .DOBDO(data_out),
    .ENARDEN(1'b0),
    .ENBWREN(1'b1),
    .REGCEAREGCE(1'b1),
    .REGCEB(1'b1),
    .RSTRAMARSTRAM(1'b0),
    .RSTRAMB(1'b0),
    .RSTREGARSTREG(1'b0),
    .RSTREGB(1'b0),
    .WEBWE(8'b0)
);
```

For practical use, Vivado's `$readmemh` synthesis directive is a cleaner alternative for initializing inferred BRAM.

---

## 7. Hardened FIFO — FIFO18E1 and FIFO36E1

### 7.1 Architecture — Why Hardened FIFOs Exist

A FIFO implemented in fabric requires:
1. A dual-port memory (BRAM or distributed RAM).
2. Read and write pointer registers.
3. Full and empty flag logic.
4. For asynchronous (dual-clock) FIFOs: Gray-code encoders for both pointers, two 2-FF synchronizer chains (one in each clock domain), and comparison logic to generate FULL/EMPTY flags.

The gray-code synchronization scheme is non-trivial and error-prone to implement manually. The RAMB36E1 tile contains this entire circuit — pointers, synchronizers, gray coders, and flag generators — in hardened silicon. `FIFO36E1` and `FIFO18E1` expose it as a ready-to-use primitive.

### 7.2 Gray-Code Synchronization Internals

**Why gray code for CDC FIFOs:**

Write and read pointers are multi-bit values. Sending a binary counter value across a clock domain creates a CDC hazard — a counter transition from `0111` to `1000` changes 4 bits simultaneously. Any of those 4 bits may be in a metastable state when sampled by the receiving clock. A 2-FF synchronizer cannot guarantee resolution of all 4 bits within one clock period.

Gray code solves this: the encoding `0100` → `1100` (gray code for 3 → 4) changes exactly 1 bit. A 2-FF synchronizer needs to resolve only one metastable bit per transition — a much weaker requirement.

**The hardened FIFO's pointer scheme:**

```
Write domain:
  wr_ptr_bin (binary counter, incremented on each write)
  wr_ptr_gray = wr_ptr_bin XOR (wr_ptr_bin >> 1)  // binary → gray
  wr_ptr_gray → 2-FF synchronizer → read domain
  
Read domain:
  rd_ptr_bin (binary counter, incremented on each read)
  rd_ptr_gray = rd_ptr_bin XOR (rd_ptr_bin >> 1)
  rd_ptr_gray → 2-FF synchronizer → write domain
  
EMPTY flag (generated in read domain):
  empty = (synced_wr_ptr_gray == rd_ptr_gray)
  
FULL flag (generated in write domain):
  full = (wr_ptr_gray == {~synced_rd_ptr_gray[MSB:MSB-1], synced_rd_ptr_gray[MSB-2:0]})
  // (XOR of top 2 bits with synchronized read pointer, rest equal)
```

This entire logic is instantiated in silicon within the BRAM tile. There is no fabric consumption for the synchronizers, comparators, or gray coders.

**When to use `FIFO36E1` vs. a hand-built FIFO:**

Always use `FIFO36E1` for CDC data transfer unless:
- The FIFO depth or width does not fit (`FIFO36E1` maximum: 512 words × 72 bits, or 32K × 1 bit).
- You need a custom almost-full/almost-empty threshold not supported by the primitive.
- You need simultaneous read and write from the same domain through arbitrary addresses — the FIFO primitive does not support random access.

```systemverilog
// Asynchronous FIFO across two clock domains:
FIFO36E1 #(
    .DATA_WIDTH        (36),         // 32 data + 4 parity
    .FIFO_MODE         ("FIFO36"),
    .FIRST_WORD_FALL_THROUGH("TRUE"), // FWFT: data appears before RD_EN
    .DO_REG            (1),          // output register (adds 1 cycle latency)
    .EN_SYN            ("FALSE"),    // FALSE = async (dual-clock) mode
    .INIT              (72'h0),
    .SRVAL             (72'h0),
    .ALMOST_FULL_OFFSET (13'h80),    // assert AF when 128 from full
    .ALMOST_EMPTY_OFFSET(13'h80)
) async_fifo (
    .WRCLK       (clk_write),
    .WREN        (wr_en),
    .DI          (wr_data),
    .FULL        (fifo_full),
    .ALMOSTFULL  (fifo_almost_full),
    .WRCOUNT     (wr_count),
    .WRERR       (wr_error),

    .RDCLK       (clk_read),
    .RDEN        (rd_en),
    .DO          (rd_data),
    .EMPTY       (fifo_empty),
    .ALMOSTEMPTY (fifo_almost_empty),
    .RDCOUNT     (rd_count),
    .RDERR       (rd_error),

    .RST         (rst),              // async reset — asserted in write domain
    .RSTREG      (1'b0)
);
```

---

## 8. DSP48E1 — Complete Datapath Reference

### 8.1 Physical Architecture

**Tile layout:**

Each DSP48E1 tile is approximately 4× the height of a CLB tile in the physical device view. The tiles form vertical stripes in the device floorplan. On XC7S50, there are 120 DSP48E1 tiles.

**Full datapath:**

```
A[29:0] ──→ [A register (opt)] ──→┐
                                   ├──→ Pre-Adder: AD = D ± A[24:0]  ──→┐
D[24:0] ──→ [D register (opt)] ──→┘                                     │
                                                                          ├──→ Multiplier: M = AD × B (43-bit)
B[17:0] ──→ [B register (opt)] ─────────────────────────────────────────┘
                                                                          
C[47:0] ──→ [C register (opt)] ──→────────────────────────────────────────→┐
                                                                            ├──→ Post-Adder/ALU: P = Z ± (W + X + CIN)
PCIN[47:0] (from previous DSP) ──→ Z selector ───────────────────────────→│
P[47:0] (feedback)              ──→                                         │
                                                                            │
M (from multiplier above)       ──→ X selector ───────────────────────────→│
A:B (concatenated 48-bit)       ──→                                         │
                                                                            ▼
                                                              P[47:0] → [P register (opt)] → PCOUT
                                                              
                                        Pattern Detector: compares P to configurable mask/pattern
                                        → PATTERNDETECT, PATTERNBDETECT outputs
```

### 8.2 Pipeline Registers

Every stage in the DSP datapath has optional input/output registers. Registering intermediate stages allows the DSP to operate at full clock frequency (550+ MHz) by splitting the datapath into balanced pipeline stages.

| Register | Parameter | Latency Added | Typical Use |
|---|---|---|---|
| A input register | `AREG = 1 or 2` | 1 or 2 cycles | High-Fmax designs |
| B input register | `BREG = 1 or 2` | 1 or 2 cycles | High-Fmax designs |
| D input register | `DREG = 1` | 1 cycle | When D path is used |
| AD (pre-adder) register | `ADREG = 1` | 1 cycle | When pre-adder is used |
| M (multiplier) register | `MREG = 1` | 1 cycle | Almost always set in FIR filters |
| C input register | `CREG = 1` | 1 cycle | When C path is used |
| P output register | `PREG = 1` | 1 cycle | Almost always set |

**Latency vs. throughput:**

A fully registered DSP48E1 (all registers enabled) has 3–4 cycles of pipeline latency but can accept a new input every clock cycle. An unregistered DSP48E1 has zero latency but runs at a much lower clock frequency — the combinational path through the multiplier alone is typically 2–3 ns, limiting Fmax to ~350 MHz.

### 8.3 OPMODE and ALUMODE Encoding

`OPMODE[6:0]` selects which values feed the W, X, Y, Z inputs of the post-adder ALU. `ALUMODE[3:0]` selects the ALU operation.

**OPMODE field breakdown:**

```
OPMODE[6:4] — selects Z input:
  000: Z = 0
  001: Z = PCIN
  010: Z = P (accumulate mode)
  011: Z = C
  100: Z = P >> 17 (MACC_EXTEND mode)
  101: Z = PCIN >> 17

OPMODE[3:2] — selects Y input (typically 0 for multiply mode):
  00: Y = 0
  10: Y = 0 (in OPMODE[3:0] = 0101 — multiply mode)
  11: Y = C

OPMODE[1:0] — selects X input:
  00: X = 0
  01: X = M (multiplier output)
  10: X = P (feedback)
  11: X = A:B (48-bit concatenation of A[11:0]:B[17:0])
```

**Common OPMODE configurations:**

| OPMODE | ALUMODE | Operation | Typical Use |
|---|---|---|---|
| `7'b000_00_01` | `4'b0000` | `P = M` | Simple pipelined multiply |
| `7'b010_00_01` | `4'b0000` | `P = P + M` | Running accumulate (MAC) |
| `7'b011_00_01` | `4'b0000` | `P = C + M` | FIR tap: P = coeff_sum + a×b |
| `7'b000_00_11` | `4'b0000` | `P = A:B` | 48-bit load of A:B value |
| `7'b001_00_01` | `4'b0000` | `P = PCIN + M` | Systolic FIR cascade |
| `7'b010_00_11` | `4'b0000` | `P = P + A:B` | Wide accumulator |
| `7'b000_00_00` | `4'b0000` | `P = 0` | Clear accumulator |

### 8.4 Pattern Detector

The pattern detector compares the P register output against two 48-bit constants: `PATTERN` and `MASK`. A bit set in MASK means "ignore this bit in the comparison."

```
PATTERNDETECT  = ((P & ~MASK) == (PATTERN & ~MASK))
PATTERNBDETECT = ((P & ~MASK) == (~PATTERN & ~MASK))
```

**Use cases:**

- **Overflow detection:** Set PATTERN to the maximum value for your fixed-point representation and MASK to the sign bit. PATTERNDETECT fires when the accumulator reaches the maximum.
- **Terminal count:** In a counter implemented as a DSP accumulator, set PATTERN to the terminal count value. PATTERNDETECT signals when the counter reaches its target.
- **Convergent rounding:** PATTERNBDETECT is used in the convergent rounding algorithm to detect "round half to even" cases.

### 8.5 DSP Cascade Chain

The cascade ports (`PCIN → PCOUT`, `ACIN → ACOUT`, `BCIN → BCOUT`) run strictly North in the DSP column — the same directional constraint as CARRY4. A chain of N cascaded DSPs must occupy N consecutive rows in a single DSP column.

**FIR filter systolic array:**

```
Tap 0:  P = coeff[0] × sample[0]       → PCOUT ─→
Tap 1:  P = PCIN + coeff[1] × sample[1] → PCOUT ─→
Tap 2:  P = PCIN + coeff[2] × sample[2] → PCOUT ─→
...
Tap N:  P = PCIN + coeff[N] × sample[N] → result

Each PCIN → PCOUT transition has a fixed 0.1–0.3 ns cell delay
(characterized in the speed file) — no INT routing delay.
```

This zero-routing-overhead cascade is the reason DSP48E1-based FIR filters routinely achieve 500+ MHz on 7-Series devices.

---

## 9. I/O Primitives — Buffers, Delays, and SERDES

### 9.1 IBUF / OBUF / IOBUF

**Physical path:**

Every signal entering or exiting the FPGA must pass through an IOB (I/O Block) tile. The IOB tile contains input buffers (ILOGIC), output buffers (OLOGIC), and programmable delay elements. On Spartan-7, all I/O banks are HR (High Range) — maximum VCCO 3.3V, maximum toggle frequency ~250 MHz for LVCMOS.

`IBUF`, `OBUF`, and `IOBUF` are the software handles to the physical buffer circuits. Vivado auto-inserts them on top-level ports during synthesis. Direct instantiation gives explicit control over:

| Parameter | `IBUF` | `OBUF` | `IOBUF` |
|---|---|---|---|
| `IOSTANDARD` | ✓ | ✓ | ✓ |
| `DRIVE` | — | ✓ (4–24 mA) | ✓ |
| `SLEW` | — | ✓ (SLOW/FAST) | ✓ |
| `IBUF_LOW_PWR` | ✓ | — | ✓ |

**Differential buffers:**

`IBUFDS` and `OBUFDS` implement LVDS, MINI_LVDS, and RSDS differential I/O. On HR banks, there is no on-chip differential termination — a 100Ω external resistor across the differential pair at the receiver is required. Without termination, signal reflections at the unterminated end cause bit errors at high frequencies.

```systemverilog
// LVDS differential input pair:
IBUFDS #(
    .IOSTANDARD ("LVDS"),
    .DIFF_TERM  ("FALSE")  // No on-chip termination on HR banks — must be external
) diff_in (
    .I  (clk_p),   // positive pin
    .IB (clk_n),   // negative pin
    .O  (clk_se)   // single-ended to fabric
);

// LVDS differential output pair:
OBUFDS #(
    .IOSTANDARD ("LVDS"),
    .SLEW       ("SLOW")
) diff_out (
    .I  (data_out),
    .O  (data_p),
    .OB (data_n)
);
```

---

### 9.2 IDELAYE2 — Programmable Input Delay

**Tap resolution and calibration:**

Each IDELAYE2 tap introduces a delay of:

```
tap_delay = 1 / (32 × 2 × F_REFCLK)

At F_REFCLK = 200 MHz:
tap_delay = 1 / (32 × 2 × 200 × 10^6) = 78.125 ps per tap
Max delay  = 31 taps × 78.125 ps = 2.42 ns
```

The formula derives from the IDELAYCTRL calibration mechanism. The IDELAYCTRL monitors the 200 MHz reference clock and continuously adjusts the analog delay circuits in each IDELAYE2 so that 32 taps equals exactly one half-period of the reference (2.5 ns at 200 MHz). This calibration compensates for process, voltage, and temperature (PVT) variation — without IDELAYCTRL, tap delay is uncalibrated and varies by ±40% across PVT corners.

**IDELAYCTRL requirement:**

One `IDELAYCTRL` primitive must be instantiated per I/O bank containing IDELAYE2 instances. It must be clocked at exactly 200 MHz (±10 MHz). Vivado issues DRC error `REQP-1712` if IDELAYE2 is present without a valid IDELAYCTRL.

**IDELAY_TYPE modes:**

| Mode | Description | Use Case |
|---|---|---|
| `"FIXED"` | Delay set at configuration time by `IDELAY_VALUE` | Stable PCB environment, known trace delay |
| `"VARIABLE"` | Delay adjustable at runtime via `CE` and `INC` | Adaptive systems, sweep during calibration |
| `"VAR_LOAD"` | Delay loaded from `CNTVALUEIN` bus | Fast load from a controller |

**Source-synchronous alignment example:**

In a parallel camera interface (e.g., 8-bit parallel at 100 MHz), each data bit arrives at a slightly different time due to PCB trace length mismatch. IDELAYE2 allows per-bit alignment:

```
Bit 0 trace: 3.2 cm → ~220 ps delay → use 3 taps to add ~235 ps to match bit 7
Bit 7 trace: 4.8 cm → ~330 ps delay → reference (no delay added)
→ Result: all 8 bits arrive aligned at the sampling clock edge
```

```systemverilog
// Per-bit IDELAY for parallel interface alignment:
genvar i;
generate
    for (i = 0; i < 8; i++) begin : data_delay
        IDELAYE2 #(
            .IDELAY_TYPE  ("VAR_LOAD"),
            .IDELAY_VALUE (0),
            .REFCLK_FREQUENCY(200.0),
            .DELAY_SRC    ("IDATAIN"),
            .DATA_TYPE    ("DATA")
        ) idelay_i (
            .IDATAIN    (raw_data[i]),
            .DATAOUT    (delayed_data[i]),
            .C          (clk),
            .CE         (1'b0),
            .INC        (1'b0),
            .LD         (load_delay[i]),
            .LDPIPEEN   (1'b0),
            .CNTVALUEIN (delay_value[i]),  // per-bit delay from calibration
            .CNTVALUEOUT(),
            .CINVCTRL   (1'b0),
            .REGRST     (1'b0)
        );
    end
endgenerate

// One IDELAYCTRL per bank — clocked at exactly 200 MHz:
IDELAYCTRL idelayctrl_bank0 (
    .REFCLK (clk_200),
    .RST    (idelayctrl_rst),
    .RDY    (idelayctrl_ready)
);
```

---

### 9.3 ISERDESE2 / OSERDESE2 — High-Speed Serial I/O

**Deserialization architecture:**

`ISERDESE2` captures high-speed serial data from a pad and deserializes it to a wider parallel word at a lower fabric frequency. It operates using two clocks:
- `CLK` — the bit-rate clock (e.g., 400 MHz for 400 Mbps data)
- `CLKDIV` — the word-rate clock = CLK / DATA_WIDTH (e.g., 50 MHz for 8-bit words at 400 MHz bit rate)

Internally, ISERDESE2 contains a chain of flip-flops clocked by both rising and falling edges of `CLK` (in DDR mode), capturing `DATA_WIDTH` bits per `CLKDIV` period.

**DATA_WIDTH and DATA_RATE combinations:**

| DATA_RATE | DATA_WIDTH | Effective Bit Rate |
|---|---|---|
| `"SDR"` | 2, 3, 4, 5, 6, 7, 8 | CLK × 1 |
| `"DDR"` | 4, 6, 8 | CLK × 2 |

For 8-bit DDR mode at CLK = 200 MHz: effective bit rate = 400 Mbps, CLKDIV = 50 MHz.

**BITSLIP alignment:**

The ISERDESE2 receiver does not know which bit in the incoming stream is the first bit of a word boundary. BITSLIP shifts the word alignment by one bit per pulse. A standard calibration procedure:
1. Transmitter sends a known training pattern (e.g., `8'b10110001`).
2. Receiver compares received word to expected pattern.
3. If mismatch, pulse BITSLIP once and check again.
4. Repeat until the received word matches — alignment is found.
5. Lock the alignment and begin normal data reception.

```systemverilog
ISERDESE2 #(
    .DATA_RATE       ("DDR"),
    .DATA_WIDTH      (8),
    .INTERFACE_TYPE  ("NETWORKING"),
    .NUM_CE          (2),
    .IOBDELAY        ("BOTH"),          // delay both clock and data paths
    .DYN_CLKDIV_INV_EN("FALSE"),
    .DYN_CLK_INV_EN  ("FALSE"),
    .OFB_USED        ("FALSE"),
    .SERDES_MODE     ("MASTER")
) iserdes_inst (
    .CLK        (clk_400),              // bit clock
    .CLKB       (~clk_400),             // inverted bit clock (DDR)
    .CLKDIV     (clk_50),              // word clock = CLK/8
    .CLKDIVP    (1'b0),
    .D          (data_from_idelay),     // from IDELAYE2 output
    .DDLY       (1'b0),
    .CE1        (1'b1), .CE2(1'b1),
    .RST        (rst),
    .BITSLIP    (bitslip_pulse),
    .Q1         (q_word[0]),           // Q1 = oldest bit
    .Q2         (q_word[1]),
    .Q3         (q_word[2]),
    .Q4         (q_word[3]),
    .Q5         (q_word[4]),
    .Q6         (q_word[5]),
    .Q7         (q_word[6]),
    .Q8         (q_word[7]),           // Q8 = newest bit
    .O          (),
    .SHIFTOUT1  (), .SHIFTOUT2  (),
    .SHIFTIN1   (1'b0), .SHIFTIN2(1'b0)
);
```

---

## 10. Clocking Primitives — BUFG, BUFR, MMCM, PLL

### 10.1 The Clock Distribution Hierarchy

```
External oscillator → IOB (IBUF/IBUFDS) → BUFG → H-Tree root
                                                      │
                                        ┌─────────────┴──────────────┐
                                  HROW (region 0)              HROW (region 1)
                                        │                            │
                              Clock Spine (N/S)            Clock Spine (N/S)
                                        │                            │
                              FF clock inputs                FF clock inputs
                              (hardwired, not PIPs)
```

**H-Tree skew properties:**

The H-Tree is a balanced binary tree of copper wires physically designed so all leaf nodes (FF clock inputs) have equal electrical path length from the root. On XC7S50, this achieves chip-wide clock skew below ~200 ps. BUFGs are required to drive the H-Tree — routing a clock through the INT fabric would produce skew measured in nanoseconds.

**Maximum active clocks:**

- 32 BUFG primitives available on XC7S50 total.
- Maximum 12 active clocks within any single clock region simultaneously (DRC error `CLOCK-012` if exceeded).
- BUFR is regional and does not count against the global BUFG limit.

### 10.2 BUFGCE — Clock Buffer with Enable

`BUFGCE` (Global Clock Buffer with Clock Enable) is a variant of BUFG with an enable input. When `CE = 0`, the clock output is held low — no transitions reach the flip-flops fed by this buffer.

This is **true clock gating** — unlike FF-level CE which merely prevents the FF from updating, BUFGCE stops the clock signal itself from propagating. The clock tree capacitance in the gated region stops switching, saving both FF dynamic power and the significant clock tree power.

```systemverilog
BUFGCE clk_gate (
    .I  (clk_in),
    .CE (subsystem_active),  // 0 = clock stopped, 1 = clock running
    .O  (clk_gated)
);
```

**Glitch-free requirement:** The CE input must be synchronous with the clock for glitch-free switching. Asserting CE asynchronously may cause a partial clock pulse at the output, which can corrupt flip-flop state. The standard pattern: gate CE with a FF in the domain being gated, ensure CE changes only when the clock output would be low (for active-high clock).

### 10.3 MMCME2 vs. PLLE2 — Choosing the Right Block

Both are clock synthesis blocks (PLL-like), but with different capabilities:

| Feature | `PLLE2_BASE/ADV` | `MMCME2_BASE/ADV` |
|---|---|---|
| Output clocks | 6 (`CLKOUT0–5`) | 7 (`CLKOUT0–6`) |
| Fractional divide | No | Yes (`CLKOUT0` only, 0.125 steps) |
| Dynamic phase shift | No | Yes (`PSEN/PSINCDEC`, ~14 ps steps) |
| Spread spectrum | No | Yes (for EMI reduction) |
| Intrinsic jitter | Lower | Higher (more complex analog circuit) |
| VCO frequency range | 600–1200 MHz | 600–1200 MHz (Spartan-7) |

**When to choose PLL:**

The PLL (`PLLE2`) has lower intrinsic output jitter — typically 50–100 ps RMS less than the MMCM. For applications where clock quality is paramount (ADC sampling clocks, high-speed SERDES reference clocks), prefer PLL. If you need fractional frequency synthesis or dynamic phase shift, MMCM is required.

**VCO frequency constraint:**

Both blocks require the internal VCO to operate between 600 and 1200 MHz (for Spartan-7). This constraint is hard — violating it causes the PLL/MMCM to either fail to lock or produce a noisy, unreliable output.

```
F_VCO = F_IN × (CLKFBOUT_MULT / DIVCLK_DIVIDE)
F_OUTn = F_VCO / CLKOUTn_DIVIDE

Verify: 600 ≤ F_VCO ≤ 1200 MHz
```

**Worked example — 24 MHz crystal input, need 200 MHz, 100 MHz, 48 MHz:**

```
Goal: F_VCO in range, all outputs derivable from it

Try: DIVCLK_DIVIDE = 1, CLKFBOUT_MULT = 50
  F_VCO = 24 × 50 / 1 = 1200 MHz  ✓ (at upper limit)

  CLKOUT0_DIVIDE = 6   → 1200/6  = 200 MHz  ✓
  CLKOUT1_DIVIDE = 12  → 1200/12 = 100 MHz  ✓
  CLKOUT2_DIVIDE = 25  → 1200/25 = 48 MHz   ✓
```

```systemverilog
MMCME2_BASE #(
    .CLKIN1_PERIOD   (41.667),  // 24 MHz → 41.667 ns period
    .CLKFBOUT_MULT_F (50.0),    // VCO = 1200 MHz
    .DIVCLK_DIVIDE   (1),
    .CLKOUT0_DIVIDE_F(6.0),     // 200 MHz
    .CLKOUT1_DIVIDE  (12),      // 100 MHz
    .CLKOUT2_DIVIDE  (25),      // 48 MHz
    .CLKOUT0_PHASE   (0.0),
    .CLKOUT1_PHASE   (0.0),
    .CLKOUT2_PHASE   (0.0)
) mmcm_i (
    .CLKIN1   (clk_24_in),
    .CLKFBIN  (clkfb),
    .CLKFBOUT (clkfb),
    .CLKOUT0  (clk_200_raw),
    .CLKOUT1  (clk_100_raw),
    .CLKOUT2  (clk_48_raw),
    .LOCKED   (pll_locked),
    .PWRDWN   (1'b0),
    .RST      (1'b0)
);

// Buffer all outputs — never use unbuffered MMCM outputs in fabric
BUFG bg0 (.I(clk_200_raw), .O(clk_200));
BUFG bg1 (.I(clk_100_raw), .O(clk_100));
BUFG bg2 (.I(clk_48_raw),  .O(clk_48));
```

**Critical rule:** Assert reset on all logic clocked by MMCM/PLL outputs until `LOCKED` is high. Before lock, the output frequency is undefined — it may be zero, it may be at a partial intermediate frequency, it may be glitching. Any flip-flop that captures data before lock may be in an indeterminate state that is never cleaned up by a reset that arrives after lock.

---

## 11. Configuration and Debug Primitives

### 11.1 ICAPE2 — Internal Configuration Access Port

**Architecture:**

ICAPE2 exposes the full configuration packet interface (described in UG470) to the internal logic fabric. Any operation that can be performed from JTAG or the SelectMAP external configuration interface can also be performed from user logic via ICAPE2: reading device status, loading partial bitstreams, triggering warm boot/multiboot, reading the device DNA, and scrubbing configuration frames.

**The byte-swap requirement:**

ICAPE2 has a byte-ordering quirk relative to the bitstream format. Each 32-bit word written to ICAPE2 must have its bytes swapped compared to the bitstream byte order:

```
Bitstream word (big-endian):  [Byte3][Byte2][Byte1][Byte0]
ICAPE2 word (must provide):   [Byte0][Byte1][Byte2][Byte3]

// Byte-swap function:
function automatic [31:0] bswap32(input [31:0] x);
    return {x[7:0], x[15:8], x[23:16], x[31:24]};
endfunction
```

Failing to byte-swap is the single most common ICAPE2 implementation error. The configuration engine silently misinterprets the command, resulting in CRC errors, failed reconfiguration, or corrupted state without a clear error message.

**IPROG / multiboot sequence:**

To trigger a warm reboot to a different bitstream stored at a different SPI flash offset:

```systemverilog
// Sequence: write WBSTAR (warm boot start address), then write IPROG command
// All words must be byte-swapped relative to UG470 listing

localparam [31:0] SYNC_WORD    = bswap32(32'hAA995566);
localparam [31:0] NOP          = bswap32(32'h20000000);
localparam [31:0] WBSTAR_WRITE = bswap32(32'h30020001); // Type 1 write to WBSTAR reg
localparam [31:0] WBSTAR_ADDR  = bswap32(32'h00400000); // Target bitstream address in flash
localparam [31:0] CMD_WRITE    = bswap32(32'h30008001); // Type 1 write to CMD reg
localparam [31:0] IPROG        = bswap32(32'h0000000F); // IPROG command value
localparam [31:0] DESYNC       = bswap32(32'h0000000D);
```

**Device DNA readback:**

```systemverilog
// The device DNA is a unique 57-bit identifier burned into each device at manufacture
// Read via the DNA_PORT primitive (simpler than ICAPE2 for this specific use):
DNA_PORT #(.SIM_DNA_VALUE(57'h0)) dna_inst (
    .CLK   (clk),
    .DIN   (1'b0),
    .READ  (dna_read),   // pulse high to load
    .SHIFT (dna_shift),  // shift out bits
    .DOUT  (dna_bit)     // serial output
);
```

### 11.2 BSCANE2 — Boundary Scan / JTAG Access

`BSCANE2` allows user logic to tap into the JTAG TAP (Test Access Port) controller. It exposes a user-defined JTAG instruction register that can be accessed from external JTAG equipment.

**Use cases:**
- Custom debug infrastructure — your own logic analyzer accessible over JTAG without consuming ILA resources.
- Manufacturing test — inject test vectors through JTAG into fabric logic.
- Secure communication channel — communicate between an external controller and FPGA logic without using user I/O pins.

**Available user JTAG registers:**

Xilinx reserves USER1 through USER4 JTAG instructions on 7-Series. `BSCANE2` with `JTAG_CHAIN = 1, 2, 3, or 4` maps to USER1–USER4.

```systemverilog
BSCANE2 #(.JTAG_CHAIN(1)) jtag_tap (
    .TCK    (jtag_tck),     // JTAG test clock
    .TDI    (jtag_tdi),     // Data shifting in from JTAG TDI
    .TDO    (jtag_tdo),     // Data shifting out to JTAG TDO
    .TMS    (),
    .SEL    (user1_sel),    // High when USER1 instruction is active
    .DRCK   (user_tck),     // Gated TCK — only toggles during shift
    .SHIFT  (shift_en),     // High during Shift-DR state
    .UPDATE (update_en),    // High during Update-DR state
    .CAPTURE(capture_en),   // High during Capture-DR state
    .RESET  (reset)
);
```

### 11.3 STARTUPE2 — Startup Sequence Control

`STARTUPE2` provides fabric access to the FPGA startup sequencer and several special-purpose pins:

| Port | Description |
|---|---|
| `CFGCLK` | Configuration clock output (frequency = bitstream load clock) |
| `CFGMCLK` | Internal oscillator (~65 MHz, available before user clock) |
| `DONE` | The DONE pin state — asserted after configuration completes |
| `EOS` | End of Startup — asserted when all startup sequence stages complete |
| `PREQ` | Program request from external |
| `USRCCLKO` | Drive the CCLK pin as a user output clock (for SPI flash communication) |

The most important use of `STARTUPE2` on Spartan-7 is driving `USRCCLKO`. The SPI flash clock pin (CCLK) is not accessible as a standard IOB after configuration. To clock an SPI flash at runtime (e.g., for XIP — execute-in-place), `STARTUPE2` must be used to drive CCLK from fabric logic.

```systemverilog
STARTUPE2 #(
    .PROG_USR    ("FALSE"),
    .SIM_CCLK_FREQ(0.0)
) startup_inst (
    .CFGCLK    (),
    .CFGMCLK   (cfgmclk_out),   // ~65 MHz free-running clock
    .EOS       (end_of_startup),
    .PREQ      (),
    .CLK       (1'b0),
    .GSR       (1'b0),
    .GTS       (1'b0),
    .KEYCLEARB (1'b1),
    .PACK      (1'b0),
    .USRCCLKO  (spi_clk),        // drives CCLK pin for SPI flash access
    .USRCCLKTS (1'b0),           // enable USRCCLKO
    .USRDONEO  (1'b1),
    .USRDONETS (1'b1)
);
```

### 11.4 XADC — Dual 12-Bit ADC

The XC7S50 contains a hardened analog-to-digital converter: the XADC (Xilinx Analog-to-Digital Converter). It provides two simultaneous 12-bit, 1 MSPS ADC channels and can connect to up to 17 external analog input pins (on supported packages).

**Built-in measurements (no external pin required):**

| Channel | Measurement |
|---|---|
| Temperature | Die junction temperature (±4°C accuracy) |
| VCCINT | Core supply voltage |
| VCCAUX | Auxiliary supply voltage |
| VCCBRAM | BRAM supply voltage |
| VCCPINT/VCCPAUX | (not applicable to Spartan-7) |

**Use cases:**

- Thermal monitoring — trigger a shutdown or throttle the design clock if junction temperature exceeds a threshold.
- Power supply health monitoring — detect voltage droops during high-activity periods.
- Analog sensor acquisition — connect external sensors (temperature sensors, pressure transducers, current sense amplifiers) directly to FPGA analog pins.

```systemverilog
XADC #(
    .INIT_40(16'h9000),  // Channel sequencer: enable temperature + VCCINT
    .INIT_41(16'h2ef0),  // Enable averaging (256 samples)
    .INIT_42(16'h0400),  // ADCCLK divider: DCLK/4
    .INIT_48(16'h4701),  // Sequencer channel selection
    .INIT_49(16'h000f),  // Sequencer channel enables
    .SIM_DEVICE("7SERIES"),
    .SIM_MONITOR_FILE("design.txt")
) xadc_inst (
    .DI     (16'b0),
    .DO     (xadc_data),
    .DRDY   (xadc_drdy),
    .DCLK   (clk),
    .DADDR  (xadc_addr),
    .DEN    (xadc_den),
    .DWE    (1'b0),
    .RESET  (rst),
    .CONVST (1'b0),
    .CONVSTCLK(1'b0),
    .VP     (vp_pin),    // dedicated VP/VN analog input pair
    .VN     (vn_pin),
    .VAUXP  (vauxp),     // auxiliary analog input pairs
    .VAUXN  (vauxn),
    .ALM    (xadc_alarm),   // alarm outputs: [6]=OT, [5]=VCCAUX, etc.
    .OT     (over_temp),    // over-temperature alarm
    .EOC    (end_of_conv),
    .EOS    (end_of_seq),
    .BUSY   (xadc_busy),
    .CHANNEL(xadc_channel),
    .MUXADDR()
);
```

**Temperature conversion:**

```
Temperature (°C) = (ADC_CODE × 503.975 / 4096) - 273.15

Where ADC_CODE is the 12-bit value read from XADC status register 0x00.
```

---

## 12. Clock Domain Crossing — Theory and Implementation

### 12.1 Physical Cause of Metastability

**The flip-flop as a dynamic system:**

A flip-flop's storage element is a cross-coupled inverter pair — a bistable circuit with two stable equilibria (0 and 1) and one unstable equilibrium at approximately VDD/2. When data arrives at the D input too close to the clock edge (violating setup time), the latch enters the metastable (unstable equilibrium) region.

Once in the metastable state, the circuit diverges from the equilibrium exponentially:

```
V_out(t) = V_meta × e^(t / τ)

Where:
  V_meta = initial deviation from the metastable voltage (≈ VDD/2)
  τ      = time constant of the feedback inverter loop
           On TSMC 28nm: τ ≈ 25–35 ps (from device characterization data)
  t      = time elapsed since the triggering clock edge
```

The flip-flop resolves to a stable value only when V_out exceeds the switching threshold of the downstream logic (~0.3 × VDD for strong-side, ~0.7 × VDD for weak-side input). The probability of still being metastable at time T is:

```
P(metastable at T) = (T_W / T_CLK) × e^(-T / τ)

Where:
  T_W   = metastability window width = setup time + hold time ≈ 60–100 ps
  T_CLK = clock period of the capturing domain
  T     = time elapsed since clock edge = T_CLK - t_setup - t_logic_downstream
```

### 12.2 MTBF Calculation

**Mean Time Between Failures:**

```
MTBF = (T_CLK / (f_data × T_W)) × e^(T_resolve / τ)

Where:
  f_data    = rate of asynchronous data transitions (Hz)
  T_resolve = time available for resolution = T_CLK - t_logic - t_setup_FF2

For XC7S50 -1 speed grade:
  τ ≈ 30 ps   (speed file characterization)
  T_W ≈ 70 ps
  T_CLK = 5 ns (200 MHz capture clock)
  t_logic + t_setup ≈ 1.2 ns (routing + setup of second FF)
  T_resolve = 5 - 1.2 = 3.8 ns
  f_data = 100 MHz
```

```
MTBF = (5×10⁻⁹ / (100×10⁶ × 70×10⁻¹²)) × e^(3.8×10⁻⁹ / 30×10⁻¹²)
     = (5×10⁻⁹ / 7×10⁻⁶) × e^(126.7)
     ≈ 7.14×10⁻⁴ × 5.3×10⁵⁴
     ≈ 3.8×10⁵¹ seconds
     ≈ 1.2×10⁴⁴ years
```

This astronomical MTBF is why a two-FF synchronizer is universally sufficient. Each order of magnitude in `T_resolve / τ` contributes an additional 10 orders of magnitude to MTBF. A third synchronizer FF (rarely needed) adds another ~60 orders of magnitude.

### 12.3 CDC Implementation Patterns

**Pattern 1 — Single-bit synchronizer (the universal primitive):**

```systemverilog
module sync_1bit #(parameter STAGES = 2) (
    input  wire clk_dst,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);
    (* ASYNC_REG = "true" *)
    (* DONT_TOUCH = "true" *)  // prevent retiming across synchronizer
    reg [STAGES-1:0] sync_ff;

    always_ff @(posedge clk_dst or negedge rst_n)
        if (!rst_n) sync_ff <= '0;
        else        sync_ff <= {sync_ff[STAGES-2:0], async_in};

    assign sync_out = sync_ff[STAGES-1];
endmodule
```

**Pattern 2 — Multi-bit CDC via handshake:**

For multi-bit data buses, synchronizing each bit independently causes skew — different bits may be captured in different cycles, giving a corrupt intermediate value. The handshake protocol ensures atomicity:

```systemverilog
// Sender (domain A):
always_ff @(posedge clk_a) begin
    if (send_req && !busy) begin
        data_reg <= data_in;   // latch data
        req_toggle <= ~req_toggle;  // toggle request signal
    end
end

// req_toggle crosses via 2-FF synchronizer to domain B
// Domain B: when synced_req_toggle changes, data_reg is stable and can be sampled
// Sender waits for ack before sending next value

// Key property: data_reg is only written when busy=0 (handshake complete)
// Data is stable for multiple cycles of domain B — no multi-bit metastability
```

**Pattern 3 — Gray-code counter for FIFO pointers:**

```systemverilog
// Write pointer in domain A — use gray encoding
function automatic [N-1:0] bin2gray(input [N-1:0] bin);
    return bin ^ (bin >> 1);
endfunction

always_ff @(posedge clk_a)
    wr_ptr_bin <= wr_ptr_bin + wr_en;

assign wr_ptr_gray = bin2gray(wr_ptr_bin);
// wr_ptr_gray is synchronized to domain B via 2-FF synchronizer
// Only 1 bit changes per increment → metastability affects at most 1 bit
```

**Pattern 4 — Pulse synchronizer:**

For single-cycle pulses, direct 2-FF synchronization may miss short pulses. Convert to level (toggle), synchronize the level, then detect the edge in the destination domain:

```systemverilog
// Source domain: convert pulse to toggle
always_ff @(posedge clk_src)
    if (pulse_in) toggle_src <= ~toggle_src;

// 2-FF synchronize the toggle
sync_1bit sync (.clk_dst(clk_dst), .async_in(toggle_src), .sync_out(toggle_dst));

// Destination domain: detect edge of synchronized toggle = pulse
reg toggle_dst_d;
always_ff @(posedge clk_dst)
    toggle_dst_d <= toggle_dst;

assign pulse_dst = toggle_dst ^ toggle_dst_d;  // XOR = edge detect = pulse
```

### 12.4 `set_false_path` vs. `set_max_delay -datapath_only` for CDC

This is a critical distinction that trips up many designers:

**`set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]`:**
- Tells Vivado to completely ignore setup and hold checks on this path.
- The path is not routed with any timing awareness — it gets whatever routing is left over.
- Vivado makes no effort to minimize the routing delay.
- Correct for paths with a proper synchronizer in place — the synchronizer handles metastability, so the timing of the raw crossing path is irrelevant.

**`set_max_delay -datapath_only -from [src] -to [dst]`:**
- Tells Vivado the path has a maximum delay constraint but the clock period does not apply.
- Vivado routes the path with timing awareness, minimizing routing delay.
- Used when the crossing path delay itself matters — for example, a 3-stage pipeline with a tight budget, or when using a combinational CDC path (rare, advanced use).
- The `-datapath_only` flag removes clock skew from the calculation.

For standard synchronizer-based CDC crossings, `set_false_path` is correct. For any CDC path where routing delay is bounded by design intent, use `set_max_delay -datapath_only`.

---

## 13. Timing Model Internals

### 13.1 Static Timing Analysis — The Path Model

Vivado's STA engine models every timing path as:

```
Data Arrival Time  = launch_clock_edge
                   + clock_source_latency    (MMCM/PLL propagation)
                   + clock_network_latency   (H-Tree to FF clock pin)
                   + cell_delay_sum          (LUT + FF clock-to-Q)
                   + net_delay_sum           (wire RC × routing hops)

Data Required Time = capture_clock_edge
                   + clock_destination_latency
                   + clock_network_latency
                   - setup_time
                   - clock_uncertainty       (jitter + skew margin)

Setup Slack = Data Required Time - Data Arrival Time
  ✓ Positive: timing met
  ✗ Negative: timing violation (hold your design in reset until fixed)

Hold Slack  = Data Arrival Time - (capture_clock_edge + hold_time + clock_uncertainty)
  ✓ Positive: hold met
  ✗ Negative: hold violation (potentially unfixable in hardware — requires design change)
```

### 13.2 Delay Components

**Cell delay (logic delay):**

Each primitive has a characterized delay from each input to each output, at each corner (worst-case slow, best-case fast, nominal). For the XC7S50 -1 speed grade:

| Cell | Input→Output | Typical Delay |
|---|---|---|
| LUT6 | I→O6 | 0.52 ns |
| LUT6 | I→O5 (fract) | 0.53 ns |
| FDRE | C→Q | 0.45 ns |
| FDRE | D setup | 0.07 ns |
| FDRE | D hold | 0.04 ns |
| CARRY4 | CI→CO | 0.10 ns |
| CARRY4 | S→O | 0.26 ns |
| MUXF7 | I→O | 0.24 ns |
| DSP48E1 | A→P (full pipe) | 3× clock periods |
| RAMB36E1 | CLK→DOB | 2.00 ns |

**Net delay (routing delay):**

Net delay is the RC delay of the physical wire route, computed using a lumped RC model (Elmore delay):

```
t_net = 0.69 × R_driver × C_total + Σᵢ (R_segmentᵢ × C_downstreamᵢ)

Where:
  R_driver    = output resistance of the driving cell (~100–500 Ω)
  C_total     = total net capacitance (load pins + wire capacitance)
  R_segmentᵢ  = resistance of each routing segment (~50–200 Ω)
  C_downstreamᵢ = capacitance seen from each branch point to all sinks
```

A critical path with `net_delay >> cell_delay` in `report_timing` indicates a routing congestion problem — the signal is being routed through long segments or many PIP hops because shorter routes are occupied by other nets.

### 13.3 Identifying Timing Violations

**Reading `report_timing_summary`:**

```
WNS (Worst Negative Slack):   Most critical setup violation. Must be ≥ 0.
TNS (Total Negative Slack):   Sum of all negative slacks. Indicates total timing work needed.
WHS (Worst Hold Slack):       Most critical hold violation. Must be ≥ 0.
THS (Total Hold Slack):       Sum of all negative hold slacks.
WPWS (Worst Pulse Width Slack): Clock pulse width vs. min pulse width. Usually not an issue.
```

**Diagnosing the violation source:**

```tcl
# Get the 10 worst setup paths:
report_timing -max_paths 10 -sort_by slack -path_type full_clock_expanded

# For each path, examine the delay breakdown:
#   Logic delay: time in cells (LUTs, FFs, CARRY4)
#   Net delay:   time in routing wires
#
# If (net_delay / total_delay) > 0.7: routing congestion is the issue
# If (logic_levels > 6): too many LUT stages — pipeline or restructure the logic
```

**Common fixes by violation type:**

| Violation | Root Cause | Fix |
|---|---|---|
| Setup — high logic delay | Too many LUT levels | Add pipeline register, recode logic |
| Setup — high net delay | Routing congestion | `(* MAX_FANOUT *)`, Pblock, phys_opt |
| Setup — placement spread | Related cells too far apart | Pblock, `phys_opt_design -directive AggressiveExplore` |
| Hold — short path | Hold path too fast (common after pipelining) | `phys_opt_design` hold fix, or add LUT1 buffer |
| Hold — CDC path | No false path constraint on CDC crossing | `set_false_path` on the crossing |

---

## 14. XDC Constraints — Complete Reference

XDC (Xilinx Design Constraints) is the mechanism for communicating all physical and timing requirements to Vivado. Constraints written in HDL attributes control individual primitives; XDC controls the global timing environment.

**A missing clock constraint is catastrophic:** Without `create_clock`, Vivado has no timing reference. All paths show `0.000` slack — not because timing is met, but because no check is being performed. The design may pass implementation and fail in hardware at any operating frequency.

### 14.1 Clock Constraints

```tcl
# Primary clock on an input port:
create_clock -name clk_sys -period 10.000 -waveform {0.000 5.000} [get_ports CLK_IN]
#   period: clock period in ns (10.000 = 100 MHz)
#   waveform: {rise_time fall_time} — optional, defaults to 50% duty cycle

# Clock on a pin internal to the design (not a port):
create_clock -name clk_recovered -period 8.000 [get_pins cdr_inst/CLK_OUT]

# Generated clock — derived from a primary clock through MMCM:
create_generated_clock \
    -name       clk_200 \
    -source     [get_pins mmcm_inst/CLKIN1] \
    -multiply_by 50 \
    -divide_by   6 \
    [get_pins mmcm_inst/CLKOUT0]
# Note: Vivado auto-creates generated clocks for MMCM outputs when
# create_clock is on the MMCM input. Explicit create_generated_clock is
# needed only when auto-creation names are wrong or the clock is unusual.

# Virtual clock for I/O constraints (no physical source):
create_clock -name virt_clk -period 10.000
```

**Verify all clocks are constrained:**

```tcl
report_clock_networks   # Shows clock topology and which clocks are constrained
report_cdc              # Reports all clock domain crossings and their status
```

### 14.2 I/O Timing Constraints

**Setup and hold requirements for source-synchronous interfaces:**

```tcl
# Input delay: data is launched by the same board-level clock as the FPGA capture
# max: worst-case data arrives this late after the clock edge
# min: best-case data arrives this early after the clock edge
set_input_delay -clock clk_sys -max 2.500 [get_ports DATA_IN[*]]
set_input_delay -clock clk_sys -min 0.800 [get_ports DATA_IN[*]]

# For DDR inputs (data valid on both clock edges):
set_input_delay -clock clk_sys -max  1.200  -rise          [get_ports DDR_DATA[*]]
set_input_delay -clock clk_sys -max  1.200  -fall          [get_ports DDR_DATA[*]]
set_input_delay -clock clk_sys -min  0.300  -rise          [get_ports DDR_DATA[*]]
set_input_delay -clock clk_sys -min  0.300  -fall          [get_ports DDR_DATA[*]]

# Output delay:
set_output_delay -clock clk_sys -max 1.500 [get_ports DATA_OUT[*]]
set_output_delay -clock clk_sys -min -0.500 [get_ports DATA_OUT[*]]
# Negative min output delay = hold requirement on the receiving device is negative
# (data can change before the clock edge at the receiver)
```

**Without I/O constraints:** Vivado cannot check PCB-level timing. Ports are `UNCONSTRAINED` in `report_timing_summary` — the design may work at room temperature on your specific board but fail across production units, temperature extremes, or after PCB respins.

### 14.3 False Path and Multicycle Constraints

```tcl
# False path: CDC crossings with synchronizers
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]

# False path: static control signals never change during operation
set_false_path -from [get_cells config_reg*]

# False path: asynchronous reset assertion timing is not critical
# (reset de-assertion MUST be synchronous — only asserting is false path)
set_false_path -to [get_pins {*/PRE */CLR}]

# Multicycle path: registered path that intentionally takes 2 cycles
set_multicycle_path -setup 2 -from [get_cells stage1*] -to [get_cells stage2*]
set_multicycle_path -hold  1 -from [get_cells stage1*] -to [get_cells stage2*]
# Hold must always be (setup_cycles - 1) to compensate for the relaxed setup check
```

**Warning on `set_false_path` misuse:** This constraint silences timing analysis entirely on the specified path. If applied to a path that is actually timing-critical (e.g., a CDC path without a proper synchronizer), Vivado will not warn about metastability. The design may work in simulation and fail unpredictably in hardware. Apply only after verifying the path is either irrelevant to function or properly handled.

### 14.4 Physical Constraints — I/O Standards and Pin Assignment

```tcl
# Assign a signal to a specific physical pin:
set_property PACKAGE_PIN T10 [get_ports CLK_IN]

# Set I/O standard for a port:
set_property IOSTANDARD LVCMOS33 [get_ports CLK_IN]

# Drive strength and slew rate (output ports only):
set_property DRIVE     8    [get_ports DATA_OUT[*]]
set_property SLEW      SLOW [get_ports DATA_OUT[*]]

# Pull-up / pull-down resistors:
set_property PULLUP    true [get_ports SDA]
set_property PULLDOWN  true [get_ports nCS]

# Input hysteresis (Schmitt trigger — for noisy inputs):
set_property HYSTERESIS SCHMITT_TRIGGER [get_ports SENSOR_IN]
```

**VCCO matching requirement:** All pins in the same I/O bank must use the same VCCO voltage. Assigning LVCMOS33 (requires 3.3V VCCO) and LVCMOS18 (requires 1.8V VCCO) to ports in the same bank is a DRC error (`BIVC-1`) and will damage the device if the constraint is bypassed.

### 14.5 Pblock Constraints

```tcl
# Create and populate a placement block:
create_pblock pb_fft
add_cells_to_pblock [get_pblocks pb_fft] [get_cells u_fft_inst]

# Size the Pblock — include all resource types the module uses:
resize_pblock [get_pblocks pb_fft] -add {SLICE_X0Y0:SLICE_X15Y49}
resize_pblock [get_pblocks pb_fft] -add {DSP48_X0Y0:DSP48_X0Y9}
resize_pblock [get_pblocks pb_fft] -add {RAMB36_X0Y0:RAMB36_X0Y4}

# Contain routing within the Pblock boundary:
set_property CONTAIN_ROUTING true [get_pblocks pb_fft]

# For Partial Reconfiguration — snap to clock region boundaries:
set_property SNAPPING_MODE ON [get_pblocks pb_fft]
```

---

## 15. Power Architecture and Clock Gating

### 15.1 Power Supply Sequencing

The XC7S50 requires three supply voltages:

| Rail | Voltage | Powers |
|---|---|---|
| VCCINT | 1.0V | Core fabric (LUTs, FFs, routing PIPs, BRAM, DSP) |
| VCCAUX | 1.8V | Analog circuits (MMCM, PLL, XADC, configuration) |
| VCCO | 1.2–3.3V | I/O bank output drivers (one supply per bank) |
| VCCBRAM | 1.0V | BRAM array (can share with VCCINT) |

**Required power-on sequence:**

1. VCCAUX first (or simultaneous with VCCINT)
2. VCCINT and VCCBRAM (simultaneous)
3. VCCO banks (after VCCINT is stable)

VCCINT before VCCAUX risks locking the configuration logic in an indeterminate state. Violating this sequence may prevent configuration from completing or corrupt internal state.

### 15.2 Dynamic Power Model

```
P_dynamic = α × C_L × V² × f

Where:
  α   = activity factor (0 to 1 — fraction of cycles where node switches)
  C_L = load capacitance (routing wire + fanout input capacitances)
  V   = supply voltage (1.0V for VCCINT resources)
  f   = clock frequency
```

**Dominant power consumers:**

- **Clock tree:** The H-Tree and all clock spines switch every cycle (α = 1). Total clock tree capacitance is substantial — gating the clock (BUFGCE) for idle subsystems saves significant power.
- **LUT glitching:** LUT outputs may glitch (toggle to incorrect intermediate values) during input transitions before settling to the final value. Each glitch is a full VCCINT swing on the net capacitance — wasted power. Wide combinational trees with many logic levels produce more glitching than short paths.
- **Routing PIPs:** Each PIP is an SRAM-controlled pass transistor. Active nets toggle the capacitance of all connected wire segments. High-fanout nets have high capacitance — one toggle dissipates energy on the entire net.

### 15.3 Clock Gating Strategies

**Level 1 — FF Clock Enable (CE input):**

The CE input gates data sampling at the FF level. The clock continues to toggle; CE=0 forces the FF to re-latch its current value. Saves ~FF_dynamic × (1 - duty_cycle) power. Does not save clock tree power.

**Level 2 — BUFGCE (true clock gating):**

Stops the clock signal from propagating to the gated region. Saves FF dynamic power plus clock tree power in the gated region. On large idle subsystems, this can reduce power by 60–90%.

```systemverilog
// Glitch-free clock gate pattern:
// CE must be synchronous — use a FF to ensure CE changes when clock is low
always_ff @(posedge clk)
    gate_ff <= subsystem_enable;  // sample enable synchronously

BUFGCE buf_gated (
    .I  (clk),
    .CE (gate_ff),       // synchronously gated CE
    .O  (clk_subsystem)
);
```

**Level 3 — Power domain shutdown (advanced):**

For VCCO banks that are entirely unused (no I/O activity expected for extended periods), the output drivers can be tristated in bulk using Vivado power constraints. Not applicable to VCCINT — the core fabric cannot be partially powered down on Spartan-7.

---

## 16. Quick Reference Decision Trees

### Synthesis Attribute Decision Tree

```
I need to preserve a signal:
  → Just keep in schematic/reports?      → (* KEEP = "true" *)
  → Probe on physical board with ILA?    → (* MARK_DEBUG = "true" *)
  → Freeze a module against all changes? → (* DONT_TOUCH = "true" *)

I need to prevent register merging:
  → TMR, fanout copies, or isolation?    → (* EQUIVALENT_REGISTER_REMOVAL = "no" *)

I need to control memory mapping:
  → Large, registered read (≥256 deep)   → (* RAM_STYLE = "block" *)
  → Small, async read (<64 deep)         → (* RAM_STYLE = "distributed" *)
  → Tiny, fully predictable timing       → (* RAM_STYLE = "registers" *)

I need to control DSP usage:
  → Force to DSP48E1 (critical path)     → (* USE_DSP = "yes" *)
  → Keep in fabric (save DSPs)           → (* USE_DSP = "no" *)
  → Two narrow operations, one DSP       → (* USE_DSP = "simd" *)

I need to control FSM encoding:
  → Fast, few states (<32)               → (* FSM_ENCODING = "one_hot" *)
  → States cross clock domain            → (* FSM_ENCODING = "gray" *)
  → Many states (>32), FF-limited        → (* FSM_ENCODING = "sequential" *)
  → Optimizer is mangling my FSM         → (* FSM_ENCODING = "none" *)

I am crossing clock domains:
  → Apply to catching FFs in dest domain → (* ASYNC_REG = "true" *)

I have a high-fanout signal:
  → Replicate to cap load per driver     → (* MAX_FANOUT = N *)

I have a pipeline shift register:
  → Need per-stage tap access?
    → Yes                                → (* SHREG_EXTRACT = "no" *)
    → No (SRL is fine)                   → (leave inference enabled)

I need fast I/O timing:
  → Force FF into IOB tile               → (* IOB = "true" *)
```

### Primitive Selection Tree

```
LOGIC:
  Any Boolean function ≤6 inputs    → LUT6 (inferred from RTL)
  7–8 input function                → LUT6 + MUXF7/F8 (auto-inferred from wide case)
  Arithmetic / comparison           → CARRY4 (inferred from +, -, >, <)

REGISTERS:
  Standard register, sync reset     → FDRE (inferred from always_ff + if/reset)
  Standard register, sync set       → FDSE
  Async reset required              → FDCE (use sparingly — see Section 4.1)
  Async preset required             → FDPE

SHIFT REGISTERS:
  Delay line, single tap out        → SRLC32E (inferred, or (* SHREG_EXTRACT *) to prevent)
  Delay line, per-stage access      → FDRE chain + (* SHREG_EXTRACT = "no" *)

MEMORY:
  ≥256 deep, registered read        → RAMB36E1 or RAMB18E1 (via RAM_STYLE = "block")
  <64 deep, zero-latency read       → Distributed RAM (via RAM_STYLE = "distributed")
  Tiny array, any port              → Registers (via RAM_STYLE = "registers")
  CDC FIFO                          → FIFO36E1 (hardened, always preferred over fabric FIFO)

MATH:
  Multiply / MAC on critical path   → DSP48E1 (via USE_DSP = "yes")
  FIR filter                        → DSP48E1 cascade chain (instantiate directly)
  Wide counter / accumulator        → DSP48E1 with OPMODE bypass

CLOCKING:
  Generate / multiply a clock       → MMCME2_BASE (lower jitter: PLLE2_BASE)
  Drive clock to entire device      → BUFG
  Gate clock to a subsystem         → BUFGCE
  Drive clock within one region     → BUFR (+ integer divide)
  Switch between two clocks         → BUFGMUX_CTRL

I/O:
  Standard input/output             → IBUF / OBUF (auto-inserted)
  Bidirectional (I²C, SPI half-duplex) → IOBUF
  Differential (LVDS)               → IBUFDS / OBUFDS
  Align data to clock               → IDELAYE2 + IDELAYCTRL
  High-speed serial capture         → ISERDESE2
  High-speed serial transmit        → OSERDESE2

CONFIGURATION:
  Load partial bitstream at runtime → ICAPE2
  Drive SPI flash clock (CCLK)      → STARTUPE2
  Custom JTAG debug port            → BSCANE2
  Read die temperature / voltage    → XADC
```

### Timing Violation Response Tree

```
report_timing_summary shows negative WNS (setup violation):

  net_delay >> cell_delay?
    → Yes: routing congestion
           → Apply (* MAX_FANOUT *) to high-fanout drivers
           → Add Pblock to co-locate related logic
           → Run phys_opt_design -directive AggressiveExplore
    → No: logic depth problem
           → count logic levels in path (report_timing -path_type full)
           → If >6 LUT levels: add pipeline register to break the path
           → Recode the combinational logic to reduce fan-in

  Violation only appears after route_design?
    → Placement too spread out
           → Pblock to force related logic together
           → DONT_TOUCH on already-closed sub-blocks to stabilize placement

report_timing_summary shows negative WHS (hold violation):

  On a CDC path?
    → Missing set_false_path constraint
           → Add set_false_path for the crossing
  On a local path?
    → phys_opt_design will insert LUT1 delay buffers automatically
    → In synthesis: avoid (* SHREG_EXTRACT = "no" *) on paths already meeting hold
```

---

## References

- **UG470** — 7 Series FPGAs Configuration User Guide
- **UG471** — 7 Series FPGAs SelectIO Resources User Guide
- **UG472** — 7 Series FPGAs Clocking Resources User Guide
- **UG474** — 7 Series FPGAs Configurable Logic Block User Guide
- **UG479** — 7 Series FPGAs DSP48E1 Slice User Guide
- **UG480** — 7 Series FPGAs XADC Dual 12-Bit ADC User Guide
- **UG901** — Vivado Design Suite User Guide: Synthesis
- **UG949** — UltraFast Design Methodology Guide (applicable to 7-Series)
- **UG953** — 7 Series FPGAs Libraries Guide
- **DS180** — 7 Series FPGAs Data Sheet: Overview
- **Rose, J. et al. (1990):** "Architecture of Programmable Gate Arrays: The Effect of Logic Block Functionality on Area Efficiency" — IEEE JSSC
- **McMurchie, L. and Ebeling, C. (1995):** "PathFinder: A Negotiation-Based Performance-Driven Router for Lookup Table-Based FPGAs" — FPGA '95
- **Project X-Ray / F4PGA:** https://github.com/f4pga/prjxray — 7-Series bitstream reverse engineering database
