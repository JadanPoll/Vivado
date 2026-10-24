# Vivado: recursive combinatorial system audit

Scope: `FINAL/index.html`, `PRODUCTION_GRADE` worker/JTAG/BLE modules, and stopwatch RTL.

## Depth 0: node selection and refinement obligations

|ID|Element|Decision|Justification|
|---|---|---|---|
|`actor`|Human/LLM action and belief|refine|Intent, interruptions, forgotten observations and edits can alter interactions|
|`repo`|Versioned GitHub repository|stop|Atomic commit snapshots assumed; GitHub internals out of scope|
|`discover`|Repository discovery and catalog|refine|Async ref resolution, tree fetch, catalog publication|
|`workspace`|Active source/XDC workspace|refine|Base URL, identity, selected files, edited bytes, revision guard|
|`draft`|Browser drafts/localStorage|refine|Save, restore, storage failure, wrong project key|
|`build`|Build coordinator|refine|Input snapshot, async stage completion, published artifact|
|`cache`|Pinned toolchain asset cache|refine|Pending/failure and buffer transfer semantics|
|`yosys`|Synthesis worker|stop|Success/error interface sufficient; internal synthesis outside this property|
|`pnr`|Placement/routing worker|stop|FASM/error interface sufficient; chip-level routing not modeled|
|`fasm`|FASM-to-frames mapping|refine|Success, warnings, errors affect pipeline provenance|
|`frames`|Frames-to-bitstream worker|stop|Completion/error boundary modeled; encoding not modeled|
|`artifact`|Compiled bitstream and provenance|refine|Selection at click, retention, replacement and warnings|
|`usb`|WebUSB/JTAG transaction|refine|Permission, IDCODE, transfer, DONE and failure|
|`board`|Urbana hardware|refine|Physical pin, active polarity, DONE, counter display, board state|
|`serial`|USB-UART transport|stop|Packet boundaries/errors abstracted at UART interface|
|`ble`|BLE client and serial bridge|refine|Connection, chunks, disconnect and delayed notifications|
|`rtl`|Stopwatch RTL and display decoder|refine|Clock, BCD carry, command parser, logical digit permutation|

## Depth 1: refinements and stopping rules

### actor

**Summary justification:** Intent, interruptions, forgotten observations and edits can alter interactions.

|Subelement|Boundary/stopping justification|
|---|---|
|`intent`|User goal (stop: external intention axiomatic)|
|`observation`|Received evidence (stop: perception details not modeled)|
|`belief`|Remembered/possibly mistaken state (stop: cognition abstracted)|
|`decision`|Chosen action (stop: abstract action label)|

|Source\Target|intent|observation|belief|decision|
|---|---|---|---|---|
|intent|U|U|U|C|
|observation|U|U|E|U|
|belief|U|U|U|C|
|decision|U|U|U|U|

Edges: observation → belief [E]: Observation updates remembered model; belief → decision [C]: Belief can influence chosen action; intent → decision [C]: Intention can influence choice

### discover

**Summary justification:** Async ref resolution, tree fetch, catalog publication.

|Subelement|Boundary/stopping justification|
|---|---|
|`ref`|Repository/ref resolver (stop: API endpoint treated as external)|
|`tree`|GitHub tree response (stop: response modeled atomically)|
|`publish`|Catalog selection/publish (stop: assignment operation)|

|Source\Target|ref|tree|publish|
|---|---|---|---|
|ref|U|C|U|
|tree|U|U|C|
|publish|U|U|U|

Edges: ref → tree [C]: Resolved SHA used to request tree; tree → publish [C]: Nontruncated response populates catalog

### workspace

**Summary justification:** Base URL, identity, selected files, edited bytes, revision guard.

|Subelement|Boundary/stopping justification|
|---|---|
|`url`|Current project URL (stop: identity domain A/B)|
|`hdl`|HDL contents (stop: payload origin represented)|
|`xdc`|XDC contents (stop: payload origin represented)|
|`identity`|Project key and ready flag (stop: association properties)|

