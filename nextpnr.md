# nextpnr Xilinx Architecture — Hyper-Detailed LLM Reference

> **Purpose**: Exhaustive, atom-level index for debugging, navigation, and understanding every component of the nextpnr Xilinx (xc7 / UltraScale+) architecture back-end. Every function, struct, enum, field, file, flow, and behavioral rule is catalogued here.

---

## TABLE OF CONTENTS

1. [File Map](#1-file-map)
2. [ChipDB / POD Data Structures](#2-chipdb--pod-data-structures)
3. [Arch Struct — Core Fields](#3-arch-struct--core-fields)
4. [ID / Identifier System](#4-id--identifier-system)
5. [BelId / WireId / PipId Primitives](#5-belid--wireid--pipid-primitives)
6. [Iterator & Range Types](#6-iterator--range-types)
7. [Bel API](#7-bel-api)
8. [Wire API](#8-wire-api)
9. [Pip API](#9-pip-api)
10. [Tile / Site System](#10-tile--site-system)
11. [LogicBelTypeZ & BRAMBelTypeZ Enums](#11-logicbeltypez--brambeltypez-enums)
12. [TileStatus / LogicTileStatus / BRAMTileStatus](#12-tilestatus--logictilestatus--bramtilestatus)
13. [Placement Validity (isBelLocationValid)](#13-placement-validity-isbelocationvalid)
14. [Delay / Timing System](#14-delay--timing-system)
15. [Routing: estimateDelay / predictDelay / getRouteBoundingBox](#15-routing-estimatedelay--predictdelay--getrouteboundingbox)
16. [Pip Availability (checkPipAvail / usp_pip_hard_unavail)](#16-pip-availability-checkpipavail--usp_pip_hard_unavail)
17. [Pack Flow (Arch::pack)](#17-pack-flow-archpack)
18. [XilinxPacker Base](#18-xilinxpacker-base)
19. [XC7Packer](#19-xc7packer)
20. [USPacker](#20-uspacker)
21. [Cell Type Transformations (XFormRule)](#21-cell-type-transformations-xformrule)
22. [LUT Packing](#22-lut-packing)
23. [FF Packing](#23-ff-packing)
24. [Carry Chain Packing (xc7 & US+)](#24-carry-chain-packing-xc7--us)
25. [MuxF Tree Packing](#25-muxf-tree-packing)
26. [DRAM Packing](#26-dram-packing)
27. [BRAM Packing](#27-bram-packing)
28. [DSP Packing](#28-dsp-packing)
29. [IO Packing (xc7)](#29-io-packing-xc7)
30. [IO Packing (US+)](#30-io-packing-us)
31. [IOLOGIC Packing (xc7)](#31-iologic-packing-xc7)
32. [IOLOGIC Packing (US+)](#32-iologic-packing-us)
33. [IDELAYCTRL Packing](#33-idelayctrl-packing)
34. [Clocking (xc7)](#34-clocking-xc7)
35. [Clocking (US+)](#35-clocking-us)
36. [Constant / Tied-Pin Handling](#36-constant--tied-pin-handling)
37. [Route Flow (Arch::route)](#37-route-flow-archroute)
38. [routeVcc](#38-routevcc)
39. [routeClock](#39-routeclock)
40. [findSourceSinkLocations](#40-findsourcesinkslocations)
41. [fixupPlacement](#41-fixupplacement)
42. [fixupRouting](#42-fixuprouting)
43. [FASM Backend (writeFasm)](#43-fasm-backend-writefasm)
44. [XDC Parser](#44-xdc-parser)
45. [Python Bindings](#45-python-bindings)
46. [cells.cc — create_cell / create_dsp_cell / create_lut](#46-cellscc--create_cell--create_dsp_cell--create_lut)
47. [pins.cc — get_invertible_pins / get_tied_pins / get_bram36_ul_pins / get_top_level_pins](#47-pinscc--get_invertible_pins--get_tied_pins--get_bram36_ul_pins--get_top_level_pins)
48. [ArchCellInfo Union](#48-archcellinfo-union)
49. [assignArchInfo / assignCellInfo](#49-assignarchinfo--assigncellinfo)
50. [Command-Line Entry (UspCommandHandler)](#50-command-line-entry-uspcommandhandler)
51. [Pip Blacklist (setup_pip_blacklist)](#51-pip-blacklist-setup_pip_blacklist)
52. [Place Flow (Arch::place)](#52-place-flow-archplace)
53. [Key Constants & Magic Numbers](#53-key-constants--magic-numbers)
54. [Cross-Reference: xc7 vs US+ Behavioral Differences](#54-cross-reference-xc7-vs-us-behavioral-differences)

---

## 1. FILE MAP

| Logical Unit | Approximate Source Location | Notes |
|---|---|---|
| Core Arch struct definition | `arch.h` | Contains all Arch member functions declared |
| Arch implementation (chipdb load, BEL/Wire/Pip API, delay, place/route top) | `arch.cc` (first concat block) | `Arch::Arch`, `getBelByName`, `getWireByName`, `getPipByName`, `estimateDelay`, `predictDelay`, `place`, `route`, `writeFasm` entrypoint |
| Logic tile validity | `arch_place.cc` (second concat block) | `xcu_logic_tile_valid`, `xc7_logic_tile_valid`, `isBelLocationValid`, `isValidBelForCell`, `fixupPlacement`, `fixupRouting` |
| Python bindings | `arch_pybindings.cc` | `arch_wrap_python` |
| Cell factory | `cells.cc` | `create_cell`, `create_dsp_cell`, `create_lut` |
| FASM backend | `fasm.cc` (part of arch.cc concat) | `FasmBackend` struct, `writeFasm` |
| Main entry | `main.cc` | `UspCommandHandler`, `main` |
| xc7 carry packing | `pack_carry_xc7.cc` | `XC7Packer::pack_carries`, `XC7Packer::has_illegal_fanout` |
| US+ carry packing | `pack_carry_usp.cc` | `USPacker::pack_carries`, `USPacker::has_illegal_fanout` |
| Shared packer utilities | `pack.cc` | `flush_cells`, `xform_cell`, `generic_xform`, `feed_through_lut`, `feed_through_muxf`, `pack_luts`, `pack_ffs`, `pack_lutffs`, `pack_muxfs`, `finalise_muxfs`, `pack_srls`, `pack_constants`, `rename_net`, `tie_port` |
| BRAM packing | `pack_bram.cc` | `XC7Packer::pack_bram`, `USPacker::pack_bram`, `USPacker::pack_uram` |
| DSP packing (xc7) | `pack_dsp_xc7.cc` | `XC7Packer::pack_dsps`, `XC7Packer::walk_dsp` |
| DSP packing (US+) | `pack_dsp_usp.cc` | `USPacker::pack_dsps` |
| IO packing (xc7) | `pack_io_xc7.cc` | `XC7Packer::pack_io`, `decompose_iob`, `pack_iologic`, `pack_idelayctrl`, IO site lookup helpers |
| IO packing (US+) | `pack_io_usp.cc` | `USPacker::pack_io`, `decompose_iob`, `pack_iologic`, `pack_idelayctrl`, `prepare_iologic` |
| IO insert helpers | `pack_io_shared.cc` | `insert_obuf`, `insert_outinv`, `invert_net`, `insert_pad_and_buf`, `create_iobuf` |
| Clocking (xc7) | `pack_clk_xc7.cc` | `XC7Packer::prepare_clocking`, `pack_plls`, `pack_gbs`, `pack_clocking` |
| Clocking (US+) | `pack_clk_usp.cc` | `USPacker::prepare_clocking`, `pack_plls`, `pack_gbs`, `pack_clocking` |
| Pre-place helpers | `pack_preplace.cc` | `find_bel_with_short_route`, `try_preplace`, `preplace_unique` |
| DRAM packing | `pack_dram.cc` | `XilinxPacker::pack_dram`, `create_dram_lut`, `create_dram32_lut`, `create_muxf_tree` |
| Pins database | `pins.cc` | `get_invertible_pins`, `get_tied_pins`, `get_bram36_ul_pins`, `get_top_level_pins` |
| XDC parser | `xdc.cc` | `Arch::parseXdc` |
| Type/ID definitions | `archdefs.h` | `BelId`, `WireId`, `PipId`, `GroupId`, `DecalId`, `ArchCellInfo`, `ArchNetInfo`, `ConstIds` enum, `id_*` constants |
| Pack header | `pack.h` | `XilinxPacker`, `USPacker`, `XC7Packer` declarations |
| Cell header | `cells.h` | Function declarations for cell factories |
| Pins header | `pins.h` | Function declarations |

---

## 2. CHIPDB / POD DATA STRUCTURES

All POD structs are packed (`NPNR_PACKED_STRUCT`) and loaded via memory-mapped file (`boost::iostreams::mapped_file_source`). All internal pointers are `RelPtr<T>` (offset-based, multiplied by 4).

### 2.1 ChipInfoPOD
**Root struct. Single instance pointed to by `Arch::chip_info`.**

| Field | Type | Meaning |
|---|---|---|
| `name` | `RelPtr<char>` | Device name string (e.g., `"xc7a35t"`, `"xczu3eg"`) |
| `generator` | `RelPtr<char>` | Chipdb generator string |
| `version` | `int32_t` | Chipdb format version |
| `width` | `int32_t` | Grid width in tiles |
| `height` | `int32_t` | Grid height in tiles |
| `num_tiles` | `int32_t` | Total tiles = width × height |
| `num_tiletypes` | `int32_t` | Number of unique tile type definitions |
| `num_nodes` | `int32_t` | Number of global routing nodes |
| `tile_types` | `RelPtr<TileTypeInfoPOD>` | Array of tile type definitions [num_tiletypes] |
| `tile_insts` | `RelPtr<TileInstInfoPOD>` | Array of tile instances [num_tiles] |
| `nodes` | `RelPtr<NodeInfoPOD>` | Array of routing nodes [num_nodes] |
| `extra_constids` | `RelPtr<ConstIDDataPOD>` | Extra string IDs appended at chipdb build time |
| `num_speed_grades` | `int32_t` | Number of timing speed grades |
| `timing_data` | `RelPtr<TimingDataPOD>` | Timing data pointer |

**Key derived access**: `chip_info->tile_insts[tile].type` → index into `chip_info->tile_types[]`.

**Tile coordinate encoding**: tile index = `y * chip_info->width + x`. Reverse: `x = tile % width`, `y = tile / width`.

---

### 2.2 TileTypeInfoPOD
**Describes one unique tile type (e.g., CLEL_L, BRAM_L, INT). Shared across all instances of that type.**

| Field | Type | Meaning |
|---|---|---|
| `type` | `int32_t` | IdString index of tile type name |
| `num_bels` | `int32_t` | BEL count in this tile type |
| `bel_data` | `RelPtr<BelInfoPOD>` | BEL array [num_bels] |
| `num_wires` | `int32_t` | Wire count in this tile type |
| `wire_data` | `RelPtr<TileWireInfoPOD>` | Wire array [num_wires] |
| `num_pips` | `int32_t` | PIP count in this tile type |
| `pip_data` | `RelPtr<PipInfoPOD>` | PIP array [num_pips] |
| `timing_index` | `int32_t` | Index into `timing_data->tile_cell_timings[]` |

---

### 2.3 BelInfoPOD
**Describes one BEL within a tile type.**

| Field | Type | Meaning |
|---|---|---|
| `name` | `int32_t` | IdString index of BEL name within site (e.g., `"AFF"`, `"A6LUT"`) |
| `type` | `int32_t` | IdString index of compatible BEL type (e.g., `ID_SLICE_LUTX`) |
| `xl_type` | `int32_t` | IdString index of Xilinx native type name |
| `timing_inst` | `int32_t` | Timing instance index within tile's timing entry |
| `num_bel_wires` | `int32_t` | Number of port-to-wire connections |
| `bel_wires` | `RelPtr<BelWirePOD>` | Port array [num_bel_wires] |
| `z` | `int16_t` | Z-coordinate; encodes position within tile; upper nibble = slice index (A-H = 0-7), lower nibble = function (see `LogicBelTypeZ`) |
| `site` | `int16_t` | Site index within tile (-1 if not in a site) |
| `site_variant` | `int16_t` | Site variant index (0 = default) |
| `is_routing` | `int16_t` | Non-zero if this is a routing BEL (hidden in GUI) |

---

### 2.4 BelWirePOD
**Maps one BEL port to a wire index within the same tile.**

| Field | Type | Meaning |
|---|---|---|
| `port` | `int32_t` | IdString index of port name |
| `type` | `int32_t` | `PORT_IN=0`, `PORT_OUT=1`, `PORT_INOUT=2` |
| `wire_index` | `int32_t` | Wire index in tile type's `wire_data[]`, or -1 |

---

### 2.5 TileWireInfoPOD
**Describes one wire within a tile type.**

| Field | Type | Meaning |
|---|---|---|
| `name` | `int32_t` | IdString index |
| `num_uphill` | `int32_t` | Count of pips that drive this wire |
| `num_downhill` | `int32_t` | Count of pips driven by this wire |
| `timing_class` | `int32_t` | Index into `timing_data->wire_timing_classes[]` |
| `pips_uphill` | `RelPtr<int32_t>` | Array of pip indices [num_uphill] |
| `pips_downhill` | `RelPtr<int32_t>` | Array of pip indices [num_downhill] |
| `num_bel_pins` | `int32_t` | Count of BEL pins attached to this wire |
| `bel_pins` | `RelPtr<BelPortPOD>` | BEL-pin array [num_bel_pins] |
| `site` | `int16_t` | Site index (-1 if not site-local) |
| `padding` | `int16_t` | Unused |
| `intent` | `int32_t` | Wire intent IdString (e.g., `ID_NODE_LOCAL`, `ID_NODE_PINFEED`) |

---

### 2.6 PipInfoPOD
**Describes one programmable interconnect point (PIP).**

| Field | Type | Meaning |
|---|---|---|
| `src_index` | `int32_t` | Source wire index in tile type |
| `dst_index` | `int32_t` | Destination wire index in tile type |
| `timing_class` | `int32_t` | Index into `timing_data->pip_timing_classes[]` |
| `padding` | `int16_t` | Unused |
| `flags` | `int16_t` | PIP type (see `PipType` enum) |
| `bel` | `int32_t` | IdString of associated BEL (used for site pips) |
| `extra_data` | `int32_t` | Multipurpose: LUT permutation encoding, pin name, etc. |
| `site` | `int16_t` | Site index (-1 for tile routing pips) |
| `site_variant` | `int16_t` | Site variant |

**`PipType` enum values** (stored in `flags`):

| Value | Constant | Meaning |
|---|---|---|
| 0 | `PIP_TILE_ROUTING` | Normal routing pip between tile wires |
| 1 | `PIP_SITE_ENTRY` | Pip entering a site from tile routing |
| 2 | `PIP_SITE_EXIT` | Pip leaving a site into tile routing |
| 3 | `PIP_SITE_INTERNAL` | Pip entirely within a site |
| 4 | `PIP_LUT_PERMUTATION` | Virtual pip representing LUT input permutation |
| 5 | `PIP_LUT_ROUTETHRU` | LUT used as route-through |
| 6 | `PIP_CONST_DRIVER` | Constant value driver pip |

---

### 2.7 TileInstInfoPOD
**Per-instance tile data (varies between instances of same type).**

| Field | Type | Meaning |
|---|---|---|
| `name` | `RelPtr<char>` | Full tile name string (e.g., `"CLEL_L_X12Y34"`) |
| `type` | `int32_t` | Index into `chip_info->tile_types[]` |
| `num_tile_wires` | `int32_t` | Count of non-site-internal tile wires (subset of type's wire count) |
| `tile_wire_to_node` | `RelPtr<int32_t>` | Per-wire node index array; -1 = tile-local, else = global node index |
| `num_sites` | `int32_t` | Number of sites in this tile instance |
| `site_insts` | `RelPtr<SiteInstInfoPOD>` | Site instance array [num_sites] |

---

### 2.8 SiteInstInfoPOD
**Per-site-instance data.**

| Field | Type | Meaning |
|---|---|---|
| `name` | `RelPtr<char>` | Full site name (e.g., `"SLICE_X12Y34"`) |
| `pin` | `RelPtr<char>` | Package pin name (e.g., `"A1"`), or `"."` if no pin |
| `site_x`, `site_y` | `int32_t` | Absolute site grid coordinates |
| `rel_x`, `rel_y` | `int32_t` | Relative position within tile |
| `inter_x`, `inter_y` | `int32_t` | Interconnect anchor coordinates (-1 if unavailable; used in delay estimation) |

---

### 2.9 NodeInfoPOD
**A global routing node spanning multiple tiles.**

| Field | Type | Meaning |
|---|---|---|
| `num_tile_wires` | `int32_t` | Number of tile wires in this node |
| `intent` | `int32_t` | Node intent IdString |
| `tile_wires` | `RelPtr<TileWireRefPOD>` | Array [num_tile_wires] of (tile, wire_index) pairs |

**Wire canonicalization**: When `tile_wire_to_node[wire] != -1`, the wire is "nodal" and its canonical `WireId` has `tile=-1`, `index=node_index`.

---

### 2.10 Timing POD Structures

**TimingDataPOD** — root timing struct:
- `num_tile_types`, `num_wire_classes`, `num_pip_classes` — array sizes
- `tile_cell_timings` → `TileCellTimingPOD[]`
- `wire_timing_classes` → `WireTimingPOD[]`
- `pip_timing_classes` → `PipTimingPOD[]`

**TileCellTimingPOD** → `tile_type_name` + `num_instances` + `InstanceTimingPOD[]`

**InstanceTimingPOD** → `inst_name` + `num_celltypes` + `CellTimingPOD[]`
- Sorted by `inst_name` IdString for binary search

**CellTimingPOD** → `variant_name` + `num_delays` + `CellPropDelayPOD[]` + `num_checks` + `CellTimingCheckPOD[]`
- Delays sorted by `(to_port, from_port)` pair for binary search

**CellPropDelayPOD**: `from_port`, `to_port`, `min_delay`, `max_delay` (in ps)

**CellTimingCheckPOD**: `check_type` (SETUP/HOLD/WIDTH), `sig_port`, `clock_port`, `min_value`, `max_value`

**WireTimingPOD**: `resistance` (mΩ), `capacitance` (fF)

**PipTimingPOD**: `is_buffered`, `min_delay`, `max_delay`, `resistance`, `capacitance`

**`db_binary_search` template** (anonymous namespace in arch.cc): Performs linear search for count < 7, binary search otherwise. Used for timing lookups. Signature: `db_binary_search(list, count, key_getter, key) → boost::optional<const T&>`.

**`xc7_cell_timing_lookup`** (Arch member): Looks up a cell delay given `tt_id` (tile timing index), `inst_id` (instance index), `variant` IdString, `from_port`, `to_port`. Returns false if not found.

---

### 2.11 ConstIDDataPOD
**Extra string IDs loaded from chipdb to extend the IdString table.**

| Field | Type | Meaning |
|---|---|---|
| `known_id_count` | `int32_t` | Number of IDs already in the compiled-in constids |
| `bba_id_count` | `int32_t` | Number of extra IDs in this chipdb |
| `bba_ids` | `RelPtr<RelPtr<char>>` | Array of string pointers |

**Loading loop** in `Arch::Arch`: iterates `bba_id_count` calling `IdString::initialize_add(this, bba_ids[i].get(), i + known_id_count)`.

---

### 2.12 RelPtr<T>
`offset` field (int32_t); `get()` returns `reinterpret_cast<const T*>(this + offset*4)`. All POD array accesses go through this. Never contains raw pointers — safe for memory-mapped files.

---

## 3. ARCH STRUCT — CORE FIELDS

```cpp
struct Arch : BaseArch<ArchRanges>
```

**Stored in `Arch` object** (i.e., always accessible as `ctx->` from packing/routing code):

| Field | Type | Purpose |
|---|---|---|
| `blob_file` | `boost::iostreams::mapped_file_source` | Memory-mapped chipdb file handle |
| `chip_info` | `const ChipInfoPOD*` | Root chipdb pointer |
| `tile_by_name` | `dict<string,int>` | Tile name → tile index cache (lazy, via `setup_byname()`) |
| `site_by_name` | `dict<string,pair<int,int>>` | Site name → (tile, site_index) cache (lazy) |
| `wire_to_net` | `dict<WireId,NetInfo*>` | Currently bound wire → net |
| `pip_to_net` | `dict<PipId,NetInfo*>` | Currently bound pip → net |
| `driving_pip_loc` | `dict<WireId,pair<int,int>>` | Wire → (x,y) of driving pip tile; used in `getPipDelay` |
| `reserved_wires` | `dict<WireId,NetInfo*>` | Reserved wires for bounce routing (set in `fixupPlacement`) |
| `tileStatus` | `vector<TileStatus>` | Per-tile status [num_tiles] |
| `args` | `ArchArgs` | Chipdb path |
| `xc7` | `bool` | **True if device name starts with "xc7"** — gates all xc7 vs US+ behavior |
| `blacklist_pips` | `dict<int,pool<int>>` | `tile_type_id → set of pip indices` that are unusable |
| `sink_locs` | `dict<WireId,Loc>` | Sink wire → estimated interconnect location (from `findSourceSinkLocations`) |
| `source_locs` | `dict<WireId,Loc>` | Source wire → estimated interconnect location |
| `pin_to_site` | `mutable dict<string,string>` | Package pin → site name (lazy via `getPackagePinSite`) |
| `wire_by_name_cache` | `mutable dict<IdString,WireId>` | Wire name lookup cache |
| `pip_by_name_cache` | `mutable dict<IdString,PipId>` | Pip name lookup cache |
| `gnd_glbl`, `gnd_row`, `vcc_glbl`, `vcc_row` | `mutable IdString` | Cached IdStrings for pseudo-net wire names (lazy) |

---

## 4. ID / IDENTIFIER SYSTEM

**`IdString`**: 32-bit integer index into a global string table. Zero = empty/invalid.

**`id_XXX` constants**: Defined as `static constexpr auto id_XXX = IdString(ID_XXX)` where `ID_XXX` comes from `ConstIds` enum built from `constids.inc` via X-macros.

**`IdString::initialize_arch(ctx)`**: Called in Arch constructor. Iterates `constids.inc` X-macro, registering every compile-time constant ID.

**`id(string)`** (from `BaseCtx`): Looks up or creates an IdString from a runtime string. Used everywhere.

**`IdStringList`**: A small vector of IdStrings, used for multi-component names (e.g., `"SLICE_X0Y0/AFF"` → `{id("SLICE_X0Y0/AFF")}`). In this arch, always wraps a single IdString.

---

## 5. BELID / WIREID / PIPID PRIMITIVES

### BelId
```cpp
struct BelId { int32_t tile = -1; int32_t index = -1; };
```
- `tile`: tile index in `chip_info->tile_insts[]`
- `index`: BEL index in the tile type's `bel_data[]`
- Default (tile=-1, index=-1) = invalid

### WireId
```cpp
struct WireId { int32_t tile = -1; int32_t index = -1; };
```
- **Nodal wire**: `tile == -1`, `index` = node index in `chip_info->nodes[]`
- **Tile-local wire**: `tile != -1`, `index` = wire index in tile type's `wire_data[]`
- Canonical form: always use `canonicalWireId(chip_info, tile, wire_index)` to convert raw (tile, local_wire_index) to canonical WireId.

**`canonicalWireId(chip_info, tile, wire)`**:
1. If `wire >= tile_insts[tile].num_tile_wires` → must be site-internal, return `{tile, wire}` (always tile-local)
2. Else lookup `tile_wire_to_node[wire]`:
   - If `-1` → tile-local, return `{tile, wire}`
   - Else → nodal, return `{-1, node_index}`

### PipId
```cpp
struct PipId { int32_t tile = -1; int32_t index = -1; };
```
- `tile`: tile index
- `index`: PIP index in tile type's `pip_data[]`

### GroupId, DecalId
Used for GUI grouping and graphical elements respectively. `GroupId` has type enum (TYPE_NONE through TYPE_LC7_SW) plus x, y. `DecalId` has type enum (TYPE_NONE/BEL/WIRE/PIP/GROUP), tile_type, index, active flag.

---

## 6. ITERATOR & RANGE TYPES

All ranges follow the pattern `struct XRange { XIter b, e; begin()/end() }`.

### BelIterator / BelRange
Iterates all BELs across all tiles. `cursor_tile` advances when `cursor_index >= num_bels` for current tile. Begin is initialized at tile=0, index=-1 then incremented. End is tile=num_tiles, index=0.

### TileWireIterator / TileWireRange
Iterates the tile-wire expansion of a nodal or tile-local wire. For nodal (tile==-1): iterates `nodes[index].tile_wires[cursor]` returning denormalized `{tile, wire_index}` pairs. For tile-local: single iteration returning the wire itself.

### WireIterator / WireRange
Iterates all canonical wires: first all nodes (tile=-1, index=0..num_nodes-1), then all tile-local wires that are NOT mapped to a node (skips any where `tile_wire_to_node[index] != -1`).

### AllPipIterator / AllPipRange
Iterates all PIPs across all tiles. Same pattern as BelIterator.

### UphillPipIterator / UphillPipRange
Given a wire, iterates all PIPs that drive it. Internally uses `TileWireIterator` to expand nodal wires, then iterates `wire_data[w.index].pips_uphill[]` for each tile-wire.

### DownhillPipIterator / DownhillPipRange
Same as Uphill but uses `pips_downhill[]`.

### BelPinIterator / BelPinRange
Given a wire, iterates all `(BelId, pin)` pairs connected to it. Uses `TileWireIterator` then `wire_data[w.index].bel_pins[]`. Returns `BelPin{bel, pin}`.

---

## 7. BEL API

### getBelByName(IdStringList name)
1. Calls `setup_byname()` (lazy init of `tile_by_name`, `site_by_name`)
2. Splits `name[0]` on `/` via `split_identifier_name`
3. If first part is in `site_by_name`: looks up (tile, site_idx), then scans `tile_info.bel_data` for matching `site == site_idx && name == belname.index`
4. Else: looks up tile by name in `tile_by_name`, scans `bel_data` for matching `name == belname.index`
5. Returns `{tile, index}` or default BelId if not found

### getBelName(BelId bel)
- If `bel_data[bel.index].site != -1`: returns `"site_name/bel_name"` using site_insts
- Else: returns `"tile_name/bel_name"` using tile_insts

### getBelsByTile(int x, int y)
Returns `BelRange` for a single tile: b.cursor_index=0, e.cursor_index=num_bels for that tile.

### getBelPinWire(BelId bel, IdString pin)
Scans `bel_data[bel.index].bel_wires[]` for matching `port == pin.index`. Returns `canonicalWireId(chip_info, bel.tile, bel_wires[i].wire_index)`.

### getBelPinType(BelId bel, IdString pin)
Same scan, returns `PortType(bel_wires[i].type)`. Returns `PORT_INOUT` if pin not found.

### getBelPins(BelId bel)
Returns `vector<IdString>` of all port names: iterates `bel_data[bel.index].bel_wires[]`, constructs `IdString{bel_wires[i].port}`.

### getBelByLocation(Loc loc)
`bi.tile = loc.y * width + loc.x`. Scans `locInfo(bi).bel_data` for `bel_data[i].z == loc.z`.

### bindBel / unbindBel
- `bindBel`: asserts `boundcells[bel.index] == nullptr`, sets `boundcells[bel.index] = cell`, copies site_variant, calls `updateLogicBel` or `updateBramBel`.
- `unbindBel`: reverses the above.

### checkBelAvail(BelId bel)
Returns `!usp_bel_hard_unavail(bel) && boundcells[bel.index] == nullptr`.

### usp_bel_hard_unavail(BelId bel)
- Returns true if `getBelType(bel).in(id_PSEUDO_GND, id_PSEUDO_VCC) && (bel.tile % width) != 0` — pseudo-drivers must be at x=0
- Commented-out SLR constraint code present

### getBelGlobalBuf(BelId bel)
Returns true for: `BUFGCTRL`, `PSEUDO_GND`, `PSEUDO_VCC`, `BUFCE_BUFG_PS`, `BUFGCE_DIV_BUFGCE_DIV`, `BUFCE_BUFCE`.

### getBelType(BelId bel)
Returns `IdString(locInfo(bel).bel_data[bel.index].type)`.

### getBelTileType(BelId bel)
Returns `IdString(locInfo(bel).type)` — the tile type IdString.

### isLogicTile(BelId bel)
Returns true for tile types: `CLEL_L`, `CLEL_R`, `CLEM`, `CLEM_R`, `CLBLL_L`, `CLBLL_R`, `CLBLM_L`, `CLBLM_R`.

### isBRAMTile(BelId bel)
Returns true for tile types: `BRAM`, `BRAM_L`, `BRAM_R`.

### getBelPackagePin(BelId bel)
Returns `site_insts[bel_data[bel.index].site].pin.get()` — the physical package pin string.

### getBelSite(BelId bel)
Returns `site_insts[bel_data[bel.index].site].name.get()`.

### getSiteLocInTile(BelId bel)
Returns `Loc{site.rel_x, site.rel_y, bel_data.site_variant}`.

### locInfo(Id &id)
Template helper: `chip_info->tile_types[chip_info->tile_insts[id.tile].type]` — gets tile type info from any BelId/WireId/PipId.

---

## 8. WIRE API

### setup_byname()
Lazy initializer. If `tile_by_name` is empty, populates it. If `site_by_name` is empty, populates it by scanning all tiles and all sites.

### getWireByName(IdStringList name)
Uses `wire_by_name_cache` (IdString → WireId) for memoization.

Name parsing:
- If starts with `"SITEWIRE/"`: strips prefix, splits on `/`, looks up site in `site_by_name`, scans `tile_info.wire_data` for `wire.site == site && wire.name == wirename.index`
- Else: splits on `/`, looks up tile, scans for `wire.site == -1 && wire.name == wirename.index`

### getWireName(WireId wire)
- If tile-local and site-local: `"SITEWIRE/site_name/wire_name"`
- Else: `"tile_name/wire_name"` using the first tile wire's tile if nodal

### wireInfo(WireId wire) const
Inline accessor:
- If `wire.tile == -1` (nodal): accesses `nodes[wire.index].tile_wires[0]` to get tile and index, then returns `tile_types[...].wire_data[wr.index]`
- Else: returns `locInfo(wire).wire_data[wire.index]`

### wireIntent(WireId wire) const
- If `wire.tile == -1`: `chip_info->nodes[wire.index].intent`
- Else: `locInfo(wire).wire_data[wire.index].intent`

### bindWire / unbindWire
- `bindWire`: asserts wire is free, sets `wire_to_net[wire] = net`, adds to `net->wires` with pip=PipId() and given strength.
- `unbindWire`: removes from `wire_to_net` and `net->wires`, unbinds associated pip if any.

### checkWireAvail(WireId wire)
`wire_to_net.find(wire) == end || wire_to_net[wire] == nullptr`.

### getWireType(WireId wire)
Returns `IdString(wireIntent(wire))`.

### getWireAttrs(WireId wire)
Returns `{{id_INTENT, IdString(wireIntent(wire)).str(this)}}`.

### getTileWireRange(WireId wire)
For nodal (tile==-1): begin cursor=-1 → ++cursor increments to 0; end cursor=`num_tile_wires`.
For tile-local: begin cursor=-1 → ++cursor to 0; end cursor=1.

### getWireBelPins(WireId wire)
Creates `BelPinRange` using `TileWireRange` as the tile-wire expansion, then `wire_data[w.index].bel_pins[]`.

### getReservedWireNet(WireId wire)
Looks up `reserved_wires` dict. Returns nullptr if not found.

---

## 9. PIP API

### getPipByName(IdStringList name)
Uses `pip_by_name_cache`.

Name parsing:
- If starts with `"SITEPIP/"`: strips prefix, splits on `/`, looks up site, then `split_identifier_name` on remainder to get bel/pin names. Scans `pip_data` for `site==site && bel==belname.index && extra_data==pinname.index`.
- Else: splits on `/` for tile, then splits on `.` to get `fromwire` and `towire` integers. Scans for `site==-1 && src_index==fromwire && dst_index==towire`.

### getPipName(PipId pip)
- If `site != -1 && flags == PIP_SITE_INTERNAL && bel != -1`: returns `"SITEPIP/site_name/bel_name/src_wire_name"`
- Else: returns `"tile_name/src_index.dst_index"`

### getPipSrcWire / getPipDstWire
`canonicalWireId(chip_info, pip.tile, pip_data[pip.index].src_index / dst_index)`.

### bindPip / unbindPip
- `bindPip`: asserts pip free and dst wire free or same net. Sets `pip_to_net[pip]=net`, `driving_pip_loc[dst]=(pip.tile%width, pip.tile/width)`, `wire_to_net[dst]=net`, `net->wires[dst]={pip, strength}`.
- `unbindPip`: reverses; erases from `pip_to_net`, `net->wires`, sets `wire_to_net[dst]=nullptr`.

### checkPipAvail(PipId pip)
`!usp_pip_hard_unavail(pip) && pip_to_net.find(pip)==end || pip_to_net[pip]==nullptr`.

### getPipDelay(PipId pip) → DelayQuad
- If `PIP_TILE_ROUTING`: Complex formula based on pip and wire timing classes, wire resistance/capacitance, driving pip location. Has special cases for global net intents (100 base) and Laguna DATA wires (5000 base). Uses `driving_pip_loc` for source-length estimation.
- If `PIP_LUT_ROUTETHRU`: 300
- Else (site pips, const driver, etc.): 25

### approx_pip_delay(int32_t start_intent, int32_t end_intent)
Lookup table for ~30 (start, end) intent combinations, returning approximate delay in delay units. Returns 100 as catch-all. Used as a quick reference (not the primary timing path).

### getPipType(PipId pip)
Returns `id_PIP`.

### getPipLocation(PipId pip)
Returns `Loc{pip.tile%width, pip.tile/width, 0}`.

---

## 10. TILE / SITE SYSTEM

**Tile grid**: Row-major. `tile_index = y * width + x`.

**Site**: A logical resource cluster within a tile (e.g., a SLICE site, IOB site). A tile can have 0..N sites. `bel_data[i].site` indexes into `tile_insts[tile].site_insts[]`.

**Site variants**: Some sites can be configured as different types (e.g., SLICEL vs SLICEM). Tracked via `tileStatus[tile].sitevariant[site_index]`. When a BEL is bound, its `site_variant` is stored; site-internal pips with non-matching variants are blocked by `usp_pip_hard_unavail`.

**`getTilesAndTypes()`**: Returns `vector<pair<string,string>>` of (tile_name, tile_type_name) for all tiles. Used by FASM backend.

**`getPackagePinSite(pin)`**: Lazy-populated via `pin_to_site` cache. Scans all tile instances and all site instances for `site.pin.get() == pin`. Returns site name or empty string.

**`getHclkForIob(BelId pad)`**: Finds the IOI tile adjacent to an IOB pad, then calls `getHclkForIoi`.
- For LIOB tiles: `ioi = pad.tile + 1`
- For RIOB tiles: `ioi = pad.tile - 1`

**`getHclkForIoi(int ioi)`**: Finds a wire named `"IOI_IOCLK0"` or `"IOI_SING_IOCLK0"` in the IOI tile's type, gets its canonical form, then returns the tile of the first uphill pip.

---

## 11. LOGICBELTYPEZ & BRAMBELTYPEZ ENUMS

### LogicBelTypeZ (lower nibble of `BelInfoPOD.z`)

| Value | Constant | Meaning |
|---|---|---|
| 0x0 | `BEL_6LUT` | 6-input LUT (primary) |
| 0x1 | `BEL_5LUT` | 5-input LUT (O5 output) |
| 0x2 | `BEL_FF` | Primary flip-flop (FF1) |
| 0x3 | `BEL_FF2` | Secondary flip-flop (FF2) |
| 0x4 | `BEL_FFMUX1` | FF1 input mux |
| 0x5 | `BEL_FFMUX2` | FF2 input mux |
| 0x6 | `BEL_OUTMUX` | Output mux |
| 0x7 | `BEL_F7MUX` | F7 mux (first level wide mux) |
| 0x8 | `BEL_F8MUX` | F8 mux |
| 0x9 | `BEL_F9MUX` | F9 mux (US+ only) |
| 0xA | `BEL_CARRY8` | US+ carry chain (8-bit) |
| 0xB | `BEL_CLKINV` | Clock inversion BEL |
| 0xC | `BEL_RSTINV` | Reset inversion BEL |
| 0xD | `BEL_HARD0` | Hardwired zero |
| 0xF | `BEL_CARRY4` | xc7 carry chain (4-bit) |

**Upper nibble** (bits [7:4] of z) encodes the "eight-index" — which of the 8 LUT-FF pairs (A=0 through H=7) in a US+ tile, or (A=0 through D=3) repeated twice for xc7 (2 half-tiles each with 4 LUT-FF pairs).

**Z encoding formula**: `z = (eight_index << 4) | bel_type`. Example: `BFF` = `(1 << 4) | BEL_FF = 0x12`.

**Half-tile index**: `z >> 6` gives 0 for bottom half (A-D), 1 for top half (E-H) in xc7 (only relevant with 4-per-half layout). In US+: halfs 0 and 1 cover eights 0-3 and 4-7.

### BRAMBelTypeZ

| Value | Constant | Meaning |
|---|---|---|
| 0 | `BEL_RAMFIFO36` | 36K RAMB/FIFO combined |
| 1 | `BEL_RAM36` | 36K RAM only |
| 2 | `BEL_FIFO36` | 36K FIFO only |
| 5 | `BEL_RAM18_U` | Upper 18K RAM half |
| 8 | `BEL_RAMFIFO18_L` | Lower 18K RAMB/FIFO |
| 9 | `BEL_RAM18_L` | Lower 18K RAM |
| 10 | `BEL_FIFO18_L` | Lower 18K FIFO |

### DSP48E1BelTypeZ (xc7)

| Value | Constant | Meaning |
|---|---|---|
| 6 | `BEL_LOWER_DSP` | Lower DSP48E1 Z position |
| 25 | `BEL_UPPER_DSP` | Upper DSP48E1 Z position |

### DSP48E2BelTypeZ (US+)

| Value | Constant | Meaning |
|---|---|---|
| 0 | `BEL_DSP_PREADD_DATA` | Pre-adder data register |
| 1 | `BEL_DSP_PREADD` | Pre-adder |
| 2 | `BEL_DSP_A_B_DATA` | A/B data pipeline |
| 3 | `BEL_DSP_MULTIPLIER` | Multiplier |
| 4 | `BEL_DSP_C_DATA` | C data pipeline |
| 5 | `BEL_DSP_M_DATA` | Multiplier data pipeline |
| 6 | `BEL_DSP_ALU` | ALU |
| 7 | `BEL_DSP_OUTPUT` | Output pipeline |

---

## 12. TILESTATUS / LOGICTILESTATUS / BRAMTILESTATUS

### TileStatus
```cpp
struct TileStatus {
    LogicTileStatus *lts = nullptr;   // Null if no logic cells placed in tile
    BRAMTileStatus  *bts = nullptr;   // Null if no BRAM cells placed
    vector<CellInfo*> boundcells;     // [num_bels] — which cell occupies each BEL
    vector<int>      sitevariant;     // [num_sites] — current site variant
    ~TileStatus() { delete lts; delete bts; }
};
```
Initialized in `Arch::Arch`: `tileStatus.resize(num_tiles)`. Each entry's `boundcells` is resized to `num_bels` for that tile type; `sitevariant` resized to `num_sites`.

### LogicTileStatus
```cpp
struct LogicTileStatus {
    CellInfo *cells[128];    // Indexed by z value (0..127)
    struct EigthTileStatus { bool valid=true, dirty=true; } eights[8];
    struct HalfTileStatus  { bool valid=true, dirty=true; } halfs[8];
};
```
`cells[z]` stores the cell at position z. Eights[i] tracks validity for LUT/mux logic in the i-th LUT-FF group. Halfs[i] tracks FF clock/SR/CE sharing validity.

**`updateLogicBel(BelId bel, CellInfo* cell)`**: Called on bind/unbind. Lazy-creates `lts` if null. Sets `lts->cells[z] = cell`. Marks dirty bits based on BEL type:
- `BEL_FF` or `BEL_FF2`: marks `halfs[(z>>4)/4]` dirty; if xc7 and half=0, also marks `eights[3]` dirty; falls through to mark `eights[z>>4]` dirty
- `BEL_6LUT` or `BEL_5LUT`: marks `eights[z>>4]` dirty; extra check if it's the top LUT (z>>4 == 7 for US+ or 3 for xc7) and is memory — marks all eights and halfs[0] dirty
- `BEL_F7MUX`: marks `eights[z>>4]` and `eights[(z>>4)+1]` dirty
- `BEL_F8MUX`: marks `eights[(z>>4)+1]` and `eights[(z>>4)+2]` dirty
- `BEL_F9MUX`: marks `eights[3]` and `eights[4]` dirty
- `BEL_CARRY8`: marks all 8 eights dirty
- `BEL_CARRY4`: marks 4 eights in the relevant half dirty

**SRL special case**: If newly placed or removed cell has `lutInfo.is_srl`, marks all 8 eights and `halfs[0]` dirty.

### BRAMTileStatus
```cpp
struct BRAMTileStatus { CellInfo *cells[12] = {nullptr}; };
```
`cells[z]` for z in 0..11 maps to BRAM BEL types by Z value.

**`updateBramBel(BelId bel, CellInfo* cell)`**: Only acts on recognized BRAM types (`RAMBFIFO18E2`, `RAMBFIFO36E2`, `RAMB18E2`, `FIFO18E2`, `RAMB36E2`, `FIFO36E2`, `RAMBFIFO36E1`, `RAMB36E1`, `RAMB18E1`). Lazy-creates `bts`, sets `bts->cells[z] = cell`.

---

## 13. PLACEMENT VALIDITY (isBelLocationValid)

Entry point: `Arch::isBelLocationValid(BelId bel, bool explain_invalid)`.

**Logic tiles** (isLogicTile):
- If `tileStatus[bel.tile].lts == nullptr` → return true (no cells, trivially valid)
- Else call `xc7_logic_tile_valid(belTileType, lts)` or `xcu_logic_tile_valid(belTileType, lts)` depending on `xc7` flag

**BRAM tiles** (belTileType in {id_BRAM, id_BRAM_L, id_BRAM_R}):
- If `bts == nullptr` → true
- `onehot(a,b,c)` lambda: ≤1 of the three is non-null
- Checks: `onehot(RAMFIFO36, RAM36, FIFO36)` and `onehot(RAMFIFO18_L, RAM18_L, FIFO18_L)`
- If any 36-bit cell present → all indices 4..11 must be null

**Other tiles**:
- Checks all BELs in that tile; if any bound cell has `usp_bel_hard_unavail(bel)` → false

---

### 13.1 xcu_logic_tile_valid (US+)

**Input**: `tileType` IdString, `LogicTileStatus& lts`

`is_slicem = (tileType == id_CLEM || tileType == id_CLEM_R)`

**Memory check**: if `cells[(7<<4)|BEL_6LUT] != nullptr && is_memory` → `tile_is_memory = true`; if 5LUT is memory → `small_memory = true`.

**Per-eight validation** (i=0..7), skipped if not dirty and already valid:
1. Get `lut6 = cells[(i<<4)|BEL_6LUT]`, `lut5 = cells[(i<<4)|BEL_5LUT]`
2. If `lut6 != nullptr`:
   - If not SLICEM and is_memory or is_srl → return false
   - If `lut5 != nullptr`: check no memory/srl type mismatch; if `input_count==6 || output_count==2` → false; if total inputs > 5, count shared inputs and fail if insufficient
3. If `lut5 != nullptr`: same SLICEM check; input count must be ≤5; output count must be 1
4. **DI/X net conflict check**: `i_net` from `lut6->lutInfo.di1_net`, `x_net` from `lut6->lutInfo.di2_net`. Then check `lut5->di1_net` against `i_net`. `lut5->di2_net` must be null.
5. **Mux assignment**: For eights 0,2,4,6: mux = F7MUX; for 1,5: mux = F8MUX; for 3: mux = F9MUX. Mux's `muxInfo.sel` must match or set `x_net`.
6. **out_fmux assignment**: For eights 1,3,5,7: `out_fmux = cells[(i-1)<<4|BEL_F7MUX]`; for 2,6: F8MUX; for 4: F9MUX.
7. **CARRY8**: if present and `carryInfo.x_sigs[i] != nullptr`, must match `x_net`.
8. **FF1 (BEL_FF)**: if D driver is not lut6 (non-MC31), lut5, or out_fmux → must use x_net (indirect).
9. **FF2 (BEL_FF2)**: if D driver is not lut6 (non-MC31), lut5, or out_fmux → must use i_net (indirect).
10. **Memory address MSB collision** (tile_is_memory && !small_memory): for i=6: `x_net` must equal `top_lut->address_msb[0]`; for i=5: `address_msb[1]`; for i=3: `address_msb[2]`.
11. **Mux output contention**: compute `out5` from LUT O5 output or 5LUT output. If `out5` used by more than 1 user or neither FF's D, mark `mux_output_used`. CARRY8 output also sets `mux_output_used`. out_fmux output check. All these must be mutually exclusive.

**Per-half validation** (i=0..1):
- For all 4 eights in half, for both FF and FF2:
  - All FFs must share same `clk`, `sr`, `clkinv`, `srinv`, `is_latch`
  - FF and FF2 within same eight can have different CE (`ce[k]`)

---

### 13.2 xc7_logic_tile_valid (xc7)

Similar to xcu but with these key differences:

`is_slicem = (tileType == id_CLBLM_L || id_CLBLM_R)`

- **No DI1/DI2 split**: only `x_net` (from `lut6->lutInfo.di2_net`), no separate `i_net`
- **SRL constraint**: SRLs not allowed in upper 4 eights (i >= 4)
- **WCLK tracking**: Memory/SRL cells must share same `wclk` net across all eights
- **CARRY4**: uses `cells[((i/4)<<6)|BEL_CARRY4]` (one per half, not one per tile)
- **FF2 direct check**: FF2 can only be directly driven by `lut5` (not lut6 or out_fmux)
- **F8MUX out_fmux assignment**: for i=0,2,4,6 and i=1,5 (same as xcu), but F9MUX doesn't exist
- **Half validation**: all FFs in a half must share same clk, sr, ce (single CE for all FFs, not per-column), clkinv, srinv, is_latch, ffsync; lattices can only be in FF1 (not FF2); wclk must match CLK of FF in half 0

---

## 14. DELAY / TIMING SYSTEM

**`delay_t`**: `int` (typedef). Units: **picoseconds × 1** (so 1000 = 1 ns). **`getDelayFromNS(float ns)`** = `delay_t(ns * 1000)`. **`getDelayNS(delay_t v)`** = `v * 0.001`.

**`DelayQuad`**: Encapsulates four delay values (minRaise, maxRaise, minFall, maxFall). In this arch, all are set to the same value (`DelayQuad(d)` sets all to `d`).

**`DelayPair`**: min/max pair.

**`DelayInfo`**: Single `delay_t delay` field. Supports `+` operator.

**`getDelayEpsilon()`**: 20

**`getRipupDelayPenalty()`**: 120

**`getWireRipupDelayPenalty(WireId wire)`**:
- If `wireIntent(wire) == ID_NODE_PINFEED`: returns `(3 * getRipupDelayPenalty()) / 2 = 180`
- Else: 120

**`getWireDelay(WireId wire)`**: Always returns `DelayQuad(0)` — wire delays are incorporated into pip delays.

---

## 15. ROUTING: estimateDelay / predictDelay / getRouteBoundingBox

### estimateDelay(WireId src, WireId dst)
Returns a rough distance-based delay estimate for the router's A* heuristic.

**Algorithm**:
1. Handle `src == dst` → return 0
2. Determine `dst_x, dst_y`:
   - If in `sink_locs`: use that location; if src and dst in same tile or same sink_loc → return 1000
   - Else if tile has sites and `site.inter_x != -1`: use inter coordinates
   - Else: tile % width, tile / width
3. Determine `src_x, src_y`:
   - If `src.tile == -1` and `src_intent == ID_PSEUDO_GND/VCC`:
     - Lazy-init `gnd_glbl`, `gnd_row`, `vcc_glbl`, `vcc_row` IdStrings
     - If wire name matches `gnd_glbl` or `vcc_glbl` → return 15000
     - Else src_x = src_tile % width; if `gnd_row/vcc_row` → src_x = width/2
   - If `src.tile == -1` (regular nodal): iterate up to min(200, num_tile_wires), find tile wire closest to dst_x/dst_y that has downhill pips (or is PINFEED intent)
   - If tile has sites: use inter coordinates
   - Else: tile coordinates
4. **Base formula**: `30 * min(|dx|, 18) + 10 * max(|dx|-18, 0) + 60 * min(|dy|, 6) + 20 * max(|dy|-6, 0) + 300`
5. If xc7: `base = (base * 3) / 2`
6. Adjustments: if dst in sink_locs → +1000; if PINFEED and same tile → -200; if LOCAL/PINBOUNCE and same tile → -100; if CLE_OUTPUT → -80

### predictDelay(BelId src_bel, IdString src_pin, BelId dst_bel, IdString dst_pin)
Used for timing-driven placement cost estimation.

- Same tile + same "slice" (`(z>>4)` match): return 0
- Same tile + different slice: FF2 penalty = 700; else = 150
- Different tiles: same `30*min(|dx|,18) + 10*max... + 60*min(|dy|,6) + 20*max... + 300` formula; if xc7 × 3/2

### getRouteBoundingBox(WireId src, WireId dst)
Returns `{x0, y0, x1, y1}` bounding box for routing.

- Start with src and dst tile coordinates
- Expand with `source_locs[src]` if present
- Expand with `sink_locs[dst]` if present, or site inter_x/y if dst is in a site
- If src is in a site: expand with site inter_x/y of dst's site (note: appears to use dst's site data — potential bug in original code)

### getBoundingBoxCost(WireId src, WireId dst, int distance)
- If src is pseudo (GND/VCC) → return 0
- If distance < 5 → return 0
- Else `(distance - 5) * 0` — always returns 0 (currently disabled)

---

## 16. PIP AVAILABILITY (checkPipAvail / usp_pip_hard_unavail)

`usp_pip_hard_unavail(PipId pip)` → bool. Returns true (hard unavailable) in these cases:

1. **Blacklisted pip**: `blacklist_pips[tile_type].count(pip.index)` — see §51
2. **PIP_SITE_ENTRY to INTENT_SITE_GND**: Only allowed if lowest LUT slots (BEL_5LUT=0, BEL_6LUT=0) are free
3. **PIP_CONST_DRIVER**: Same LUT slot check for ground driver
4. **PIP_SITE_INTERNAL with TRIBUF bel**: Always blocked
5. **PIP_SITE_INTERNAL with non-zero site_variant**: Blocked if tile's sitevariant for that site doesn't match pip's site_variant
6. **PIP_LUT_PERMUTATION**: Blocked if LUT at that eight is memory or SRL; allowed if from==to
7. **PIP_LUT_ROUTETHRU**:
   - If `eight == 0` → always blocked (ground conflict)
   - If `dest & 0x1` → blocked (routethru to MUX not supported)
   - Else blocked if either 6LUT or 5LUT at that eight is occupied

---

## 17. PACK FLOW (Arch::pack)

`Arch::pack()` dispatches to either `XC7Packer` or `USPacker` based on `xc7` flag.

### xc7 pack order:
1. `pack_constants()`
2. `pack_inverters()`
3. `pack_io()`
4. `prepare_clocking()`
5. `pack_constants()` ← second pass after IO/clocking transforms
6. `pack_iologic()`
7. `pack_idelayctrl()`
8. `pack_clocking()`
9. `pack_muxfs()`
10. `pack_carries()`
11. `pack_srls()`
12. `pack_luts()`
13. `pack_dram()`
14. `pack_bram()`
15. `pack_dsps()`
16. `pack_ffs()`
17. `finalise_muxfs()`
18. `pack_lutffs()`

### US+ pack order:
1. `pack_constants()`
2. `pack_inverters()`
3. `pack_io()`
4. `prepare_iologic()`
5. `prepare_clocking()`
6. `pack_constants()`
7. `pack_iologic()`
8. `pack_idelayctrl()`
9. `pack_clocking()`
10. `pack_muxfs()`
11. `pack_carries()`
12. `pack_luts()`
13. `pack_dram()`
14. `pack_bram()`
15. `pack_uram()`
16. `pack_dsps()`
17. `pack_ffs()`
18. `finalise_muxfs()`
19. `pack_lutffs()`

After packing: `assignArchInfo()`, set `attrs[id_step]="pack"`, call `archInfoToAttributes()`.

---

## 18. XILINXPACKER BASE

```cpp
struct XilinxPacker { Context *ctx; pool<IdString> packed_cells; vector<unique_ptr<CellInfo>> new_cells; int autoidx=0; ... }
```

### flush_cells()
- For each cell in `packed_cells`: disconnects all ports, erases from `ctx->cells`
- For each cell in `new_cells`: asserts not already in `ctx->cells`, inserts
- Clears both collections

### XFormRule
```cpp
struct XFormRule {
    IdString new_type;
    dict<IdString, IdString> port_xform;              // 1:1 port rename
    dict<IdString, vector<IdString>> port_multixform;  // 1:N port fanout
    dict<IdString, IdString> param_xform;              // parameter rename
    vector<pair<IdString,string>> set_attrs;           // forced attrs
    vector<pair<IdString,Property>> set_params;        // forced params
};
```

### xform_cell(rules, ci)
1. Sets `ci->attrs[id_X_ORIG_TYPE] = ci->type.str(ctx)`
2. Sets `ci->type = rule.new_type`
3. For each port: if in `port_multixform`: disconnect original, create multiple new ports with connections, set `X_ORIG_PORT_*` attrs; else rename (stripping `[]` if no explicit mapping), set `X_ORIG_PORT_*` attr
4. Applies `param_xform` (renames parameters)
5. Applies `set_attrs` and `set_params`

### generic_xform(rules, print_summary)
Iterates all cells, calls `xform_cell` for any cell whose type has a rule. Optionally prints summary.

### feed_through_lut(net, feed_users)
Creates a `LUT1` (INIT=2, i.e., buffer) with input connected to `net` and output to a new net. Reconnects `feed_users` to the new net. Net name: `net->name + "$legal$" + autoidx`. LUT name: same pattern.

### feed_through_muxf(net, type, feed_users)
Creates a MUXF7/8/9 cell with I0=`net`, S=GND, output to new net. Reconnects feed_users to new net.

### pack_inverters()
Converts all `INV` cells to `LUT1` with `INIT=1`, renaming port `I` → `I0`.

### is_constrained(cell)
Returns `cell->cluster != ClusterId()`.

### int_name(base, postfix, is_hierarchy)
Returns `base + "$subcell$" + postfix` (if hierarchy) or `base + "$intcell$" + postfix`.

### create_internal_net(base, postfix, is_hierarchy)
Creates a new NetInfo with name `base + "$subnet$" + postfix` (or `$intnet$`), inserts into `ctx->nets`, returns pointer.

### rename_net(old, newname)
Extracts net from `ctx->nets[old]`, changes its name, re-inserts at new key.

### tie_port(ci, port, value, inv)
Ensures port exists (creates if needed as PORT_IN). Connects to VCC if `value || inv`, GND otherwise. If `!value && inv`: sets `IS_<port>_INVERTED = 1`.

### invert_net(toinv)
- If driver is LUT1 with INIT=1 (inverter): returns the pre-inversion net; sweeps the LUT if single user
- Else: creates new LUT1 inverter, returns output net

### preplace_unique(cell)
If cell has no BEL constraint, finds first available BEL of matching type and constrains to it. Used for PSS_ALTO_CORE / PS7.

---

## 19. XC7PACKER

Extends `XilinxPacker`.

### XC7Packer::has_illegal_fanout(NetInfo* carry)
Returns true if:
- carry net has >2 users
- Multiple MUXCY users
- Multiple XORCY users
- Non-MUXCY/XORCY users
- MUXCY.CI user on wrong port
- Both MUXCY and XORCY present but their S/LI nets differ

### XC7Packer::pack_carries()
1. `split_carry4s()` — converts CARRY4 into chains of MUXCY/XORCY primitives
2. Finds root MUXCYs (those with no MUXCY driver or illegal fanout on CI)
3. Chains MUXCYs into `CarryGroup` structures; handles trailing XORCY
4. For non-chain exit: inserts feed-through LUT + XORCY + dummy MUXCY
5. Groups chains of 4 MUXCYs into `CARRY4` cells, constrained relative to root
6. y-constraint formula: `-(i/4 + i/(4*25))` — skips every 25th tile (tile height pattern in xc7)
7. LUT input budget check: total unique inputs across S-LUT + DI-LUT ≤ 5; if >5, clears di_lut; if S-LUT has >4 inputs, clears s_lut too
8. Creates feedthrough LUTs as needed
9. Blasts remaining MUXCY→LUT3(INIT=0xCA) and XORCY→LUT2(INIT=0x6)
10. Applies `c4_rules` renaming CI→CIN

**Split_carry4s()**: Converts each CARRY4 into 4 pairs of (MUXCY, XORCY). Initial carry-in taken from CI or CYINIT (prefers CYINIT if CI is GND or absent). New cell names: `original$split$muxcy0` etc.

---

## 20. USPACKER

Extends `XilinxPacker`.

### USPacker::has_illegal_fanout
Same logic as XC7Packer version.

### USPacker::pack_carries()
Nearly identical to XC7Packer but:
- Groups into CARRY8 (8 per group, not 4)
- y-constraint: `-(i/8)` — no skipping
- First CARRY8 in chain: CI maps to AX; subsequent: CI maps to CIN
- After transform: adds `EX` port connected to GND
- CARRY_TYPE param set to `"SINGLE_CY8"`

### USPacker::pack_bram()
Handles `RAMB18E2` and `RAMB36E2`. Key differences from xc7:
- `ECCPIPECE` maps to `ECCPIPECEL`
- SDP rules remap `WEBWE` bus differently
- Post-transform: ties extra `WEA2`/`WEA3` to VCC for RAMB18E2

### USPacker::pack_uram()
Simple XFormRule: `URAM288` and `URAM288_BASE` → `BEL_URAM288`.

### USPacker::pack_dsps()
Complex macro expansion:
1. Trims ACIN/BCIN/PCIN ports connected to GND (cascade ports)
2. Creates 8 sub-cells (one per `dsp_subcell_names` type)
3. Sub-cells are cluster-constrained relative to first sub-cell with `constr_z = subcell_index`
4. Moves ports from DSP48E2 to appropriate sub-cells by name
5. Copies params from DSP48E2 to all sub-cells
6. Records macro port mapping in `X_MACRO_PORTS_*` attributes
7. Expands bus ports via `generic_xform`

---

## 21. CELL TYPE TRANSFORMATIONS (XFormRule)

### LUT rules (in pack_luts):
`LUT1..LUT6` → `SLICE_LUTX`:
- Port `I0..I(k-1)` → `A1..Ak`
- Port `O` → `O6`
`LUT6_2` → same as LUT6

### FF rules (in pack_ffs):
All FD types → `SLICE_FFX`:
- `FDCE/FDPE/FDRE/FDSE`: `C` → `CK` (xc7) or `CLK` (US+); CLR/PRE/R/S → `SR`
- `FDRE`/`FDSE`: set attr `X_FFSYNC = "1"`
- `FDCE_1/FDPE_1/FDRE_1/FDSE_1`: same + set param `IS_C_INVERTED = 1`

### MuxF rules (in finalise_muxfs):
- `MUXF7` → `SELMUX2_1` (xc7) or `F7MUX` (US+); ports `I0→0`, `I1→1`, `S→S0`, `O→OUT`
- `MUXF8` → `SELMUX2_1` or `F8MUX`; same port mapping
- `MUXF9` → `F9MUX`; same

### SRL rules (in pack_srls):
- `SRL16E` → `SLICE_LUTX`: `CLK→CLK`, `CE→WE`, `D→DI2`, `Q→O6`; attr `X_LUT_AS_SRL="1"`; A inputs shifted up by 2, A1 and A6 tied to VCC
- `SRLC32E` → `SLICE_LUTX`: `CLK→CLK`, `CE→WE`, `D→DI1`, `Q→O6`; attr `X_LUT_AS_SRL="1"`; A inputs shifted up by 2, A1 tied to VCC

### DRAM rules:
- `RAMD64E` → `SLICE_LUTX`: `RADR0-5→A1-6`, `WADR0-7→WA1-8`, `I→DI1`, `O→O6`, `IS_CLK_INVERTED↔IS_WCLK_INVERTED`
- `RAMD32` (6LUT mode): `RADR0-4→A1-5`, `WADR0-4→WA1-5`, `I→DI2`, `O→O6`
- `RAMD32` (5LUT mode): same but `I→DI1`, `O→O5`

### BRAM rules:
- xc7: `RAMB18E1→RAMB18E1_RAMB18E1`, `RAMB36E1→RAMB36E1_RAMB36E1`
- US+: `RAMB18E2→RAMB18E2_RAMB18E2`, `RAMB36E2→RAMB36E2_RAMB36E2`
- WEA port multixform: `WEA[0]→{WEA0,WEA1}`, `WEA[1]→{WEA2,WEA3}`

### IO rules (xc7):
- `OBUF→IOB33_OUTBUF`: `I→IN`, `O→OUT`, `T→TRI`
- `IBUF→IOB33_INBUF_EN`: `I→PAD`, `O→OUT`
- HP bank variants: `IBUF→IOB18_INBUF_DCIEN`, `OBUF→IOB18_OUTBUF_DCIEN`
- `PAD→PAD` (identity), `INV→INVERTER` (`I→IN`, `O→OUT`), `PS7→PS7_PS7`

### IO rules (US+):
- `PAD→IOB_PAD`, `OBUF→IOB_OUTBUF`, `OBUFT→IOB_OUTBUF` (`T→TRI`), `OBUFT_DCIEN→IOB_OUTBUF` (`T→TRI`)
- `INBUF→IOB_INBUF`, `IBUFCTRL→IOB_IBUFCTRL` (`T→TRI`), `DIFFINBUF→IOB_DIFFINBUF`
- `INV→HPIO_OUTINV` (`I→IN`, `O→OUT`), `PS8→PSS_ALTO_CORE`

---

## 22. LUT PACKING

`pack_luts()`: Applies LUT rules (§21). Calls `generic_xform(lut_rules, true)`.

**LUT6_2**: Both O5 and O6 outputs used from same LUT configuration. Treated same as LUT6.

---

## 23. FF PACKING

`pack_ffs()`: Applies FF rules (§21). Calls `generic_xform(ff_rules, true)`.

`pack_lutffs()`: Constrains LUT-FF pairs when FF is directly fed by LUT's O6 output.
- Iterates cells looking for unconstrained `SLICE_FFX`
- If D is driven by `SLICE_LUTX` O6, and that LUT is unconstrained:
  - Sets `lut->cluster = lut->name`; `ff->cluster = lut->name`
  - `ff->constr_x=0, constr_y=0, constr_z = BEL_FF - BEL_6LUT = 0x2 - 0x0 = 2`
- Reports count of constrained pairs

---

## 24. CARRY CHAIN PACKING (xc7 & US+)

### split_carry4s() (shared in XilinxPacker)
Iterates all `CARRY4` cells. For each:
- Gets CI or CYINIT (prefers CYINIT if CI absent/GND)
- For i=0..3: creates XORCY and MUXCY
  - MUXCY gets CI, DI[i], and shares S[i] with XORCY LI
  - XORCY gets O[i]
  - CO[i] becomes the new CI for next iteration (created internally if no user)

### pack_carries() flow (both xc7 and US+):
1. `split_carry4s()`
2. Find root MUXCYs (no MUXCY driver, or illegal fanout)
3. Build CarryGroup chains
4. Handle chain termination:
   - If trailing XORCY: create dummy MUXCY, pack it
   - If other users: create zero LUT + feed_xorcy + dummy MUXCY for chain output
5. Group into CARRY4 (xc7) or CARRY8 (US+) cells
6. Apply constraints relative to root
7. Check S and DI LUT eligibility; create feedthrough LUTs as needed
8. Blast unchained MUXCY/XORCY to soft logic
9. Apply final `c4_rules` or `c8_rules` for port renaming

### CARRY4 constraint y formula (xc7):
`c4->constr_y = -(i/4 + i/(4*25))` — the `i/(4*25)` skips a tile every 25 CARRY4s (100 MUXCYs), matching the physical tile skip in xc7 fabric.

### CARRY8 constraint y formula (US+):
`c8->constr_y = -i/8` — simple, no skipping needed.

---

## 25. MUXF TREE PACKING

`pack_muxfs()`:
1. Find mux roots: MUXF9 (all), MUXF8 (if O not driving a MUXF9), MUXF7 (if O not driving a MUXF8)
2. Mark roots with `MUX_TREE_ROOT = 1` attr
3. For each root: `legalise_muxf_tree(root, mux_roots)` — inserts feedthrough LUTs or MUXFs where inputs are wrong type or constrained
4. For each root: `constrain_muxf_tree(root, root, 0)` — assigns cluster constraints

### legalise_muxf_tree(curr, mux_roots):
For each input (I0, I1):
- If curr is MUXF7: input must be unconstrained LUT; if not, insert feedthrough LUT
- If curr is MUXF8: input must be unconstrained MUXF7; if not, insert feedthrough MUXF7
- If curr is MUXF9: input must be unconstrained MUXF8; if not, insert feedthrough MUXF8
- Recurse into inputs

### constrain_muxf_tree(curr, base, zoffset):
- `base_z`: F7MUX=BEL_F7MUX, F8MUX=BEL_F8MUX, F9MUX=BEL_F9MUX, else=constr_z
- `curr_z = zoffset * 16 + bel_type`
- input_spacing: MUXF7=1, MUXF8=2, MUXF9=4
- Recurse: I0 → `zoffset + input_spacing`, I1 → `zoffset`

### create_muxf_tree(base, name_base, data, select, out, zoffset):
Builds a binary mux tree from `data` nets using `select` signals. Creates intermediate nets and MUXF7/8/9 cells. Calls `constrain_muxf_tree` on the root.

### finalise_muxfs():
Applies type renames (§21) via `generic_xform`.

---

## 26. DRAM PACKING

`pack_dram()` in XilinxPacker.

**DRAMType struct**: `{abits, dbits, rports}`. Registered for: RAM32X1S(5,1,0), RAM32X1D(5,1,1), RAM64X1S(6,1,0), RAM64X1D(6,1,1), RAM128X1S(7,1,0), RAM128X1D(7,1,1), RAM256X1S(8,1,0), RAM256X1D(8,1,1), RAM512X1S(9,1,0), RAM512X1D(9,1,1).

**DRAMControlSet struct**: `{wa[], wclk, we, wclk_inv, memtype}`. Used as dict key (with hash/eq).

**Address inversion optimization**: Tied-low address inputs (GND) are converted to VCC + INIT bit-inversion. Avoids routing GND.

**Grouping**: Cells with same DRAMControlSet are grouped together to share address/control infrastructure.

### RAM64X1D:
- Height = 8 (US+) or 4 (xc7)
- Top cell (z=height-1): write-address-only `RAMD64E` (no output)
- Remaining cells: SPO goes to z=height-2 (folded into address buffer if possible) and DPO with DPRA addresses at lower z values

### RAM32X1D:
- Same but adds `GND` as A6/DPRA5 (lower 5 bits only)

### RAM128X1D / RAM256X1D:
- Split into 2 (128) or 4 (256) write-address RAMD64E cells + MUXF7/F8 decode tree for both SPO and DPO ports

### RAM64M / RAM32M (whole-slice):
- 4 independent data bits, each a separate RAMD64E or RAMD32 LUT
- zoffset = 4 for xc7 (upper half), 0 for US+ (lower half)

### RAMD64E → SLICE_LUTX transform (dram_rules):
See §21.

---

## 27. BRAM PACKING

### XC7Packer::pack_bram()
1. Defines TDP rules: `RAMB18E1→RAMB18E1_RAMB18E1`, `RAMB36E1→RAMB36E1_RAMB36E1`
2. WEA multi-xform: `WEA[0]→{WEA0,WEA1}`, `WEA[1]→{WEA2,WEA3}`
3. Handles ul_pins for 36-bit mode (upper/lower split)
4. SDP rules: remap WEBWE to duplicate pins, clear WEA
5. First pass: detect SDP mode (`WRITE_WIDTH_B == 36 or 72`), apply SDP rules
6. Byte-enable rewrite based on write width
7. Apply TDP rules to remaining cells
8. Post-transform fixes: tie ADDRATIEHIGH/ADDRBTIEHIGH to VCC; handle WEA width; tie unused WEBWE to GND; special 1-bit write width handling for RAMB36E1

### USPacker::pack_bram()
Same structure but for E2 variants. Differences:
- `ECCPIPECE → ECCPIPECEL`
- Post-transform: tie `WEA2/WEA3` to VCC for RAMB18E2 (not GND)

---

## 28. DSP PACKING

### XC7Packer::pack_dsps()
1. XFormRule: `DSP48E1 → DSP48E1_DSP48E1`
2. Scan all DSP48E1 cells: collect constant-driven ports (D/RSTD/CARRYINSEL2/etc.) into `DSP_GND_PINS` and `DSP_VCC_PINS` attrs, then disconnect from constant nets
3. ACIN/BCIN/PCIN ports connected to GND are disconnected (cascade unused)
4. Find root DSPs (no cascade input used)
5. For each root: `walk_dsp(root, root, BEL_UPPER_DSP)`

### walk_dsp(root, current_cell, constr_z):
Recursively follows COUT cascade outputs. Each cascaded cell is cluster-constrained:
- `constr_y = previous_y + (is_lower_bel ? -5 : 0)` — lower bel jumps 5 tiles up
- `constr_z = constr_z` alternating BEL_LOWER_DSP ↔ BEL_UPPER_DSP
- Error if cascaded cell conflicts or COUT drives multiple users

### USPacker::pack_dsps()
1. Trim cascade inputs tied to GND
2. Expand DSP48E2 to 8 sub-cells (DSP_PREADD_DATA through DSP_OUTPUT)
3. Sub-cells 1-7 cluster relative to sub-cell 0 at constr_z=0..7
4. Port routing: A[0:29]→DSP_A_B_DATA, B[0:17]→DSP_A_B_DATA, C[0:47]→DSP_C_DATA, D[0:26]→DSP_PREADD_DATA/DIN
5. Remaining ports: connect to whichever sub-cell has that port
6. Params copied to all sub-cells
7. Macro port attrs recorded
8. Final `generic_xform` for bus port expansion

---

## 29. IO PACKING (xc7)

### XC7Packer::pack_io()
1. `ctx->setup_byname()` — called explicitly first
2. `get_top_level_pins(ctx, toplevel_ports)` — populates IO port recognition dict
3. For each `$nextpnr_ibuf/obuf/iobuf`: call `insert_pad_and_buf(ci)` → creates PAD cell and iobuf
4. `flush_cells()`
5. Assign package pin constraints: if `PACKAGE_PIN` attr → `LOC`; look up site; for RIOB18 tiles → `site/IOB18/PAD`, else `site/IOB33/PAD`
6. Assign unconstrained IOs from `available_io_bels` queue
7. For each iob: `decompose_iob(iob.second.cell, true, iostandard)`
8. `flush_cells()`
9. Apply `hriobuf_rules` or `hpiobuf_rules` based on BEL name (IOB33 vs IOB18)
10. Apply `hrio_rules` (PAD, INV, PS7)
11. Post-xform: replace leading "IOB33"/"IOB18" in type with X_IOB_SITE_TYPE attr value

### decompose_iob (xc7):
Handles: `IBUF/IBUF_IBUFDISABLE/IBUF_INTERMDISABLE` (se_ibuf), `IOBUF/IOBUF_DCIEN/IOBUF_INTERMDISABLE` (se_iobuf), `OBUF/OBUFT` (se_obuf), `IBUFDS/IBUFDS_INTERMDISABLE/IBUFDS` (diff_ibuf), `IOBUFDS/IOBUFDS_DCIEN` (diff_iobuf), `OBUFDS/OBUFTDS` (diff_obuf).

For se_ibuf/se_iobuf: `insert_ibuf` → BEL = `site/IOB33/INBUF_EN` (or IOB18 variant); for se_obuf/se_iobuf: `insert_obuf` → BEL = `site/IOB33/OUTBUF`.

For diff: `insert_diffibuf` → BEL = `site_p/IOB33M/INBUF_EN`; obuf_p = `site_p/IOB33M/OUTBUF`; create `O_ININV` inverter at `site_n/IOB33S/O_ININV`; obuf_n = `site_n/IOB33S/OUTBUF`.

**Site lookup helpers** (xc7):
- `get_ologic_site(io_bel)`: BFS backwards from OUTBUF/IN pin, finds first OLOGIC site
- `get_ilogic_site(io_bel)`: BFS forwards from INBUF/OUT pin, finds first ILOGIC site
- `get_idelay_site(io_bel)`: BFS forwards from INBUF/OUT, finds IDELAY site
- `get_odelay_site(io_bel)`: BFS backwards from OUTBUF/IN, finds ODELAY site (IOB18 only)
- `get_ioctrl_site(io_bel)`: Gets HCLK tile for IOB, scans its sites for IDELAYCTRL

---

## 30. IO PACKING (US+)

### USPacker::pack_io()
Similar flow but simpler site naming:
- PAD constraint: `site + "/PAD"` (no IOB33/IOB18 qualifier)
- Uses `id_IOB_PAD` (not `id_PAD`) for available IO BEL filtering

### decompose_iob (US+):
- se_ibuf/se_iobuf: `insert_inbuf` → BEL = `site/INBUF`; `insert_ibufctrl` → BEL = `site/IBUFCTRL`. For se_iobuf, IBUFCTRL.T gets connected.
- se_obuf/se_iobuf: `insert_obuf` → BEL = `site/OUTBUF`
- diff: `insert_diffinbuf` → BEL = `site_dibuf/DIFFINBUF` (site found by walking PADOUT wire downhill); `insert_ibufctrl` for positive and negative channels
- diff pseudo-output: `insert_outinv` → BEL = `site_p/OUTINV`; obuf_p → `site_p/OUTBUF`; obuf_n → `site_n/OUTBUF`

**`diffinbuf_site(site_p)`**: Walks PADOUT bel's OUT wire downhill until a BEL pin is found; returns that bel's site.

**Site lookup helpers (US+)**:
- `get_iol_site(io_bel)`: BFS from IBUFCTRL.O downhill until bel pin found (not same wire)
- `get_ioctrl_site(iol_bel)`: Walks `RXTX_BITSLICE/TX_BIT_CTRL_OUT0` downhill to find CONTROL site

---

## 31. IOLOGIC PACKING (xc7)

### XC7Packer::pack_iologic()
Processes: `IDELAYE2`, `ODELAYE2`, `ODDR`, `OSERDESE2`, `IDDR`, `ISERDESE2`.

**IDELAYE2**: Finds INBUF_EN/INBUF_DCIEN driver of IDATAIN. Gets `idelay_site`. BEL = `iol_site/IDELAYE2`.

**ODELAYE2**: Finds OUTBUF driver of DATAOUT. Gets `odelay_site`. BEL = `iol_site/ODELAYE2`.

**ODDR**:
- Finds OUTBUF or ODELAY user of Q
- Determines if driving TRI (tristate) vs data output
- Rule: `IOB18` → OLOGICE2_TFF or OLOGICE2_OUTFF; else → OLOGICE3_TFF or OLOGICE3_OUTFF
- `C→CK`, `S/R→SR`
- BEL = `ol_site/TFF` or `ol_site/OUTFF`

**OSERDESE2**: Finds OUTBUF via Q or OFB. BEL = `ol_site/OSERDESE2`.

**IDDR**: `fold_inverter(ci, "C")` first. Finds INBUF or IDELAYE2 driver of D. `C→{CK,CKB}`, `S/R→SR`. BEL = `iol_site/IFF`.

**ISERDESE2**: `fold_inverter(ci, "CLKB")`, `fold_inverter(ci, "OCLKB")`. IOBDELAY=IFD uses DDLY input; IOBDELAY=NONE uses D. BEL = `iol_site/ISERDESE2`.

**fold_inverter(cell, port)**: If port is driven by `LUT1(INIT=1)` or `INV`, folds inversion into cell: disconnects port from inverted net, reconnects to pre-inversion net, sets `IS_<port>_INVERTED=1`. Sweeps the inverter cell if no other users.

### iologic_rules (xc7):
- `IDDR → ILOGICE3_IFF`: `C→{CK,CKB}`, `S/R→SR`
- `ISERDESE2 → ISERDESE2_ISERDESE2`
- `OSERDESE2 → OSERDESE2_OSERDESE2`
- `IDELAYE2 → IDELAYE2_IDELAYE2`
- `ODELAYE2 → ODELAYE2_ODELAYE2`

---

## 32. IOLOGIC PACKING (US+)

### USPacker::prepare_iologic()
- Converts `ODDRE1` → `OSERDESE3` with `ODDR_MODE="TRUE"`; renames ports: `C→CLK`, `SR→RST`, `D1→D[0]`, `D2→D[4]`, `Q→OQ`

### USPacker::pack_iologic()
Processes IDELAYE3, ODELAYE3, IDDRE1/ISERDESE3, OSERDESE3.

**IDELAYE3**: Finds IOB_IBUFCTRL driver of IDATAIN. Gets iol_site. If HPIO: `hp_iol_rules`, BEL=`iol_site/IDELAY`. Non-HPIO: error.

**ODELAYE3**: Finds IOB_OUTBUF user of DATAOUT. Gets iol_site. If HPIO: `hp_iol_rules`, BEL=`iol_site/ODELAY`.

**IDDRE1/ISERDESE3**: Finds IOB_IBUFCTRL or IDELAYE3 driver of D. HPIO: `hp_iol_rules`, BEL=`iol_site/ISERDES` (adds IFD_CE=GND); HDIO: `hd_iol_rules`, BEL=`iol_site/IDDR`.

**OSERDESE3**: Finds IOB_OUTBUF or ODELAYE3 user of OQ. HPIO: RST special-case (GND→VCC + inversion), `hp_iol_rules`, BEL=`iol_site/OSERDES` (adds OFD_CE=GND); HDIO: disconnect T, `hd_iol_rules`, BEL=`iol_site/OPTFF`.

### HP vs HD IO rules (US+):
- hp: `IDDRE1→ISERDESE3` (`C→CLK`, `CB→CLK_B`, `R→RST`, `Q1→Q0`, `Q2→Q1`); `OSERDESE3→OSERDESE3`; `IDELAYE3→IDELAYE3`; `ODELAYE3→ODELAYE3`
- hd: `IDDRE1→IOL_IDDR` (`C→CK`, `CB→CK_C`, `R→RST`); `OSERDESE3→IOL_OPTFF` (`CLK→CK`, `D[0]→D1`, `D[4]→D2`)

---

## 33. IDELAYCTRL PACKING

Both xc7 and US+ versions follow the same pattern:

1. Find single IDELAYCTRL cell (error if >1)
2. Find all IDELAYE2/ODELAYE2 (xc7) or IDELAYE3/ODELAYE3 (US+) cells with BEL attrs; collect unique ioctrl sites
3. Error if no IDELAY cells found
4. For each ioctrl site: create duplicate IDELAYCTRL, connect REFCLK and RST, optionally connect RDY
5. If multiple sites and RDY net: AND-gate all duplicate RDY signals using LUT2 cells (INIT=8 = AND2)
6. Disconnect original IDELAYCTRL from REFCLK/RST, mark for packing removal

xc7 post-transform: `IDELAYCTRL → IDELAYCTRL_IDELAYCTRL`.
US+ post-transform: `IDELAYCTRL → BITSLICE_CONTROL_BEL` with `RDY → VTC_RDY`.

---

## 34. CLOCKING (xc7)

### XC7Packer::prepare_clocking()
Upgrades: `MMCME2_BASE→MMCME2_ADV`, `PLLE2_BASE→PLLE2_ADV`.
`BUFG → BUFGCTRL`: renames `I→I0`; ties CE0=high-inverted(S0-true), S0=high-inverted, S1=low-inverted, IGNORE0=high-inverted.
`BUFGCE → BUFGCTRL`: renames `I→I0`, `CE→CE0`; ties S0=high-inverted, S1=low-inverted, IGNORE0=high-inverted.
Records used BELs from BEL attrs.

### XC7Packer::pack_plls()
`MMCME2_ADV → MMCME2_ADV_MMCME2_ADV`, `PLLE2_ADV → PLLE2_ADV_PLLE2_ADV`.
For MMCM_MMCM_TOP: sets default params (CLKIN periods, CLKOUT divide/phase/duty_cycle, COMPENSATION). If COMPENSATION=INTERNAL: disconnects CLKFBIN, connects to VCC.
Preplaces: `try_preplace(ci, id_CLKIN1)`.

### XC7Packer::pack_gbs()
`BUFGCTRL` (identity transform). Preplaces via `try_preplace(ci, id_I0)`.
Preplaces PS7 first (`preplace_unique`).
Also preplaces `BUFG_BUFG` via `try_preplace(ci, id_I)`.

---

## 35. CLOCKING (US+)

### USPacker::prepare_clocking()
Upgrades: `MMCME2_ADV→MMCME4_ADV`, `MMCME4_BASIC→MMCME4_ADV`, `PLLE4_BASIC→PLLE4_ADV`, `BUFG→BUFGCE`.

### USPacker::pack_plls()
`MMCME4_ADV → MMCM_MMCM_TOP`, `PLLE4_ADV → PLL_PLL_TOP`.
Same CLKFBIN fix for INTERNAL compensation.
`try_preplace(ci, id_CLKIN1)`.

### USPacker::pack_gbs()
`BUFGCTRL→BUFGCTRL`, `BUFG_PS→BUFCE_BUFG_PS`, `BUFGCE_DIV→BUFGCE_DIV_BUFGCE_DIV`, `BUFGCE→BUFCE_BUFCE`.
Preplaces PSS_ALTO_CORE first.
Preplaces buffer types via `try_preplace(ci, id_I0)` or `id_I`.

### try_preplace(cell, port):
1. If cell already has BEL attr → return
2. Get net on `port`; if no net or no driver → return
3. If driver has no BEL attr → return
4. Get driver BEL wire; if no wire → return
5. BFS downhill from driver wire up to 50000 visits; find first unconstrained BEL of matching type with matching belpin == port
6. If found: set BEL attr, add to `used_bels`

---

## 36. CONSTANT / TIED-PIN HANDLING

### pack_constants()
1. Lazy-loads `tied_pins` and `invertible_pins` if empty
2. Creates `$PACKER_GND_DRV` cell (type PSEUDO_GND, port Y) and `$PACKER_GND_NET` net if not already present. Same for VCC.
3. Collects `const_ports`: ports from `tied_pins` that aren't already driven; also GND/VCC cell outputs from synthesis
4. For each `const_port`:
   - Creates port if needed
   - If existing net is undriven: disconnect
   - If `!cval && invertible_pins.count(ci->type) && invertible_pins.at(ci->type).count(pname)`: sets `IS_<pname>_INVERTED=1`, flips cval to true (GND→VCC+inversion optimization)
   - Connects to GND or VCC net
5. Erases dead (GND/VCC-driver) nets

### Invertible pins optimization
When a pin has an `IS_x_INVERTED` parameter AND the pin is being tied to GND, the tool instead ties it to VCC and sets the inversion parameter. This is more routable because VCC has global distribution while GND routing may be constrained.

**Exception**: Certain pins are explicitly NOT in `invertible_pins` to prevent this optimization:
- `IDELAYE2.IDATAIN` — no routing arc from PSEUDO_VCC to IDELAY/IDATAIN in chipdb
- `ISERDESE2.CLKDIVP` — no IS_CLKDIVP_INVERTED parameter exists; no routing arc

### get_tied_pins
Large function in `pins.cc` defining default pin values. Key entries:
- RAMB18E2/RAMB36E2: WEA/WEBWE tied VCC; CLK/EN/RST tied GND; REGCE tied VCC; CASDOMUX tied GND
- RAMB18E1/RAMB36E1: similar
- BUFGCTRL: S0/S1/IGNORE0/IGNORE1/CE0/CE1 tied GND
- URAM288: RST_A/B GND; EN_A/B VCC; BWE VCC; OREG_CE VCC
- DSP48E2: all RST pins GND; CE pins VCC; A/B/C/D/ALUMODE/etc. GND
- DSP48E1: similar but CE pins GND (not VCC)
- MMCME4_ADV/PLLE2_ADV/MMCME2_ADV: various clock/control pins with documented defaults
- IO primitives: specific DCITERMDISABLE/OSC_EN/etc.

### get_invertible_pins
Large function in `pins.cc`. Covers BUFGCTRL, all FD types, SRLs, DSP48E1/E2, FIFO, IDDR, ODDR, IDELAYE2, ODELAYE2, ISERDESE2, OSERDESE2, MMCM, PLL, BRAM, OSERDESE3, IDDRE1, IDELAYE3, ODELAYE3, many GTs, URAM288, etc.

---

## 37. ROUTE FLOW (Arch::route)

```cpp
bool Arch::route()
```
1. `assign_budget(getCtx(), true)` — timing-driven budget assignment
2. Determine router from settings (`id_router`, default `"router2"`)
3. If not router2: `routeVcc()`
4. `routeClock()` — always
5. `findSourceSinkLocations()` — always
6. If `"router1"`: `router1(getCtx(), Router1Cfg(getCtx()))`
7. If `"router2"`: `Router2Cfg cfg; cfg.bb_margin_x=4; cfg.bb_margin_y=4; cfg.backwards_max_iter=200; cfg.perf_profile=true; router2(getCtx(), cfg); result=true`
8. `fixupRouting()`
9. Set `settings[id_route] = 1`
10. `archInfoToAttributes()`

---

## 38. ROUTEVCC

`Arch::routeVcc()`: Special BFS routing for the `$PACKER_VCC_NET` pseudo-net.

1. Binds the VCC net's source wire with STRENGTH_STRONG
2. For each user: BFS **uphill** from sink wire
3. BFS termination: reach a wire already bound to VCC net
4. Trace back via backtrace dict; bind each wire and pip with STRENGTH_STRONG
5. If user's pin has no sink wire → fatal error

**Why uphill BFS**: Avoids flood-fill from VCC source. Finds shortest path from each sink backwards to the already-routed VCC tree.

---

## 39. ROUTECLOCK

`Arch::routeClock()`: Routes global clock nets using dedicated resources.

**Global net detection** (returns early if not global):
- Driver cell type in `{BUFGCTRL, BUFCE_BUFG_PS, BUFCE_BUFCE, BUFGCE_DIV_BUFGCE_DIV}` with port O
- PLLE2_ADV with single user that is BUFGCTRL/BUFCE_BUFCE/BUFGCE_DIV
- Single user that is PLLE2_ADV on port CLKIN1

**Routing**:
1. Bind source wire with STRENGTH_LOCKED
2. For each user: BFS uphill from sink wire
3. **Wire filtering**: rejects wires with intents `ID_NODE_DOUBLE`, `ID_NODE_HLONG`, `ID_NODE_HQUAD`, `ID_NODE_VLONG`, `ID_NODE_VQUAD`, `ID_NODE_SINGLE`, `ID_NODE_CLE_OUTPUT`, `ID_NODE_OPTDELAY`, and xc7-specific `ID_BENTQUAD`, `ID_DOUBLE`, `ID_HLONG`, etc. — only uses dedicated clock resources
4. If no route found with dedicated resources:
   - For single-user PLLE2_ADV CLKIN1: retry with no wire filter (lenient fallback)
   - Else: just continues (may route later by main router)
5. If route found: bind all wires and pips with STRENGTH_LOCKED

---

## 40. FINDSOURCESINKSLOCATIONS

`Arch::findSourceSinkLocations()`:

**Sink locations**: For each net's user port:
- Skip if cell BEL is unset, is a logic tile, or (xc7 only) is BRAM tile
- BFS **uphill** from sink wire, limit 500 iterations
- When a non-site wire with "routing" intent is found (not PINFEED/VCC/GND/DEFAULT/DEDICATED/OPTDELAY/INPUT):
  - Store `sink_locs[sink] = Loc(tile_x, tile_y, 0)`
  - Also populate all wires on the backtrace path

**Source locations**: For each net's driver:
- BFS **downhill** from source wire, limit 500 iterations
- When non-site wire with "routing" intent found (not PINFEED/VCC/GND/DEFAULT/DEDICATED/OPTDELAY/OUTPUT/INT_INTERFACE):
  - Store `source_locs[source] = Loc(tile_x, tile_y, 0)`

**Purpose**: Improves delay estimation by providing actual interconnect anchor locations rather than BEL grid locations, important for IO cells whose BELs are far from the INT tile.

---

## 41. FIXUPPLACEMENT

`Arch::fixupPlacement()`:

### Part 1: LUT input re-assignment
For each tile with logic, for each z position with a 5LUT:
1. Collect input signal sets for 5LUT and 6LUT
2. If memory or SRL: connect A6 of 6LUT to VCC; skip re-assignment
3. Disconnect all A1-A6 ports from both LUTs; erase X_ORIG_PORT attrs
4. Re-assign: iterate unique inputs from both LUTs; assign sequential ports A1, A2, ... to both LUTs; record X_ORIG_PORT mapping
5. Rename 5LUT's O6→O5; update X_ORIG_PORT_O5/O6
6. Connect A6 of 6LUT to VCC

### Part 2: PSS_ALTO_CORE (US+ PS) pin tying
Ties all unconnected input pins to GND or VCC. Special-cases:
- Skips PAD-related pins (`_PAD_` in name)
- Skips PSVERSION/PSSGTS/PSSGPWRDWNB etc.
- VCC for NIRQ/NFIQ pins, SSIN/WP/RSOP/REOP/GMIITXCLK/DPVIDEOINCLK/DPSAXISAUDIOCLK
- GND otherwise

### Part 3: PS7_PS7 (xc7 PS) pin tying
Ties all unconnected input pins to GND except: PAD pins, TEST/DEBUGSELECT/MIO/DDR pins.

### Part 4: BITSLICE_CONTROL_BEL pin tying
Ties specific pins: `EN_VTC`=VCC, `DLY_TEST_IN`/`RIU_NIBBLE_SEL`/`TBYTE_IN0-3`=GND.

### Part 5: Reserved wires (US+ only)
For each tile with logic, for each of 8 z-positions:
- Computes `x_net` and `i_net` from LUT DI nets, mux sel nets, CARRY8 x_sigs, indirect FF connections
- If `x_net != nullptr`: finds PINBOUNCE wire for `"<letter>X"` signal; adds to `reserved_wires`
- If `i_net != nullptr`: finds PINBOUNCE wire for `"<letter>_I"` signal; adds to `reserved_wires`

**`get_bouncewire(tile, swname)`**: Finds site wire by name, then walks uphill until `wireIntent == ID_NODE_PINBOUNCE`.

---

## 42. FIXUPROUTING

`Arch::fixupRouting()`:

### Part 1: LUT permutation application
1. Collects all `PIP_LUT_PERMUTATION` pips used across all nets into `used_perm_pips[tile]`
2. For each tile with permutation pips, for each z with a LUT:
   - Decodes `extra_data`: `z = (extra_data>>8)&0xF`, `from_port = ports[(extra_data>>4)&0xF]`, `to_port = ports[extra_data&0xF]`
   - Records `new_connections[from_port].push_back(to_port)`
   - Saves original nets and X_ORIG_PORT attrs
   - Disconnects and reconnects according to new_connections
   - Updates X_ORIG_PORT attrs (concatenates original port strings)

### Part 2: PAD net routing
For cells of type `IOB_PAD`:
- Unbinds all currently bound wires on the PAD net
- Rebinds PAD wire with STRENGTH_LOCKED
- Routes from driver wire to PAD wire via `route_bfs`
- Routes from PAD wire to each user's sink wire via `route_bfs`

`route_bfs(net, src, dst)`: BFS uphill from dst until src is found as a pip source. Traces back binding wires and pips.

### Part 3: OSERDESE3 T_BYPASS
For cells of type OSERDESE3 with no T_OUT port: sets `OSERDES_T_BYPASS = "TRUE"`.

---

## 43. FASM BACKEND (writeFasm)

`Arch::writeFasm(filename)` creates a `FasmBackend` and calls `be.write_fasm()`.

`write_fasm()` call order: `get_invertible_pins`, `write_logic`, `write_io`, `write_routing`, `write_bram`, `write_clocking`, `write_ip`.

### FasmBackend state:
- `ctx`: context pointer
- `out`: output stream
- `fasm_ctx`: stack of strings for hierarchical prefix (`.`-separated)
- `pips_by_tile`: `dict<int, vector<PipId>>` populated by `write_pip` calls
- `invertible_pins`: loaded from `get_invertible_pins`
- `pp_config`: pseudo-pip config map (from `get_pseudo_pip_data`)
- `last_was_blank`: blank line tracking

### Prefix helpers:
- `push(x)` / `pop()` / `pop(N)`: manage `fasm_ctx` stack
- `write_prefix()`: writes all stack elements joined by `.`
- `write_bit(name, value=true)`: writes `prefix.name` if value is true
- `write_vector(name, bits, invert)`: writes `prefix.name = N'b...`
- `write_int_vector(name, value, width, invert)`: converts integer to bit vector

### write_logic():
For each tile with logic cells: calls `write_luts_config(tile, 0)`, `write_luts_config(tile, 1)`, `write_ffs_config(tile, 0)`, `write_ffs_config(tile, 1)`, `write_carry_config(tile, 0)`, `write_carry_config(tile, 1)`.

**write_luts_config(tile, half)**:
- Pushes tile name and half name (`get_half_name(half, is_mtile)`)
- For each LUT position (ALUT..DLUT):
  - Writes `INIT[63:0]` via `get_lut_init(lut6, lut5)`
  - Writes SMALL/RAM/SRL mode bits
  - Writes DI1MUX routing for SLICEM
- Writes WA7USED, WA8USED, WEMUX for SLICEM

**get_lut_init(lut6, lut5)**:
Returns 64 bits computed from LUT INIT parameter and X_ORIG_PORT mapping. For fracturable (both present): lower 32 bits from lut5, upper 32 from lut6. Logical-to-physical input mapping applied via phys_to_log dict.

**write_ffs_config(tile, half)**:
- Tracks found_ff, negedge_ff, is_latch, is_sync, is_clkinv, is_srused, is_ceused (shared across half)
- For each FF cell: writes ZINI, ZRST bits; determines type from X_ORIG_TYPE (FDRE/FDSE/FDCE/FDPE with _1 variants); tracks shared properties
- Writes LATCH, FFSYNC, CLKINV, NOCLKINV, SRUSEDMUX, CEUSEDMUX

**write_carry_config(tile, half)**:
Writes PRECYINIT routing for CARRY4's PRECYINIT_OUT site wire. Writes CARRY4 CY0 routing for each column (ABCD).

**get_half_name(half, is_m)**:
- is_m (CLBLM tile): `"SLICEM_X0"` for half=0, `"SLICEL_X1"` for half=1
- else: `"SLICEL_X0"` or `"SLICEL_X1"`

### write_routing():
Calls `get_pseudo_pip_data()` first.
For each net's wires: if pip != PipId(), calls `write_pip(pip, ni)`.

**write_pip(pip, net)**:
- Skips PSEUDO_GND/VCC dst intent
- Skips non-TILE_ROUTING and non-SITE_INTERNAL flags
- For SITE_INTERNAL with T1→T1INV_OUT: writes ZINV_T1 bit (router1 specific)
- For TILE_ROUTING with pseudo-pip config: writes all config strings from pp_config; handles SING IOI3 top/bottom flip
- For TILE_ROUTING without pseudo-pip: writes `tile_name.dst_name.src_name`; DSP tiles return early (missing PPIPs); SING IOI special handling; IOI OCLKM handling

**get_pseudo_pip_data()**: Hardcoded lookup table for ~100+ pseudo-pip configurations for: L/RIOI3, RIOI, CLK_HROW, CLK_BUFG, HCLK_IOI, INT_INTERFACE tile types.

### write_io():
For PAD cells: calls `write_io_config(ci)`.
For ILOGICE3_IFF/OLOGICE2-3_OUTFF/OSERDESE2/ISERDESE2/IDELAYE2/ODELAYE2: calls `write_iol_config(ci)`.
For each HCLK: writes STEPDOWN, VREF, ONLY_DIFF_IN_USE, TMDS_33_IN_USE, LVDS_25_IN_USE bits.

**write_io_config(pad)**: Large function handling all IOB33/IOB18 standard configurations. Writes DRIVE, SLEW, IN/IN_DIFF, IN_ONLY, PULLTYPE, STEPDOWN bits. Updates `ioconfig_by_hclk` for bank-wide bits.

**write_iol_config(ci)**: Handles IFF/OUTFF/OSERDESE2/ISERDESE2/IDELAYE2/ODELAYE2 config bits. Writes IN_USE, DDR settings, IDELMUXE3, clock inversion, init, reset value bits.

### write_bram():
For BRAM_L/BRAM_R tiles:
- Checks BRAMTileStatus for RAM36 (uses same cell for both halves) vs RAM18_L/U
- Calls `write_bram_half(tile, 0, lower)`, `write_bram_half(tile, 1, upper)`

**write_bram_half()**: Writes IN_USE, read/write widths (`write_bram_width`), DOA_REG/DOB_REG, invertible pins (ZINV_*), write modes, ZINIT/ZSRVAL vectors, INIT data (`write_bram_init`). Also writes CASCOUT_ARD/BWR_ACTIVE for half=0.

**write_bram_init(half, ci, is_36)**: Writes INIT_00..INIT_3F and INITP_00..INITP_07 vectors. For 36-bit BRAMs: interleaves even/odd bits into two 18-bit halves.

### write_clocking():
For BUFGCTRL cells: writes IN_USE, INIT_OUT, IS_IGNORE0/1_INVERTED, ZINV_CE0/1, ZINV_S0/1.
For PLLE2_ADV: calls `write_pll`.
For MMCME2_ADV: calls `write_mmcm`.
Scans tiles for HCLK_L/R (ENABLE_BUFFER bits), CLK_HROW (GCLK_ACTIVE bits, CK_IN_ACTIVE bits), HCLK_CMT (CCIO_ACTIVE/USED, HCLK_CK_USED bits).
Second pass: CLK_BUFG_REBUF (GCLK_ENABLE_ABOVE/BELOW), HCLK_CMT (more HCLK bits).

**write_pll(ci)** / **write_mmcm(ci)**:
- `write_pll_clkout` for each clock output (DIVCLK, CLKFBOUT, CLKOUT0-5 for PLL; same + CLKOUT6 for MMCM)
- Computes VCO frequency from CLKFBOUT_MULT_F and CLKIN1_PERIOD
- PLL: 4 VCO range entries (900/1100/1400/1600 MHz) with LK table and filter register values
- MMCM: 4 VCO range entries (675/900/1100/∞ MHz) with different table values

**write_pll_clkout(name, ci)**:
Computes high/low count, edge, no_count, phasemux, delaytime, frac from DIVIDE_F/MULT_F and PHASE params. Writes CLKOUT1/2 fields per Xilinx FASM specification.

### write_ip():
For DSP48E1 cells: calls `write_dsp_cell(ci)`.

**write_dsp_cell(ci)**:
- Pushes tile name, "DSP48", DSP position
- Writes AREG/BREG (0 or 2 only), A_INPUT/B_INPUT cascade bits
- USE_DPORT, USE_SIMD (ONE48/TWO24/FOUR12)
- PATTERN vector (48 bits)
- MASK vector (46 bits — truncated from 48)
- SEL_MASK, all ZINV/Z register bits (ZADREG, ZALUMODEREG, etc.)
- `write_bus_zinv` for ALUMODE/INMODE/OPMODE buses
- `write_const_pins("GND")` and `write_const_pins("VCC")` — writes tile-side constant pin connections from `DSP_GND_PINS`/`DSP_VCC_PINS` attrs

---

## 44. XDC PARSER

`Arch::parseXdc(std::istream& in)`:

**Tokenizer**: `split_to_args(line, group_brackets)` — splits on whitespace, groups `[...]`/`{...}` when `group_brackets=true`.

**Supported commands**:
- `set_property [-dict {key val ...}] PROPERTY VALUE [get_ports portname]`: sets attrs on matching cells
- `create_clock [-period N] [-name X] [-waveform X] [-add] [get_ports/get_nets target]`: sets `clkconstr` on matching nets

**Unsupported**: everything else (logged as warning).

**`get_cells([get_ports name])`**: Returns PAD cells (or other top-level cells) by name from `ctx->cells`.

**`get_nets([get_ports/get_nets name])`**: Returns nets via `getNetByAlias(name)`.

**Known limitations**: `[current_design]` target → warning, skip. `INTERNAL_VREF` property → skip.

---

## 45. PYTHON BINDINGS

`arch_wrap_python(py::module& m)` (only compiled without `NO_PYTHON`):

Wraps: `ArchArgs`, `BelId` (with `index` field), `WireId`, `PipId`, `Arch(ArchArgs)`, `Context` (with `checksum`, `pack`, `place`, `route`, `isValidBelForCell`).

Uses template wrappers: `fn_wrapper_2a<Context, &Context::isValidBelForCell, ...>`.

Wraps ranges: `BelRange`, `WireRange`, `AllPipRange`, `UphillPipRange`, `DownhillPipRange`, `BelPinRange`.

Wraps maps: `CellMap` (as `IdCellMap`), `NetMap` (as `IdNetMap`), `HierarchyMap`.

`BelPin` wrapped with `bel` and `pin` readonly fields.

---

## 46. CELLS.CC — create_cell / create_dsp_cell / create_lut

### create_cell(ctx, type, name)
Factory for common cell types. Creates `CellInfo` and adds ports. Handles:
- `SLICE_LUTX`: A1-A6, WA1-9, DI1, DI2, CLK, WE, SIN (in); O5, O6, MC31 (out)
- `SLICE_FFX`: D, SR, CE, CLK (in); Q (out)
- `RAMD64E`: RADR0-5, WADR0-7, CLK, I, WE (in); O (out)
- `RAMD32`: RADR0-4, WADR0-4, CLK, I, WE (in); O (out)
- `MUXF7/F8/F9`: I0, I1, S (in); O (out)
- `CARRY8`: CI, CI_TOP (in); DI[0:7], S[0:7] (in); CO[0:7], O[0:7] (out)
- `MUXCY`: CI, DI, S (in); O (out)
- `XORCY`: CI, LI (in); O (out)
- `PAD`: PAD (inout)
- `INBUF`: VREF, PAD, OSC_EN, OSC[0:3] (in); O (out)
- `IBUFCTRL`: I, IBUFDISABLE, T (in); O (out)
- `OBUF/IBUF`: I (in); O (out)
- `OBUFT`: I, T (in); O (out)
- `IOBUF`: I, T (in); O (out); IO (inout)
- `OBUFT_DCIEN`: I, T, DCITERMDISABLE (in); O (out)
- `DIFFINBUF`: DIFF_IN_P, DIFF_IN_N, OSC_EN[0:1], OSC[0:3], VREF (in); O, O_B (out)
- `HPIO_VREF`: FABRIC_VREF_TUNE[0:6] (in); VREF (out)
- `INV`: I (in); O (out)
- `IDELAYCTRL`: REFCLK, RST (in); RDY (out)
- `IBUF_INTERMDISABLE`: I, IBUFDISABLE, INTERMDISABLE (in); O (out)
- `IBUFDS`: I, IB (in); O (out)
- `IBUFDS_INTERMDISABLE_INT`: I, IB, IBUFDISABLE, INTERMDISABLE (in); O (out)
- `CARRY4`: CI, CYINIT (in); DI[0:3], S[0:3] (in); CO[0:3], O[0:3] (out)

### create_dsp_cell(ctx, type, name)
Factory for DSP sub-cell types. Handles all 8 DSP sub-types with their specific bus widths.

### create_lut(ctx, name, inputs, output, init)
Creates `LUT<N>` where N = inputs.size(). Ports I0..I(N-1), O. Connects inputs and output nets. Sets INIT param.

---

## 47. PINS.CC — get_invertible_pins / get_tied_pins / get_bram36_ul_pins / get_top_level_pins

### get_bram36_ul_pins(ctx, ul_pins)
Finds one RAMB36E1_RAMB36E1 or RAMB36E2_RAMB36E2 BEL. Iterates all input bel pins. For each pin ending in a letter `L` followed by optional digits, checks for a corresponding `U` pin. If found, creates a logical pin `base_name[bus_suffix]` mapping to `{L_pin, U_pin}`. Used to create `port_multixform` entries in BRAM pack rules.

### get_top_level_pins
Maps IO cell types to their top-level (PAD-connected) port names. Used in IO packing to identify which ports connect directly to package pins.

---

## 48. ARCHCELLINFO UNION

```cpp
struct ArchCellInfo : BaseClusterInfo {
    union {
        struct { /* lutInfo */ } lutInfo;
        struct { /* ffInfo */  } ffInfo;
        struct { /* carryInfo */ } carryInfo;
        struct { /* muxInfo */ } muxInfo;
    };
};
```

### lutInfo fields:
| Field | Type | Meaning |
|---|---|---|
| `is_memory` | `bool` | LUT used as distributed RAM |
| `is_srl` | `bool` | LUT used as SRL |
| `input_count` | `int` | Number of connected inputs (0-6) |
| `output_count` | `int` | Number of connected outputs (0-2) |
| `memory_group` | `int` | DRAM group index (unused, always 0) |
| `only_drives_carry` | `bool` | Output only drives CARRY4/8 input |
| `input_sigs[6]` | `NetInfo*` | Connected input nets (by A1-A6) |
| `output_sigs[2]` | `NetInfo*` | Connected output nets (O6=0, O5=1) |
| `address_msb[3]` | `NetInfo*` | WA7/WA8/WA9 nets for memory MSBs |
| `di1_net` | `NetInfo*` | DI1 (direct input 1) net |
| `di2_net` | `NetInfo*` | DI2 (direct input 2) net |
| `wclk` | `NetInfo*` | Write clock net (for memory/SRL) |

### ffInfo fields:
| Field | Type | Meaning |
|---|---|---|
| `is_latch` | `bool` | Cell is a latch (X_FF_AS_LATCH attr) |
| `is_clkinv` | `bool` | Clock inverted (`IS_CLK_INVERTED` or xc7 negedge) |
| `is_srinv` | `bool` | SR inverted (`IS_R/S/CLR/PRE_INVERTED`) |
| `ffsync` | `bool` | Synchronous reset/set (X_FFSYNC attr) |
| `is_paired` | `bool` | Unused/reserved |
| `clk` | `NetInfo*` | Clock net |
| `sr` | `NetInfo*` | Set/reset net |
| `ce` | `NetInfo*` | Clock enable net |
| `d` | `NetInfo*` | Data input net |

### carryInfo fields:
| Field | Type | Meaning |
|---|---|---|
| `out_sigs[8]` | `NetInfo*` | O[0:7] output nets |
| `cout_sigs[8]` | `NetInfo*` | CO[0:7] output nets |
| `x_sigs[8]` | `NetInfo*` | AX-HX bounce-wire nets (US+); CYINIT for xc7 CARRY4 at index 0 |

### muxInfo fields:
| Field | Type | Meaning |
|---|---|---|
| `sel` | `NetInfo*` | S0 select input net |
| `out` | `NetInfo*` | OUT output net |

---

## 49. ASSIGNARCHINFO / ASSIGNCELLINFO

### assignArchInfo()
Iterates all cells and calls `assignCellInfo` on each.

### assignCellInfo(CellInfo* cell)
Populates the `ArchCellInfo` union based on cell type:

**SLICE_LUTX**:
- Counts connected inputs (A1-A6) → `input_count`, `input_sigs[]`
- Counts connected outputs (O6, O5) → `output_count`, `output_sigs[]`
- Sets `di1_net`, `di2_net`, `wclk`
- `is_srl` from `X_LUT_AS_SRL` attr
- `is_memory` from `X_LUT_AS_DRAM` attr
- `only_drives_carry`: true if clustered and single output drives CARRY4 (xc7) or CARRY8 (US+)
- `address_msb[0:2]` from WA7, WA8, WA9 ports

**SLICE_FFX**:
- `d` = D port net; `clk` = CK (xc7) or CLK (US+) net; `ce` = CE; `sr` = SR
- `is_clkinv` from `IS_CLK_INVERTED` param
- `is_srinv` from `IS_R_INVERTED || IS_S_INVERTED || IS_CLR_INVERTED || IS_PRE_INVERTED`
- `is_latch` from `X_FF_AS_LATCH` attr
- `ffsync` from `X_FFSYNC` attr

**F7MUX/F8MUX/F9MUX/SELMUX2_1**:
- `sel` = S0 port; `out` = OUT port

**CARRY8**:
- `out_sigs[i]` = `O<i>` port; `cout_sigs[i]` = `CO<i>`; `x_sigs[i]` = `<A+i>X` port

**CARRY4**:
- `out_sigs[i]` = `O<i>`; `cout_sigs[i]` = `CO<i>`; `x_sigs[i]` = null for i>0; `x_sigs[0]` = CYINIT port

---

## 50. COMMAND-LINE ENTRY (UspCommandHandler)

```cpp
class UspCommandHandler : public CommandHandler
```

**Options** (`getArchOptions()`):
- `--chipdb <file>`: chipdb binary (required)
- `--xdc <file>` (multi-value): XDC constraint files
- `--fasm <file>`: output FASM bitstream file

**`createContext(values)`**: Creates `Context(ArchArgs{chipdb})`. Errors if no `--chipdb`.

**`customAfterLoad(ctx)`**: Parses each XDC file via `ctx->parseXdc(in)`.

**`customBitstream(ctx)`**: If `--fasm` given, calls `ctx->writeFasm(filename)`.

**`main(argc, argv)`**: Creates `UspCommandHandler`, calls `handler.exec()`.

---

## 51. PIP BLACKLIST (setup_pip_blacklist)

`Arch::setup_pip_blacklist()`: Called in `Arch::Arch` **only if xc7**.

Iterates all tile types, blacklisting specific pips:

| Tile Type Prefix | Condition | Purpose |
|---|---|---|
| `HCLK_CMT` | dst wire contains `"FREQ_REF"` | Broken frequency reference pips |
| `CMT_TOP_L_LOWER` | All pips | Entire tile unusable |
| `CLK_HROW_TOP` | dst=`CK_BUFG_CASCO*` AND src=`CK_BUFG_CASCIN*` | Cascade routing blacklist |
| `HCLK_IOI` | dst=`RCLK_BEFORE_DIV*` AND src=`IMUX*` | IMUX-to-RCLK invalid route |
| `*IOI*` | dst=`*CLKB*` AND src=`*IMUX22*` | IOI clock routing constraint |
| `*IOI*` | dst=`*OCLKB*` AND src=`*IOI_OCLK_*` | OCLKB routing constraint |
| `*IOI*` | dst=`*OCLKM*` AND src=`*IMUX31*` | OCLKM routing constraint |
| `CMT_TOP_R*` | dst=`*PLLOUT_CLK_FREQ_BB_REBUFOUT*` | PLL rebuf routing |
| `CMT_TOP_R*` | dst=`*MMCM_CLK_FREQ_BB*` | MMCM freq routing |

Blacklisted by inserting pip index into `blacklist_pips[td.type]` (keyed by tile type index integer, not name).

---

## 52. PLACE FLOW (Arch::place)

```cpp
bool Arch::place()
```

Reads `settings[id_placer]` (default = `"heap"`).

**heap placer** (`PlacerHeapCfg`):
- `criticalityExponent = 7`
- `ioBufTypes`: PSEUDO_GND, PSEUDO_VCC, IOB_IBUFCTRL, IOB_OUTBUF
- `alpha = 0.08`, `beta = 0.4`
- `placeAllAtOnce = true`
- `hpwl_scale_x = 1`, `hpwl_scale_y = 2`
- `spread_scale_x = 2`, `spread_scale_y = 1`
- `netShareWeight = 0`
- `solverTolerance = 0.6e-6`
- `cellGroups`: one group containing `{SLICE_LUTX, SLICE_FFX, CARRY8}`

**sa placer**: `placer1(getCtx(), Placer1Cfg(getCtx()))`.

After placement: `fixupPlacement()`, set `attrs[id_step]="place"`, `archInfoToAttributes()`.

---

## 53. KEY CONSTANTS & MAGIC NUMBERS

| Constant | Value | Location | Meaning |
|---|---|---|---|
| `delay_t` unit | 1 ps | archdefs.h | 1000 = 1ns |
| `getDelayEpsilon()` | 20 | arch.h | Minimum non-zero delay |
| `getRipupDelayPenalty()` | 120 | arch.h | Base rip-up cost |
| PINFEED ripup penalty | 180 | arch.cc | 3/2 × 120 |
| Pseudo-GND global wire delay | 15000 | arch.cc | Very high to discourage long routes |
| Pseudo-VCC/GND sink bonus | 1000 | arch.cc | Added to estimateDelay for sink_locs |
| estimateDelay base constant | 300 | arch.h | Baseline delay estimate |
| estimateDelay x-breakpoint | 18 | arch.h | Beyond 18 tiles, lower cost per tile |
| estimateDelay y-breakpoint | 6 | arch.h | Beyond 6 tiles, lower cost per tile |
| xc7 delay multiplier | 3/2 | arch.cc | xc7 routing is slower |
| predictDelay FF2 penalty | 700 | arch.cc | FF2 routing harder than FF1 |
| predictDelay same-slice cost | 0 | arch.cc | Free if same slice |
| predictDelay diff-slice | 150 | arch.cc | Same tile, different slice |
| `max_visit` in try_preplace | 50000 | pack_preplace.cc | BFS effort limit |
| `iter_max` sink/source BFS | 500 | arch.cc | findSourceSinkLocations limit |
| node tile_wires scan limit | 200 | arch.cc | estimateDelay nodal wire scan |
| BFS visit limit (routeVcc) | Unbounded | arch.cc | Until VCC net reached |
| xc7 carry skip factor | `i/(4*25)` | pack_carry_xc7.cc | Skip tile every 25 CARRY4s |
| CARRY8 z per tile | 8 | arch.h | US+ 8-deep carry |
| CARRY4 z per tile | 4 | arch.h | xc7 4-deep carry |
| BEL_LOWER_DSP | 6 | arch.h | xc7 DSP z |
| BEL_UPPER_DSP | 25 | arch.h | xc7 DSP z |
| LUT input budget | 5 | pack_carry | max unique inputs per LUT pair |
| FASM pip_epsilon | 35 | arch.h | Minimum pip routing delay |
| DSP48E2 subcell count | 8 | pack_dsp_usp.cc | Expansion count |

---

## 54. CROSS-REFERENCE: xc7 vs US+ BEHAVIORAL DIFFERENCES

| Aspect | xc7 | UltraScale+ |
|---|---|---|
| `xc7` flag | `true` | `false` |
| Device name prefix | `"xc7"` | anything else |
| Carry cell | `CARRY4` (4-bit) | `CARRY8` (8-bit) |
| Carry init port | `CYINIT` → `BEL_CARRY4` | `AX` → `BEL_CARRY8` |
| Carry chain skip | Every 25 CARRY4s | None |
| Logic tile types | CLBLL_L/R, CLBLM_L/R | CLEL_L/R, CLEM, CLEM_R |
| SLICEM check | `CLBLM_L/R` | `CLEM/CLEM_R` |
| Max LUT-FF groups | 4 per half-tile (8 total) | 8 (all one half concept) |
| DI/X split | Only X (di2_net) | Both I (di1_net) and X (di2_net) |
| FF clock port | `id_CK` | `id_CLK` |
| MUXF9 support | No (error) | Yes |
| FF CE per column | Shared (one CE for all FFs) | Per-column (ce[k]) |
| WCLK/CLK sharing | FF half 0 shares with WCLK | Tracked separately |
| F7/F8 types | `SELMUX2_1` | `F7MUX` / `F8MUX` |
| BRAM types | RAMB18E1, RAMB36E1 | RAMB18E2, RAMB36E2 |
| URAM | Not present | `URAM288` → `BEL_URAM288` |
| DSP type | `DSP48E1` (monolithic) | `DSP48E2` → 8 sub-cells |
| PS cell | `PS7_PS7` | `PSS_ALTO_CORE` |
| BUFG mapping | `BUFG → BUFGCTRL` (in prepare_clocking) | `BUFG → BUFGCE` |
| PLL types | PLLE2_ADV, MMCME2_ADV | PLLE4_ADV, MMCME4_ADV |
| IOB site naming | `site/IOB33/PAD` or `site/IOB18/PAD` | `site/PAD` |
| INBUF | Not present (uses INBUF_EN in IOB33) | `INBUF` + `IBUFCTRL` |
| IOCTRL type | `IDELAYCTRL_IDELAYCTRL` | `BITSLICE_CONTROL_BEL` |
| Reserved wires | Not used | Used (I/X bounce wires) |
| Pip blacklist | Yes (`setup_pip_blacklist`) | No |
| routeVcc | Skipped for router2 | Skipped for router2 |
| BRAM validity | Included | Included |
| DRAM height | 4 per tile | 8 per tile |
| IOL rules | ILOGICE3_IFF, OLOGICE2/3 | ISERDESE3, OSERDESE3, IOL_IDDR/OPTFF |
| IDELAY/ODELAY types | IDELAYE2, ODELAYE2 | IDELAYE3, ODELAYE3 |
| SERDES types | ISERDESE2, OSERDESE2 | ISERDESE3, OSERDESE3, IDDRE1→ISERDES/IDDR |

---

*End of reference document. All function signatures, field names, magic values, and behavioral rules are indexed above for rapid LLM lookup and debugging.*
