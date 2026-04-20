# XC7S50 Exhaustive Practitioner Reference
### A Research-Grade Architectural, Topological, and Theoretical Guide

> **Scope:** This document targets the intersection of hardware architecture, digital design theory, Vivado toolchain internals, and domain-specific applications including bitstream reverse engineering, neuromorphic computing, and partial reconfiguration. It is intended as a living reference for practitioners operating at or beyond the boundary of standard FPGA engineering practice.

---

## Table of Contents

1. [Top-Level Resource Inventory](#1-top-level-resource-inventory)
2. [Logic Resources — CLB Tiles, Slices, and BELs](#2-logic-resources--clb-tiles-slices-and-bels)
3. [Memory & Math — Hard IP Blocks](#3-memory--math--hard-ip-blocks)
4. [The Routing Fabric — INT and IOB Tiles](#4-the-routing-fabric--int-and-iob-tiles)
5. [Topological Layout & Design Implications](#5-topological-layout--design-implications)
6. [Advanced Hard IP & Clock Generation](#6-advanced-hard-ip--clock-generation)
7. [Bitstream & Configuration Layer](#7-bitstream--configuration-layer)
8. [Timing Model & Constraints](#8-timing-model--constraints)
9. [Power Architecture](#9-power-architecture)
10. [I/O Subsystem In Depth](#10-io-subsystem-in-depth)
11. [Vivado Compilation Pipeline Internals](#11-vivado-compilation-pipeline-internals)
12. [Debugging Primitives](#12-debugging-primitives)
13. [Theoretical Foundations](#13-theoretical-foundations)
14. [Domain Applications](#14-domain-applications)
15. [Complete Resource Summary](#15-complete-resource-summary)

---

## 1. Top-Level Resource Inventory

| Parameter | Value |
|---|---|
| I/O Banks | 5 High-Range (HR) |
| Pins per Bank | 50 |
| Total User I/O | 250 |
| Clock Regions | 6 (arranged 2 columns × 3 rows) |
| Device Family | Spartan-7 (7-series architecture) |
| Process Node | TSMC 28nm HPL (High Performance Low Power) |
| Configuration Memory | SRAM-based (volatile; requires external flash or on-board config) |

### 1.1 Clock Region Topology

The 6 clock regions are arranged in a 2×3 grid (2 columns of CLB tiles wide, 3 rows tall). Each clock region:
- Spans exactly one HROW (Horizontal Clock Row) boundary at its vertical midpoint.
- Contains its own set of BUFR, BUFIO, and BUFMR primitives for regional clock distribution.
- Is fed from the global clock H-Tree via a Clock Spine that runs vertically through the region.
- Can support up to 12 global clocks simultaneously (from the global BUFG pool).

**Implication:** Logic that must share a fast, low-skew clock must reside within the same clock region, or be driven by a global BUFG. Crossing clock regions with a regional clock (BUFR) is illegal and will cause a DRC error in Vivado.

---

## 2. Logic Resources — CLB Tiles, Slices, and BELs

### 2.1 CLB Tile Structure

- **CLB Tiles:** 4,075 total physical locations across the die.
- **Slices per CLB:** 2 (one CLB = one SliceL + one SliceM, or two SliceL, depending on column).
- **Total Slices:** 8,150

### 2.2 Slice Variants

| Variant | Count | Capabilities |
|---|---|---|
| SliceL | 5,750 | Combinational logic, ROM (LUT as ROM), F7/F8 muxes, CARRY4 |
| SliceM | 2,400 | All SliceL features + Distributed RAM (64-bit) + SRL16/SRL32 |

**SliceM placement ratio:** 2,400 / 8,150 ≈ 29.4% of all slices are SliceM. Vivado will automatically map Distributed RAM and shift register primitives to SliceM locations. If your design instantiates more Distributed RAM than available SliceM tiles can support, synthesis will fail with a resource overflow error.

### 2.3 BELs Per Slice (Basic Elements of Logic)

Each Slice contains the following BELs:

| BEL | Count per Slice | Total (8,150 Slices) | Notes |
|---|---|---|---|
| LUT6 | 4 | 32,600 | 6-input, 64-bit truth table |
| Flip-Flop | 8 | 65,200 | 2 FFs per LUT output (O5 FF + O6 FF) |
| CARRY4 | 1 | 8,150 | Hardwired carry chain |
| F7MUX | 2 | 16,300 | Combines outputs of 2 LUTs |
| F8MUX | 1 | 8,150 | Combines outputs of 2 F7MUXes |
| SRL16/SRL32 | 4 | 32,600 | SliceM only; LUTs repurposed as shift registers |
| DRAM (64-bit) | 1 | 2,400 | SliceM only; LUTs repurposed as RAM |

### 2.4 LUT6 Internal Architecture

A LUT6 is physically a **64-bit SRAM array** with a 6-bit address bus. The address inputs are the 6 logic inputs (A1–A6). The output is the bit addressed by the input vector.

```
Inputs A[6:1] → 6-bit address → 64-bit SRAM[address] → Output O6
```

**Fractured LUT operation (LUT6 as dual LUT5):**

The same 64-bit SRAM can be partitioned into two independent 32-bit halves. When fractured:
- **O5 output:** Addresses the lower 32 bits using inputs A[5:1] (A6 ignored for this output).
- **O6 output:** Addresses the full 64 bits using A[6:1], but in fractured mode is configured to implement a second independent 5-input function using inputs A[5:1].

This works because any 5-input Boolean function requires only 32 truth-table entries. Two unrelated 5-input functions can coexist in a single LUT6 as long as they share the same 5 inputs (A1–A5). If they require different inputs entirely, fracturing is impossible and Vivado must use two separate LUT sites.

**Implication for packing:** Vivado's mapper aggressively attempts LUT fracturing to improve density. In timing-critical paths, forcing a signal through a fractured LUT may introduce additional routing delay because the O5 and O6 outputs connect to different downstream BELs within the slice. This can be the source of subtle, hard-to-diagnose hold-time violations.

### 2.5 CARRY4 Chain Mechanics

The CARRY4 primitive implements a 4-bit carry-propagate-generate chain in dedicated silicon:

```
For each bit i:
  S[i]  = P[i] XOR CIN[i]        (Sum output)
  CO[i] = G[i] OR (P[i] AND CI[i]) (Carry output)

Where:
  P[i] = propagate = LUT O6 output (configured as XOR of two inputs)
  G[i] = generate  = LUT O5 output (configured as AND of two inputs)
```

The carry output `CO[3]` of one CARRY4 connects to `CIN` of the next CARRY4 **strictly in the North direction** — hardwired silicon routing, not a PIP. This means:
- A 64-bit adder requires 16 CARRY4 primitives stacked in 16 consecutive CLB rows.
- The entire chain must occupy a single column of CLBs (same X coordinate, increasing Y).
- **A horizontal span constraint on a carry chain is physically impossible.** Vivado will issue a routing error if you attempt it.

### 2.6 F7 and F8 Multiplexers

These are hardwired 2:1 multiplexers that extend the effective LUT input count:

- **F7MUX:** Selects between the O6 outputs of two adjacent LUTs (LUT A and LUT B within a slice), controlled by a third signal. Implements a 7-input function (6 inputs to each LUT + 1 select).
- **F8MUX:** Selects between the outputs of two F7MUXes, controlled by a fourth signal. Implements an 8-input function.

**Use case:** Large multiplexers in control logic. A 256:1 mux built from F7/F8 chains uses far fewer routing resources than one built from standard LUT logic because the mux selection travels on dedicated hardwired paths within the slice, bypassing the INT tile entirely.

---

## 3. Memory & Math — Hard IP Blocks

### 3.1 Block RAM (BRAM) — RAMB36E1

- **Count:** 75 RAMB36E1 tiles
- **Capacity per tile:** 36 Kb (36,864 bits) of true dual-port SRAM
- **Splittable:** Each RAMB36E1 can be configured as 2× independent RAMB18E1 (18 Kb each)
- **Total effective sites:** 150 × 18 Kb sites
- **Total capacity:** 2,700 Kb = 337.5 KB

**RAMB36E1 port configurations (width × depth):**

| Data Width | Depth | Parity Bits Included |
|---|---|---|
| 1 | 32K | No |
| 2 | 16K | No |
| 4 | 8K | No |
| 9 | 4K | Yes (1 parity per 8 data) |
| 18 | 2K | Yes |
| 36 | 1K | Yes |
| 72 | 512 | Yes (True Dual Port only) |

**True Dual Port (TDP) vs. Simple Dual Port (SDP):**
- **TDP:** Two fully independent ports (Port A, Port B), each with its own address, data, enable, and clock. Both ports can simultaneously read and write to any address. Width per port is limited to 18 bits for RAMB36E1 in TDP mode.
- **SDP:** Port A is dedicated write, Port B is dedicated read. This unlocks the full 36-bit (or 72-bit with parity) width per operation, effectively treating the BRAM as a single 36-bit-wide memory.

**Read-Before-Write vs. Write-First collision behavior:**
When both ports access the same address simultaneously, the behavior is configurable:
- `READ_FIRST`: The old data is read out before the new data is written. Safe but slower apparent write latency.
- `WRITE_FIRST`: The newly written data is immediately forwarded to the output. Creates a transparent write behavior.
- `NO_CHANGE`: Output register holds its previous value during a write. Lowest power, useful for write-only operations.

### 3.2 Hardened BRAM FIFO

The RAMB36E1 contains dedicated FIFO control logic etched in silicon:

**FIFO primitives available:**
- `FIFO36E1`: Full 36-bit wide, 512-deep (or other configurations) synchronous or asynchronous FIFO.
- `FIFO18E1`: 18-bit wide variant.

**Asynchronous (dual-clock) FIFO internals:**

The hardened async FIFO uses a **Gray-code pointer synchronization scheme** to safely cross the read/write pointer values between clock domains:

1. Write pointer increments in the write clock domain, encoded as Gray code.
2. The Gray-coded write pointer is synchronized into the read clock domain using a 2-FF synchronizer chain.
3. The read-domain logic compares the synchronized write pointer to the read pointer to generate the `EMPTY` flag.
4. The same process runs in reverse for the `FULL` flag.

Gray code is used because only 1 bit changes per increment, making it immune to multi-bit metastability during synchronization — a binary counter changing from `0111` to `1000` changes 4 bits simultaneously, any of which could be in a metastable state when sampled by the receiving clock.

**Implication:** This entire Gray-code synchronizer is implemented in hardened silicon within the BRAM tile. Using a FIFO built from SLICEs instead requires manually instantiating the Gray-code logic, the synchronizer chain, and the pointer comparison logic — consuming dozens of LUTs and requiring careful CDC timing constraints. The hardened FIFO is always the correct choice for CDC data transfer.

### 3.3 DSP48E1 — Full Datapath

- **Count:** 120 DSP48E1 tiles
- **Physical dimensions:** Each DSP tile is approximately 4× the height of a CLB tile in the device view, forming unmistakable vertical stripes.

**Complete DSP48E1 pipeline stages:**

```
Stage 0: Input Registers (optional, 1 cycle latency each)
  - A register (30-bit): feeds pre-adder A input
  - B register (18-bit): feeds multiplier B input
  - C register (48-bit): feeds post-adder C input
  - D register (25-bit): feeds pre-adder D input
  - P register (48-bit): output register / accumulator feedback

Stage 1: Pre-Adder
  AD = D ± A[24:0]   (25-bit result)
  (Controlled by INMODE[3:0])

Stage 2: Multiplier
  M = AD × B         (43-bit product, sign-extended)

Stage 3: Post-Adder / ALU
  P = Z ± (W + X + CIN)
  Where:
    X ∈ {0, M, P, A:B concatenated}
    Z ∈ {0, PCIN, P, C, P>>17, PCIN>>17}
  (Controlled by ALUMODE[3:0] and OPMODE[6:0])

Stage 4: Pattern Detector
  Compares P against a configurable 48-bit pattern and mask.
  Used for overflow detection, convergent rounding, and terminal count detection.
```

**OPMODE and ALUMODE encoding (selected common configurations):**

| OPMODE[6:0] | ALUMODE[3:0] | Operation |
|---|---|---|
| 000_0101 | 0000 | P = M + C (MAC) |
| 000_0101 | 0000 | P = P + M (accumulate) |
| 000_0011 | 0000 | P = A:B (48-bit load) |
| 011_0101 | 0000 | P = M + P (running sum) |
| 000_0101 | 0011 | P = -(M + C) |

**DSP cascade chain:**

DSP48E1 tiles have dedicated cascade ports:
- `PCOUT → PCIN`: Passes the 48-bit accumulator output directly to the next DSP in the column without entering the INT routing matrix.
- `ACOUT → ACIN`: Passes the A input (30-bit) downstream.
- `BCOUT → BCIN`: Passes the B input (18-bit) downstream.

This cascade chain runs **strictly in the North direction** (same column, increasing row), mirroring the CARRY4 constraint. A cascaded DSP chain cannot span columns.

**Implication for FIR filters:** A 16-tap FIR filter implemented as a systolic array uses 16 DSP48E1 tiles stacked vertically, with PCOUT→PCIN passing the running sum upward. The entire accumulation occurs without a single signal entering the INT matrix — the result is extremely fast (Fmax often limited by the clock-to-out of the final P register, not routing).

---

## 4. The Routing Fabric — INT and IOB Tiles

### 4.1 INT Tile (Interconnect)

Every functional tile (CLB, BRAM, DSP, IOB) is paired 1:1 with an adjacent INT tile. The INT tile is the switch matrix — it contains **PIPs (Programmable Interconnect Points)**, which are SRAM-controlled pass transistors that connect wire segments.

**INT tile wire segment hierarchy:**

| Segment Type | Reach | Direction | Typical Use |
|---|---|---|---|
| Direct | 1 tile (neighbor) | N, S, E, W | Local feedback, FF→LUT |
| Double | 2 tiles | N, S, E, W | Short connections |
| Quad | 4 tiles | N, S, E, W | Medium-distance routing |
| Long | 12+ tiles | H, V | Cross-chip signals |
| Global | Full chip | H-Tree | Clock distribution only |

**PIP types:**
- **Single-driver PIPs:** A wire segment is driven by exactly one source. This is the standard case.
- **Bidirectional PIPs:** Some older 7-series wire segments are bidirectional — enabling them connects two wire segments, and either can drive. Vivado's router avoids bidirectional PIPs when possible due to contention risk.

**Routing congestion mechanics:**

Wire segments are a finite resource. Each INT tile has a fixed number of wire tracks per direction. When more signals need to cross a tile than there are wire segments, the router must detour — using Quad or Long segments instead of Direct or Double. Each hop through a higher-level segment adds:
- **Additional routing delay** (RC delay of the longer wire)
- **Additional PIP delay** (each pass transistor adds ~50–100 ps)

A timing violation caused by routing congestion manifests as a path where the **net delay** (time in wires) far exceeds the **logic delay** (time in LUTs/FFs). In Vivado's timing report, this appears as `net delay >> cell delay`.

### 4.2 IOB Tile

250 IOB tiles (one per pin). Each IOB contains:

| Primitive | Function |
|---|---|
| ILOGIC | Input path: captures incoming data, synchronizes it to fabric clock |
| OLOGIC | Output path: registers outgoing data, drives the pad |
| IDELAY | Programmable input delay: 32 taps × ~78 ps/tap = ~2.5 ns max delay |
| ODELAY | Programmable output delay (requires IDELAYCTRL) |
| IBUF / OBUF | Input/output buffers — required on all I/O paths |
| IOBUF | Bidirectional buffer for tristate I/O |

---

## 5. Topological Layout & Design Implications

### 5.1 Carry Chain Direction

Hardwired South-to-North (bottom-to-top, increasing Y coordinate).

- A 64-bit adder = 16 CARRY4 = 16 CLB rows in a single column.
- Placement constraints must allow vertical stacking. Horizontal Pblock constraints that prevent this will fail routing.

### 5.2 Fractured LUTs

Single LUT6 → dual LUT5 via O5/O6 outputs. Vivado enables this automatically during mapping. In congested designs, fracturing unrelated logic into the same LUT can hurt timing by forcing unrelated signals to share placement.

### 5.3 BRAM and DSP Cascade

Dedicated vertical cascade paths bypass the INT matrix entirely. BRAM stacking (for wide or deep memories) and DSP chaining (for FIR filters, matrix multiply) should always exploit these paths. The cascade delay is specified in the device speed files as a fixed cell delay — typically 0.1–0.3 ns — independent of routing.

### 5.4 INT Routing Hierarchy

Direct → Quad → Long, with increasing delay per hop. Timing violations caused by routing detours are distinguishable from logic-delay violations by inspecting the `ROUTE_THRU` and net delay components in Vivado's timing report (`report_timing -path_type full_clock_expanded`).

### 5.5 Clock H-Tree

The H-Tree is a balanced binary tree of copper wires, physically laid out so that every leaf node (the input of a BUFG or Clock Spine) has equal path length from the root. This ensures **clock skew** (the variation in clock arrival time between different flip-flops) remains below ~50 ps across the entire die.

**Clock distribution hierarchy on XC7S50:**
1. External clock pin → IBUF → BUFG (or MMCM → BUFG)
2. BUFG drives the H-Tree root
3. H-Tree branches to HROW (Horizontal Clock Row) at the center of each clock region
4. HROW feeds vertical Clock Spines running N and S through each column
5. Clock Spines feed individual flip-flop clock inputs via hardwired clock connections (not PIPs)

**Maximum global clocks:** 32 BUFG primitives available on XC7S50, but only 12 can be active within any single clock region simultaneously. Exceeding 12 active clocks in one region is a Vivado DRC error (`CLOCK-012`).

---

## 6. Advanced Hard IP & Clock Generation

### 6.1 Clock Management Tiles (CMTs) — MMCMs and PLLs

**Count:** 5 MMCMs + 5 PLLs

**PLL architecture:**

A PLL is a second-order feedback control system:

```
REF_CLK → Phase Detector → Loop Filter → VCO → Output Divider → OUT_CLK
                 ↑                                      |
                 └──────────── Feedback Divider ─────────┘
```

- **Phase Detector:** Compares the phase of REF_CLK to the feedback clock. Outputs a voltage proportional to phase error.
- **Loop Filter:** Low-pass filter that averages the phase error voltage. The bandwidth of this filter determines lock time and jitter peaking.
- **VCO:** Voltage-Controlled Oscillator. On 7-series, the VCO must run between **600 MHz and 1600 MHz** (for Spartan-7). This is a hard constraint.
- **Output Divider (CLKOUT_DIVIDE):** Divides the VCO frequency to produce the output clock. Range: 1–128.
- **Feedback Divider (DIVCLK_DIVIDE, CLKFBOUT_MULT):** Sets the multiplication factor.

**Frequency synthesis formula:**

```
F_VCO = F_IN × (CLKFBOUT_MULT / DIVCLK_DIVIDE)
F_OUT = F_VCO / CLKOUT_DIVIDE

Constraints:
  600 MHz ≤ F_VCO ≤ 1600 MHz  (Spartan-7 speed grade dependent)
  F_IN after DIVCLK_DIVIDE must be between 19 MHz and 800 MHz
```

**Example:** F_IN = 24 MHz, desired F_OUT = 200 MHz
```
Choose: DIVCLK_DIVIDE = 1, CLKFBOUT_MULT = 50, CLKOUT_DIVIDE = 6
F_VCO = 24 × (50 / 1) = 1200 MHz  ✓ (within 600–1600)
F_OUT = 1200 / 6 = 200 MHz  ✓
```

**MMCM additional capabilities over PLL:**

| Feature | PLL | MMCM |
|---|---|---|
| Fractional divide (CLKOUT_DIVIDE_F) | No | Yes (0.125 steps) |
| Phase shift (dynamic) | No | Yes (~10 ps steps via PSCLK) |
| Spread-spectrum (BANDWIDTH) | No | Yes |
| Number of output clocks | 6 | 7 |
| Fine phase shift input | No | PSEN/PSINCDEC/PSDONE |

**Phase shift mechanics (MMCM):**

The MMCM supports dynamic phase shifting via the PSEN interface. Each pulse on PSINCDEC/PSEN shifts the output phase by one VCO tap (~1/56th of the VCO period). For a 1200 MHz VCO, one tap ≈ 1000/1200/56 ≈ **14.9 ps**. This allows real-time alignment of clocks without reconfiguration — critical for source-synchronous interfaces.

**Jitter types:**

- **Period jitter:** Cycle-to-cycle variation in clock period. Measured in ps RMS.
- **Phase jitter:** Accumulated phase deviation over time. Measured in ps RMS.
- **Deterministic jitter:** Fixed, repeatable jitter from known sources (power supply noise, EMI).
- **Random jitter:** Gaussian-distributed thermal noise floor.

Total jitter = Deterministic jitter + k × Random jitter (where k is a multiplier based on BER target).

The PLL has lower intrinsic jitter than the MMCM because it has a simpler analog circuit. For designs where output clock jitter is the primary concern (e.g., ADC sampling clocks), prefer PLL over MMCM when fractional divide and dynamic phase shift are not needed.

### 6.2 Hardened FIFOs — Full Analysis

See Section 3.2 for the complete Gray-code synchronization derivation and FIFO primitive configurations.

### 6.3 Internal Configuration Access Port (ICAP)

See Section 7 for the full ICAP, configuration frame structure, and Partial Reconfiguration analysis.

### 6.4 DSP48E1 Pre-Adder

See Section 3.3 for the full DSP datapath including pre-adder, OPMODE/ALUMODE encoding, and cascade analysis.

---

## 7. Bitstream & Configuration Layer

### 7.1 Configuration Memory Architecture

The XC7S50 is an **SRAM-based FPGA**. Its configuration is volatile — it is lost on power-down. The configuration defines:
- The truth tables of all LUT6 BELs (64 bits each)
- The routing PIP states (each PIP is 1 SRAM bit)
- The initialization values of all flip-flops and BRAMs
- The control registers of all hard IP blocks (MMCM multiply ratios, IOB standards, etc.)

**Configuration memory organization:**

The configuration memory is organized as a **frame-based array**:
- The fundamental unit of configuration is a **Configuration Frame**.
- Each frame is **101 32-bit words** = 3,232 bits wide.
- Frames are addressed by a **Frame Address Register (FAR)** with the following fields:

```
FAR[31:0]:
  Bits [31:23] = Reserved (0)
  Bits [22:20] = Block Type (0=CLB/IOB, 1=BRAM content, 2=BRAM config)
  Bits [19]    = Top/Bottom half (0=top, 1=bottom)
  Bits [18:15] = Row address
  Bits [14:7]  = Column address (major address)
  Bits [6:0]   = Frame offset (minor address, within the column)
```

**Column types and frame counts:**

Each tile column has a fixed number of configuration frames (minor addresses):

| Column Type | Frames per Column |
|---|---|
| CLB (SliceL/SliceM) | 36 |
| BRAM (config) | 28 |
| BRAM (data/init) | 128 |
| DSP | 28 |
| IOB | 42 |
| Clock (CMT) | 30 |
| INT | Part of adjacent functional tile |

**Total frame count for XC7S50:** Approximately 3,655 frames (varies by column composition). Each frame = 3,232 bits. Total configuration bits ≈ 11.8 Mb.

### 7.2 Configuration Packets — The Bitstream Format

A Xilinx bitstream is not raw frame data. It is a **sequence of configuration packets** preceded by sync and header words. The packet protocol:

**Bitstream structure:**

```
1. Dummy word:          0xFFFFFFFF (×8, for bus width detection)
2. Sync word:           0xAA995566 (marks start of valid packet stream)
3. Bus width detect:    0x000000BB, 0x11220044 sequence
4. Packet sequence:     Series of Type 1 and Type 2 packets
5. Desync word:         0x0000000D (RCRC command, then DESYNC)
```

**Type 1 packet format:**

```
Bits [31:29] = 001 (Header type = 1)
Bits [28:27] = Opcode (00=NOP, 01=Read, 10=Write, 11=Reserved)
Bits [26:13] = Register address (which configuration register to access)
Bits [12:11] = Reserved
Bits [10:0]  = Word count (number of 32-bit words following this header)
```

**Type 2 packet format:**

```
Bits [31:29] = 010 (Header type = 2)
Bits [28:27] = Opcode
Bits [26:0]  = Word count (larger word count for bulk frame writes)
```

Type 2 packets always follow a Type 1 packet to the same register and extend the word count beyond what a Type 1 can specify (Type 1 max = 2047 words; Type 2 max = 2^27 words).

**Key configuration registers (selected):**

| Register | Address | Function |
|---|---|---|
| CRC | 0x00 | Cyclic Redundancy Check |
| FAR | 0x01 | Frame Address Register |
| FDRI | 0x02 | Frame Data Register Input (write frames) |
| FDRO | 0x03 | Frame Data Register Output (readback) |
| CMD | 0x04 | Command register (WCFG, RCFG, GCAPTURE, etc.) |
| CTRL0 | 0x05 | Control register (encryption enable, readback security) |
| MASK | 0x06 | Mask for CTRL0 writes |
| STAT | 0x07 | Status register (EOS, CRC error, DCI match, etc.) |
| IDCODE | 0x0C | Device IDCODE (must match target device) |

**IDCODE for XC7S50:** `0x362D093` (verify against UG470 Table 5-5 for speed grade variant).

### 7.3 CRC Checking

Every bitstream write sequence includes CRC validation. The CRC polynomial used is **CRC-32 (IEEE 802.3)**:

```
G(x) = x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1
```

The CRC is computed over all packet data written since the last CRC reset. At the end of a frame write sequence, a `WCFG` followed by a `CRC` register write causes the FPGA to verify the computed CRC against the expected value embedded in the bitstream. A mismatch sets the `CRC_ERROR` bit in the STAT register and aborts configuration.

**Implication for bitstream patching:** Any modification to a bitstream (e.g., changing a LUT truth table for reverse engineering or weight injection) requires recalculating and rewriting the CRC fields throughout the bitstream. Tools like `xc3sprog` and the `prjxray` utilities handle this automatically. Manual patching without CRC recalculation will result in a configuration failure.

### 7.4 Readback and Scrubbing

**Readback** allows the current configuration state to be read back through the JTAG interface or ICAP:

1. Issue `GCAPTURE` command: Latches the current state of all flip-flops and LUT RAM into the configuration memory shadow registers.
2. Set FAR to starting frame address.
3. Issue `RCFG` command.
4. Read FDRO register: Returns frame data word by word.

**Configuration scrubbing** is used in radiation-hardened designs (aerospace, high-altitude) to detect and correct **SEUs (Single Event Upsets)** — bit flips in configuration SRAM caused by cosmic ray particles.

Scrubbing procedure:
1. Periodically read back the configuration frames.
2. Compare against a known-good golden bitstream stored in external flash.
3. If a mismatch is detected (SEU), rewrite the corrupted frame.

This can be done externally (via JTAG, by a processor) or internally (via ICAP) for autonomous self-repair.

### 7.5 Bitstream Security

The XC7S50 supports bitstream encryption and authentication:

**Encryption:** AES-256-CBC
- The bitstream is encrypted using a 256-bit key stored in the device's battery-backed BBRAM or eFUSE (one-time programmable) array.
- The FPGA's configuration engine decrypts the bitstream on-the-fly during loading.
- **BBRAM key:** Volatile. Lost on power-down or battery removal. Can be re-programmed.
- **eFUSE key:** Non-volatile, permanent. One-time write. Cannot be changed or erased.

**Authentication:** HMAC-SHA-256
- An HMAC is computed over the bitstream data using a secret key.
- Prevents bitstream tampering even by parties who cannot decrypt the content.

**Readback protection:**
- Setting `CTRL0[6:5]` (Security bits) in the bitstream disables readback via JTAG.
- Level 1: Disables configuration readback.
- Level 2: Disables all JTAG access (including boundary scan). **This is permanent if set via eFUSE.**

**Implication for reverse engineering:** An encrypted XC7S50 bitstream is not directly analyzable without the AES key. However, side-channel attacks (power analysis, EM analysis during decryption) have been demonstrated against 7-series devices in academic literature. Unencrypted bitstreams are fully analyzable using Project X-Ray's frame-to-tile mapping database.

### 7.6 ICAP — Internal Configuration Access Port

The ICAP primitive exposes the full configuration packet interface to the internal logic fabric:

```verilog
ICAPE2 #(
  .DEVICE_ID(32'h362D093),  // XC7S50 IDCODE
  .ICAP_WIDTH("X32"),        // 32-bit interface
  .SIM_CFG_FILE_NAME("NONE")
) icap_inst (
  .CLK(clk),
  .CE(ce_n),      // Active low chip enable
  .CSIB(csib),    // Active low chip select
  .RDWRB(rdwrb),  // 1=Read, 0=Write
  .I(din[31:0]),  // Data input (write)
  .O(dout[31:0])  // Data output (read/status)
);
```

**Critical implementation note — byte swapping:**

The ICAP interface has a **byte-swap quirk** relative to the SelectMAP configuration interface. Each 32-bit word written to ICAP must have its bytes swapped relative to the bitstream byte order:

```
Bitstream word (big-endian): [B3][B2][B1][B0]
ICAP word (little-endian):   [B0][B1][B2][B3]
```

Failure to byte-swap is the single most common ICAP implementation error. The configuration engine will silently misinterpret commands, causing corrupt configuration or a CRC error.

**Partial Reconfiguration via ICAP:**

1. Vivado generates a **partial bitstream** (`.bit` file) covering only the Reconfigurable Partition.
2. The partial bitstream is stored in an accessible memory (BRAM, external flash via SPI/AXI).
3. The static logic (always-on) streams the partial bitstream word-by-word into ICAP.
4. The FPGA's configuration engine writes only the frames corresponding to the reconfigurable region, leaving all other frames untouched.
5. The reconfigurable partition's logic is atomically replaced. The static logic continues running throughout.

**Partial bitstream generation in Vivado:**
- Requires defining `RECONFIGURABLE_MODULE` properties in the XDC.
- The `PR_VERIFY` tool checks that the partial bitstream is compatible with the static design's partition pins.
- Partition pins must be registered (FF-based) — combinational logic crossing a PR boundary is illegal.

---

## 8. Timing Model & Constraints

### 8.1 The Static Timing Analysis Model

Vivado performs **Static Timing Analysis (STA)** — it analyzes all timing paths in the design without simulation, using a graph-based model of delays.

**Path types:**
- **Setup (max) path:** Data must arrive at the destination FF's D input *before* the capturing clock edge minus setup time.
- **Hold (min) path:** Data must remain stable at D for a minimum time *after* the capturing clock edge.

**Slack definition:**

```
For a setup (max) path:
  Data Arrival Time   = launch_clock_edge + clock_source_latency
                      + clock_path_delay + logic_delay + net_delay

  Data Required Time  = capture_clock_edge + clock_destination_latency
                      + clock_path_delay - setup_time

  Setup Slack = Data Required Time - Data Arrival Time

  ✓ Positive slack: timing met
  ✗ Negative slack: timing violation (must fix)

For a hold (min) path:
  Hold Slack = Data Arrival Time - (capture_clock_edge + hold_time)
```

**Clock uncertainty:**

Vivado adds a **clock uncertainty** term to account for:
- Clock jitter (from MMCM/PLL output jitter specs)
- Clock skew (from H-Tree imbalance)
- Margin for process/voltage/temperature (PVT) variation

```
Effective setup slack = Raw slack - clock_uncertainty - inter-clock_skew
```

### 8.2 Delay Components

Every path delay has two components:

| Component | Source | Typical Range |
|---|---|---|
| Cell delay | Logic propagation through BEL | 0.1 – 0.6 ns per LUT stage |
| Net delay | Wire RC delay + PIP delay | 0.05 – 3+ ns depending on route |

**Inter-connect delay model:**

Vivado uses a **lumped RC model** for wire delays. Each wire segment has a characterized resistance (R) and capacitance (C). The delay for a wire segment is:

```
t_wire = 0.69 × R × C  (Elmore delay model for RC trees)
```

For a fanout-N net, the total net delay to the worst-case sink is:

```
t_net = R_driver × C_total + Σ(R_segment_i × C_downstream_i)
```

where `C_total` is the total capacitance of the entire net and `C_downstream_i` is the capacitance seen from the i-th branch point to the sink.

### 8.3 XDC Constraints — Complete Reference

#### 8.3.1 Clock Constraints

```tcl
# Define a primary clock on a port or pin
create_clock -name clk_main -period 5.000 -waveform {0.000 2.500} [get_ports CLK_IN]

# Define a generated clock (output of MMCM)
create_generated_clock -name clk_200 \
  -source [get_pins mmcm_inst/CLKIN1] \
  -multiply_by 50 -divide_by 6 \
  [get_pins mmcm_inst/CLKOUT0]

# Virtual clock (for I/O timing constraints, no physical source)
create_clock -name virt_clk -period 10.000
```

**Why a missing clock constraint is catastrophic:**

Without `create_clock`, Vivado has no timing reference for any path. It defaults to a propagated delay analysis with no launch/capture edges defined. This means:
- All setup/hold checks are unconstrained.
- The timing report will show `0.000` slack everywhere — not because timing is met, but because no check is being performed.
- The design may implement fine in simulation and fail in hardware at any clock frequency.

Always verify that `report_clock_networks` shows no unconstrained clocks.

#### 8.3.2 I/O Timing Constraints

```tcl
# Input delay relative to a clock (source-synchronous interface)
# Data is launched by the same clock that the FPGA uses to capture it
set_input_delay -clock clk_main -max 2.000 [get_ports DATA_IN]
set_input_delay -clock clk_main -min 0.500 [get_ports DATA_IN]

# Output delay
set_output_delay -clock clk_main -max 1.500 [get_ports DATA_OUT]
set_output_delay -clock clk_main -min 0.200 [get_ports DATA_OUT]
```

**Without I/O constraints:**

Vivado cannot check whether the PCB-level timing requirements are met. The I/O paths will be marked `UNCONSTRAINED` in `report_timing_summary`. The design may work on your specific PCB at room temperature but fail during production testing or at temperature extremes.

#### 8.3.3 False Path Constraints

```tcl
# Static signals: control registers written at startup, never during operation
set_false_path -from [get_cells config_reg*]

# Asynchronous reset path: reset assertion timing is not critical
set_false_path -to [get_pins */CLR]

# Between two unrelated clock domains (with proper CDC synchronizers in place)
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
```

**Warning:** `set_false_path` tells Vivado to ignore a path entirely. If you apply it to a path that is actually timing-critical (e.g., a CDC path without a synchronizer), Vivado will not warn you about metastability. Use `set_false_path` only when you have manually verified the path is safe.

#### 8.3.4 Multicycle Path Constraints

```tcl
# Data takes 2 clock cycles to propagate (pipelined operation)
set_multicycle_path -setup 2 -from [get_cells stage1_reg*] -to [get_cells stage2_reg*]
# Also relax the hold check (setup N means hold check shifts by N-1)
set_multicycle_path -hold 1 -from [get_cells stage1_reg*] -to [get_cells stage2_reg*]
```

**When to use:** Shared multipliers, time-division-multiplexed datapaths, any case where a computation intentionally takes multiple cycles but is not pipelined at every stage.

#### 8.3.5 Placement Constraints (Pblocks)

```tcl
# Define a Pblock (placement block)
create_pblock pblock_fft
add_cells_to_pblock [get_pblocks pblock_fft] [get_cells fft_inst]
resize_pblock [get_pblocks pblock_fft] -add {SLICE_X0Y0:SLICE_X15Y49}
resize_pblock [get_pblocks pblock_fft] -add {DSP48_X0Y0:DSP48_X0Y19}

# Constrain the Pblock to only use resources inside its boundary
set_property CONTAIN_ROUTING true [get_pblocks pblock_fft]
```

**When to use Pblocks:**
- Partial Reconfiguration: Reconfigurable partitions must have Pblock constraints.
- Congestion relief: Force unrelated logic away from a congested area.
- Timing closure: Force a critical path's cells close together to minimize routing delay.

---

## 9. Power Architecture

### 9.1 Voltage Rails

The XC7S50 requires three separate supply voltages:

| Rail | Voltage | Powers |
|---|---|---|
| VCCINT | 1.0V | Core logic fabric (LUTs, FFs, routing PIPs, DSP, BRAM) |
| VCCO | 1.2V – 3.3V | I/O bank output drivers (per-bank, must match I/O standard) |
| VCCAUX | 1.8V | Auxiliary circuits (MMCM, PLL, configuration logic, XADC) |
| VCCBRAM | 1.0V | BRAM array power (can be shared with VCCINT) |

**VCCO per I/O standard:**

| I/O Standard | VCCO Required |
|---|---|
| LVCMOS33 | 3.3V |
| LVCMOS25 | 2.5V |
| LVCMOS18 | 1.8V |
| LVCMOS15 | 1.5V |
| LVCMOS12 | 1.2V |
| LVDS (HR bank) | 2.5V (recommended) |
| SSTL135 | 1.35V |

**All pins within a single I/O bank must use the same VCCO voltage.** Mixing standards that require different VCCO in the same bank is a DRC error and will damage the device if forced.

### 9.2 Power Consumption Model

Total power = Static (leakage) power + Dynamic (switching) power

```
P_total = P_static + P_dynamic

P_dynamic = α × C_L × V^2 × f

Where:
  α     = Activity factor (fraction of clock cycles where a node switches)
  C_L   = Load capacitance of the net (from routing + fanout)
  V     = Supply voltage
  f     = Clock frequency
```

**Dominant power consumers on XC7S50:**

| Resource | Primary Power Source |
|---|---|
| VCCINT routing | Dynamic: switching PIPs and wire capacitance |
| LUTs | Dynamic: glitching (momentary incorrect outputs during input transitions) |
| Flip-Flops | Dynamic: clock tree capacitance × toggle rate |
| BRAM | Dynamic: read/write access + static leakage |
| MMCM/PLL | Static: analog VCO circuits always draw current when enabled |
| I/O drivers | Dynamic: proportional to output swing × capacitance × frequency |

**Glitching:** LUT outputs can momentarily toggle to incorrect values during the propagation of input changes before settling to the correct output. This is called **glitching** or **hazard switching**. Every glitch is a full VCCINT swing on the net capacitance — wasted dynamic power. High glitch rates occur in wide combinational trees (many logic levels without registers) and can dominate power in datapath-heavy designs.

### 9.3 Clock Gating

The most effective power reduction technique is **clock gating** — preventing a register's clock from toggling when the register's output is not needed.

**Synthesis-inferred clock gating:**

```verilog
// Vivado will infer a clock enable → BUFCE gate
always @(posedge clk) begin
  if (enable)
    data_reg <= data_in;
end
```

Vivado maps the `enable` condition to the **CE (Clock Enable)** input of the flip-flop BEL, not to the clock. The FF's internal clock enable gate (`BUFCE`) prevents the FF from toggling when CE=0, saving the FF's dynamic power. The clock itself still toggles at the FF's clock pin, but the internal storage is gated.

**True clock gating (BUFGCE):**

For gating entire subsystems, use `BUFGCE` — a clock buffer with an enable:

```verilog
BUFGCE bufgce_inst (
  .I(clk_in),
  .CE(subsystem_enable),
  .O(clk_gated)
);
```

This prevents the clock from toggling at all in the gated region, saving both the FF dynamic power and the **clock tree power** (the H-Tree capacitance driving the entire region). For large idle subsystems, this can reduce power by 50–90%.

**Power supply sequencing:**

VCCAUX must be powered before or simultaneously with VCCINT. Powering VCCINT before VCCAUX can cause the configuration logic to enter an indeterminate state. The recommended sequence is:
1. VCCAUX (1.8V)
2. VCCINT (1.0V) and VCCBRAM (1.0V) simultaneously
3. VCCO banks (after VCCINT is stable)

---

## 10. I/O Subsystem In Depth

### 10.1 HR vs HP Banks

The XC7S50 has **only HR (High Range) I/O banks** — it does not have HP (High Performance) banks.

| Feature | HR Banks (XC7S50) | HP Banks (Artix-7/Kintex-7) |
|---|---|---|
| VCCO range | 1.2V – 3.3V | 1.2V – 1.8V |
| Max toggle frequency | ~250 MHz (LVCMOS) | ~600 MHz |
| IDELAY resolution | ~78 ps/tap | ~10 ps/tap |
| LVDS termination | External (no internal Vtt) | Internal (on-chip termination) |
| DDR3 support | No (no DCI termination) | Yes |
| Designed for | General purpose, sensor I/F | High-speed SerDes, memory I/F |

**Implication:** The XC7S50 cannot directly interface with DDR3 memory without external termination resistors and is limited in very high-speed serial interfaces. For designs requiring DDR3, Artix-7 or Kintex-7 (with HP banks) should be used.

### 10.2 IDELAY — Programmable Input Delay

Each IOB input has an `IDELAY` primitive — a programmable delay line:

```
IDELAYE2 #(
  .IDELAY_TYPE("FIXED"),     // FIXED, VARIABLE, VAR_LOAD
  .IDELAY_VALUE(16),         // 0–31 taps
  .HIGH_PERFORMANCE_MODE("TRUE"),
  .SIGNAL_PATTERN("DATA"),   // DATA or CLOCK
  .REFCLK_FREQUENCY(200.0),  // IDELAYCTRL reference clock in MHz
  .CINVCTRL_SEL("FALSE"),
  .PIPE_SEL("FALSE")
) idelay_inst (
  .IDATAIN(data_from_pad),
  .DATAOUT(data_to_fabric),
  .C(clk),
  .CE(1'b0),
  .INC(1'b0),
  .LD(1'b0),
  .LDPIPEEN(1'b0),
  .CNTVALUEIN(5'b0),
  .CINVCTRL(1'b0),
  .REGRST(1'b0)
);

IDELAYCTRL idelayctrl_inst (
  .REFCLK(clk_200mhz),  // Must be exactly 200 MHz ±10 MHz
  .RST(rst),
  .RDY(idelayctrl_rdy)
);
```

**Tap resolution:** Each tap introduces approximately `1/(32 × 2 × F_REFCLK)` delay:
```
tap_delay = 1 / (32 × 2 × 200 MHz) = 78.125 ps/tap
Max delay = 31 × 78.125 ps ≈ 2.42 ns
```

**IDELAYCTRL requirement:** The `IDELAYCTRL` primitive must be instantiated once per I/O bank that uses IDELAY. It must be clocked at exactly 200 MHz (±10 MHz). Without IDELAYCTRL, the IDELAY tap resolution is uncalibrated and the delays are undefined. Vivado will issue DRC error `REQP-1712` if IDELAY is used without a calibrated IDELAYCTRL.

**Use case — source-synchronous data capture:**

In a source-synchronous interface (e.g., camera parallel bus, LVDS sensor), the data and clock are launched by the same source. Due to PCB trace length mismatches, the data may arrive at a different time than the clock. IDELAY allows the designer to add precise delays to individual data pins to align all data bits with the center of the clock eye.

### 10.3 ISERDES — Input Serializer/Deserializer

`ISERDESE2` deserializes high-speed single-ended or differential data from the pad into a wider parallel word at a lower fabric frequency:

```
ISERDESE2 #(
  .DATA_RATE("DDR"),        // SDR or DDR
  .DATA_WIDTH(8),           // 2,3,4,5,6,7,8 (SDR) or 4,6,8 (DDR)
  .INTERFACE_TYPE("NETWORKING"), // NETWORKING, MEMORY, MEMORY_DDR3
  .NUM_CE(2),
  .IOBDELAY("BOTH")
) iserdes_inst (
  .CLK(fast_clk),           // High-speed serial clock (bit clock)
  .CLKB(fast_clk_n),        // Complement (for DDR)
  .CLKDIV(slow_clk),        // Fabric clock (fast_clk / DATA_WIDTH)
  .D(data_from_pad),
  .Q1(q[0]), .Q2(q[1]), .Q3(q[2]), .Q4(q[3]),
  .Q5(q[4]), .Q6(q[5]), .Q7(q[6]), .Q8(q[7]),
  .CE1(1'b1), .CE2(1'b1),
  .RST(rst),
  .BITSLIP(bitslip)
);
```

**Timing example:** 400 Mbps data rate
- Serial clock: 400 MHz
- DATA_WIDTH: 8 (DDR mode, so 4 DDR cycles per word)
- Fabric clock (CLKDIV): 400/8 = 50 MHz
- Result: 8-bit parallel word delivered to fabric at 50 MHz = 400 Mbps effective throughput

**BITSLIP function:** In a received data stream, the receiver doesn't know which bit is the first bit of a word. `BITSLIP` pulses shift the deserialization alignment by one bit position. A training pattern (known sequence like `0xAB`) is transmitted and the receiver pulses `BITSLIP` until the received pattern matches — this is called **bit alignment** and is required for any SERDES interface.

### 10.4 OSERDES — Output Serializer

`OSERDESE2` serializes a parallel word from the fabric to a high-speed serial output:

```
OSERDESE2 #(
  .DATA_RATE_OQ("DDR"),     // SDR or DDR
  .DATA_RATE_TQ("SDR"),     // Tristate rate
  .DATA_WIDTH(8),
  .TRISTATE_WIDTH(1),
  .SERDES_MODE("MASTER")
) oserdes_inst (
  .CLK(fast_clk),
  .CLKDIV(slow_clk),
  .D1(d[0]), .D2(d[1]), .D3(d[2]), .D4(d[3]),
  .D5(d[4]), .D6(d[5]), .D7(d[6]), .D8(d[7]),
  .OQ(data_to_pad),
  .TQ(tristate_to_pad),
  .OCE(1'b1), .TCE(1'b1),
  .RST(rst)
);
```

### 10.5 Differential I/O Standards on HR Banks

The XC7S50 HR banks support differential signaling, but with limitations compared to HP banks:

**Supported differential standards on HR banks:**

| Standard | VCCO | Typical Use |
|---|---|---|
| LVDS | 2.5V | General high-speed diff signaling |
| MINI_LVDS | 2.5V | Lower power LVDS variant |
| RSDS | 2.5V | Reduced swing differential |
| BLVDS | 2.5V | Bus LVDS (multi-drop) |
| LVPECL | 3.3V | Clock distribution from oscillators |

**HR bank LVDS limitation:** HR banks do not have on-chip differential termination (no internal 100Ω termination resistor). An external 100Ω termination resistor must be placed on the PCB across the differential pair at the receiver. Without termination, signal reflections will corrupt the received data.

---

## 11. Vivado Compilation Pipeline Internals

### 11.1 Full Pipeline Stages

```
HDL Source (VHDL/Verilog/SystemVerilog)
    │
    ▼ Elaboration (xelab)
    │  - Parses HDL syntax
    │  - Resolves hierarchy (module/entity instantiation)
    │  - Evaluates generate statements and parameters
    │  - Produces an elaborated netlist (schematic)
    │  - No technology mapping yet — pure behavioral
    │
    ▼ Synthesis (synth_design)
    │  - Technology mapping: maps RTL to 7-series primitives
    │  - LUT inference: Boolean minimization (using ESPRESSO or similar)
    │  - Register retiming (if enabled): moves FFs across logic levels for timing
    │  - Resource sharing: reuses multipliers/adders across multiple operations
    │  - FSM encoding: encodes state machines (binary, one-hot, Gray, etc.)
    │  - Produces: synthesized netlist (.dcp checkpoint)
    │
    ▼ opt_design
    │  - Constant propagation: eliminates logic driven by constant values
    │  - Sweep (dead code elimination): removes cells with no downstream fanout
    │  - Remap: re-maps LUT combinations for better packing
    │  - Retarget: replaces cells with more efficient primitives where possible
    │
    ▼ place_design
    │  - Global placement: assigns every cell to a physical site (X,Y coordinate)
    │  - Analytical placement: minimizes estimated wirelength (quadratic model)
    │  - Timing-driven refinement: moves cells to minimize estimated slack violations
    │  - Legalization: ensures no two cells occupy the same physical site
    │
    ▼ phys_opt_design (optional but recommended)
    │  - Post-placement physical optimization
    │  - Replication: copies high-fanout cells to reduce net delay
    │  - Retiming: moves pipeline registers to balance delays
    │  - Hold fixing: adds delay buffers on paths with hold violations
    │
    ▼ route_design
    │  - Global routing: assigns nets to routing channels
    │  - Detailed routing: assigns specific wire segments and PIPs
    │  - Timing-driven: prioritizes critical paths for best routes
    │  - Produces: fully routed design (.dcp checkpoint)
    │
    ▼ write_bitstream
       - Generates configuration frames from placed and routed netlist
       - Computes CRC, applies encryption if enabled
       - Produces: .bit bitstream file
```

### 11.2 Synthesis Deep Dive

**LUT inference — Boolean minimization:**

Vivado's synthesis engine uses a variant of **two-level logic minimization** (related to Quine-McCluskey and ESPRESSO) to reduce a multi-level Boolean expression to its simplest form, then maps it to LUT6 primitives.

For an N-input function where N ≤ 6: maps directly to one LUT6.
For N > 6: decomposes into a tree of LUT6s, possibly using F7/F8 muxes.

**Technology-specific optimization:** Vivado knows the 7-series LUT can implement any 6-input function. It exploits this by:
- Absorbing inverters into LUTs (no extra cell cost).
- Merging XNOR/XOR with adjacent LUT (since XOR is "free" in a LUT).
- Recognizing carry-chain patterns and mapping to CARRY4.
- Recognizing multiplier patterns and mapping to DSP48E1.

**FSM encoding strategies:**

| Encoding | Flip-Flop Count | LUT Cost | Best For |
|---|---|---|---|
| Binary | log₂(N) | High (decoder needed) | Minimum FF usage |
| One-hot | N | Low (direct state decode) | Speed (Vivado default) |
| Gray | log₂(N) | Medium | Low EMI, sequential states |
| Johnson | 2×log₂(N) | Low | Simple hardware counter |

Vivado defaults to one-hot encoding for FSMs with more than 5 states because the state decode logic (combinational next-state logic) is simpler with one-hot, improving Fmax.

### 11.3 Placement as Quadratic Assignment

The placement problem is formally a **Quadratic Assignment Problem (QAP)**:

```
Minimize: Σᵢ Σⱼ f(i,j) × d(π(i), π(j))

Where:
  i, j    = cells to be placed
  f(i,j)  = communication weight (net connections between i and j)
  d(a,b)  = distance between physical sites a and b
  π(i)    = assignment of cell i to a physical site
```

QAP is **NP-hard** (no known polynomial-time exact solution). Vivado uses a **simulated annealing** heuristic for the global placement phase:

1. Start with a random (or seed-based) placement.
2. Propose a random swap of two cells.
3. Compute the change in estimated wirelength (ΔHPWL — Half-Perimeter Wirelength).
4. Accept the swap if ΔHPWL < 0 (improvement).
5. Accept the swap with probability `e^(-ΔHPWL/T)` if ΔHPWL ≥ 0 (allows escaping local minima).
6. Gradually lower temperature T (annealing schedule).
7. Continue until temperature reaches near zero (frozen solution).

**Why placement is non-deterministic:** The simulated annealing uses a pseudo-random number generator seeded by the system clock or a user-specified seed. Different runs can produce different placements and therefore different timing results. Setting `-seed` in `place_design` makes results reproducible.

### 11.4 Routing as Steiner Tree

The routing problem is a variant of the **Steiner Minimum Tree (SMT)** problem on a graph:

- **Nodes:** All source and sink pins of a net, plus legal routing junctions (INT tile wire endpoints).
- **Edges:** Wire segments with associated delay costs.
- **Goal:** Find the minimum-cost tree that connects all pins of each net.

For a multi-pin net (1 source, K sinks), the Steiner tree may include **Steiner points** — intermediate routing nodes that are not source or sink pins but are needed to efficiently branch the route.

SMT is **NP-hard**. Vivado uses a **negotiation-based router** (similar to PathFinder):

1. **Initial routing:** Route each net independently, ignoring resource conflicts. Use a shortest-path algorithm (Dijkstra's) weighted by delay.
2. **Rip-up and reroute:** Identify overused wire segments (where multiple nets share the same physical wire). Penalize those segments.
3. **Iterate:** Reroute nets that used overloaded segments, now avoiding them due to the penalty.
4. **Converge:** Repeat until no wire segment is overloaded (legal routing) and timing is met.

**Timing-driven routing:** Critical paths (paths with small or negative slack) are routed first and given priority access to the best (shortest, least loaded) wire segments. Non-critical paths are routed afterward with remaining resources.

---

## 12. Debugging Primitives

### 12.1 ILA — Integrated Logic Analyzer

The `ILA` (Integrated Logic Analyzer) is a Xilinx debug core that acts as an oscilloscope inside the FPGA fabric. It uses BRAM to capture a window of signal states triggered by a user-defined condition.

**Architecture:**

```
Probe signals (up to 1024 bits wide)
    │
    ▼
Comparator Logic (trigger condition evaluation)
    │
    ├─→ Trigger: starts capture
    │
    ▼
BRAM Capture Buffer (depth: 1K–131K samples, power of 2)
    │
    ▼
AXI-Lite Debug Hub (DBGMCU)
    │
    ▼
JTAG interface → Vivado Hardware Manager
```

**Resource consumption:**

For an ILA with 64 probe bits and 1024-sample depth:
- BRAM: `ceil(64/36) × ceil(1024/depth_per_bram)` ≈ 2 BRAM36 tiles
- LUT/FF: ~100–300 LUTs for trigger logic (depends on trigger complexity)

**Trigger conditions:**

Vivado Hardware Manager supports:
- Value comparison: `signal == 8'hAB`
- Range comparison: `signal > 8'h10 && signal < 8'h80`
- Edge detection: `signal'event` (rising/falling/any edge)
- Counter-based: trigger after N events
- Boolean combinations of the above

**Trigger position:** The capture buffer can be configured to capture N samples before the trigger event (pre-trigger) and M samples after. This allows observing the state of the system leading up to a failure condition.

**Advanced trigger:** For multi-stage triggers (e.g., "trigger state A, then state B, then capture"), ILA supports a **trigger state machine** with up to 16 states.

### 12.2 VIO — Virtual I/O

The `VIO` core allows driving and probing internal fabric signals from Vivado Hardware Manager over JTAG, without needing physical I/O pins:

- **Output probes:** Drive internal signals (like a function generator). Can force a register to a specific value.
- **Input probes:** Read internal signal values. Updates at the JTAG scan rate (~1 kHz, not real-time).

**Resource consumption:** Minimal — a few LUTs and FFs. No BRAM required (VIO does not capture waveforms, only reads/writes current values).

**Typical use cases:**
- Drive a stimulus into a DSP to test computation results.
- Override a configuration register without recompiling.
- Toggle a reset signal interactively.
- Monitor counters, state machine state, error flags.

### 12.3 JTAG TAP Controller

The **JTAG TAP (Test Access Port) Controller** is a standard IEEE 1149.1 state machine that governs all JTAG communication:

```
JTAG State Machine (abbreviated):
  Test-Logic-Reset
    └── Run-Test/Idle
          ├── Select-DR-Scan → Capture-DR → Shift-DR → Update-DR
          └── Select-IR-Scan → Capture-IR → Shift-IR → Update-IR
```

**JTAG interface pins:**
- `TCK` — Test Clock
- `TMS` — Test Mode Select (navigates state machine)
- `TDI` — Test Data In (serial input)
- `TDO` — Test Data Out (serial output)

**Xilinx-specific JTAG instructions:**

| Instruction | IR Value | Function |
|---|---|---|
| BYPASS | 0xFF | Connects TDI→TDO through a 1-bit shift register |
| IDCODE | 0x09 | Reads the 32-bit device IDCODE |
| CFG_IN | 0x05 | Writes configuration data (bitstream loading) |
| CFG_OUT | 0x04 | Reads configuration data (readback) |
| USER1–USER4 | 0x02–0x23 | User-defined JTAG access (for ILA/VIO debug hub) |

**Debug hub communication:**

The ILA and VIO cores communicate with Vivado Hardware Manager through the `JTAG_AXI` or `debug_hub` infrastructure:
1. Vivado Hardware Manager connects to the FPGA via JTAG (using a JTAG cable like the Digilent HS2 or embedded in the Xilinx Platform Cable).
2. It issues a USER1 or USER2 JTAG instruction to access the debug hub's custom DR (data register).
3. The debug hub is an AXI-Lite master that communicates with ILA and VIO cores over an internal AXI fabric.
4. Vivado Hardware Manager reads/writes ILA control registers (trigger configuration, capture depth, arm state) and VIO probe values over this path.

---

## 13. Theoretical Foundations

### 13.1 LUT Theory — Why 6 Inputs?

**The foundational question:** Why does the Xilinx 7-series use LUT6 rather than LUT4 (Virtex-II) or LUT8?

**Area-delay tradeoff model:**

For a logic network implementing a function of N primary inputs using K-input LUTs:
- **Logic levels** (depth): `L(K) ≈ log_K(N)` — decreases as K increases
- **LUT count** (area): Increases as K increases (each LUT is larger)
- **Wire count** (routing): Also increases with K (more inputs per LUT = more wires)

The optimal K balances these factors. Research by Rose et al. (1990) and subsequent studies using empirical MCNC benchmark circuits found that **K=6 minimizes the product of area × delay** for SRAM-based LUT architectures, because:
- Going from K=4 to K=6 reduces circuit depth (fewer logic levels) significantly.
- Going from K=6 to K=8 adds silicon area faster than it reduces depth (diminishing returns).
- K=6 also aligns well with the fracturing optimization (dual LUT5) without wasting area.

**LUT as SRAM — formal derivation:**

A K-input LUT implements the function:

```
f(x₁, x₂, ..., x_K) = M[x_K × 2^(K-1) + ... + x₁ × 2^0]
```

Where M is a 2^K-bit memory (truth table). The LUT is a **multiplexer tree** at the transistor level:

```
For K=2 (LUT2 example):
  M[0], M[1], M[2], M[3] = truth table bits

  Output = M[0]·(¬x₁)·(¬x₂) + M[1]·x₁·(¬x₂) + M[2]·(¬x₁)·x₂ + M[3]·x₁·x₂
         = 2:1MUX(2:1MUX(M[0], M[1], x₁), 2:1MUX(M[2], M[3], x₁), x₂)
```

For K=6: a balanced binary tree of 63 pass-transistor 2:1 multiplexers, with a 64-bit SRAM array at the leaves.

**Why the LUT delay is roughly constant regardless of the function implemented:**

All 2^64 possible 6-input Boolean functions have the same propagation delay through the LUT — the signal travels the same path through the multiplexer tree. The truth table contents (SRAM values) are read at power-on; during operation, only the multiplexer select signals (logic inputs) change. This is fundamentally different from standard cell CMOS logic, where complex gates (NAND with many inputs) are inherently slower than simple inverters.

### 13.2 Place and Route — Complexity Theory

**Placement as QAP:**

The Quadratic Assignment Problem (QAP) was formulated by Koopmans and Beckmann (1957). It is in the complexity class **NP-hard**, meaning:
- No polynomial-time exact algorithm is known.
- Approximation to within a constant factor is also NP-hard for general instances.
- For FPGA placement specifically, the problem is further constrained by BEL compatibility (a DSP cell can only go to a DSP site, etc.).

**Routing as Integer Linear Programming:**

The detailed routing problem can be formulated as an ILP (Integer Linear Programming) problem:

```
Minimize: Σ_e w_e × x_e    (weighted sum of wire usage)

Subject to:
  Σ_{e ∈ path(s,t)} x_e ≥ 1    ∀ nets (s,t)   (connectivity)
  Σ_{nets using e} x_e ≤ capacity_e    ∀ edges e   (capacity)
  x_e ∈ {0, 1}    (integer: either use this wire or not)
```

ILP is NP-complete. The negotiation-based router (PathFinder) is a Lagrangian relaxation heuristic that solves the capacity constraints iteratively.

**Channel routing vs. switchbox routing:**

7-series routing uses a **switchbox** model (INT tiles are switchboxes, not channel routers). In channel routing (older paradigm), wires run in parallel channels between rows of cells. In switchbox routing, each intersection has a programmable connection box that can route signals in any direction. Switchbox routing has higher routing density but requires more complex algorithms.

### 13.3 Clock Domain Crossing — Metastability Theory

**Physical cause of metastability:**

A flip-flop's setup time requirement exists because the cross-coupled inverters of the SRAM cell (the flip-flop storage element) need sufficient time to reach a stable state. If data arrives too close to the clock edge:

```
The FF storage latch is modeled as a first-order dynamic system:
  V_out(t) = V_meta × e^(t/τ)   (exponential divergence from metastable point)

Where:
  V_meta = the metastable voltage (approximately VDD/2)
  τ       = the time constant of the feedback loop (technology-dependent, ~20-50 ps for 28nm)
  t       = time elapsed since the clock edge
```

The flip-flop resolves to a stable value (0 or 1) only when `V_out` exceeds the switching threshold of the downstream logic. The probability that the FF is still metastable at time T after the clock edge is:

```
P(metastable at time T) = (T_W / T_CLK) × e^(-T/τ)

Where:
  T_W   = metastability window (setup + hold time window, ~20-100 ps)
  T_CLK = clock period (e.g., 5 ns for 200 MHz)
  T     = resolution time available (clock period minus logic delay)
  τ     = flip-flop time constant
```

**Mean Time Between Failures (MTBF) for a synchronizer:**

```
MTBF = (T_CLK / (f_data × T_W)) × e^(T_resolve / τ)

Where:
  f_data   = rate of data transitions crossing the boundary (Hz)
  T_resolve = time available for resolution = T_CLK - t_logic - t_setup
```

**Example calculation:**

For XC7S50 in -2 speed grade:
- `τ ≈ 35 ps` (from device characterization data)
- `T_W ≈ 60 ps`
- `T_CLK = 5 ns` (200 MHz)
- `t_logic + t_setup ≈ 1 ns`
- `T_resolve = 5 - 1 = 4 ns`
- `f_data = 100 MHz`

```
MTBF = (5e-9 / (100e6 × 60e-12)) × e^(4e-9 / 35e-12)
     = (5e-9 / 6e-9) × e^(114.3)
     = 0.833 × e^(114.3)
     ≈ 0.833 × 3.5 × 10^49
     ≈ 2.9 × 10^49 seconds
     ≈ 9.2 × 10^41 years
```

This astronomical MTBF is why a **double-synchronizer (two FFs in series)** is universally accepted as sufficient for virtually all practical applications: the second FF gets the full clock period to resolve any metastability that escaped the first FF, and the combined MTBF becomes many orders of magnitude larger than the age of the universe.

**Two-FF synchronizer:**

```verilog
always @(posedge clk_dest) begin
  sync_ff1 <= async_signal;  // First FF: may go metastable
  sync_ff2 <= sync_ff1;      // Second FF: resolves metastability
end
// Use sync_ff2 in destination clock domain
```

**Critical implementation note:** The two FFs of a synchronizer must be placed in the **same slice**, or at minimum in **adjacent slices**. This minimizes the routing delay between them, maximizing `T_resolve` for the second FF. Vivado's `set_false_path -to [get_pins sync_ff1/D]` plus placement constraints enforces this. Never allow Vivado to pipeline the synchronizer across distant logic.

### 13.4 Partial Reconfiguration — Theoretical Constraints

**Partition pin theory:**

A PR boundary is where static logic nets cross into (or out of) a reconfigurable partition. At the boundary, signals must pass through a **Partition Pin** — a defined routing point that is fixed for both the static and reconfigurable implementations.

**Why PR boundaries must be registered:**

During the partial reconfiguration process (while a new partial bitstream is being loaded), the logic inside the reconfigurable partition is in an undefined state — some frames have been updated, others have not. If combinational logic in the reconfigurable region drives static logic directly (without a register at the boundary), the static logic sees undefined glitches throughout the PR process.

A registered (FF-based) boundary means:
- The FF's output is held at its last valid value (by the FF's master latch) while the combinational logic feeding its D input glitches.
- The FF only samples a new value on the next clock edge *after* reconfiguration is complete and the combinational logic has settled.

**Decoupler primitive:**

Before initiating PR, best practice is to:
1. Assert a **decoupler** that drives known values (0 or 1) onto the static logic's inputs from the partition boundary.
2. Load the partial bitstream (PR process).
3. Release the decoupler.
4. Allow the new partial logic to initialize and become valid.

Without decoupling, the static logic may sample invalid data from the partially-reconfigured partition and propagate incorrect state through the system.

---

## 14. Domain Applications

### 14.1 Bitstream Reverse Engineering

#### 14.1.1 Project X-Ray Architecture

**Project X-Ray** (and its successor **Project F4PGA/prjxray**) is an open-source effort that systematically maps every bit in the XC7S50 (and all 7-series) bitstream to its corresponding function (which LUT truth table bit, which routing PIP, which FF initialization value, etc.).

**Methodology — Fuzzing:**

The mapping was generated by a **fuzzing** process:
1. Synthesize a design with a single known element (e.g., one LUT with truth table `0x0000000000000001`).
2. Generate the bitstream.
3. XOR the bitstream against a reference (empty) bitstream to find which bits changed.
4. Record: "These bits at these frame/offset addresses correspond to this LUT6 truth table bit at this tile/BEL location."
5. Repeat systematically for every LUT bit, every PIP, every configuration option.

The result is a **database** (YAML/JSON) mapping:

```
<tile_type>.<site>.<BEL>.<feature> → <FAR>.<word_offset>.<bit_offset>
```

For example:
```yaml
CLBLL_L.SLICEL_X0.A6LUT.INIT[0]: FAR=0x00200000, word=50, bit=12
```

#### 14.1.2 Reading a Bitstream

To extract all LUT truth tables from an unencrypted bitstream:

1. Parse the bitstream packet stream (Section 7.2) to extract all FDRI write sequences.
2. Decode the FAR values to determine which tile column/row each frame belongs to.
3. For each frame, use the X-Ray database to locate the bit positions of each LUT's INIT value.
4. Reconstruct the 64-bit truth table for each LUT6 in the design.
5. Reverse-engineer the Boolean function: `f(A1,...,A6) = INIT[A6×32 + A5×16 + A4×8 + A3×4 + A2×2 + A1]`

**Tools:**
- `xc7frames2bit` / `xc7bit2frames`: Convert between bitstream and frame dump.
- `fasm2frames` / `frames2fasm`: Convert between FASM (FPGA Assembly) and frames.
- **FASM format:** A human-readable representation of every set configuration bit:
  ```
  CLBLL_L_X2Y50.SLICEL_X0.A6LUT.INIT[63]
  CLBLL_L_X2Y50.SLICEL_X0.AUSED
  INT_L_X2Y50.NE2BEG1.NE2END1
  ```

#### 14.1.3 Routing Reconstruction

PIP bits in the bitstream represent the routing. Each PIP bit, when set, connects two specific wire segments in a specific INT tile. The X-Ray database maps each PIP to its frame/bit address:

```yaml
INT_L.NE2BEG1.NE2END1: FAR=..., word=..., bit=...
```

From the set of active PIP bits, the complete routing graph of the implemented design can be reconstructed — effectively recovering the netlist connectivity without access to the original HDL source.

**Use cases:**
- Recovering a design from a bitstream when source code is lost.
- Analyzing competitor IP cores distributed as bitstreams.
- Verifying that a supplied bitstream matches a claimed netlist (supply chain security).
- Academic research into FPGA architecture and reverse engineering defenses.

#### 14.1.4 Weight Injection (Live Bitstream Modification)

For neural network accelerators, **weight injection** modifies the configuration bits corresponding to LUT truth tables (which encode fixed weights) without full reprogramming:

1. Identify which LUT BELs implement weight constants (from synthesis reports or FASM analysis).
2. Compute the new truth table for the modified weight value.
3. Modify the corresponding bits in the bitstream frame.
4. Recalculate the CRC for the modified frames.
5. Write the modified frame(s) via ICAP.

Because only a few frames are modified (one frame per tile column per row), this process is vastly faster than full reprogramming — a single frame write takes microseconds vs. milliseconds for a full bitstream load.

### 14.2 Neural Network and Neuromorphic Mapping

#### 14.2.1 Fixed-Point Quantization and DSP Mapping

Neural network weights and activations are typically represented in floating point (FP32) for training but must be quantized to fixed-point for efficient FPGA implementation.

**Fixed-point representation:**

```
Q-format Q(m.n): m integer bits, n fractional bits, total = m + n + 1 (sign bit)
Value = integer_representation × 2^(-n)

Example: Q(4.11) for 16-bit weights
  Range: -16.0 to +15.99951171875
  Resolution: 2^(-11) ≈ 0.000488
```

**Mapping to DSP48E1:**

The DSP48E1 has a 25×18 multiplier. For Q-format multiplication:
- If weight width ≤ 18 bits and activation width ≤ 25 bits → single DSP48E1
- If weight width ≤ 36 bits and activation width ≤ 25 bits → cascade 2 DSP48E1 (using BCOUT→BCIN)
- If weight width > 36 bits → 3+ DSP48E1 cascade

**Accumulator overflow prevention:**

For a dot product of K terms, each Q(m.n), the accumulator must be at least:
```
Accumulator width ≥ 2 × (m + n + 1) + ceil(log₂(K)) bits
```

The DSP48E1's 48-bit accumulator handles dot products of up to:
```
K ≤ 2^(48 - 2×bitwidth)
For 8-bit weights × 8-bit activations: K ≤ 2^(48-16) = 2^32 ≈ 4 billion terms
For 16-bit × 16-bit: K ≤ 2^(48-32) = 2^16 = 65,536 terms
```

#### 14.2.2 Systolic Array Architecture

A systolic array is a 2D grid of processing elements (PEs) where data flows rhythmically between neighbors. For matrix multiplication C = A × B:

```
PE(i,j) operation per cycle:
  C[i][j] += A[i][k] × B[k][j]   (for k = 0, 1, ..., K-1)

Data flow:
  - A[i][*] flows East (left-to-right) through row i
  - B[*][j] flows South (top-to-bottom) through column j
  - C[i][j] accumulates in place
```

**Mapping to XC7S50:**

Each PE maps to one DSP48E1:
- `A` input feeds the pre-adder or directly to the 25-bit multiplier input.
- `B` input feeds the 18-bit multiplier input.
- `P` register accumulates the partial sum.
- `PCOUT → PCIN` cascade carries the partial sum to the next PE in the column.

For a 4×4 systolic array on XC7S50 (16 DSP tiles):
- Requires 4 DSP columns of 4 tiles each (4 consecutive rows in each column).
- Maximum array size given 120 DSP tiles: ~10×12 = 120 PEs (with careful floorplanning).

#### 14.2.3 Spiking Neural Networks (SNNs) on FPGA

SNNs encode information as temporal spike patterns rather than continuous values. This maps efficiently to FPGA because:
- **Spikes are binary events** → single-bit signals, no multipliers needed for spike propagation.
- **Spike timing is encoded in FF state** → each neuron is a counter/comparator circuit.
- **Sparse activity** → most neurons are silent most of the time → low dynamic power.

**Leaky Integrate-and-Fire (LIF) neuron model:**

```
Membrane potential update (discrete time):
  V[t+1] = (1 - 1/τ_m) × V[t] + I[t]   (if no spike at t)
  V[t+1] = V_reset                        (if V[t] ≥ V_threshold → emit spike)

FPGA implementation:
  V[t] → 16-bit register (SliceM FF)
  τ_m  → right-shift by log₂(τ_m) bits (implemented as wire, zero LUT cost)
  I[t] → summation of incoming spike weights (BRAM lookup + adder tree)
  Spike → V[t] ≥ V_threshold (comparator, implemented in CARRY4 chain)
```

**Synaptic weight lookup:**

For a 1000-neuron SNN with 1000 synapses per neuron:
- Weight matrix: 1000 × 1000 × 16 bits = 16 Mb
- Exceeds XC7S50 BRAM capacity (2.7 Mb).
- Solution: **Sparse encoding** (store only non-zero weights) + external PSRAM/HyperRAM.
- Or: **Weight quantization** to 4 bits → 4 Mb (fits in BRAM with compression).

#### 14.2.4 Partial Reconfiguration for Dynamic Synaptic Plasticity

**Hebbian learning on FPGA via PR:**

1. **Static region:** Neuron state machines, spike routing fabric, output interfaces.
2. **Reconfigurable region:** Synaptic weight lookup tables (LUT-based for small networks, BRAM init for larger).

**Learning loop:**

```
1. Run SNN for T timesteps (evaluate current weights)
2. Measure output error / reward signal
3. Compute weight updates (STDP rule, backprop through time, etc.)
4. Generate new FASM for modified LUT INIT values (or new BRAM .init file)
5. Use prjxray to generate partial bitstream from FASM diff
6. Stream partial bitstream into ICAP
7. Resume SNN with updated weights
8. Repeat
```

**Latency of weight update:**

- Partial bitstream size (for one tile column): ~36 frames × 101 words × 4 bytes ≈ 14.5 KB
- ICAP throughput: 32 bits per clock at 100 MHz = 400 MB/s
- Time to write 14.5 KB: 14,500 / (400 × 10^6) ≈ 36 μs per column

For a 100-column SNN (updating all weight columns): ~3.6 ms total reconfiguration time.

### 14.3 Partial Reconfiguration — Complete Implementation Guide

#### 14.3.1 Vivado PR Design Flow

**Step 1: Partition the design**

```tcl
# Define the reconfigurable partition
set_property HD.RECONFIGURABLE true [get_cells rp_inst]

# Set the Pblock for the reconfigurable partition
create_pblock pblock_rp
add_cells_to_pblock [get_pblocks pblock_rp] [get_cells rp_inst]
resize_pblock [get_pblocks pblock_rp] -add {SLICE_X0Y0:SLICE_X15Y49}
set_property SNAPPING_MODE ON [get_pblocks pblock_rp]
```

**Step 2: Implement the static design**

```tcl
# Synthesize each module independently
synth_design -mode out_of_context -top rm_a -part xc7s50csga324-1
synth_design -top top -part xc7s50csga324-1

# Implement static design (with black box for RP)
opt_design
place_design
route_design
write_checkpoint -force static_routed.dcp
```

**Step 3: Implement each reconfigurable module**

```tcl
# Load the locked static checkpoint
open_checkpoint static_routed.dcp
lock_design -level routing  # Lock all static design routes
# Add reconfigurable module
read_checkpoint -cell rp_inst rm_a_synth.dcp
opt_design
place_design
route_design
write_checkpoint -force rm_a_routed.dcp
write_bitstream -cell rp_inst rm_a_partial.bit  # Partial bitstream
```

**Step 4: Verify PR compatibility**

```tcl
pr_verify -in_checkpoint1 rm_a_routed.dcp -in_checkpoint2 rm_b_routed.dcp
# PR_VERIFY checks that partition pins are identical between implementations
```

#### 14.3.2 Partition Pin Routing

Partition pins are the specific routing nodes where static and reconfigurable region nets connect. For each net crossing the PR boundary:
- The static implementation fixes the route up to the partition pin location.
- Each reconfigurable implementation must route from the partition pin into the RP.
- All RP implementations must use the **same partition pin locations** for the same net — this is enforced by `lock_design -level routing` and verified by `pr_verify`.

The partition pin is a specific wire segment within an INT tile at the RP boundary. It is chosen by Vivado's router and locked into the static design DCP.

#### 14.3.3 ICAP Controller Implementation

A minimal ICAP controller for PR:

```verilog
module icap_controller (
  input  wire        clk,
  input  wire        start,        // Pulse to begin PR
  input  wire [31:0] data_in,      // Bitstream data (byte-swapped)
  input  wire        data_valid,
  output reg         done,
  output reg         error
);
  // ICAP byte-swap function
  function [31:0] byte_swap;
    input [31:0] x;
    byte_swap = {x[7:0], x[15:8], x[23:16], x[31:24]};
  endfunction

  reg [31:0] icap_din;
  reg        icap_ce_n, icap_write_n;
  wire [31:0] icap_dout;

  ICAPE2 #(.ICAP_WIDTH("X32")) icap_i (
    .CLK(clk),
    .CE(icap_ce_n),
    .CSIB(icap_ce_n),
    .RDWRB(icap_write_n),
    .I(byte_swap(icap_din)),
    .O(icap_dout)
  );

  // State machine: IDLE → SYNC → STREAM → DESYNC → DONE
  // (full state machine implementation omitted for brevity;
  //  must write sync word 0xAA995566, then stream FDRI packets,
  //  then write DESYNC command, then assert done)
endmodule
```

---

## 15. Complete Resource Summary

| Resource | Count | Key Notes |
|---|---|---|
| **Logic** | | |
| CLB Tiles | 4,075 | 2 Slices per tile |
| SliceL | 5,750 | Combinational, ROM, CARRY4 |
| SliceM | 2,400 | + Distributed RAM + SRL |
| LUT6 | 32,600 | Fracturable to dual LUT5 |
| Flip-Flops | 65,200 | CE gating supported |
| CARRY4 | 8,150 | N→S chain only |
| F7MUX | 16,300 | Within-slice mux |
| F8MUX | 8,150 | Within-slice mux |
| **Memory** | | |
| BRAM36 | 75 | TDP/SDP, hardened FIFO |
| BRAM18 | 150 | From splitting BRAM36 |
| Total BRAM | 2,700 Kb | = 337.5 KB |
| Distributed RAM | 614,400 bits | SliceM only |
| **Math** | | |
| DSP48E1 | 120 | Pre-adder + 25×18 mult + 48-bit accum |
| **Clock** | | |
| Clock Regions | 6 | 2×3 grid |
| BUFG | 32 | Global clock buffers (12 active/region max) |
| BUFR | 12 | Regional clock buffers |
| MMCM | 5 | Fractional divide, dynamic phase shift |
| PLL | 5 | Lower jitter, simpler |
| HROW | 3 | Horizontal clock rows (one per row of regions) |
| **I/O** | | |
| HR I/O Banks | 5 | VCCO: 1.2–3.3V |
| User I/O | 250 | 50 per bank |
| IOB Tiles | 250 | ILOGIC/OLOGIC/IDELAY/ODELAY |
| IDELAY taps | 32 | ~78 ps/tap at 200 MHz REFCLK |
| ISERDES width | Up to 8 | DDR mode |
| **Routing** | | |
| INT Tiles | ~4,075+ | 1:1 with functional tiles |
| PIP types | Direct/Quad/Long | Hierarchy by distance |
| **Configuration** | | |
| Config frames | ~3,655 | 101 words × 32 bits each |
| Total config bits | ~11.8 Mb | SRAM-based, volatile |
| ICAP | 1 | Full 32-bit configuration interface |
| AES-256 encryption | Supported | BBRAM or eFUSE key storage |
| HMAC-SHA-256 auth | Supported | Tamper detection |
| **Debug** | | |
| ILA | Soft IP | BRAM-backed, up to 1024 probe bits |
| VIO | Soft IP | JTAG-driven, real-time probe/drive |
| JTAG TAP | 1 | IEEE 1149.1, USER1–USER4 for debug |
| **Process** | | |
| Technology node | 28nm HPL | TSMC |
| VCCINT | 1.0V | Core logic |
| VCCAUX | 1.8V | Analog, config |
| VCCO | 1.2–3.3V | Per-bank I/O |

---

## References and Further Reading

- **UG470** — 7 Series FPGAs Configuration User Guide (Xilinx/AMD)
- **UG471** — 7 Series FPGAs SelectIO Resources User Guide
- **UG472** — 7 Series FPGAs Clocking Resources User Guide
- **UG474** — 7 Series FPGAs Configurable Logic Block User Guide
- **UG479** — 7 Series FPGAs DSP48E1 Slice User Guide
- **UG480** — 7 Series FPGAs XADC Dual 12-Bit 1 MSPS Analog-to-Digital Converter User Guide
- **UG483** — 7 Series FPGAs PCB Design Guide
- **UG912** — Vivado Design Suite Properties Reference Guide
- **UG949** — UltraFast Design Methodology Guide (applicable to 7-series)
- **DS180** — 7 Series FPGAs Data Sheet: Overview
- **Project X-Ray:** https://github.com/f4pga/prjxray
- **Rose, J. et al. (1990):** "Architecture of Programmable Gate Arrays: The Effect of Logic Block Functionality on Area Efficiency" — IEEE JSSC
- **Koopmans, T. and Beckmann, M. (1957):** "Assignment Problems and the Location of Economic Activities" — Econometrica
- **PathFinder:** McMurchie, L. and Ebeling, C. (1995) "PathFinder: A Negotiation-Based Performance-Driven Router" — FPGA '95