|Source\Target|url|hdl|xdc|identity|
|---|---|---|---|---|
|url|U|C|C|U|
|hdl|U|U|U|C|
|xdc|U|U|U|C|
|identity|U|U|U|U|

Edges: url → hdl [C]: URL selects source bytes; url → xdc [C]: URL selects XDC bytes; hdl → identity [C]: Committed source associated with workspace key; xdc → identity [C]: XDC availability determines readiness

### draft

**Summary justification:** Save, restore, storage failure, wrong project key.

|Subelement|Boundary/stopping justification|
|---|---|
|`key`|localStorage identity key (stop: string abstraction)|
|`payload`|Saved source/XDC (stop: content abstracted by origin)|
|`storage`|Storage outcome (stop: success/failure boundary)|

|Source\Target|key|payload|storage|
|---|---|---|---|
|key|U|C|U|
|payload|U|U|U|
|storage|U|C|U|

Edges: key → payload [C]: Key indexes stored project bytes; storage → payload [C]: Storage success permits save/restore

### build

**Summary justification:** Input snapshot, async stage completion, published artifact.

|Subelement|Boundary/stopping justification|
|---|---|
|`snapshot`|Captured input snapshot (stop: immutable payload origin)|
|`stage`|Yosys/PNR/FASM/frames stage (stop: worker outcomes atomic)|
|`publish`|Ready artifact publication (stop: atomic assignment)|

|Source\Target|snapshot|stage|publish|
|---|---|---|---|
|snapshot|U|E|U|
|stage|U|U|C|
|publish|U|U|U|

Edges: snapshot → stage [E]: Stages consume captured input; stage → publish [C]: Successful final stage publishes result

### cache

**Summary justification:** Pending/failure and buffer transfer semantics.

|Subelement|Boundary/stopping justification|
|---|---|
|`key`|Pinned asset/version key (stop: immutable revision label)|
|`promise`|Pending/rejected loader (stop: Promise scheduling boundary)|
|`bytes`|Decoded and transferred assets (stop: bytes not needed here)|

|Source\Target|key|promise|bytes|
|---|---|---|---|
|key|U|E|U|
|promise|U|U|C|
|bytes|U|U|U|

Edges: key → promise [E]: Asset key selects loader promise; promise → bytes [C]: Successful resolved promise supplies assets

### fasm

**Summary justification:** Success, warnings, errors affect pipeline provenance.

|Subelement|Boundary/stopping justification|
|---|---|
|`features`|Feature-to-frame map (stop: map lookup boundary)|
|`warning`|Unmapped feature telemetry (stop: warning label)|
|`frames`|Output frame data (stop: bytes abstracted)|

|Source\Target|features|warning|frames|
|---|---|---|---|
|features|U|C|C|
|warning|U|U|U|
|frames|U|U|U|

Edges: features → frames [C]: Recognized features generate frame bits; features → warning [C]: Missing features generate warning count

### artifact

**Summary justification:** Selection at click, retention, replacement and warnings.

|Subelement|Boundary/stopping justification|
|---|---|
|`origin`|Source/toolchain provenance (stop: revision label)|
|`buffer`|Compiled bitstream bytes (stop: opaque immutable value)|
|`selected`|Selected artifact at flash click (stop: captured reference)|

|Source\Target|origin|buffer|selected|
|---|---|---|---|
|origin|U|E|U|
|buffer|U|U|C|
|selected|U|U|U|

Edges: origin → buffer [E]: Result is associated with build provenance; buffer → selected [C]: Flash handler captures selected array

### usb

**Summary justification:** Permission, IDCODE, transfer, DONE and failure.

|Subelement|Boundary/stopping justification|
|---|---|
|`permission`|WebUSB permission (stop: grant/deny outcome)|
|`idcode`|Device identity read (stop: pass/fail outcome)|
|`shift`|Program bitstream transfer (stop: success/interruption outcome)|
|`status`|DONE status check (stop: asserted/low outcome)|

|Source\Target|permission|idcode|shift|status|
|---|---|---|---|---|
|permission|U|C|U|U|
|idcode|U|U|C|U|
|shift|U|U|U|C|
|status|U|U|U|U|

