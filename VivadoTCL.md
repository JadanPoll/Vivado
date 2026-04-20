# Vivado Tcl Commands — Exhaustive Annotated Reference
### Complete command tree with key flags, sub-options, and practical notes

> **How to read this document:**
> - Each command has a one-line description.
> - Flags listed below a command are its most important options.
> - `[optional]` = flag is optional. `<required>` = argument is required.
> - Version notes marked as `[2019+]`, `[2020+]` etc. where relevant.
> - Commands marked `⚠️` require special care or have common pitfalls.

---

## Table of Contents
1. [add_*](#add_)
2. [all_*](#all_)
3. [apply_*](#apply_)
4. [check_*](#check_)
5. [close_*](#close_)
6. [commit_*](#commit_)
7. [compile_*](#compile_)
8. [config_*](#config_)
9. [connect_*](#connect_)
10. [convert_*](#convert_)
11. [copy_*](#copy_)
12. [create_*](#create_)
13. [current_*](#current_)
14. [delete_*](#delete_)
15. [disconnect_*](#disconnect_)
16. [display_*](#display_)
17. [export_*](#export_)
18. [find_*](#find_)
19. [generate_*](#generate_)
20. [get_* — Object Query Commands](#get_--object-query-commands)
21. [group_*](#group_)
22. [implement_*](#implement_)
23. [import_*](#import_)
24. [launch_*](#launch_)
25. [list_*](#list_)
26. [lock_*](#lock_)
27. [log_*](#log_)
28. [make_*](#make_)
29. [move_*](#move_)
30. [open_*](#open_)
31. [phys_* and power_*](#phys_-and-power_)
32. [place_*](#place_)
33. [pr_*](#pr_)
34. [program_*](#program_)
35. [read_*](#read_)
36. [refresh_*](#refresh_)
37. [remove_*](#remove_)
38. [rename_*](#rename_)
39. [report_*](#report_)
40. [reset_*](#reset_)
41. [route_design](#route_design)
42. [run_*](#run_)
43. [save_*](#save_)
44. [scan_*](#scan_)
45. [set_*](#set_)
46. [Simulation Commands](#simulation-commands)
47. [start_* and stop_*](#start_-and-stop_)
48. [synth_*](#synth_)
49. [update_*](#update_)
50. [upgrade_*](#upgrade_)
51. [validate_*](#validate_)
52. [wait_*](#wait_)
53. [write_*](#write_)
54. [Non-Prefixed and Singular Commands](#non-prefixed-and-singular-commands)

---

## add_*

### add_bp
Add a debug breakpoint in simulation.
```
add_bp <file> <line_number>
```
- `-type line` — line breakpoint (default)
- `-type condition <expr>` — conditional breakpoint

### add_cells_to_pblock
Assign logical cells to a physical placement block (Pblock).
```
add_cells_to_pblock <pblock> <cells>
```
- `-clear_locs` — remove any existing placement constraints from the cells before adding
- `-add_primitives` — include all sub-primitives of the given cells
- ⚠️ Cells must be synthesized before they can be added to a Pblock.

### add_condition
Add a trigger condition to a simulation breakpoint.
```
add_condition -name <name> <expression>
```
- `-radix <bin|hex|dec>` — set display radix for the condition value

### add_drc_checks
Register custom Design Rule Checks into the DRC engine.
```
add_drc_checks <check_objects>
```

### add_files
Add source, constraint, or simulation files to the active project.
```
add_files <file_or_directory>
```
- `-fileset <name>` — specify target fileset (sources_1, constrs_1, sim_1)
- `-norecurse` — do not recurse into subdirectories
- `-scan_for_includes` — scan for include file references
- `-copy_to <dir>` — copy the file into the project directory

### add_force
Force a signal to a specific value during simulation.
```
add_force <signal_path> <value>
```
- `-radix <bin|hex|dec|oct>` — radix of the value
- `-repeat_every <time>` — create a repeating force (clock generation)
- `-cancel_after <time>` — automatically release the force after this time
- ⚠️ Forces override RTL logic. Use `remove_force` to release.

### add_hw_hbm_pc
Add a High Bandwidth Memory (HBM) performance counter for monitoring. `[UltraScale+ only]`

### add_hw_probe_enum
Add an enumerated type definition to a hardware probe for human-readable display in Hardware Manager.

### add_peripheral_interface
Add an AXI or other interface to a custom IP peripheral being created in the IP Packager.
```
add_peripheral_interface -name <name> -interface_definition <def> <peripheral>
```

### add_qor_checks
Add custom Quality of Results (QoR) checks to the analysis flow. `[2019+]`

### add_to_power_rail
Assign design elements to a named power rail for power analysis grouping.

### add_wave
Add a signal or object to the simulation waveform viewer.
```
add_wave <signal_path>
```
- `-radix <bin|hex|dec|oct|ascii>` — display radix
- `-color <color>` — waveform trace color
- `-name <display_name>` — override the display name in the waveform
- `-recursive` — add all signals in the specified hierarchy level

### add_wave_divider
Add a labeled visual divider between signal groups in the waveform.
```
add_wave_divider <label>
```
- `-after <wave_object>` — insert divider after this wave object

### add_wave_group
Create a collapsible group of signals in the waveform viewer.
```
add_wave_group <group_name>
```
- `-after <wave_object>` — insert group after this wave object

### add_wave_marker
Add a time marker annotation to the waveform view.
```
add_wave_marker <time>
```
- `-name <name>` — label for the marker

### add_wave_virtual_bus
Create a virtual bus by concatenating multiple signals into one display lane.
```
add_wave_virtual_bus -name <name> <signals>
```
- `-radix <bin|hex|dec>` — display radix for the concatenated bus

---

## all_*

> These commands return collections of objects and are almost always used as arguments to other commands (e.g., `get_property PERIOD [all_clocks]`).

### all_clocks
Return all clocks defined in the current design.
```
all_clocks
```
- No flags. Used in constraint files to apply rules to every clock.

### all_cpus
Return all processor core cells (MicroBlaze, ARM, RISC-V) in the design.

### all_dsps
Return all DSP48E1/DSP48E2 block cells in the design.
- Often used with `get_property` to audit DSP utilization per module.

### all_fanin
Return all cells or pins in the fan-in cone of a given sink.
```
all_fanin -to <sink_pin> [depth <n>]
```
- `-flat` — flatten hierarchy in results
- `-startpoints_only` — return only the register/port sources, not intermediate logic
- `-levels <n>` — limit traversal depth (default: unlimited)
- ⚠️ Without `-levels`, this can return the entire design on large nets.

### all_fanout
Return all cells or pins in the fan-out cone of a given source.
```
all_fanout -from <source_pin> [depth <n>]
```
- `-flat` — flatten hierarchy
- `-endpoints_only` — return only register/port sinks
- `-levels <n>` — limit traversal depth

### all_ffs
Return all flip-flop cells in the design.
- Equivalent to `get_cells -filter {REF_NAME =~ FD*}`

### all_hsios
Return all High-Speed I/O cells (GTX, GTH, GTHE4 transceivers etc.).

### all_inputs
Return all top-level input ports of the design.
- Equivalent to `get_ports -filter {DIRECTION == IN}`

### all_latches
Return all latch cells in the design.
- ⚠️ Latches are almost always unintentional in synchronous FPGA design. Finding them with this command and `report_cdc` is a critical design review step.

### all_outputs
Return all top-level output ports of the design.

### all_rams
Return all RAM cells (BRAM, Distributed RAM) in the design.

### all_registers
Return all register cells (FFs and latches) or register pins.
```
all_registers
```
- `-clock <clock_name>` — return only registers clocked by this clock
- `-edge_triggered` — return only edge-triggered FFs (excludes latches)
- `-level_sensitive` — return only level-sensitive latches
- `-output_pins` — return the Q output pins rather than the cells

---

## apply_*

### apply_bd_automation
Run the IP Integrator automation rules engine on a block design.
```
apply_bd_automation -rule <rule_name> -config <config_dict> <objects>
```
- `-rule xilinx.com:bd_rule:axi4` — connect AXI interfaces automatically
- `-rule xilinx.com:bd_rule:clkrst` — connect clocks and resets automatically
- `-config {Master /cpu/M_AXI Clk /clk_wiz/clk_out1}` — configuration key-value pairs
- ⚠️ Always review what automation connects — it can make unexpected clock choices.

### apply_board_connection
Connect an IP block's interface to a physical board interface (from the board file).
```
apply_board_connection -board_interface <interface> -ip_intf <ip_interface> -diagram <bd_name>
```

### apply_hw_ila_trigger
Pre-configure and apply an ILA trigger condition so it activates at FPGA startup without manual intervention.
```
apply_hw_ila_trigger <hw_ila_object>
```

---

## check_*

### check_syntax
Verify HDL syntax of source files without running full synthesis.
```
check_syntax
```
- `-fileset <fileset_name>` — check a specific fileset
- `-return_string` — return results as a string rather than printing

### check_timing
Validate that timing constraints are complete, consistent, and cover all paths.
```
check_timing
```
- `-override_defaults <checks>` — run specific checks only
- `-no_header` — suppress report header
- `-return_string` — return results as string
- `-verbose` — include additional diagnostic detail
- ⚠️ Always run after `read_xdc`. Unconstrained clocks will be flagged here before they silently corrupt your timing analysis.

---

## close_*

### close_bd_design
Close the active block design without closing the project.
```
close_bd_design <design_name>
```

### close_design
Close the active synthesized or implemented design from memory.
```
close_design
```

### close_hw_manager
Close the hardware manager session and release JTAG resources.

### close_hw_target
Disconnect from a specific JTAG hardware target.
```
close_hw_target [<target>]
```

### close_project
Close the currently open Vivado project.
```
close_project
```
- `-delete` — delete the project from disk after closing ⚠️ irreversible

### close_saif
Close a SAIF (Switching Activity Interchange Format) file that was open for power activity logging.

### close_sim
Close the active simulation session.
```
close_sim
```
- `-quiet` — suppress warnings if no simulation is open

### close_vcd
Close a VCD (Value Change Dump) waveform file that was open for writing.

### close_wave_config
Close a waveform configuration file.

---

## commit_*

> `commit_*` commands write pending property changes back to the physical hardware device over JTAG. They pair with `set_property` on hardware objects.

### commit_hw_hbm
Write pending HBM configuration property changes to the device. `[UltraScale+ only]`

### commit_hw_mig
Write pending MIG (Memory Interface Generator) configuration to the device.

### commit_hw_sio
Write pending Serial I/O (GTX/GTH transceiver) property changes to the device.
```
commit_hw_sio <hw_sio_objects>
```

### commit_hw_sysmon
Write pending System Monitor (XADC/Sysmon) configuration to the device.

### commit_hw_vio
Write pending output probe values to a VIO (Virtual I/O) core on the device.
```
commit_hw_vio <hw_vio_object>
```
- ⚠️ Must call this after `set_property OUTPUT_VALUE` on VIO probes, or the values will not reach the hardware.

---

## compile_*

### compile_c
Compile C/C++ source code for MicroBlaze or HLS flows within the Vivado/Vitis environment.
```
compile_c <source_files>
```
- `-include_dirs <dirs>` — specify include directories
- `-defines <macros>` — specify preprocessor defines

### compile_simlib
Compile third-party simulation libraries (Synopsys VCS, Mentor QuestaSim, etc.) for use with Vivado simulation.
```
compile_simlib
```
- `-simulator <xsim|modelsim|questa|vcs|riviera|activehdl>` — target simulator
- `-family <family>` — device family to compile primitives for (e.g., `spartan7`)
- `-language <vhdl|verilog|all>` — HDL language to compile
- `-dir <output_dir>` — output directory for compiled libraries
- `-force` — overwrite existing compiled libraries

---

## config_*

### config_compile_simlib
Configure the default settings for `compile_simlib`.
```
config_compile_simlib -sim_version <version> -family <family>
```

### config_design_analysis
Configure settings for design analysis reports (critical path depth, etc.). `[2019+]`
```
config_design_analysis -max_paths <n>
```

### config_flows
Configure which implementation sub-steps are enabled in a flow.

### config_hw_sio_gts
Configure Serial I/O transceiver GTs for hardware scan.

### config_implementation
Set implementation strategy options programmatically.
```
config_implementation -effort_level <normal|high>
```

### config_inter_slr_muxing
Configure the SLR (Super Logic Region) crossing mux insertion strategy. `[UltraScale+ multi-SLR only]`

### config_ip_cache
Configure IP output product caching behavior.
```
config_ip_cache
```
- `-enable` / `-disable` — enable or disable the IP cache
- `-clear` — clear the cache
- `-location <dir>` — set the cache directory

### config_linter
Configure the HDL linter rules (sensitivity list checks, variable usage, etc.).

### config_timing_analysis
Configure how the timing engine handles analysis edge cases.
```
config_timing_analysis
```
- `-ignore_io_paths <true|false>` — exclude unconstrained I/O paths from summary
- `-disable_flight_delays <true|false>` — exclude package flight delay from I/O analysis
- `-enable_primitive_hold_check <true|false>` — include hold checks on primitives

### config_timing_corners
Configure which PVT corners are analyzed in multi-corner timing analysis.
```
config_timing_corners
```
- `-corner <Slow|Fast>` — select which corner to configure
- `-delay_model <interconnect|cell>` — select delay model type

---

## connect_*

### connect_bd_intf_net
Connect two interface ports (AXI, AXI-Stream, etc.) in a block design.
```
connect_bd_intf_net <intf_pin_1> <intf_pin_2>
```
- `-intf_net <net_name>` — assign a name to the created interface net

### connect_bd_net
Connect individual single-bit or bus nets in a block design.
```
connect_bd_net <pin_1> <pin_2> [<pin_3> ...]
```
- `-net <net_name>` — assign a name to the net

### connect_debug_cores
Connect instantiated ILA/VIO debug cores to the debug hub network.
```
connect_debug_cores
```
- ⚠️ Must be called after `implement_debug_core` before `write_bitstream`.

### connect_debug_port
Connect a specific signal net to a probe port on a debug core.
```
connect_debug_port <core>/<port> <net>
```

### connect_hw_server
Connect Vivado Hardware Manager to a Vivado Lab Edition hw_server process.
```
connect_hw_server
```
- `-url <host:port>` — server address (default: `localhost:3121`)
- `-allow_non_jtag` — allow non-JTAG connection types

### connect_net
Connect a logical net to a pin in the post-synthesis netlist (used during ECO — Engineering Change Order — flows).
```
connect_net -net <net_name> -objects <pins>
```
- ⚠️ ECO netlist edits are not preserved across re-synthesis. Document them carefully.

---

## convert_*

### convert_ips
Upgrade or convert older IP cores to the current Vivado version's format.
```
convert_ips <ip_objects>
```

### convert_ngc
Convert legacy NGC (ISE-era) netlist files to Vivado-compatible EDIF or DCP format.
```
convert_ngc <ngc_file>
```
- ⚠️ NGC netlists from ISE are not directly compatible with Vivado. This conversion is lossy for some primitives.

---

## copy_*

### copy_bd_objs
Duplicate selected block design objects (cells, nets, ports) within or between designs.
```
copy_bd_objs <objects>
```
- `-to_design <design_name>` — copy objects to a different block design

### copy_constraints
Duplicate an existing constraint set.
```
copy_constraints -from <source_set> <new_name>
```

### copy_ip
Clone an existing IP customization to create a new independent instance.
```
copy_ip -name <new_name> <ip_object>
```

### copy_run
Duplicate a synthesis or implementation run configuration.
```
copy_run -name <new_run_name> <source_run>
```

---

## create_*

### create_bd_cell
Instantiate an IP core or hierarchical module into the active block design.
```
create_bd_cell -type ip -vlnv <vendor:lib:name:version> <cell_name>
```
- `-type ip` — instantiate from IP catalog
- `-type module` — instantiate a user HDL module
- `-type hier` — create a hierarchical container (subsystem)
- `-vlnv xilinx.com:ip:axi_gpio:2.0` — example VLNV for AXI GPIO

### create_bd_design
Create a new block design in the current project.
```
create_bd_design <design_name>
```
- `-cell <parent_cell>` — create as a sub-design of a hierarchical cell

### create_bd_net
Create a named wire (net) in the active block design.
```
create_bd_net <net_name>
```

### create_bd_port
Create a top-level external port on the block design.
```
create_bd_port -name <name> -type <clk|rst|data|intr> -dir <I|O|IO>
```
- `-type clk` — clock port (enables clock frequency properties)
- `-type rst` — reset port (enables polarity properties)
- `-freq_hz <hz>` — set clock frequency hint (used by automation rules)

### create_clock ⚠️
Define a primary clock timing constraint. **Without this, all timing analysis is invalid.**
```
create_clock -name <name> -period <ns> [get_ports <port>]
```
- `-name <name>` — logical name for the clock
- `-period <ns>` — clock period in nanoseconds (e.g., `5.000` for 200 MHz)
- `-waveform {<rise_time> <fall_time>}` — specify non-50% duty cycle (default: `{0 period/2}`)
- `-add` — add a second clock on the same source pin (for dual-edge clocking)
- ⚠️ Always define clocks on their source pins (ports or MMCM outputs), not intermediate nets.
- ⚠️ Do not define a clock on a BUFG output — define it on BUFG's input (the MMCM output).

### create_debug_core
Instantiate an ILA or VIO debug core in the design.
```
create_debug_core <name> <type>
```
- `<type>` options: `ila` (Integrated Logic Analyzer), `vio` (Virtual I/O), `axis_ila`
- After creation, set probe widths: `set_property C_DATA_DEPTH 1024 [get_debug_cores <name>]`

### create_generated_clock
Define a clock derived from another clock (MMCM output, clock divider, etc.).
```
create_generated_clock -name <name> -source <master_source_pin> [options] <output_pin>
```
- `-source <pin>` — the master clock source pin (e.g., MMCM CLKIN1 port)
- `-multiply_by <n>` — frequency multiplication factor
- `-divide_by <n>` — frequency division factor
- `-edges {1 3 5}` — edge-based specification for non-integer ratios
- `-duty_cycle <pct>` — output duty cycle percentage
- `-invert` — clock is inverted relative to source
- `-combinational` — for clocks passed through combinational logic ⚠️ avoid if possible
- ⚠️ For MMCM/PLL outputs, Vivado can often auto-derive generated clocks. Use `create_generated_clock` to override or name them explicitly.

### create_hw_bitstream
Create a hardware bitstream object for configuration memory programming.
```
create_hw_bitstream -hw_device <device> -memdev <mem_device> <bitstream_file>
```

### create_ip
Instantiate an IP core in an IP-centric (non-block-design) project.
```
create_ip -name <ip_name> -vendor <vendor> -library <lib> -version <ver> -module_name <name>
```
- `-dir <dir>` — output directory for IP files
- ⚠️ After `create_ip`, configure it with `set_property CONFIG.<param> <value> [get_ips <name>]`, then call `generate_target all`.

### create_pblock
Create a physical placement block (rectangle) for floorplanning.
```
create_pblock <pblock_name>
```
- After creation, resize with: `resize_pblock [get_pblocks <name>] -add {SLICE_X0Y0:SLICE_X15Y49}`
- Resource types: `SLICE_`, `DSP48_`, `RAMB18_`, `RAMB36_`, `BUFG_`
- `-locs <range>` — directly specify location range at creation time

### create_project
Create a new Vivado project.
```
create_project <name> <directory>
```
- `-part <part_name>` — target device (e.g., `xc7s50csga324-1`)
- `-force` — overwrite if project already exists
- `-in_memory` — create a non-file-system project (for batch/scripted flows)
- `-ip` — create an IP project (for IP packaging)

### create_run
Create a new synthesis or implementation run configuration.
```
create_run <run_name>
```
- `-flow <flow_name>` — synthesis/implementation strategy (e.g., `Vivado Synthesis 2023`)
- `-strategy <strategy>` — named strategy (e.g., `Flow_PerfOptimized_high`)
- `-parent_run <synth_run>` — link an impl run to its parent synthesis run
- `-constrset <constraint_set>` — assign a constraint set to this run

### create_testbench
Generate a simulation testbench template for a specified module.

---

## current_*

### current_bd_design
Get or set the active block design.
```
current_bd_design [<design_name>]
```

### current_bd_instance
Get or set the hierarchical scope within the active block design (for relative path commands).
```
current_bd_instance [<cell_path>]
```
- `current_bd_instance /` — return to top level

### current_board_part
Get the currently active board part definition.

### current_design
Get the name of the active synthesized or implemented design loaded in memory.

### current_hw_device
Get or set the active hardware device (FPGA) in the Hardware Manager.
```
current_hw_device [<device_object>]
```

### current_instance
Get or set the active hierarchical scope in the design netlist (affects relative cell/net name resolution).
```
current_instance [<cell_path>]
```
- `current_instance` (no arg) — returns to top level

### current_project
Get the name of the currently open project.

### current_run
Get or set the active synthesis or implementation run.
```
current_run [<run_object>]
```
- `-synthesis` — target the active synthesis run
- `-implementation` — target the active implementation run

---

## delete_*

### delete_bd_objs
Delete objects from the active block design.
```
delete_bd_objs <objects>
```

### delete_debug_core
Remove an ILA or VIO debug core from the design.
```
delete_debug_core <core_object>
```

### delete_ip_run
Delete an out-of-context IP synthesis run.
```
delete_ip_run <run_object>
```

### delete_pblocks
Remove one or more Pblock constraints from the design.
```
delete_pblocks <pblock_objects>
```

### delete_runs
Delete synthesis or implementation runs.
```
delete_runs <run_objects>
```

---

## disconnect_*

### disconnect_bd_net
Remove a net connection between pins in a block design.
```
disconnect_bd_net <net_name> <pins>
```

### disconnect_hw_server
Disconnect from the Vivado hardware server.
```
disconnect_hw_server [<server_object>]
```

### disconnect_net
Remove a logical net connection from a pin in the post-synthesis netlist (ECO flow).
```
disconnect_net -net <net_name> -objects <pins>
```

---

## display_*

### display_hw_ila_data
Load and display previously captured ILA data in the waveform viewer.
```
display_hw_ila_data <hw_ila_data_object>
```

### display_hw_sio_scan
Display a Serial I/O eye scan result in the Hardware Manager.
```
display_hw_sio_scan <scan_object>
```

---

## export_*

### export_bd_synth
Export a block design for out-of-context synthesis.
```
export_bd_synth -run <run_name>
```

### export_ip_user_files
Export all IP-generated files needed for simulation and synthesis.
```
export_ip_user_files
```
- `-of_objects <ip_objects>` — export for specific IPs only
- `-no_script` — skip script generation
- `-force` — overwrite existing files

### export_simulation
Generate simulation scripts for use with third-party simulators.
```
export_simulation
```
- `-simulator <xsim|modelsim|questa|vcs|riviera|activehdl>` — target simulator
- `-directory <dir>` — output directory
- `-of_objects <objects>` — export for specific IP or fileset
- `-lib_map_path <path>` — path to pre-compiled simulation libraries
- `-use_ip_compiled_libs` — use cached IP compiled libs

---

## find_*

### find_bd_objs
Search for block design objects by name or property.
```
find_bd_objs -regexp <pattern>
```
- `-type <cell|net|port|pin|intf_pin|intf_net>` — filter by object type

### find_routing_path
Find and return the routing path between two physical nodes in the routed design.
```
find_routing_path -from <node_or_pin> -to <node_or_pin>
```
- ⚠️ Requires a fully routed design (post `route_design`).
- Extremely useful for bitstream reverse engineering — identifies which PIPs are active on a net.

---

## generate_*

### generate_mem_files
Generate memory initialization files (`.mem`, `.coe`) from source data.
```
generate_mem_files <directory>
```

### generate_target
Generate all output products (netlists, simulation files, constraints) for an IP or block design.
```
generate_target all [get_ips <ip_name>]
generate_target all [get_files <bd_file>]
```
- `all` — generate all output product types
- `synthesis` — generate synthesis netlist only
- `simulation` — generate simulation files only
- `implementation` — generate implementation files only
- ⚠️ Must be called after `create_ip` or modifying IP parameters before the IP can be used in synthesis.

### generate_vcd_ports
Generate VCD port declarations for SAIF-based power analysis.

---

## get_* — Object Query Commands

> This is the most critical command family in Vivado Tcl. Almost every analysis and constraint script is built from `get_*` queries filtered by `-filter` expressions.

### get_bels ⚠️ (Critical for low-level analysis)
Retrieve individual BEL (Basic Element of Logic) sites within slices.
```
get_bels [<pattern>]
```
- `-of_objects <sites>` — get BELs within specific sites
- `-filter {TYPE =~ LUT*}` — filter by BEL type
- `-regexp <pattern>` — use regex for name matching
- BEL types: `A6LUT`, `B6LUT`, `C6LUT`, `D6LUT`, `AFF`, `BFF`, `CARRY4`, `F7MUX`, `F8MUX`
- Example: `get_bels -of_objects [get_sites SLICE_X0Y0]` → returns all BELs in that slice
- Used in bitstream analysis to map logical primitives to physical bit addresses.

### get_bd_cells
Retrieve block design cell instances.
```
get_bd_cells [<pattern>]
```
- `-hierarchical` — search all hierarchy levels
- `-filter {VLNV =~ *axi_gpio*}` — filter by IP type

### get_bd_nets
Retrieve block design nets.
```
get_bd_nets [<pattern>]
```

### get_bd_pins
Retrieve block design pin objects.
```
get_bd_pins <cell>/<pin_pattern>
```

### get_bd_ports
Retrieve top-level external ports of the block design.

### get_bd_intf_nets
Retrieve block design interface nets (AXI, AXI-Stream buses).

### get_bd_intf_pins
Retrieve block design interface pins.

### get_bd_intf_ports
Retrieve top-level interface ports of the block design.

### get_cells
Retrieve logical cell instances from the design hierarchy.
```
get_cells [<pattern>]
```
- `-hierarchical` — search all hierarchy levels (use with `-filter` to avoid huge results)
- `-filter {REF_NAME == FDRE}` — filter by primitive type
- `-filter {IS_PRIMITIVE == 1}` — return only leaf-level primitives
- `-filter {NAME =~ */dsp_*}` — wildcard name filter
- `-regexp <pattern>` — regex-based name matching
- `-include_replicated_objects` — include replicated cells (from `phys_opt_design`)
- Example: `get_cells -hierarchical -filter {REF_NAME == DSP48E1}` → all DSP cells

### get_clocks
Retrieve defined timing clock objects.
```
get_clocks [<pattern>]
```
- `-of_objects <pins>` — get clocks propagated to specific pins
- `-include_generated_clocks` — include generated clocks in results
- `-filter {IS_VIRTUAL == 0}` — exclude virtual clocks

### get_cdc_violations
Retrieve CDC (Clock Domain Crossing) violations after running `report_cdc`.
```
get_cdc_violations
```
- `-of_objects <cdc_report>` — get violations from a specific report object
- `-filter {SEVERITY == Critical}` — filter by severity

### get_debug_cores
Retrieve ILA/VIO debug core instances.
```
get_debug_cores [<pattern>]
```

### get_debug_ports
Retrieve probe ports on a debug core.
```
get_debug_ports <core>/probe*
```

### get_drc_checks
Retrieve available DRC check definitions.
```
get_drc_checks [<pattern>]
```
- `-filter {CATEGORY == timing}` — filter by category

### get_drc_violations
Retrieve DRC violation objects after running `report_drc`.
```
get_drc_violations
```
- `-filter {SEVERITY == Error}` — filter critical violations only

### get_files
Retrieve source files in the project.
```
get_files [<pattern>]
```
- `-of_objects <fileset>` — files in a specific fileset
- `-filter {FILE_TYPE == Verilog}` — filter by file type
- `-used_in <synthesis|simulation>` — files used in a specific flow

### get_filesets
Retrieve fileset objects in the project.
```
get_filesets [<pattern>]
```

### get_hw_devices
Retrieve hardware device objects connected via JTAG.
```
get_hw_devices [<pattern>]
```
- `-of_objects <hw_target>` — devices on a specific target

### get_hw_ilas
Retrieve ILA core objects visible in Hardware Manager.
```
get_hw_ilas
```
- `-of_objects <hw_device>` — ILAs on a specific device

### get_hw_probes
Retrieve probe objects within an ILA core.
```
get_hw_probes [<pattern>] -of_objects <hw_ila>
```

### get_hw_servers
Retrieve connected hardware server objects.

### get_hw_targets
Retrieve available JTAG hardware targets (cables/boards).
```
get_hw_targets [<pattern>]
```

### get_hw_vios
Retrieve VIO core objects visible in Hardware Manager.

### get_ips
Retrieve IP core instances in the project.
```
get_ips [<pattern>]
```
- `-filter {TYPE == XCI}` — filter by IP file type

### get_nets
Retrieve logical net objects.
```
get_nets [<pattern>]
```
- `-hierarchical` — search all hierarchy levels
- `-filter {TYPE == SIGNAL}` — exclude power/ground nets
- `-of_objects <cells|pins>` — nets connected to specific objects
- `-segments` — return all segment objects of a net

### get_nodes ⚠️ (Critical for routing analysis)
Retrieve routing graph node objects (wire endpoints in INT tiles).
```
get_nodes [<pattern>]
```
- `-of_objects <tiles|wires|pips>` — nodes in specific tiles or connected to specific wires
- `-filter {COST_CODE_NAME == LOCAL}` — filter by routing cost tier
- Example: `get_nodes -of_objects [get_tiles INT_L_X2Y10]`
- Used with `find_routing_path` for route tracing.

### get_package_pins
Retrieve physical package pin objects.
```
get_package_pins [<pattern>]
```
- `-filter {IS_GENERAL_PURPOSE == 1}` — user I/O pins only
- `-of_objects <io_bank>` — pins in a specific I/O bank
- Example: `get_property PACKAGE_PIN [get_ports CLK_IN]` — find which pin a port is assigned to

### get_pblocks
Retrieve Pblock objects.
```
get_pblocks [<pattern>]
```

### get_pins
Retrieve logical cell pin objects.
```
get_pins [<pattern>]
```
- `-hierarchical` — search all levels
- `-filter {DIRECTION == IN}` — input pins only
- `-of_objects <cells|nets>` — pins on specific cells or connected to nets
- `-leaf` — return only leaf-level primitive pins

### get_pips ⚠️ (Critical for routing/bitstream analysis)
Retrieve Programmable Interconnect Point objects.
```
get_pips [<pattern>]
```
- `-of_objects <tiles|nodes|wires>` — PIPs in or connected to specific objects
- `-filter {IS_FIXED == 1}` — PIPs that are fixed (locked routes)
- Example: `get_pips -of_objects [get_tiles INT_L_X2Y10]` → all PIPs in that INT tile
- ⚠️ Can return millions of objects on a full device. Always filter by tile.
- Used in route tracing and bitstream reverse engineering to identify which switch connections are active.

### get_ports
Retrieve top-level I/O port objects.
```
get_ports [<pattern>]
```
- `-filter {DIRECTION == IN}` — input ports
- `-filter {DIRECTION == OUT}` — output ports
- `-filter {DIRECTION == INOUT}` — bidirectional ports

### get_property
Read the value of a property on any Vivado object.
```
get_property <property_name> <object>
```
- Example: `get_property PERIOD [get_clocks clk_main]` → returns clock period
- Example: `get_property LOC [get_cells dsp_inst]` → returns physical placement location
- Example: `get_property INIT [get_cells lut_inst]` → returns LUT truth table (hex)
- Example: `get_property ROUTE [get_nets data_net]` → returns routing string

### get_runs
Retrieve synthesis or implementation run objects.
```
get_runs [<pattern>]
```
- `-filter {IS_SYNTHESIS == 1}` — synthesis runs only
- `-filter {STATUS == Complete}` — completed runs only

### get_selected_objects
Retrieve currently selected objects in the Vivado GUI.

### get_site_pins ⚠️
Retrieve physical site pin objects (the connection points between BELs and the routing fabric).
```
get_site_pins [<pattern>]
```
- `-of_objects <sites|bels>` — site pins for specific sites or BELs
- `-filter {DIRECTION == IN}` — input site pins only
- Used for detailed placement and routing analysis at the BEL level.

### get_sites
Retrieve physical device site objects (SLICE_X0Y0, DSP48_X0Y0, etc.).
```
get_sites [<pattern>]
```
- `-of_objects <tiles|pblocks>` — sites within specific tiles or Pblocks
- `-filter {SITE_TYPE == SLICEL}` — filter by site type
- `-filter {IS_USED == 1}` — occupied sites only
- Site types: `SLICEL`, `SLICEM`, `DSP48E1`, `RAMB36E2`, `IOB33`, `MMCME2_ADV`

### get_slrs
Retrieve Super Logic Region objects. `[UltraScale+ multi-die only]`

### get_speed_models
Retrieve timing speed model objects for specific cells (used in custom timing analysis).
```
get_speed_models <cell_type>
```

### get_timing_arcs
Retrieve timing arc objects (individual setup/hold/propagation arcs within cells).
```
get_timing_arcs
```
- `-of_objects <cells|pins>` — arcs for specific cells
- `-filter {TYPE == setup}` — setup arcs only
- Used for manual timing analysis and custom constraint creation.

### get_timing_paths
Retrieve timing path objects from the static timing analysis engine.
```
get_timing_paths
```
- `-from <startpoints>` — path source (registers, ports)
- `-to <endpoints>` — path destination
- `-through <pins|cells>` — path must pass through these objects
- `-max_paths <n>` — limit number of returned paths (default: 1)
- `-nworst <n>` — return N worst paths per endpoint
- `-setup` — return setup-critical paths
- `-hold` — return hold-critical paths
- `-slack_less_than <ns>` — filter paths with slack worse than this value
- `-dataflow` — show dataflow-only paths (no clock paths)
- Example: `get_timing_paths -setup -max_paths 10 -slack_less_than 0` → all failing setup paths

### get_tiles ⚠️ (Critical for physical analysis)
Retrieve physical tile objects (CLB, INT, BRAM, DSP, IOB tile grid locations).
```
get_tiles [<pattern>]
```
- `-of_objects <sites|pips|nodes>` — tiles containing specific objects
- `-filter {TYPE == INT_L}` — filter by tile type
- `-filter {TILE_X == 2}` — filter by X coordinate
- Tile types: `CLBLL_L`, `CLBLL_R`, `CLBLM_L`, `CLBLM_R`, `INT_L`, `INT_R`, `BRAM_L`, `DSP_L`, `IOB33`, `HCLK`
- Example: `get_tiles -filter {TYPE =~ BRAM*}` → all BRAM tile locations

### get_wires ⚠️ (Critical for routing analysis)
Retrieve individual wire segment objects within the routing fabric.
```
get_wires [<pattern>]
```
- `-of_objects <tiles|nodes|pips>` — wires in specific tiles or connected to nodes/PIPs
- `-filter {TILE_NAME =~ INT_L*}` — filter by tile name
- Example: `get_wires -of_objects [get_nodes INT_L_X2Y10/NE2BEG1]`
- ⚠️ Can return enormous collections. Always scope with `-of_objects`.

---

## group_*

### group_bd_cells
Group block design cells into a hierarchical subsystem container.
```
group_bd_cells <group_name> <cells>
```
- `-parent <parent_cell>` — parent hierarchy level for the group

### group_path
Create a named timing path group for organizing `report_timing` output.
```
group_path -name <group_name>
```
- `-from <startpoints>` — paths originating from these points
- `-to <endpoints>` — paths ending at these points
- `-through <pins>` — paths passing through these pins
- `-weight <n>` — relative weight for timing-driven placement of this group
- `-default_clock` — place unconstrained clock paths into this group

---

## implement_*

### implement_debug_core
Insert, wire, and place debug cores (ILA/VIO) into the implemented design.
```
implement_debug_core
```
- ⚠️ Must be called after `route_design` and before `write_bitstream` when using debug cores.

---

## import_*

### import_files
Copy external files into the project directory and add them to the project.
```
import_files <files>
```
- `-fileset <fileset>` — target fileset
- `-force` — overwrite existing files

### import_ip
Import an existing `.xci` IP customization file into the project.
```
import_ip <xci_file>
```

---

## launch_*

### launch_runs
Start one or more synthesis or implementation runs.
```
launch_runs <run_objects>
```
- `-jobs <n>` — number of parallel CPU threads to use
- `-to_step <step>` — stop after a specific implementation step (e.g., `route_design`)
- `-next_step` — run only the next step in sequence
- `-force` — run even if results are up to date
- `-pre_launch_script <script.tcl>` — run a Tcl script before the run starts
- `-post_launch_script <script.tcl>` — run a Tcl script after the run completes
- Example: `launch_runs impl_1 -jobs 8` → 8-threaded implementation

### launch_simulation
Start a simulation session.
```
launch_simulation
```
- `-mode <behavioral|post-synthesis|post-implementation>` — simulation type
- `-type <functional|timing>` — functional (no delay) or gate-level timing simulation
- `-simset <fileset>` — simulation fileset to use
- `-absolute_path` — use absolute paths in generated scripts

---

## list_*

### list_property
Show all properties and their values for a given Vivado object.
```
list_property <object>
```
- `-class <class_name>` — list properties for an object class (not instance)
- `-all` — include read-only properties

### list_targets
Show all available JTAG hardware targets.

---

## lock_*

### lock_design ⚠️ (Critical for Partial Reconfiguration)
Lock placement and/or routing of the current design to preserve it across RM implementations.
```
lock_design
```
- `-level placement` — lock only cell placement (sites), not routing
- `-level routing` — lock both placement and routing ← **use this for PR flows**
- `-unlock` — remove locks from the design
- ⚠️ In the PR flow: after implementing the static design, call `lock_design -level routing` before loading each reconfigurable module. This prevents Vivado from moving any static routes when implementing the RM.

---

## log_*

### log_saif
Begin logging switching activity to a SAIF file for post-simulation power analysis.
```
log_saif <saif_file>
```
- `-scope <hierarchy_path>` — log activity only for signals in this scope

### log_wave
Log all simulation signals to a waveform database file.
```
log_wave -r /
```
- `-r` — recursive (log all signals in the design)
- `-ports_only` — log only port signals

---

## make_*

### make_diff_pair_ports
Create differential I/O port pairs (P and N) at the top level.
```
make_diff_pair_ports <p_port> <n_port>
```

### make_wrapper
Generate an HDL wrapper file around a block design, required before synthesis.
```
make_wrapper -files [get_files <bd_file>] -top
```
- `-top` — generate a top-level wrapper suitable for synthesis
- `-testbench` — generate a simulation testbench wrapper
- ⚠️ Must be called and the resulting wrapper added to the project before synthesizing any block design.

---

## move_*

### move_bd_cells
Relocate cells within the block design hierarchy.
```
move_bd_cells -to_hier_cell <destination> <cells>
```

### move_pblock
Relocate a Pblock by changing its site range assignment.
```
resize_pblock <pblock> -add {SLICE_X0Y0:SLICE_X10Y25}
```
- ⚠️ There is no `move_pblock` primitive — use `delete_pblocks` and `create_pblock` with a new range, or use `resize_pblock` to redefine the range.

---

## open_*

### open_bd_design
Open an existing block design file.
```
open_bd_design <bd_file_path>
```

### open_checkpoint
Load a saved design checkpoint (`.dcp`) file into memory.
```
open_checkpoint <dcp_file>
```
- `-part <part>` — override the target part
- ⚠️ DCP files contain a complete snapshot of the design state (netlist + placement + routing). Opening a DCP is the primary mechanism for resuming work or loading partial results.

### open_hw_manager
Open the hardware debugging session in Vivado.
```
open_hw_manager
```

### open_hw_target
Connect to a specific JTAG hardware target (board).
```
open_hw_target [<target_object>]
```

### open_project
Open a saved Vivado project.
```
open_project <xpr_file>
```
- `-read_only` — open project without write access

### open_run
Load a completed synthesis or implementation run result into memory for analysis.
```
open_run <run_name>
```
- `-name <design_name>` — assign a name to the opened design in memory
- Example: `open_run impl_1 -name impl_design` → loads the implemented design

---

## phys_* and power_*

### phys_opt_design
Run post-placement physical optimization to improve timing.
```
phys_opt_design
```
- `-directive <directive>` — optimization strategy:
  - `Default` — standard optimization
  - `Explore` — more aggressive exploration
  - `AggressiveExplore` — maximum exploration (longer runtime)
  - `AlternateReplication` — focus on replication of high-fanout nets
  - `AggressiveFanoutOpt` — aggressive fanout reduction
- `-fanout_opt` — optimize high-fanout nets by replication
- `-placement_opt` — re-optimize critical path placement
- `-routing_opt` — optimize routing for critical paths
- `-retime` — perform register retiming across logic boundaries
- `-hold_fix` — insert delay buffers to fix hold violations
- `-critical_cell_opt` — swap cells to improve critical path delays
- ⚠️ Running `phys_opt_design` multiple times can sometimes improve timing further. Diminishing returns typically set in after 2–3 iterations.

### power_opt_design
Apply power reduction optimizations before or after placement.
```
power_opt_design
```
- `-quiet` — suppress output messages
- Inserts clock enables, optimizes BRAM power modes, reduces unnecessary switching.

---

## place_*

### place_cell
Manually assign a specific logical cell to a physical site (ECO/manual floorplanning).
```
place_cell <cell> <site>
```
- Example: `place_cell dsp_inst DSP48_X0Y5`
- ⚠️ Manual placement overrides Vivado's placer. Use only when you have a specific reason — it can make timing closure harder.

### place_design
Run the global cell placement algorithm.
```
place_design
```
- `-directive <directive>` — placement strategy:
  - `Default` — standard placement
  - `Explore` — tries multiple placements (longer runtime)
  - `ExtraNetDelay_high` — spreads placement to reduce net delays
  - `SpreadLogic_high` — spreads logic to reduce congestion
  - `AltSpreadLogic_high` — alternative spread algorithm
  - `WLDrivenBlockPlacement` — wirelength-driven placement
  - `RuntimeOptimized` — faster placement, lower QoR
  - `Quick` — fastest placement, lowest QoR
- `-no_timing_driven` — disable timing-driven placement (rarely useful)
- `-unplace` — unplace all cells (reset placement)
- ⚠️ After placement, always run `report_timing_summary` before routing to catch placement-caused violations early.

### place_ports
Assign top-level I/O ports to specific physical package pins.
```
place_ports <ports>
```
- ⚠️ Normally done via XDC `set_property PACKAGE_PIN` constraints. `place_ports` is for interactive use.

---

## pr_*

### pr_recombine
Recombine a partitioned Partial Reconfiguration design back into a single monolithic checkpoint.
```
pr_recombine -cell <rp_cell> -reconfig_module <rm_dcp>
```

### pr_verify ⚠️
Verify that two or more Reconfigurable Module implementations are compatible with each other and the static design.
```
pr_verify -in_checkpoint1 <dcp1> -in_checkpoint2 <dcp2>
```
- `-full_check` — perform exhaustive compatibility checking
- ⚠️ This must pass before a partial bitstream is valid for use. A failed `pr_verify` means partition pins are mismatched between RM implementations — the design will malfunction at runtime.

---

## program_*

### program_hw_cfgmem
Program a configuration flash memory (QSPI, BPI) device connected to the FPGA.
```
program_hw_cfgmem -hw_cfgmem <cfgmem_object>
```
- `-force` — program even if device appears programmed

### program_hw_devices
Program the FPGA with a bitstream file.
```
program_hw_devices [get_hw_devices]
```
- `-bitfile <path>` — path to `.bit` file (if not already set as property)
- `-ltxfile <path>` — path to `.ltx` debug probes file
- ⚠️ Set the bitstream first: `set_property PROGRAM.FILE {path/to/design.bit} [get_hw_devices]`
- ⚠️ Set the LTX file for ILA/VIO: `set_property PROBES.FILE {path/to/design.ltx} [get_hw_devices]`

---

## read_*

### read_checkpoint
Import a DCP file as a black-box module reference (does not open for editing).
```
read_checkpoint -cell <cell_name> <dcp_file>
```
- `-cell <name>` — load DCP as the implementation of a specific hierarchical cell
- ⚠️ Used in the PR flow to load a locked static design when implementing RMs.

### read_hw_ila_data
Import a previously saved ILA capture data file for offline analysis.
```
read_hw_ila_data <data_file>
```

### read_verilog
Read Verilog source files into the in-memory design (non-project mode).
```
read_verilog <files>
```
- `-sv` — parse as SystemVerilog
- `-library <lib>` — assign to a specific HDL library

### read_vhdl
Read VHDL source files into the in-memory design.
```
read_vhdl <files>
```
- `-library <lib>` — assign to a specific VHDL library (default: `work`)
- `-vhdl2008` — parse as VHDL-2008 ⚠️ not all constructs supported

### read_xdc
Read Xilinx Design Constraint files into the design.
```
read_xdc <xdc_file>
```
- `-mode <out_of_context|default>` — constraint mode
- `-unmanaged` — read constraints without project management tracking

---

## refresh_*

### refresh_design
Update the active design after constraint changes without re-running implementation.
```
refresh_design
```

### refresh_hw_device
Refresh the hardware device status in Hardware Manager.
```
refresh_hw_device [<device_object>]
```
- `-update_hw_probes <true|false>` — reload probe definitions from LTX file

---

## remove_*

### remove_files
Remove files from the project (does not delete from disk by default).
```
remove_files <files>
```
- `-fileset <fileset>` — remove from specific fileset
- `-delete` — also delete the file from disk ⚠️

### remove_force
Release a forced signal value applied with `add_force` during simulation.
```
remove_force <force_object>
```

### remove_net
Delete a logical net from the post-synthesis netlist (ECO flow).
```
remove_net <net>
```

### remove_wave
Remove a signal from the simulation waveform viewer.
```
remove_wave <wave_object>
```

---

## rename_*

### rename_cell
Change a logical cell's name in the netlist.
```
rename_cell -to <new_name> <cell>
```

### rename_net
Change a logical net's name in the netlist.
```
rename_net -to <new_name> <net>
```

---

## report_*

### report_bus_skew ⚠️
Report the skew between signals in a bus (clock-domain-crossing bus analysis).
```
report_bus_skew
```
- `-from <sources>` — source pins
- `-to <sinks>` — sink pins
- `-warn_on_violation` — generate warning messages on violations
- `-dataflow` — analyze dataflow skew

### report_cdc ⚠️
Analyze and report Clock Domain Crossing issues.
```
report_cdc
```
- `-from <clocks>` — source clock domains
- `-to <clocks>` — destination clock domains
- `-severity <critical|warning|info>` — filter by severity
- `-details` — include detailed path information
- `-return_string` — return report as string
- `-file <file>` — write report to file
- `-waived` — include waived violations
- `-no_header` — suppress header
- ⚠️ Always run before routing. Critical CDC issues (unsynchronized crossings) cause random failures that are nearly impossible to debug in hardware.

### report_clock_interaction
Show the relationships and timing interaction between all clock domains.
```
report_clock_interaction
```
- `-delay_type <min|max|min_max>` — which delay to analyze
- `-significant_bits <n>` — decimal precision
- ⚠️ Look for "Unsafe" entries — these are CDC paths that need synchronization.

### report_clock_networks
Report the clock network topology and flag any unconstrained clocks.
```
report_clock_networks
```
- `-hierarchical` — show hierarchical clock sources
- ⚠️ Any clock shown as "Unconstrained" means `create_clock` was not called for it. All timing on paths clocked by it is invalid.

### report_clock_utilization
Report BUFG, BUFR, MMCM, and PLL usage and remaining availability.
```
report_clock_utilization
```
- `-clock_roots_only` — show only clock root primitives

### report_compile_order
Report the HDL source file compilation order (dependency chain).
```
report_compile_order
```
- `-fileset <fileset>` — report for a specific fileset
- `-used_in <synthesis|simulation>` — report for specific use

### report_design_analysis ⚠️
Report design quality metrics: critical path depth, congestion heatmap, and QoR.
```
report_design_analysis
```
- `-max_paths <n>` — number of paths to analyze
- `-show_all` — show all paths including unconstrained
- `-congestion` — include routing congestion heat map analysis `[2018+]`
- `-complexity` — show logic depth complexity analysis
- `-timing` — include timing-related analysis
- `-file <file>` — output to file
- ⚠️ The congestion heatmap from this command is the primary tool for diagnosing placement congestion that causes routing failures.

### report_drc
Run Design Rule Checks and report violations.
```
report_drc
```
- `-checks <check_list>` — run only specific checks
- `-ruledecks <ruledecks>` — run a named set of rules
- `-file <file>` — write to file
- `-return_string` — return as string
- `-quiet` — suppress output

### report_io
Report I/O pin assignments, I/O standards, and I/O bank assignments.
```
report_io
```
- `-file <file>` — output to file
- ⚠️ Always run before generating the bitstream. Unassigned I/O or mismatched VCCO/IOSTANDARD combinations are caught here.

### report_methodology
Run Xilinx UltraFast Design Methodology checks for design quality best practices.
```
report_methodology
```
- `-checks <checks>` — specific methodology checks to run
- `-file <file>` — write to file
- ⚠️ Includes checks for missing CDC constraints, unregistered I/Os, and other common design pitfalls.

### report_power
Estimate device power consumption.
```
report_power
```
- `-file <file>` — write to file
- `-format <text|xml>` — output format
- `-hier <cell>` — report power breakdown for a specific hierarchy
- `-advisory` — include power reduction advisories
- ⚠️ For accurate results, run after synthesis and provide switching activity via SAIF or `set_switching_activity`.

### report_property
Show all properties and values for a specific object.
```
report_property <object>
```
- `-all` — include read-only properties
- `-return_string` — return as string

### report_qor_suggestions ⚠️
Generate automated suggestions for timing closure improvements. `[2018+]`
```
report_qor_suggestions
```
- `-max_suggestions <n>` — limit number of suggestions
- `-file <file>` — write to file
- `-of_objects <runs>` — generate suggestions for specific runs
- Outputs directives, placement, and constraint changes that may improve QoR.

### report_route_status
Report routing completion status, including unrouted nets and routing errors.
```
report_route_status
```
- `-of_objects <nets>` — report status for specific nets
- `-file <file>` — write to file
- ⚠️ A design with unrouted nets (`report_route_status` showing failures) cannot be used for bitstream generation.

### report_ssn
Report Simultaneous Switching Noise (SSN) analysis for I/O banks.
```
report_ssn
```
- `-file <file>` — write to file
- `-format <text|html>` — output format
- ⚠️ Important for designs with many output drivers switching simultaneously — can cause I/O signal integrity failures on real PCBs.

### report_timing ⚠️
Show detailed static timing analysis for specific paths.
```
report_timing
```
- `-from <startpoints>` — path source
- `-to <endpoints>` — path destination
- `-through <pins|cells>` — path must pass through these
- `-max_paths <n>` — number of paths to report (default: 1)
- `-nworst <n>` — worst N paths per endpoint
- `-setup` — report setup paths
- `-hold` — report hold paths
- `-delay_type <min|max|min_max>` — delay type
- `-path_type <short|full|full_clock|full_clock_expanded>` — detail level
  - `full_clock_expanded` ← most detailed; shows every segment of clock and data path
- `-slack_less_than <ns>` — show only paths with slack worse than this value
- `-no_report_unconstrained` — exclude unconstrained paths
- `-file <file>` — write to file
- `-return_string` — return as string
- `-dataflow` — show only data path (no clock path shown)

### report_timing_summary ⚠️
Show overall timing pass/fail status across all clock domains.
```
report_timing_summary
```
- `-max_paths <n>` — paths per timing group (default: 10)
- `-nworst <n>` — worst N paths per endpoint
- `-setup` / `-hold` — limit to setup or hold analysis
- `-file <file>` — write to file
- `-return_string` — return as string
- `-warn_on_violation` — exit with warning if any violations exist
- `-check_timing_verbose` — include constraint completeness check
- ⚠️ The WNS (Worst Negative Slack) in this summary is the single most important timing metric. WNS < 0 = timing violation = design will malfunction at the target frequency.

### report_utilization
Show FPGA resource usage breakdown.
```
report_utilization
```
- `-hierarchical` — show utilization broken down by module hierarchy
- `-hierarchical_depth <n>` — depth of hierarchy to show
- `-file <file>` — write to file
- `-return_string` — return as string
- `-pblocks <pblocks>` — report utilization within specific Pblocks

---

## reset_*

### reset_project
Clear all run data and results for the project without deleting sources.
```
reset_project
```

### reset_runs
Reset one or more synthesis or implementation runs to their initial unrun state.
```
reset_runs <run_objects>
```

### reset_timing
Clear all applied timing constraints from the in-memory design.
```
reset_timing
```
- ⚠️ Useful for debugging constraint conflicts — after `reset_timing`, re-apply constraints one group at a time to isolate the problem.

---

## route_design

Perform global and detailed signal routing.
```
route_design
```
- `-directive <directive>` — routing strategy:
  - `Default` — standard routing
  - `Explore` — multiple routing attempts
  - `AggressiveExplore` — maximum exploration
  - `NoTimingRelaxation` — never relax timing to achieve routing completion
  - `MoreGlobalIterations` — more global routing passes
  - `HigherDelayCost` — prefer shorter routes even at delay cost
  - `RuntimeOptimized` — faster routing, lower QoR
  - `Quick` — fastest routing, lowest QoR (for DRC checks only)
- `-nets <nets>` — route only specific nets
- `-unroute` — unroute all nets (reset routing)
- `-preserve` — preserve existing routing (re-route only unrouted nets)
- `-tns_cleanup` — post-routing TNS (Total Negative Slack) cleanup pass `[2018+]`
- ⚠️ After routing, always run `report_timing_summary` and `report_route_status` before `write_bitstream`.

---

## run_*

### run
Advance simulation time.
```
run <time><units>
```
- `run 100ns` — run for 100 nanoseconds
- `run 1us` — run for 1 microsecond
- `run -all` — run until simulation terminates or breakpoint hits
- `run 1000` — run 1000 time units (in current simulation time scale)

### run_hw_ila
Arm and trigger an ILA core to begin data capture.
```
run_hw_ila <hw_ila_object>
```
- ⚠️ Before calling, configure trigger conditions via `set_property` on the ILA object.

---

## save_*

### save_bd_design
Save the active block design to disk.
```
save_bd_design
```

### save_constraints
Write any unsaved constraint changes back to the XDC file.
```
save_constraints
```
- `-force` — write even if no changes detected

### save_project_as
Clone the current project to a new name and location.
```
save_project_as <new_name> <new_dir>
```
- `-include_run_results` — include all run output files in the copy
- `-force` — overwrite if destination exists

---

## scan_*

### scan_ir_hw_jtag
Scan the JTAG instruction register of a connected device.
```
scan_ir_hw_jtag <n_bits> <tdi_value>
```
- Used for low-level JTAG debugging and custom TAP access.

---

## set_*

### set_bus_skew
Constrain the maximum routing skew allowed across a bus (for source-synchronous interfaces).
```
set_bus_skew -from <sources> -to <sinks> <skew_ns>
```
- ⚠️ Critical for parallel bus interfaces where all bits must arrive at the destination within a tight window.

### set_clock_groups ⚠️
Declare that two or more clock groups are asynchronous (no timing analysis between them).
```
set_clock_groups -asynchronous -group {clk_a} -group {clk_b}
```
- `-asynchronous` — clocks have no phase relationship (most common for independent domains)
- `-exclusive` — clocks are mutually exclusive (never active simultaneously, e.g., clock mux outputs)
- `-physically_exclusive` — same as exclusive, for physically distinct clock networks
- `-logically_exclusive` — logically exclusive (clock mux)
- `-group <clocks>` — define each clock group
- ⚠️ `set_clock_groups -asynchronous` is equivalent to `set_false_path` in both directions between the groups. Do not use it unless you have proper CDC synchronizers in place — it tells Vivado to ignore those paths, not to protect them.

### set_clock_latency
Model the external board-level clock delay (trace delay from oscillator to FPGA pin).
```
set_clock_latency -source <ns> [get_ports <clock_port>]
```
- `-source` — applies to source latency (before the clock definition point)
- `-late` / `-early` — specify worst-case late or early arrival
- Used to model PCB-level clock routing delays for accurate I/O timing analysis.

### set_clock_sense
Set the polarity sense (non-inverted or inverted) of a clock through a specific cell.
```
set_clock_sense -positive <pins>
set_clock_sense -negative <pins>
```
- Used when a clock passes through a LUT or combinational cell — tells Vivado whether it is inverted.

### set_data_check
Constrain a data-to-data timing relationship (not clock-to-data).
```
set_data_check -from <source_pin> -to <sink_pin> -setup <ns>
set_data_check -from <source_pin> -to <sink_pin> -hold <ns>
```
- Used for constraining signals that are not registered but have specific setup/hold requirements relative to another data signal.

### set_disable_timing
Disable specific timing arcs within a cell (advanced hold fixing or loop-breaking).
```
set_disable_timing -from <from_pin> -to <to_pin> <cell>
```
- ⚠️ Use with extreme care. Disabling a timing arc removes it from all timing analysis — any path through that arc becomes unconstrained and unverified.

### set_drive
Model the external drive strength seen at an input port (affects timing analysis of input paths).
```
set_drive <drive_strength> [get_ports <input_ports>]
```

### set_false_path ⚠️
Tell Vivado to completely ignore timing analysis on a specific path.
```
set_false_path
```
- `-from <startpoints>` — path sources
- `-to <endpoints>` — path destinations
- `-through <pins|cells>` — path must pass through these
- `-setup` — apply only to setup analysis
- `-hold` — apply only to hold analysis
- `-from [get_clocks clk_a] -to [get_clocks clk_b]` — ignore all cross-domain paths
- ⚠️ `set_false_path` does not protect a path — it ignores it entirely. Using it on an unprotected CDC path is a common and dangerous mistake that causes random hardware failures.

### set_input_delay ⚠️
Constrain the external input data arrival time relative to a clock.
```
set_input_delay -clock <clock> -max <ns> [get_ports <ports>]
set_input_delay -clock <clock> -min <ns> [get_ports <ports>]
```
- `-clock <clock>` — reference clock for the delay
- `-max <ns>` — maximum arrival time (setup analysis)
- `-min <ns>` — minimum arrival time (hold analysis)
- `-clock_fall` — delay is relative to the falling edge of the clock
- `-add_delay` — add to an existing constraint rather than replace
- ⚠️ Must specify both `-max` and `-min` for complete I/O timing analysis. A missing `-min` means hold analysis on this input is unconstrained.

### set_load
Model external capacitive load on output pins for timing analysis.
```
set_load <capacitance_pF> [get_ports <output_ports>]
```

### set_max_delay
Constrain the maximum allowable delay on a path.
```
set_max_delay <ns>
```
- `-from <sources>` — path sources
- `-to <endpoints>` — path endpoints
- `-through <pins>` — through specific pins
- `-datapath_only` — relax clock skew compensation for this path ← use for CDC paths with known timing budget
- ⚠️ `-datapath_only` is the correct way to constrain a CDC path where you know the exact timing budget. It removes clock uncertainty and skew from the analysis — use only when you are certain of the source-to-destination clock relationship.

### set_multicycle_path ⚠️
Relax timing analysis for paths that intentionally take multiple clock cycles.
```
set_multicycle_path <n>
```
- `-from <sources>` — path sources
- `-to <endpoints>` — path endpoints
- `-setup <n>` — number of cycles for setup analysis (data can be N cycles late)
- `-hold <n-1>` — **must also set hold** to `N-1` when setting setup to `N` ← most common mistake
- `-start` — reference the launch clock for the multicycle count
- `-end` — reference the capture clock for the multicycle count (default)
- ⚠️ Always pair `-setup N` with `-hold N-1`. Failing to do so means the hold check tightens to an impossible requirement, and the router will fail trying to fix it.

### set_operating_conditions
Set the PVT (Process-Voltage-Temperature) corner for timing and power analysis.
```
set_operating_conditions -grade <commercial|industrial|extended|military>
```
- `-process <typical|slow|fast>` — process corner
- `-voltage <vccint_value>` — override VCCINT voltage
- `-temperature <celsius>` — override junction temperature

### set_output_delay ⚠️
Constrain the external output data requirement time relative to a clock.
```
set_output_delay -clock <clock> -max <ns> [get_ports <ports>]
set_output_delay -clock <clock> -min <ns> [get_ports <ports>]
```
- Same flags as `set_input_delay` but applied to output ports.
- ⚠️ Must specify both `-max` and `-min`. `-max` drives setup analysis; `-min` drives hold analysis.

### set_property
Write a value to any property on any Vivado object.
```
set_property <property_name> <value> <object>
```
- Common examples:
  - `set_property PACKAGE_PIN E3 [get_ports CLK_IN]` — assign I/O pin
  - `set_property IOSTANDARD LVCMOS33 [get_ports DATA_OUT]` — set I/O standard
  - `set_property INIT 64'hFEDCBA9876543210 [get_cells lut_inst/A6LUT]` — set LUT truth table
  - `set_property LOC SLICE_X0Y0 [get_cells reg_inst]` — lock cell placement
  - `set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_net]` — allow non-clock routing ⚠️
  - `set_property HD.RECONFIGURABLE true [get_cells rp_cell]` — mark PR partition
  - `set_property CONTAIN_ROUTING true [get_pblocks pblock_rp]` — contain routing to Pblock
  - `set_property SNAPPING_MODE ON [get_pblocks pblock_rp]` — snap Pblock to PR-legal boundaries

### set_switching_activity
Set toggle rate assumptions for power analysis.
```
set_switching_activity
```
- `-toggle_rate <rate>` — toggle rate as a percentage of clock frequency
- `-static_probability <prob>` — probability the signal is high (0.0–1.0)
- `-type <lut_output|register|io>` — node type to apply to
- `-hier <cell>` — apply to a specific hierarchy

---

## Simulation Commands

> These commands operate within an active simulation session launched by `launch_simulation`.

### restart
Reset the simulation to time 0 without relaunching.
```
restart
```
- ⚠️ Faster than `launch_simulation` for iterative testbench debugging.

### run
See [run_*] section — same command, different context.

### step
Advance simulation by one HDL source line or event.
```
step
```
- `-over` — step over (do not enter called procedures/modules)
- `-into` — step into (enter called procedures/modules)
- `-out` — step out of current scope back to caller

### force
Force a signal to a specific value (alias for `add_force` in simulation context).
```
force <signal> <value>
```

### release
Release a forced signal value.
```
release <signal>
```

### get_value
Read the current simulation value of a signal.
```
get_value <signal_path>
```
- `-radix <bin|hex|dec|oct|ascii>` — display radix
- Returns the current simulation time value of the signal.

### set_value
Write a value to a signal in the simulation (for testbench control).
```
set_value <signal_path> <value>
```
- `-radix <bin|hex|dec>` — value radix

### current_time
Return the current simulation timestamp.
```
current_time
```
- Returns a string like `"100 ns"`.

### get_objects
Retrieve simulation object handles by HDL path.
```
get_objects <hdl_path_pattern>
```
- `-r` — recursive search
- `-filter {TYPE == signal}` — filter by object type (signal, variable, port, etc.)

### examine
Examine (read) the value of one or more simulation objects.
```
examine <objects>
```
- `-radix <bin|hex|dec>` — display radix
- `-time <time>` — examine value at a specific past simulation time

### deposit
Deposit a value onto a signal without creating a persistent force.
```
deposit <signal> <value>
```
- Unlike `force`, a deposit can be overridden by the RTL logic on the next event.

---

## start_* and stop_*

### start_gui
Launch the Vivado graphical interface from a batch/Tcl session.
```
start_gui
```

### startgroup
Begin an atomic GUI undo group (all actions until `endgroup` are undone as one step).
```
startgroup
```

### stop_gui
Close the Vivado GUI and return to Tcl console mode.
```
stop_gui
```

### stop_vcd
Stop dumping signal values to the open VCD file.
```
stop_vcd
```

---

## synth_*

### synth_design ⚠️
Run RTL synthesis — the primary synthesis command.
```
synth_design -top <top_module_name> -part <part>
```
- `-top <name>` — top-level module/entity name ← **required**
- `-part <part>` — target device ← **required in non-project mode**
- `-include_dirs <dirs>` — Verilog include search paths
- `-generic <param=value>` — override generic/parameter values
- `-flatten_hierarchy <none|rebuilt|full>` — hierarchy flattening mode
  - `rebuilt` ← default; rebuilds hierarchy after optimization for clean reports
  - `full` ← full flatten; best optimization but loses hierarchy in reports
  - `none` ← preserve all hierarchy; most restrictive optimization
- `-gated_clock_conversion <off|on|auto>` — convert gated clocks to CE-based clocks
- `-directive <directive>` — synthesis strategy
  - `Default`, `RuntimeOptimized`, `AreaOptimized_high`, `AreaOptimized_medium`, `AlternateRoutability`, `FewerCarryChains`
- `-fsm_extraction <auto|one_hot|sequential|johnson|gray|user_encoding|off>` — FSM encoding
- `-resource_sharing <auto|on|off>` — share hardware resources across operations
- `-retiming <true|false>` — enable register retiming
- `-no_lc` — disable LUT combining (fracturing)
- `-keep_equivalent_registers` — prevent merging of identical registers
- `-mode <default|out_of_context>` — OOC mode for IP or block design sub-modules
- `-bufg <n>` — maximum number of BUFG primitives to insert (default: 12)
- ⚠️ After synthesis, always check `report_utilization` for unexpected resource counts before proceeding to implementation.

### synth_ip
Run out-of-context synthesis for a specific IP core.
```
synth_ip <ip_objects>
```
- `-force` — re-synthesize even if up to date

---

## update_*

### update_compile_order
Re-evaluate the HDL source file dependency order after adding or modifying files.
```
update_compile_order -fileset <fileset>
```

### update_design
Replace a black-box cell in the netlist with a new sub-design netlist (used in PR RM flows).
```
update_design -cell <cell_name> -black_box
update_design -cell <cell_name> -netlist <netlist_file>
```
- `-black_box` — convert the cell to an empty black box ← used before loading a new RM
- `-netlist <file>` — replace black box with a specific netlist
- ⚠️ In the PR flow: `update_design -cell rp_inst -black_box` then `read_checkpoint -cell rp_inst rm_b.dcp`

### update_ip_catalog
Refresh the IP repository to pick up newly added or modified IP cores.
```
update_ip_catalog
```
- `-add_ip <xci_or_zip>` — add a specific IP package to the catalog
- `-repo_path <path>` — specify custom IP repository path

---

## upgrade_*

### upgrade_ip
Update one or more IP cores to the latest version available in the current Vivado installation.
```
upgrade_ip <ip_objects>
```
- `-log <file>` — write upgrade log to file
- ⚠️ Always review the upgrade log. IP parameter renames or removed ports can break the containing design silently.

---

## validate_*

### validate_bd_design
Check the active block design for connection errors, unconnected ports, and IP configuration problems.
```
validate_bd_design
```
- `-force` — force re-validation even if already validated
- ⚠️ Always run before calling `generate_target` or `export_bd_synth` on a block design.

### validate_ip
Check an IP core's configuration for errors.
```
validate_ip <ip_objects>
```

---

## wait_*

### wait_on_hw_ila
Block the Tcl script until an ILA core triggers and completes its capture.
```
wait_on_hw_ila <hw_ila_object>
```
- `-timeout <seconds>` — abort wait after this many seconds
- ⚠️ Essential in automated test scripts — without this, the script continues before capture is complete and `read_hw_ila_data` returns empty results.

### wait_on_runs
Block the Tcl script until specified runs complete.
```
wait_on_runs <run_objects>
```
- `-timeout <seconds>` — abort after timeout
- `-quiet` — suppress output while waiting
- Example: `wait_on_runs impl_1` — blocks until implementation finishes

---

## write_*

### write_bd_tcl
Export the active block design as a self-contained Tcl script that can recreate it from scratch.
```
write_bd_tcl <output_file>
```
- `-force` — overwrite existing file
- `-include_layout` — include GUI layout information
- ⚠️ Use this for version control of block designs — BD files (`.bd`) are large binary-ish XML; the Tcl script is diffable.

### write_bitstream ⚠️
Generate the final programming bitstream from the routed design.
```
write_bitstream <output_file>
```
- `-force` — overwrite existing bitstream
- `-cell <cell>` — write a partial bitstream for a specific cell (PR flow)
- `-no_partial_bitfile` — skip writing partial bitstream in a PR design
- `-bin_file` — also write a raw binary (`.bin`) file
- `-readback_file` — include readback mask file generation
- `-logic_location_file` — write logic location file (`.ll`) mapping nets to bitstream bits
- ⚠️ Always run `report_timing_summary` and `report_drc` before this. A bitstream generated from a design with timing violations will silently produce hardware that malfunctions.

### write_cfgmem
Generate a flash programming file (`.mcs` or `.bin`) for configuration memory.
```
write_cfgmem
```
- `-format <MCS|BIN|HEX>` — output format
- `-size <mb>` — flash memory size in megabytes
- `-interface <SPIx1|SPIx2|SPIx4|BPIx8|BPIx16>` — flash interface type
- `-loadbit {up 0x00000000 design.bit}` — input bitstream and load address
- `-force` — overwrite existing file
- Example: `write_cfgmem -format MCS -size 16 -interface SPIx4 -loadbit {up 0 design.bit} -file flash.mcs`

### write_checkpoint
Save the current design state to a DCP file for later use.
```
write_checkpoint <output_file>
```
- `-force` — overwrite existing file
- `-cell <cell>` — write checkpoint for a specific hierarchical cell only
- ⚠️ Write checkpoints after each major step (synthesis, placement, routing) to enable resuming without re-running expensive steps.

### write_hw_ila_data
Export captured ILA waveform data to a file for offline analysis.
```
write_hw_ila_data <output_file> <hw_ila_data_object>
```
- `-csv` — export as CSV format (importable to Excel/Python)

### write_project_tcl
Export the entire project as a Tcl script that can recreate it from scratch.
```
write_project_tcl <output_file>
```
- `-force` — overwrite
- `-use_bd_files` — reference BD files directly rather than inline Tcl
- ⚠️ Use for project portability and version control — the `.xpr` project file is not easily version-controlled.

### write_schematic
Export a schematic view of the design to a file.
```
write_schematic <output_file>
```
- `-format <pdf|svg|png>` — output format
- `-orientation <landscape|portrait>` — page orientation

### write_xdc
Export the current timing and physical constraints to an XDC file.
```
write_xdc <output_file>
```
- `-force` — overwrite
- `-no_fixed_only` — include all constraints, not just fixed ones
- `-exclude_timing` — export physical constraints only
- `-cell <cell>` — export constraints scoped to a specific cell

---

## Non-Prefixed and Singular Commands

### archive_project
Package the project and all its files into a portable ZIP archive.
```
archive_project <output_zip>
```
- `-force` — overwrite existing archive
- `-include_run_results` — include synthesis and implementation output files
- `-exclude_run_results` — omit run outputs (smaller archive, sources only)

### auto_detect_xpm
Automatically detect and enable Xilinx Parameterized Macros (XPM) in the design.
```
auto_detect_xpm
```

### boot_hw_device
Trigger a JTAG boot or reprogram sequence on the connected hardware device.
```
boot_hw_device <device_object>
```

### endgroup
End an atomic GUI undo group started by `startgroup`.
```
endgroup
```

### filter
Filter a Tcl list of objects based on property expressions.
```
filter <objects> <expression>
```
- Example: `filter [get_cells -hierarchical *] {REF_NAME == FDRE && IS_PRIMITIVE == 1}`
- ⚠️ `filter` operates on an already-retrieved list. For large designs, prefer `-filter` on `get_*` commands directly — it is faster because filtering happens before the list is built.

### help
Display command documentation in the Tcl console.
```
help <command_name>
```
- `help -category <category>` — list all commands in a category
- `help -syntax <command>` — show syntax only

### highlight_objects
Colorize specific objects in the Vivado GUI for visual inspection.
```
highlight_objects -color <color> <objects>
```
- Colors: `red`, `green`, `blue`, `yellow`, `orange`, `purple`, `cyan`, `magenta`, `white`, `black`

### link_design
Load a netlist and build the in-memory design for a non-project flow.
```
link_design -top <top_name> -part <part>
```
- `-mode <default|out_of_context>` — design mode
- `-reconfig_partitions <cell_list>` — specify PR partitions during link

### opt_design
Optimize the synthesized netlist before placement.
```
opt_design
```
- `-directive <directive>`:
  - `Default`
  - `Explore` — more aggressive constant propagation and mapping
  - `ExploreArea` — optimize for area
  - `ExploreSequentialArea` — reduce sequential resource usage
  - `NoBramPowerOpt` — skip BRAM power optimization
  - `RuntimeOptimized` — faster, lower QoR
- `-propconst` — propagate constants (default on)
- `-sweep` — remove unused logic (dead code elimination, default on)
- `-remap` — remap LUT combinations (default on)
- `-resynth_area` — re-synthesize for area reduction
- `-resynth_seq_area` — re-synthesize to reduce register count

### pr_verify
See [pr_*] section.

### redo
Redo the last undone GUI action.
```
redo
```

### resize_pblock
Change the site range of an existing Pblock.
```
resize_pblock <pblock> -add {<range>}
```
- `-add {SLICE_X0Y0:SLICE_X15Y49}` — add sites to the Pblock
- `-remove {SLICE_X0Y0:SLICE_X5Y10}` — remove sites from the Pblock
- `-locs <range>` — replace all sites with this new range

### show_objects
Display object properties in a GUI property table.
```
show_objects <objects>
```

### show_schematic
Open the schematic viewer for selected objects.
```
show_schematic <objects>
```
- `-name <view_name>` — name the schematic tab

### undo
Revert the last GUI action.
```
undo
```

### unplace_cell
Remove the placement assignment from a cell (returns it to unplaced state).
```
unplace_cell <cells>
```

### unroute_nets
Remove the routing from specific nets.
```
unroute_nets <nets>
```
- `-physical_nets` — also unroute power and ground nets

### xsim
Launch the Xilinx Simulator (XSim) engine directly.
```
xsim <snapshot_name>
```
- `-gui` — launch with waveform GUI
- `-tclbatch <tcl_script>` — run a Tcl script in batch mode
- `-log <logfile>` — write log to file
- `-wdb <wdb_file>` — specify waveform database file

---

*End of Vivado Tcl Exhaustive Reference*
