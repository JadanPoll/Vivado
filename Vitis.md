# Vitis XSCT / XSDB Commands — Exhaustive Annotated Reference
### Complete command tree covering Classic XSCT (2019–2021), Unified IDE (2022+), and XSDB

> **How to read this document:**
> - Commands marked `[Classic]` work primarily in Vitis 2019–2021 XSCT.
> - Commands marked `[Unified]` are the 2022+ Vitis Unified IDE equivalents.
> - Commands marked `[Both]` work in both flows.
> - Commands marked `[XSDB]` are hardware debugging commands (version-independent).
> - `⚠️` marks commands with critical pitfalls or common mistakes.

---

## Version Flow Overview

```
Classic XSCT (2019–2021):          Unified IDE XSCT (2022+):
  setws / getws                       setws / getws
  platform create                     platform create
  domain create (using BSP concept)   domain create (primary abstraction)
  bsp create / bsp config             ← deprecated; use domain
  app create                          app create (same, but uses domains)
  app build                           app build
```

**Key conceptual difference:**
In Classic XSCT, a **BSP (Board Support Package)** is the primary software platform abstraction.
In Unified IDE, a **Domain** replaces the BSP. A domain defines `{OS, processor, hardware platform}` as a single object. Multiple apps can share one domain.

---

## Table of Contents
1. [Workspace and Project Management](#1-workspace-and-project-management)
2. [Platform Management](#2-platform-management)
3. [Domain Management (Unified IDE primary)](#3-domain-management-unified-ide-primary)
4. [BSP Management (Classic XSCT)](#4-bsp-management-classic-xsct)
5. [Application Project Management](#5-application-project-management)
6. [System Project Management](#6-system-project-management)
7. [HSI — Hardware Software Interface](#7-hsi--hardware-software-interface)
8. [Repository and IP Management](#8-repository-and-ip-management)
9. [Target Connection and Management (XSDB)](#9-target-connection-and-management-xsdb)
10. [Device Programming and Download (XSDB)](#10-device-programming-and-download-xsdb)
11. [Debugging and Execution (XSDB)](#11-debugging-and-execution-xsdb)
12. [Registers and Memory (XSDB)](#12-registers-and-memory-xsdb)
13. [Expressions, Variables, and Stack Inspection (XSDB)](#13-expressions-variables-and-stack-inspection-xsdb)
14. [Cache and MMU Control (XSDB)](#14-cache-and-mmu-control-xsdb)
15. [JTAG — Low-Level Control (XSDB)](#15-jtag--low-level-control-xsdb)
16. [Profiling and RTOS (XSDB)](#16-profiling-and-rtos-xsdb)
17. [Sysmon and System Debug (XSDB)](#17-sysmon-and-system-debug-xsdb)
18. [Utility and Miscellaneous](#18-utility-and-miscellaneous)

---

## 1. Workspace and Project Management

### setws `[Both]`
Set the active Vitis/XSCT workspace directory. All subsequent project commands operate relative to this path.
```
setws <workspace_path>
```
- ⚠️ Must be the first command in any XSCT script. Without it, project creation writes to an undefined location.
- Example: `setws /home/user/vitis_ws`

### getws `[Both]`
Return the path of the currently active workspace.
```
getws
```

### importprojects `[Both]`
Import existing Vitis/Eclipse projects into the current workspace.
```
importprojects <project_path>
```
- `-path <path>` — path containing the project(s) to import
- Recursively searches for `.project` files at the given path.
- ⚠️ Does not copy project files — creates workspace references to the original location.

### deleteprojects `[Both]`
Delete a project from the workspace.
```
deleteprojects -name <project_name>
```
- `-workspace-only` — remove from workspace only, do not delete files from disk

### getprojects `[Both]`
List all projects in the current workspace.
```
getprojects
```
- `-type <app|platform|system>` — filter by project type `[Unified]`

---

## 2. Platform Management

### platform create `[Both]`
Create a new Vitis hardware platform from an XSA (Exported Hardware Specification) file.
```
platform create -name <platform_name> -hw <xsa_file>
```
- `-name <n>` — platform name
- `-hw <xsa_file>` — path to the `.xsa` file exported from Vivado
- `-os <standalone|linux|freertos>` — default OS for auto-generated domains `[Unified]`
- `-proc <processor_name>` — target processor for default domain `[Unified]`
- `-out <dir>` — output directory for the platform `[Unified]`
- ⚠️ The `.xsa` file is generated in Vivado via `File → Export → Export Hardware`. It contains the hardware design description (memory map, IP configuration, clock frequencies).

### platform write `[Both]`
Write (save) the platform configuration to disk.
```
platform write
```

### platform read `[Both]`
Open and load an existing platform from a `.xpfm` file.
```
platform read <xpfm_file>
```

### platform generate `[Both]`
Generate all platform output files (BSP sources, linker scripts, hardware headers).
```
platform generate
```
- `-domains <domain_list>` — generate only specific domains
- ⚠️ Must be called after `platform create` or after modifying domain settings. Without this, the generated source files are stale or missing.

### platform active `[Both]`
Set or get the active platform in the workspace.
```
platform active [<platform_name>]
```

### platform list `[Both]`
List all platforms in the current workspace.
```
platform list
```

### platform remove `[Both]`
Remove a platform from the workspace.
```
platform remove <platform_name>
```

### platform config `[Unified]`
Configure platform-level settings.
```
platform config -updatehw <new_xsa_file>
```
- `-updatehw <xsa>` — update the platform with a new hardware export (after Vivado changes)
- ⚠️ After any change to the Vivado design (adding/removing IP, changing addresses), re-export the XSA and use `-updatehw` to propagate changes to Vitis.

---

## 3. Domain Management (Unified IDE — Primary Abstraction)

> A **Domain** in Unified IDE = `{hardware platform + processor + OS + BSP settings}`.
> This is the replacement for the Classic BSP concept.

### domain create `[Unified]` ⚠️
Create a new software domain within a platform.
```
domain create -name <domain_name> -os <os_type> -proc <processor>
```
- `-name <n>` — domain name
- `-os <standalone|linux|freertos|xilkernel>` — operating system
- `-proc <ps7_cortexa9_0|psu_cortexa53_0|microblaze_0|...>` — target processor instance name (from the XSA)
- `-arch <32|64>` — processor architecture (64-bit for Cortex-A53, 32-bit for Cortex-A9/MicroBlaze)
- `-runtime <cpp|c>` — runtime language
- ⚠️ The processor name must exactly match the instance name in the hardware design. Check the XSA with `hsi get_cells -filter {IP_TYPE == PROCESSOR}`.

### domain active `[Both]`
Set or get the active domain.
```
domain active [<domain_name>]
```

### domain list `[Unified]`
List all domains in the active platform.
```
domain list
```

### domain config `[Unified]`
Configure domain-level BSP settings and driver parameters.
```
domain config -lib <library_name>
domain config -os <setting> <value>
domain config -proc <setting> <value>
```
- `-lib <n>` — add a software library to the domain (e.g., `xilffs`, `xilrsa`, `lwip`, `xilinx-embeddedsw`)
- `-remove-lib <n>` — remove a library
- `-os <param> <value>` — set an OS configuration parameter
  - Example: `domain config -os stdin uart0` — set stdin source
- `-proc <param> <value>` — set a processor BSP parameter
  - Example: `domain config -proc sleep_timer axi_timer_0`
- ⚠️ After any `domain config` change, `platform generate` must be called to regenerate BSP sources.

### domain report `[Unified]`
Report the configuration of the active or specified domain.
```
domain report
```

### domain remove `[Unified]`
Remove a domain from the platform.
```
domain remove <domain_name>
```

---

## 4. BSP Management (Classic XSCT — pre-2022)

> In Vitis 2019–2021, BSPs are created explicitly. In 2022+, use `domain` instead.

### bsp create `[Classic]`
Create a new Board Support Package.
```
bsp create -name <bsp_name> -hwproject <platform_name> -proc <processor> -os <os_type>
```
- `-name <n>` — BSP name
- `-hwproject <n>` — parent hardware platform project
- `-proc <processor>` — target processor instance
- `-os <standalone|freertos|linux>` — operating system
- `-cpu_instance <n>` — alternate form of processor selection

### bsp config `[Classic]`
Configure a BSP parameter (OS or driver settings).
```
bsp config <parameter> <value>
```
- Common parameters:
  - `stdin <uart_instance>` — set standard input UART
  - `stdout <uart_instance>` — set standard output UART
  - `sleep_timer <timer_instance>` — set sleep timer source
  - `microblaze_exceptions <true|false>` — enable MicroBlaze exceptions
- ⚠️ After `bsp config`, always call `bsp regenerate` to rebuild BSP sources.

### bsp setlib `[Classic]`
Add a software library to the BSP.
```
bsp setlib -name <library_name>
```
- Common libraries: `xilffs` (FAT filesystem), `xilrsa` (RSA), `lwip` (TCP/IP), `xilinx-embeddedsw`

### bsp removelib `[Classic]`
Remove a software library from the BSP.
```
bsp removelib -name <library_name>
```

### bsp regenerate `[Classic]` ⚠️
Regenerate all BSP source files after configuration changes.
```
bsp regenerate
```
- ⚠️ The single most commonly forgotten step in Classic XSCT flows. Config changes do nothing until `bsp regenerate` is called.

### bsp build `[Classic]`
Compile the BSP libraries.
```
bsp build
```

### bsp listparams `[Classic]`
List all configurable parameters for the active BSP.
```
bsp listparams
```

### bsp list `[Classic]`
List all BSP projects in the workspace.
```
bsp list
```

### bsp getlibs `[Classic]`
List all libraries currently configured in the active BSP.
```
bsp getlibs
```

---

## 5. Application Project Management

### app create `[Both]`
Create a new embedded application project.
```
app create -name <app_name> -platform <platform_name> -domain <domain_name> -template <template>
```
- `-name <n>` — application name
- `-platform <n>` — parent platform
- `-domain <n>` — target domain `[Unified]`
- `-hwproject <n>` — parent hardware platform `[Classic]` (replaces `-platform`)
- `-bsp <n>` — target BSP `[Classic]` (replaces `-domain`)
- `-template <template>` — starting template:
  - `"Empty Application"` — blank project
  - `"Hello World"` — UART hello world
  - `"Memory Tests"` — memory test application
  - `"Peripheral Tests"` — peripheral self-test
  - `"FreeRTOS Hello World"` — FreeRTOS example
  - `"lwIP Echo Server"` — TCP/IP echo server
  - `"Zynq FSBL"` — First Stage Bootloader for Zynq
  - `"MicroBlaze Bootloader"` — MicroBlaze bootloader
- `-lang <c|c++>` — source language

### app build `[Both]`
Build (compile and link) the application.
```
app build -name <app_name>
```
- ⚠️ Build output (`.elf`) is in `<workspace>/<app_name>/Debug/` or `<app_name>/Release/` depending on build configuration.

### app clean `[Both]`
Clean the build output for an application.
```
app clean -name <app_name>
```

### app config `[Both]`
Configure application build settings.
```
app config -name <app_name> <setting> <value>
```
- `-name <n>` — target application
- Common settings:
  - `build-config <Debug|Release>` — switch build configuration
  - `compiler-optimization <O0|O1|O2|O3|Os>` — optimization level
  - `define-compiler-symbols <MACRO=value>` — add preprocessor defines
  - `include-path <path>` — add include directory
  - `library-search-path <path>` — add library search path
  - `libraries <lib_name>` — link against a library
  - `linker-script <file>` — override default linker script
  - `compiler-misc <flags>` — pass arbitrary compiler flags

### app list `[Both]`
List all application projects in the workspace.
```
app list
```

### app remove `[Both]`
Remove an application project from the workspace.
```
app remove <app_name>
```

### build `[Both]`
Build all projects in the workspace.
```
build
```
- `-all` — build all projects
- Equivalent to calling `app build` on every application in the workspace.

### clean `[Both]`
Clean all build outputs in the workspace.
```
clean
```

---

## 6. System Project Management

### sysproj create `[Both]`
Create a system project that groups multiple applications for deployment together.
```
sysproj create -name <sysproject_name> -platform <platform_name>
```
- A system project is the container for generating a full boot image (BOOT.bin via `bootgen`).

### sysproj build `[Both]`
Build the system project (generates BOOT.bin if configured).
```
sysproj build -name <sysproject_name>
```

### sysproj config `[Both]`
Configure system project settings.
```
sysproj config -name <n> <setting> <value>
```
- `-bootimage <true|false>` — enable BOOT.bin generation
- `-addapp <app_name>` — add an application to the system project

### sysproj list `[Both]`
List all system projects in the workspace.
```
sysproj list
```

### sysproj remove `[Both]`
Remove a system project.
```
sysproj remove <sysproject_name>
```

---

## 7. HSI — Hardware Software Interface

> HSI commands allow introspection of the hardware design from Tcl. They operate on the `.xsa` / `.hdf` hardware description file and expose the complete hardware topology: processors, IPs, memory maps, bus connections, and parameters.

### hsi open_hw_design `[Both]`
Open an XSA or HDF hardware design file for introspection.
```
hsi open_hw_design <xsa_or_hdf_file>
```
- Returns a design handle used in subsequent `hsi` commands.
- ⚠️ In Vitis 2022+, the XSA format replaces HDF. Both are internally similar but `.hdf` support is deprecated.

### hsi close_hw_design `[Both]`
Close the currently loaded hardware design.
```
hsi close_hw_design <design_handle>
```

### hsi get_cells `[Both]`
Get all IP block instances in the hardware design.
```
hsi get_cells
```
- `-filter {IP_TYPE == PROCESSOR}` — get only processor IP instances
- `-filter {IP_NAME == axi_gpio}` — filter by IP type name
- Returns cell objects with properties like `IP_NAME`, `INSTANCE_NAME`, `IP_TYPE`.
- Example: `hsi get_cells -filter {IP_TYPE == PROCESSOR}` → returns `ps7_0`, `microblaze_0`, etc.

### hsi get_pins `[Both]`
Get interface pins on a specific IP block.
```
hsi get_pins -of_objects [hsi get_cells <cell_name>]
```
- `-filter {TYPE == clk}` — clock pins only
- `-filter {DIRECTION == I}` — input pins only

### hsi get_intf_ports `[Both]`
Get the top-level interface ports of the hardware design.
```
hsi get_intf_ports
```

### hsi get_intf_nets `[Both]`
Get all interface nets (bus connections) in the hardware design.
```
hsi get_intf_nets
```

### hsi get_mem_ranges `[Both]` ⚠️
Get the memory address ranges assigned to a specific processor — this is how you find base addresses of peripherals.
```
hsi get_mem_ranges -of_objects [hsi get_cells <processor_name>]
```
- Returns objects with properties: `BASE_VALUE`, `HIGH_VALUE`, `MEM_TYPE`, `INSTANCE`
- Example:
  ```tcl
  set proc [hsi get_cells -filter {IP_TYPE == PROCESSOR}]
  set mem_ranges [hsi get_mem_ranges -of_objects $proc]
  foreach r $mem_ranges {
    puts "[hsi get_property INSTANCE $r]: [hsi get_property BASE_VALUE $r]"
  }
  ```
- ⚠️ The base addresses shown here must match the `#define` values in the generated `xparameters.h`. If they don't, the XSA was not regenerated after a Vivado address editor change.

### hsi get_property `[Both]`
Read a property from an HSI object.
```
hsi get_property <property_name> <object>
```
- Common properties:
  - `IP_NAME` — the type name of the IP (e.g., `axi_gpio`, `axi_uartlite`)
  - `INSTANCE_NAME` — the instance name in the design (e.g., `gpio_0`)
  - `IP_TYPE` — `PROCESSOR`, `PERIPHERAL`, `BUS`, etc.
  - `BASE_VALUE` — base address (on mem_range objects)
  - `HIGH_VALUE` — high address
  - `CLK_FREQ_HZ` — clock frequency in Hz
  - `C_BASEADDR` — IP parameter: base address configuration
  - `C_HIGHADDR` — IP parameter: high address configuration

### hsi set_property `[Both]`
Write a property on an HSI object (used to modify BSP/driver parameters during generation).
```
hsi set_property <property_name> <value> <object>
```

### hsi get_sw_processor `[Both]`
Get the software processor object associated with the current BSP or domain.
```
hsi get_sw_processor
```
- Returns the processor instance targeted by the active software platform.

### hsi get_driver `[Both]`
Get the driver associated with a specific IP peripheral.
```
hsi get_driver -of_objects [hsi get_cells <peripheral_name>]
```
- Returns the driver object (with `NAME` = driver name, `VER` = version).

### hsi get_os `[Both]`
Get the operating system associated with the current BSP/domain.
```
hsi get_os
```

### hsi get_ip_name `[Both]`
Get the IP type name of a cell.
```
hsi get_ip_name <cell_object>
```
- Equivalent to `hsi get_property IP_NAME <cell>`.

### hsi get_param_value `[Both]`
Get the value of a specific IP configuration parameter.
```
hsi get_param_value -cell <cell_name> <param_name>
```
- Example: `hsi get_param_value -cell axi_gpio_0 C_GPIO_WIDTH` → returns GPIO bus width
- ⚠️ Parameter names are IP-specific and begin with `C_` by convention (Xilinx IP parameter naming).

### hsi generate_bsp `[Both]`
Generate BSP source files directly from an open hardware design (scripted flow).
```
hsi generate_bsp -dir <output_dir> -proc <processor> -os <os_type>
```
- `-dir <dir>` — output directory
- `-proc <processor>` — target processor instance
- `-os <standalone|freertos|linux>` — OS type
- `-lib <libraries>` — additional libraries to include

### hsi get_cells (processors) — Processor Names Reference
Common processor instance names found in XSA files:

| Hardware Platform | Processor Instance Name |
|---|---|
| Zynq-7000 (PS) | `ps7_cortexa9_0`, `ps7_cortexa9_1` |
| Zynq UltraScale+ MPSoC (PS) | `psu_cortexa53_0`, `psu_cortexa53_1`, `psu_cortexr5_0`, `psu_cortexr5_1`, `psu_pmu_0` |
| Versal (PS) | `psv_cortexa72_0`, `psv_cortexr5_0`, `psv_pmc_0` |
| MicroBlaze (PL softcore) | `microblaze_0` (instance name set by designer) |
| RISC-V (PL softcore) | Designer-defined instance name |

---

## 8. Repository and IP Management

### repo `[Both]`
Set or get custom IP and BSP driver repository paths.
```
repo -set <path>
repo -get
```
- `-set <path>` — add a directory as an IP/driver repository
- `-get` — return the current repository paths
- `-clean` — clear all custom repository paths
- ⚠️ Required when using custom IP or BSP drivers not shipped with Vitis. Must be set before `platform generate`.

### getrepos `[Both]`
Return the list of all configured repository paths.
```
getrepos
```

---

## 9. Target Connection and Management (XSDB)

> XSDB commands interact with physical hardware over JTAG. They are independent of the Vitis project flow and can be used standalone with `xsdb` or within `xsct`.

### connect `[XSDB]`
Connect to a Xilinx hw_server or directly to a JTAG cable.
```
connect
```
- `-url <host:port>` — connect to a specific hw_server (default: `TCP:localhost:3121`)
- `-symbol` — connect in symbol server mode
- `-host <hostname>` — specify hostname
- `-port <port>` — specify port number
- ⚠️ Before running XSDB commands on hardware, a `hw_server` process must be running. Start it with `hw_server` in a separate terminal or via Vivado Lab Edition.

### disconnect `[XSDB]`
Disconnect from the current hardware server.
```
disconnect
```
- `-host <hostname>` — disconnect from a specific server

### targets `[XSDB]` ⚠️
List, filter, and select JTAG targets (processors, debug modules, JTAG chains).
```
targets
```
- `-set` — set the active target (used with target index or filter)
- `-filter {name =~ "ARM*"}` — filter by name pattern
- `-filter {jtag_cable_name =~ "*Digilent*"}` — filter by cable name
- `-index <n>` — select target by index number
- `-nocase` — case-insensitive filter
- Example output:
  ```
  1  APU (target 1)
     2  ARM Cortex-A9 MPCore #0 (Running)
     3  ARM Cortex-A9 MPCore #1 (Running)
  4  xc7z020 (target 4, JTAG)
  ```
- ⚠️ Always call `targets -set <index>` to select the correct processor before `stop`, `con`, `mrd`, `rrd`, or `dow`. Operating on the wrong target silently fails or corrupts the wrong processor's state.

### target `[XSDB]`
Set the active target by index (shorthand for `targets -set`).
```
target <index>
```
- Example: `target 2` — select the first ARM Cortex-A9 core

### jtag targets `[XSDB]`
List raw JTAG chain nodes (lower-level than `targets`).
```
jtag targets
```

---

## 10. Device Programming and Download (XSDB)

### fpga `[XSDB]`
Download a bitstream file to the FPGA or Versal device.
```
fpga <bitstream_file>
```
- `-file <path>` — explicit file path (same as positional argument)
- `-partial` — download a partial bitstream (PR flow)
- `-no-revision-check` — skip bitstream revision mismatch check
- Example: `fpga /path/to/design.bit`
- ⚠️ For Zynq devices, the PL (FPGA) must be initialized before downloading the PL bitstream. If running Linux on the PS, the FPGA can be programmed from Linux via `/dev/xdevcfg`. From XSDB, ensure the PS is initialized first with `loadhw` or the FSBL has run.

### device program `[XSDB]`
Program a device using a full device configuration (bitstream + ELF for Versal PDI).
```
device program <pdi_or_bit_file>
```
- Used for Versal PDI (Program Device Image) files.

### device status `[XSDB]`
Read the device status and boot mode registers.
```
device status
```

### dow `[XSDB]` ⚠️
Download a compiled ELF file or raw binary data to the target processor's memory.
```
dow <elf_file>
```
- `-data <binary_file> <address>` — download raw binary to a specific address
- `-clear` — zero-fill BSS sections before downloading
- `-keepsym` — keep symbol table loaded (for debugging)
- `-force` — download even if already loaded
- Example: `dow /path/to/app.elf`
- ⚠️ `dow` only loads the ELF into memory — it does not start execution. Call `con` afterward to begin running.
- ⚠️ The target processor must be **stopped** (`stop`) before calling `dow`. Downloading to a running processor will corrupt its execution state.

### loadhw `[XSDB]`
Load a hardware description file to initialize the hardware platform for the active target.
```
loadhw -hw <xsa_file>
```
- `-mem-ranges <ranges>` — specify custom memory ranges
- Used to initialize Zynq/ZynqMP PS peripherals from XSDB without running an FSBL.

### configparams `[XSDB]`
Get or set configuration parameters for the XSDB session.
```
configparams <param_name> [<value>]
```
- `force-mem-access 1` — force memory access even if processor is running ⚠️ use carefully
- `global-memory-ap 1` — use global memory access port

---

## 11. Debugging and Execution (XSDB)

### stop `[XSDB]` ⚠️
Halt execution on the active target processor.
```
stop
```
- ⚠️ Always halt the processor before modifying registers, reading/writing memory at program addresses, or downloading new code. Reading register state on a running processor returns stale or undefined values.

### con `[XSDB]`
Continue (resume) execution on the active target processor.
```
con
```
- `-addr <address>` — start/resume execution at a specific address
- `-block` — block the Tcl script until the next stop event (breakpoint, halt)
- Example: `con -block` — resume and wait for breakpoint to hit

### rst `[XSDB]` ⚠️
Reset the system, a specific processor, or the debug subsystem.
```
rst
```
- `-system` — full system reset (all processors, peripherals, PL)
- `-processor` — reset only the active processor
- `-cores` — reset all processor cores
- `-srst` — assert system reset via JTAG SRST pin
- `-type <por|srst|dbg>` — specify reset type:
  - `por` — Power-On Reset (full device reset)
  - `srst` — System Reset
  - `dbg` — Debug reset (resets debug logic only, not application state)
- `-ps-only` — reset PS only, keep PL running `[Zynq/ZynqMP]`
- ⚠️ `rst -system` will reset the FPGA configuration. The PL bitstream is lost and must be re-downloaded.

### bpadd `[XSDB]`
Add a hardware or software breakpoint.
```
bpadd <address_or_symbol>
```
- `-addr <address>` — set breakpoint at a specific memory address
- `-file <filename> -line <n>` — set source-level breakpoint at file/line
- `-type <hw|sw>` — hardware or software breakpoint
  - `hw` — uses hardware debug registers (limited count, typically 6 on Cortex-A9)
  - `sw` — replaces instruction at address with a breakpoint instruction (unlimited, but modifies code)
- `-target-id <id>` — set breakpoint on a specific target (useful for multi-core)
- Returns a breakpoint ID for use with `bpremove`, `bpdisable`.

### bpremove `[XSDB]`
Remove a breakpoint by its ID.
```
bpremove <bp_id>
```
- `bpremove -all` — remove all breakpoints

### bpdisable `[XSDB]`
Disable a breakpoint without removing it.
```
bpdisable <bp_id>
```

### bpenable `[XSDB]`
Re-enable a previously disabled breakpoint.
```
bpenable <bp_id>
```

### bplist `[XSDB]`
List all breakpoints and their current state.
```
bplist
```

### bpstatus `[XSDB]`
Check whether a specific breakpoint was hit.
```
bpstatus <bp_id>
```

### wpadd `[XSDB]`
Add a watchpoint (data breakpoint) on a memory address.
```
wpadd -addr <address>
```
- `-read` — trigger on read access
- `-write` — trigger on write access
- `-rw` — trigger on either read or write
- `-mask <value>` — apply address mask (watch a range)
- Returns a watchpoint ID.

### wpremove `[XSDB]`
Remove a watchpoint.
```
wpremove <wp_id>
```
- `wpremove -all` — remove all watchpoints

### n `[XSDB]`
Step to the next C/C++ source line (step over — does not enter function calls).
```
n
```

### s `[XSDB]`
Step into the next C/C++ source line (step into — enters function calls).
```
s
```

### ni `[XSDB]`
Step to the next assembly instruction (step over — does not enter CALL targets).
```
ni
```

### si `[XSDB]`
Step a single assembly instruction (step into — follows CALL/branch targets).
```
si
```

### stpout `[XSDB]`
Step out of the current function back to the caller.
```
stpout
```

### bt `[XSDB]`
Print the call stack backtrace for the active processor thread.
```
bt
```
- `-maxframes <n>` — limit number of frames shown
- Example output:
  ```
  #0  main () at src/main.c:42
  #1  0x00001234 in _start ()
  ```

### backtrace `[XSDB]`
Full alias for `bt` with frame selection.
```
backtrace [<n_frames>]
```

---

## 12. Registers and Memory (XSDB)

### mrd `[XSDB]` ⚠️
Memory Read — read one or more words from a physical memory address.
```
mrd <address>
```
- `-size <1|2|4|8>` — access size in bytes (byte/halfword/word/doubleword)
- `-value` — return value as a Tcl integer (for scripting)
- `-force` — read even if address is not in the memory map
- `-count <n>` — read N consecutive locations
- Example: `mrd -size 4 0xFF200000` — read 32-bit word from address
- Example: `mrd -size 4 -count 16 0x00000000` — read 16 words from address 0
- ⚠️ For peripheral registers, the address is the physical AXI base address + register offset. Use `hsi get_mem_ranges` to find base addresses.

### mwr `[XSDB]` ⚠️
Memory Write — write one or more words to a physical memory address.
```
mwr <address> <value>
```
- `-size <1|2|4|8>` — access size in bytes
- `-force` — write even if address is not in the memory map
- `-count <n>` — write the same value to N consecutive locations
- Example: `mwr 0xFF200000 0x00000001` — write 1 to address
- ⚠️ Writing to peripheral control registers directly via `mwr` takes effect immediately on the hardware. There is no undo. Always verify addresses before writing.

### mask_write `[XSDB]`
Perform a safe read-modify-write on a memory address using a bitmask.
```
mask_write <address> <mask> <value>
```
- Reads current value, clears bits in `<mask>`, ORs in `<value>`, writes back.
- Example: `mask_write 0xFF200000 0x00000007 0x00000005` — set bits [2:0] to 0b101
- ⚠️ Safer than `mwr` for control registers where you only want to change specific bits.

### rrd `[XSDB]`
Register Read — read processor or coprocessor register values.
```
rrd
```
- `rrd` (no args) — list all readable registers with their current values
- `rrd <register_name>` — read a specific register
- Common register names:
  - `r0`–`r15` — Cortex-A9/R5 general purpose registers
  - `pc` — Program Counter
  - `sp` — Stack Pointer
  - `lr` — Link Register
  - `cpsr` — Current Program Status Register
  - `x0`–`x30` — AArch64 general purpose registers
  - `pc`, `sp`, `xzr` — AArch64 special registers
- ⚠️ Processor must be stopped before reading registers. Running register reads return undefined values.

### rwr `[XSDB]`
Register Write — write a value to a processor register.
```
rwr <register_name> <value>
```
- Example: `rwr pc 0x00100000` — set Program Counter to address
- ⚠️ Writing PC to an invalid address and then continuing execution will crash the processor.

### getaddrmap `[XSDB]`
Get the full memory address map for the active target processor.
```
getaddrmap
```
- Returns all memory regions (DDR, OCM, peripherals, etc.) with their base/high addresses and access permissions.

### memmap `[XSDB]`
Print the resolved memory map of the target in a human-readable format.
```
memmap
```
- `-addr <address>` — look up which region contains a specific address

---

## 13. Expressions, Variables, and Stack Inspection (XSDB)

### locals `[XSDB]`
Print the local variables in the current stack frame.
```
locals
```
- Returns variable names and values for the current C/C++ function scope.
- ⚠️ Requires debug symbols (compiled with `-g`). Release builds strip symbols — `locals` returns nothing.

### print `[XSDB]`
Evaluate and print a C expression or variable value.
```
print <expression>
```
- Example: `print my_variable` — print a variable's value
- Example: `print *my_pointer` — dereference and print a pointer
- Example: `print my_array[5]` — print array element
- Supports basic C expressions: arithmetic, dereference, array indexing, member access.
- ⚠️ Requires debug symbols and a stopped processor.

### dis `[XSDB]`
Disassemble instructions at the current PC or a specified address.
```
dis
```
- `-addr <address>` — disassemble starting at this address (default: current PC)
- `-count <n>` — number of instructions to disassemble (default: ~10)
- Example: `dis -addr 0x00100000 -count 20`
- Useful for debugging without source — inspect what assembly the compiler actually generated.

### info `[XSDB]`
Print various kinds of debug information about the current target state.
```
info functions <pattern>
info variables <pattern>
info stack
info threads
```
- `info functions <pattern>` — list all functions matching pattern (from symbol table)
- `info variables` — list all global/static variables
- `info stack` — print stack backtrace (alias for `bt`)
- `info threads` — list all threads on the target (RTOS-aware)

---

## 14. Cache and MMU Control (XSDB)

### cache `[XSDB]` ⚠️
Control the L1/L2 cache on the target processor.
```
cache
```
- `cache -flush` — flush (write-back) the data cache to main memory
- `cache -invalidate` — invalidate the instruction cache
- `cache -flush -invalidate` — flush and invalidate both caches
- ⚠️ **This is critical when downloading new code.** If the instruction cache contains stale cached values from a previous execution, the processor will execute old instructions even after `dow`. Always `cache -flush -invalidate` after downloading new ELF when the cache is enabled.

### mmu `[XSDB]`
Control or query the MMU state.
```
mmu
```
- `mmu -enable` — enable the MMU
- `mmu -disable` — disable the MMU
- `mmu -dump` — dump the current page table entries

---

## 15. JTAG — Low-Level Control (XSDB)

> These commands operate at the raw JTAG signal level, bypassing the higher-level debug subsystem. Used for custom JTAG peripherals, boundary scan, and device identification.

### jtag targets `[XSDB]`
List all raw JTAG chain nodes.
```
jtag targets
```
- `-filter {name =~ "xc7*"}` — filter by name
- ⚠️ This is different from the `targets` command — `jtag targets` shows the physical JTAG chain, while `targets` shows debug-capable processors.

### jtag frequency `[XSDB]`
Set the JTAG TCK clock frequency.
```
jtag frequency <hz>
```
- Example: `jtag frequency 15000000` — set TCK to 15 MHz
- ⚠️ Default frequency may be too high for some boards. If JTAG communication is unreliable, reduce to 6 MHz or lower.

### jtag lock `[XSDB]`
Acquire exclusive JTAG access, preventing other processes from accessing the cable.
```
jtag lock
```

### jtag unlock `[XSDB]`
Release exclusive JTAG access.
```
jtag unlock
```

### jtag sequence `[XSDB]`
Build a raw JTAG shift sequence.
```
set seq [jtag sequence]
$seq irshift -state IRUPDATE -hex 6 09
$seq drshift -state DRPAUSE -tdi 0 32
```
- Returns a sequence object.
- `irshift` — shift into the instruction register
- `drshift` — shift into the data register
- `-state <JTAG_state>` — end state after this shift operation
- `-hex <bit_count> <value>` — shift a hex value
- `-tdi <bit> <count>` — shift a repeated bit value

### jtag run_sequence `[XSDB]`
Execute a built JTAG sequence.
```
$seq run
```
- Returns the captured TDO data.

### jtag get_port_list `[XSDB]`
List all detected physical JTAG cable ports.
```
jtag get_port_list
```

### jtag open_port `[XSDB]`
Open a specific JTAG port by name.
```
jtag open_port <port_name>
```

### jtag close_port `[XSDB]`
Close a JTAG port.
```
jtag close_port <port>
```

### xsdb_set_bscan `[XSDB]`
Configure the BSCAN (Boundary Scan) chain position for accessing custom JTAG topologies or user logic connected to the BSCAN primitive.
```
xsdb_set_bscan -target <target> -chain <chain_position>
```
- Used when accessing a MicroBlaze debug module connected through the BSCAN primitive in the PL.

---

## 16. Profiling and RTOS (XSDB)

### tcfprof `[XSDB]`
Configure and run TCF (Target Communication Framework) based performance profiling.
```
tcfprof start -sampling-period <us>
tcfprof stop
tcfprof report
```
- `-sampling-period <us>` — PC sampling interval in microseconds
- Samples the Program Counter at the specified interval to build a statistical execution profile.

### profile `[XSDB]`
Start or stop software profiling (gprof-compatible).
```
profile
```
- `-start` — begin profiling
- `-stop` — stop profiling
- `-report` — generate profiling report

### getos `[XSDB]`
Get RTOS information for the active target (FreeRTOS, ThreadX, etc.).
```
getos
```
- Returns OS name and version if an RTOS is detected.
- Enables RTOS-aware debugging features like thread listing and per-thread stack inspection.

### getdrivers `[XSDB]`
Get Xilinx driver information for IP peripherals connected to the target processor.
```
getdrivers
```
- Returns driver name, version, and the peripheral instance each driver manages.

### info threads `[XSDB]`
List all threads on the target (requires RTOS support).
```
info threads
```

### thread `[XSDB]`
Switch the active debug thread context.
```
thread <thread_id>
```
- `thread <id>` — switch to thread with this ID
- Thread-aware debugging allows inspecting stack frames and local variables per-thread.

---

## 17. Sysmon and System Debug (XSDB)

### sysdbg_read_reg `[XSDB]`
Read a system debug register (Sysmon/XADC registers, PMU registers on ZynqMP/Versal).
```
sysdbg_read_reg <register_name>
```
- `sysdbg_read_reg temperature` — read die temperature from Sysmon
- `sysdbg_read_reg vccint` — read VCCINT voltage from Sysmon

### sysdbg_write_reg `[XSDB]`
Write a system debug register.
```
sysdbg_write_reg <register_name> <value>
```

### set_axistream_switch `[XSDB]`
Route AXI-Stream debug traffic through the AXI debug fabric.
```
set_axistream_switch -master <m_port> -slave <s_port>
```
- Used in Versal and UltraScale+ designs with the Debug Hub connected to AXI-Stream fabric.

---

## 18. Utility and Miscellaneous

### version `[Both]`
Print the current XSCT/XSDB version.
```
version
```

### exit `[Both]`
Exit the XSCT or XSDB shell.
```
exit
```

### source `[Both]`
Execute a Tcl script file.
```
source <script_file>
```
- Standard Tcl command — works identically in both XSCT and XSDB contexts.

### after `[Both]`
Pause execution for a specified time (Tcl built-in, useful for hardware startup delays).
```
after <milliseconds>
```
- Example: `after 1000` — wait 1 second
- ⚠️ Always add delays after reset (`rst`) commands to allow hardware to initialize before accessing peripherals. Typical post-reset delay: `after 2000` (2 seconds).

### openhw `[XSDB]`
Shorthand to open a hardware description (combines `connect` + `targets` selection + `loadhw`).
```
openhw <xsa_file>
```

### closehw `[XSDB]`
Shorthand to close the hardware and disconnect.
```
closehw
```

### scwutil `[Unified]`
Vitis Unified IDE workspace utility commands. `[2022+]`
```
scwutil import <project_path>
scwutil list
```
- `scwutil import` — import projects into the Unified IDE workspace
- `scwutil list` — list all workspace components

---

## Appendix A — Complete XSCT Workflow Reference

### Classic XSCT Script Template (2019–2021)

```tcl
# 1. Set workspace
setws /path/to/workspace

# 2. Create hardware platform
platform create -name hw_platform -hw /path/to/design.xsa

# 3. Create BSP
bsp create -name standalone_bsp \
           -hwproject hw_platform \
           -proc ps7_cortexa9_0 \
           -os standalone

# 4. Configure BSP
bsp config stdin ps7_uart_1
bsp config stdout ps7_uart_1
bsp regenerate

# 5. Build BSP
bsp build

# 6. Create application
app create -name my_app \
           -hwproject hw_platform \
           -bsp standalone_bsp \
           -proc ps7_cortexa9_0 \
           -template "Hello World"

# 7. Build application
app build -name my_app

# Output: workspace/my_app/Debug/my_app.elf
```

### Unified IDE XSCT Script Template (2022+)

```tcl
# 1. Set workspace
setws /path/to/workspace

# 2. Create platform
platform create -name hw_platform \
                -hw /path/to/design.xsa \
                -os standalone \
                -proc ps7_cortexa9_0

# 3. Create domain (replaces BSP)
domain create -name standalone_domain \
              -os standalone \
              -proc ps7_cortexa9_0

# 4. Configure domain
domain config -os stdin ps7_uart_1
domain config -os stdout ps7_uart_1

# 5. Generate platform (replaces bsp regenerate + bsp build)
platform generate

# 6. Create application
app create -name my_app \
           -platform hw_platform \
           -domain standalone_domain \
           -template "Hello World"

# 7. Build application
app build -name my_app
```

---

## Appendix B — Complete XSDB Debug Workflow Reference

```tcl
# 1. Connect to hardware server
connect

# 2. List available targets
targets

# 3. Select the target processor (e.g., ARM Cortex-A9 #0)
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}

# 4. Program the FPGA bitstream (if Zynq)
fpga /path/to/design.bit

# 5. Initialize PS (Zynq PS initialization)
loadhw -hw /path/to/design.xsa

# 6. Stop the processor
stop

# 7. Set stack pointer and PC (for bare-metal without FSBL)
rwr sp 0x00100000
rwr pc 0x00000000

# 8. Download application ELF
dow /path/to/app.elf

# 9. Flush instruction cache after download
cache -flush -invalidate

# 10. Set a breakpoint
bpadd -file main.c -line 42

# 11. Start execution and wait for breakpoint
con -block

# 12. Inspect state after breakpoint
rrd pc
locals
print my_variable

# 13. Step through code
n
n
s

# 14. Read a peripheral register
mrd -size 4 0xFF200000

# 15. Write a peripheral register
mwr 0xFF200004 0x00000001

# 16. Continue execution
con

# 17. Disconnect
disconnect
```

---

*End of Vitis XSCT/XSDB Exhaustive Reference*