Edges: permission → idcode [C]: Granted access permits ID read; idcode → shift [C]: Correct ID permits programming; shift → status [C]: Transfer followed by DONE read

### board

**Summary justification:** Physical pin, active polarity, DONE, counter display, board state.

|Subelement|Boundary/stopping justification|
|---|---|
|`pins`|Physical pin connections (stop: canonical XDC given)|
|`clock`|Oscillator/ticks (stop: discrete elapsed event)|
|`done`|Configuration DONE level (stop: binary observation)|

|Source\Target|pins|clock|done|
|---|---|---|---|
|pins|U|U|U|
|clock|U|U|U|
|done|U|U|U|

Edges: pins → clock [U]: No direct causal relation specified; retain uncertainty; clock → done [U]: No direct causal relation established

### ble

**Summary justification:** Connection, chunks, disconnect and delayed notifications.

|Subelement|Boundary/stopping justification|
|---|---|
|`gatt`|Connection state (stop: connected/disconnected)|
|`chunks`|Outgoing BLE write chunks (stop: delivery nondeterministic)|
|`rx`|Received bytes/notifications (stop: command label)|

|Source\Target|gatt|chunks|rx|
|---|---|---|---|
|gatt|U|C|C|
|chunks|U|U|U|
|rx|U|U|U|

Edges: gatt → chunks [C]: Write requires connected characteristic; gatt → rx [C]: Notifications require active session

### rtl

**Summary justification:** Clock, BCD carry, command parser, logical digit permutation.

|Subelement|Boundary/stopping justification|
|---|---|
|`rx`|UART command framing (stop: bytes collapsed to command)|
|`counter`|BCD counter state (stop: decimal digit ranges)|
|`scan`|Digit scan/permutation (stop: mapping labels)|

|Source\Target|rx|counter|scan|
|---|---|---|---|
|rx|U|C|U|
|counter|U|U|E|
|scan|U|U|U|

Edges: rx → counter [C]: Decoded commands control stopwatch; counter → scan [E]: Displayed nibble values originate from counters


## Ordered-pair matrix (depth 0)

**E** evidenced, **C** conditional, **X** excluded direct interface with stated justification, **U** unresolved; unresolved pairs are not impossible. Rows are source; columns are target.

|Source\Target|actor|repo|discover|workspace|draft|build|cache|yosys|pnr|fasm|frames|artifact|usb|board|serial|ble|rtl|
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
|actor|E|U|E|E|E|E|U|U|U|U|U|E|E|U|E|E|U|
|repo|U|U|C|C|U|U|U|U|U|U|U|U|U|U|U|U|U|
|discover|U|U|C|C|U|U|U|U|U|U|U|U|U|U|U|U|U|
|workspace|U|U|E|E|C|C|U|U|U|U|U|U|U|U|U|U|U|
|draft|U|U|U|C|E|U|U|U|U|U|U|U|U|U|U|U|U|
|build|U|U|U|U|U|U|C|C|C|C|C|C|U|U|U|U|U|
|cache|U|U|U|U|U|C|E|U|U|U|U|U|U|U|U|U|U|
|yosys|U|X|U|U|U|C|U|U|U|U|U|U|U|U|U|U|U|
|pnr|U|X|U|U|U|C|U|U|U|U|U|U|U|U|U|U|U|
|fasm|U|U|U|U|U|C|U|U|U|U|U|U|U|U|U|U|U|
|frames|U|X|U|U|U|C|U|U|U|U|U|U|U|U|U|U|U|
|artifact|U|U|U|U|U|U|U|U|U|U|U|E|C|U|U|U|U|
|usb|C|U|U|U|U|U|U|U|U|U|U|U|E|C|U|U|U|
|board|U|X|U|U|X|U|U|U|U|U|U|U|C|E|U|U|E|
|serial|U|X|U|U|U|U|U|U|U|U|U|U|U|U|U|U|C|
|ble|U|X|U|U|U|U|U|U|U|U|U|U|U|U|U|E|C|
|rtl|U|X|U|U|X|U|U|U|U|U|U|U|U|E|C|C|E|

## Labeled relation evidence

|Source → Target|Class|Event/condition|Source|
|---|---|---|---|
|actor → discover|E|click Discover|`FINAL/index.html:854-859`|
|actor → workspace|E|edit URL, source or XDC|`FINAL/index.html:632,908-919`|
|actor → draft|E|trigger save, reopen or dismiss confirmation|`FINAL/index.html:392-403,645-663`|
|actor → build|E|click Build|`FINAL/index.html:1084-1115`|
|actor → artifact|E|choose artifact for download or flash|`FINAL/index.html:979-980,1249-1255`|
|actor → usb|E|request USB hardware access|`FINAL/index.html:1257`|
|actor → ble|E|connect/disconnect/send command|`FINAL/index.html:587-600`|
|actor → serial|E|connect/send terminal bytes|`FINAL/index.html:563-600`|
|actor → actor|E|forget/refresh/revise prior observation|`model: epistemic actor transitions`|
|repo → discover|C|resolve ref and fetch tree if network succeeds|`FINAL/index.html:767-866`|
|repo → workspace|C|fetch specified commit files|`FINAL/index.html:728-738,825-828`|
|discover → workspace|C|select project and initiate file fetch|`FINAL/index.html:807-838,879-881`|
|discover → discover|C|pending fetch succeeds/fails/late|`FINAL/index.html:854-885`|
|workspace → workspace|E|invalidate/switch/edit/reload|`FINAL/index.html:705-720,807-845`|
|workspace → draft|C|save draft if storage writable|`FINAL/index.html:645-655,915-918`|
|draft → workspace|C|merge matching identity if stored|`FINAL/index.html:739-763`|
|workspace → build|C|snapshot selected HDL and XDC if ready|`FINAL/index.html:1099-1115`|
|workspace → discover|E|base URL editing can invalidate active selection|`FINAL/index.html:632,705-720`|
|build → yosys|C|launch synthesis worker|`FINAL/index.html:1120-1133`|
|yosys → build|C|synthesis success/error response|`FINAL/index.html:1123-1133`|
|build → cache|C|get pinned database/wasm/FASM assets|`FINAL/index.html:1138-1144,1178-1182`|
|cache → build|C|return assets or reject promise|`FINAL/index.html:283-310`|
|build → pnr|C|launch nextpnr worker|`FINAL/index.html:1146-1172`|
|pnr → build|C|emit FASM or error|`FINAL/index.html:1154-1172`|
|build → fasm|C|send FASM and map to worker|`FINAL/index.html:1183-1197`|
|fasm → build|C|return frames, warning telemetry, or error|`FINAL/index.html:1187-1198`|
|build → frames|C|send frames and part YAML|`FINAL/index.html:1200-1227`|
|frames → build|C|return bitstream or error|`FINAL/index.html:1211-1227`|
|build → artifact|C|publish bitstream when assembly succeeds|`FINAL/index.html:1227-1238`|
|artifact → usb|C|capture selected bitstream at click|`FINAL/index.html:1249-1264`|
|usb → board|C|JTAG program device after IDCODE check|`PRODUCTION_GRADE/ftdi-jtag.js:160-199`|
|board → usb|C|provide silicon IDCODE and DONE status|`PRODUCTION_GRADE/ftdi-jtag.js:124-157,192-199`|
|usb → actor|C|log flash success or error|`FINAL/index.html:1264-1269`|
|board → rtl|E|clock and input signals drive HDL|`stopwatch/top.v:top`|
|rtl → board|E|drive display segments, anodes and LEDs|`stopwatch/top.v:hex_driver`|
|ble → rtl|C|delimit UART command with LF|`stopwatch/top.v:BLE UART parser`|
|rtl → ble|C|return UART answer when requested|`stopwatch/top.v:UART TX response`|
|ble → ble|E|connect/disconnect/chunk/receive notifications|`PRODUCTION_GRADE/urbana-ble.js:34-124`|
|serial → rtl|C|UART bridge data to FPGA|`stopwatch/top.v:UART_RXD`|
|rtl → serial|C|USB terminal monitors BLE incoming data|`stopwatch/top.v:UART_RXD`|
|rtl → rtl|E|advance counters/scan digits/decode commands|`stopwatch/top.v:hex_driver and counters`|
|artifact → artifact|E|retain earlier version across source edits|`FINAL/index.html:410,1091,1227`|
|cache → cache|E|warmup, deduplicate promise, retry after rejection|`FINAL/index.html:277-326`|
|draft → draft|E|persist/fail/restore local records|`FINAL/index.html:645-655,888-905`|
|board → board|E|clock advances, reset, DONE can remain low|`Urbana device behavior and stopwatch RTL`|
|usb → usb|E|permission, init, transfer, status, close|`PRODUCTION_GRADE/ftdi-jtag.js:30-199`|
|board → repo|X|No direct interface at modeled depth|Physical board has no direct GitHub network/API interface; only JTAG/UART pins|
|rtl → repo|X|No direct interface at modeled depth|Synthesized stopwatch contains no network/GitHub client|
|ble → repo|X|No direct interface at modeled depth|BLE GATT UART client has no repository write path|
|serial → repo|X|No direct interface at modeled depth|FTDI UART driver has no repository write path|
|board → draft|X|No direct interface at modeled depth|FPGA signals cannot directly mutate browser localStorage|
|rtl → draft|X|No direct interface at modeled depth|HDL has no direct localStorage interface|
|frames → repo|X|No direct interface at modeled depth|Frames2bit worker produces bitstream bytes, never repository writes|
|yosys → repo|X|No direct interface at modeled depth|Yosys worker produces synthesis data, never repository writes|
|pnr → repo|X|No direct interface at modeled depth|nextpnr worker produces FASM, never repository writes|

Unresolved pairs require follow-up, not exclusion. Pairwise coverage is an **audit of knowledge**, not proof of transition completeness.

## Computed reachability and shortest counterexamples

### workspace_original

States: 6899; edges: 31620; depth: 10; truncated: False.

**WRONG_SOURCE_ASSOCIATION** (shortest depth 5): begin Fetch HDL at current URL → user switches project URL from A to B → begin Fetch XDC at current URL → Fetch XDC response updates editor → Fetch HDL response commits into current workspace. End state: `{'selected': 1, 'identity': 1, 'source_origin': 0, 'xdc_origin': 1}`.

**WRONG_XDC_ASSOCIATION** (shortest depth 5): begin Fetch HDL at current URL → begin Fetch XDC at current URL → user switches project URL from A to B → Fetch XDC response updates editor → Fetch HDL response commits into current workspace. End state: `{'selected': 1, 'identity': 1, 'source_origin': 0, 'xdc_origin': 0}`.

### workspace_guarded

States: 3055; edges: 15832; depth: 10; truncated: False.

No modeled contract violation reached within this projection and bound.

### build_program

States: 13161; edges: 67331; depth: 15; truncated: False.

**WRONG_SOURCE_ASSOCIATION** (shortest depth 5): begin Fetch HDL at current URL → user switches project URL from A to B → begin Fetch XDC at current URL → Fetch XDC response updates editor → Fetch HDL response commits into current workspace. End state: `{'selected': 1, 'identity': 1, 'source_origin': 0, 'xdc_origin': 1}`.

**WRONG_XDC_ASSOCIATION** (shortest depth 5): begin Fetch HDL at current URL → begin Fetch XDC at current URL → user switches project URL from A to B → Fetch XDC response updates editor → Fetch HDL response commits into current workspace. End state: `{'selected': 1, 'identity': 1, 'source_origin': 0, 'xdc_origin': 0}`.

### transport_display

States: 978; edges: 3248; depth: 10; truncated: False.

No modeled contract violation reached within this projection and bound.

## Model limitations

- No complete verification of FPGA gates or routing
- Unresolved node pairs cannot be claimed impossible
- Bounded interleavings, not all infinite traces
- Actor and hardware outcomes abstracted by labels