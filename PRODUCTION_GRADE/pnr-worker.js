// =============================================================================
// pnr-worker.js  —  NextPNR Place-and-Route Web Worker
// Fixes applied:
//   1. successHandled + lastError reset at the top of every run
//   2. postRun / onExit race is safe (guard already present, now documented)
//   3. handleSuccess log used correct key 'text' instead of 'message'
//   4. wasmBuffer captured into a local const before any async hand-off
//   5. proc_exit WASI stub uncommented to prevent silent pipeline hangs
//   6. applyFasmFix IN_ONLY comment added for dot-in-name edge case
// =============================================================================

let lastError   = "(no nextpnr stderr received)";
let bootStage = "not started";
let recentDiagnostics = [];
function recordDiagnostic(source, value) {
    const line = `[${source}] ${String(value)}`;
    recentDiagnostics.push(line);
    if (recentDiagnostics.length > 24) recentDiagnostics.shift();
    lastError = line;
    self.postMessage({ type: "log", text: line });
}
function diagnosticSummary() {
    return `stage=${bootStage}; ${recentDiagnostics.length ? recentDiagnostics.join(" | ") : "no diagnostic emitted by nextpnr"}`;
}
let successHandled = false;
let finished = false;
let exitCode = null;
function failOnce(message) {
    if (finished) return;
    finished = true;
    self.postMessage({ type: 'error', message });
    self.postMessage({ type: 'done' });
}

self.onmessage = function(event) {
    const msg = event.data;
    if (msg.type === 'run') runNextpnr(msg);
};

function runNextpnr(msg) {
    // --- FIX 1: Reset run-level state so a reused worker starts clean ----------
    successHandled = false;
    finished = false;
    exitCode = null;
    lastError      = "(no nextpnr stderr received)";
    bootStage = "processing inputs";
    recentDiagnostics = [];
    // ---------------------------------------------------------------------------

    // Emscripten's generated runtime sends stderr to console.error rather than
    // Module.printErr. Its WASM __abort_js can call abort(\"\") with no reason.
    // Capture stderr and keep the actual JS/WASM abort stack visible.
    const originalConsoleError = console.error;
    console.error = function(...args) {
        recordDiagnostic('NEXTPNR CONSOLE', args.map(String).join(' '));
        originalConsoleError.apply(console, args);
    };

    self._baseUrl = msg.baseUrl;

    // --- FIX 4: Capture the transferred buffer into a local before any async --
    //     After postMessage transfer the ArrayBuffer is detached; a local const
    //     holds the reference safely for the synchronous instantiateWasm call.
    const wasmBuffer = msg.wasmBuffer;
    // ---------------------------------------------------------------------------

    // =========================================================================
    // XDC FILTERING LOGIC (Vivado → nextpnr-xilinx emulation)
    // =========================================================================
    let filteredXdc = msg.xdc;
    let primaryClockFreqMHz = null;


    let cleanedJsonStr = new TextDecoder().decode(new Uint8Array(msg.jsonBuffer)); // fallback: raw

    try {
        const netlist   = JSON.parse(cleanedJsonStr);


    // Strip $scopeinfo cells — nextpnr-xilinx has no placer entry for them

    // Count BEFORE scrub
    let scopeInfoCount = 0;
    for (const modName in netlist.modules) {
        const cells = netlist.modules[modName].cells || {};
        for (const cellName in cells) {
            if (cells[cellName].type === '$scopeinfo') scopeInfoCount++;
        }
    }

    // Now scrub
    for (const modName in netlist.modules) {
        const cells = netlist.modules[modName].cells || {};
        for (const cellName in cells) {
            if (cells[cellName].type === '$scopeinfo') delete cells[cellName];
        }
    }
    cleanedJsonStr = JSON.stringify(netlist);

    self.postMessage({ type: 'log', text: `[PNR] Scrubbed ${scopeInfoCount} $scopeinfo cell(s) from netlist.` });

    const validPorts = new Set();



        
        const topModules = Object.entries(netlist.modules || {}).filter(([name, m]) => m.attributes && (m.attributes.top === 1 || m.attributes.top === '1' || m.attributes.top === '00000000000000000000000000000001'));
        if (topModules.length !== 1) throw new Error('Expected exactly one Yosys top module, found ' + topModules.length);
        const topPorts = topModules[0][1].ports || {};
        Object.keys(topPorts).forEach(p => validPorts.add(p));

        let droppedPorts      = [];
        let droppedDirectives = 0;
        let appliedCount      = 0;
        const assignedPins = new Map();
        const assignedPorts = new Map();

        filteredXdc = msg.xdc.split('\n').map(line => {
            let trimmed = line.trim();

            // Preserve full-line comments verbatim
            if (trimmed.startsWith('#')) return trimmed;

            // Strip inline comments
            const hashIdx = trimmed.indexOf('#');
            if (hashIdx !== -1) trimmed = trimmed.substring(0, hashIdx).trim();

            // Strip trailing semicolons (nextpnr XDC parser rejects them)
            if (trimmed.endsWith(';')) trimmed = trimmed.slice(0, -1).trim();

            return trimmed;

        }).filter(trimmed => {
            if (trimmed.startsWith('#') || trimmed === '') return true;

            // 1. Blocklist: unsupported Vivado board / config directives
            if (
                trimmed.includes('get_iobanks')     ||
                trimmed.includes('get_iobank')      ||
                trimmed.includes('current_instance')||
                trimmed.startsWith('current_design')||
                trimmed.includes('INTERNAL_VREF')   ||
                trimmed.includes('IO_BUFFER_TYPE')  ||
                trimmed.includes('CFGBS')           ||
                trimmed.includes('CFGBVS')          ||
                trimmed.includes('CONFIG_VOLTAGE')  ||
                trimmed.includes('SPI_buswidth')    ||
                trimmed.includes('UNUSEDPIN')       ||
                trimmed.includes('COMPRESS')
            ) {
                droppedDirectives++;
                return false;
            }

            // 2. Port-existence check
            //    Note: if a FASM port name itself contains a dot this regex still
            //    captures it correctly because we match on the full braced string.
            const match = trimmed.match(
                /get_ports\s+(?:\{([^}]+)\}|([a-zA-Z0-9_]+(?:\[\d+\])?))/
            );
            if (match) {
                const fullPort = match[1] || match[2];
                const basePort = fullPort.replace(/\[\d+\]/g, '');

                const isUsed =
                    validPorts.has(fullPort)          ||
                    validPorts.has(basePort)           ||
                    validPorts.has('\\' + fullPort)    ||
                    validPorts.has('\\' + basePort);

                if (!isUsed) {
                    droppedPorts.push(fullPort);
                    return false;
                }
                const pin = trimmed.match(/PACKAGE_PIN\s+([A-Z]+\d+)/i);
                if (pin) {
                    const physical = pin[1].toUpperCase();
                    const previousPort = assignedPins.get(physical);
                    const previousPin = assignedPorts.get(fullPort);
                    if (previousPort && previousPort !== fullPort) throw new Error(`Pin ${physical} assigned to both ${previousPort} and ${fullPort}`);
                    if (previousPin && previousPin !== physical) throw new Error(`Port ${fullPort} assigned to both ${previousPin} and ${physical}`);
                    assignedPins.set(physical, fullPort);
                    assignedPorts.set(fullPort, physical);
                }
                appliedCount++;
                return true;
            }

            // 3. Keep everything else (create_clock, etc.)
            return true;

        }).join('\n');

        self.postMessage({ type: 'log', text: `[PNR] XDC Filter: Applied ${appliedCount} active port constraints.` });

        if (droppedDirectives > 0) {
            self.postMessage({ type: 'log', text: `[PNR] XDC Filter: Stripped ${droppedDirectives} unsupported board directives.` });
        }

        if (droppedPorts.length > 0) {
            const uniqueDrops = [...new Set(droppedPorts)];
            self.postMessage({
                type: 'log',
                text: `[WARN] Ignored ${uniqueDrops.length} orphaned XDC constraints missing from netlist: ${uniqueDrops.join(', ')}`
            });
        }

    } catch (e) {
        failOnce(`[PNR] Netlist/XDC validation failed: ${e.message}`);
        return;
    }
    // Translate a single basic primary-clock constraint to nextpnr's global
    // frequency option. Some synth_xilinx netlists expose a port with no
    // getNetByAlias entry; nextpnr's parseXdc currently terminates instead of
    // reporting that missing alias. Global --freq avoids that lookup while
    // retaining the requested timing target (period in ns -> MHz).
    const clockLines = filteredXdc.split('\n').filter(l => /^\s*create_clock\b/.test(l));
    if (clockLines.length === 1) {
        const line = clockLines[0].trim();
        const parsed = line.match(/^create_clock\s+-period\s+(\d+(?:\.\d+)?)(?:\s+-name\s+[\w.-]+)?\s+\[get_ports\s+\{?([\w.]+)\}?\]$/);
        if (parsed) {
            const period = Number(parsed[1]);
            if (!(period > 0) || !Number.isFinite(1000 / period)) {
                failOnce('Invalid create_clock period: ' + parsed[1]);
                return;
            }
            primaryClockFreqMHz = 1000 / period;
            filteredXdc = filteredXdc.split('\n').filter(l => l !== clockLines[0]).join('\n');
            self.postMessage({type:'log',text:'[TIMING] Primary clock '+parsed[2]+' period '+period+' ns -> nextpnr --freq '+primaryClockFreqMHz.toPrecision(9)+' MHz; preserved target, bypassed invalid input-port net alias lookup.'});
        }
    }
    // Other clock/SDC forms are left unchanged; never silently drop them.

    // =========================================================================

    self.Module = {
        noInitialRun: false,
        wasmBinary: wasmBuffer,   // FIX 4: use the captured local

        // =====================================================================
        // WASM INSTANTIATION
        // =====================================================================
        instantiateWasm: function(imports, successCallback) {
            if (!imports.env) imports.env = {};

            // --- FIX 5: Uncomment proc_exit stub ---------------------------------
            // Without this, any normal C++ exit() call from nextpnr throws a
            // RuntimeError that bypasses onExit/postRun entirely, leaving the
            // pipeline silently hung forever.
            if (!imports.wasi_snapshot_preview1) imports.wasi_snapshot_preview1 = {};
            imports.wasi_snapshot_preview1.proc_exit = function(code) {
                exitCode = code;
                // Don't close the worker: postRun must still read /out.fasm.
            };
            // ---------------------------------------------------------------------

            bootStage = "instantiating nextpnr WASM";
            WebAssembly.instantiate(wasmBuffer, imports)   // FIX 4: local ref
                .then(function(output) {
                    bootStage = "WASM instantiated; entering nextpnr runtime";
                    successCallback(output.instance, output.module);
                })
                .catch(function(err) {
                    recordDiagnostic('WASM BOOT ERROR', err && (err.stack || err.message) || err);
                    failOnce(`WASM Boot Error: ${diagnosticSummary()}`);
                });

            return {};
        },
        // =====================================================================

        arguments: [
            '--chipdb', '/chipdb.bin',
            '--json',   '/design.json',
            '--xdc',    '/design.xdc',
            '--fasm',   '/out.fasm',
            '--timing-allow-fail',
            ...(primaryClockFreqMHz === null ? [] : ['--freq', String(primaryClockFreqMHz)])
        ],

        preRun: function() {
    bootStage = "writing chipdb/netlist/XDC into WASM filesystem";
    self.FS.writeFile('/chipdb.bin', new Uint8Array(msg.chipdbBuffer));
    self.FS.writeFile('/design.json', cleanedJsonStr);  // $scopeinfo already stripped
    self.FS.writeFile('/design.xdc', filteredXdc);
    bootStage = 'nextpnr executable running';
        },

        print:    function(text) { self.postMessage({ type: 'log', text }); },
        printErr: function(text) {
            recordDiagnostic('NEXTPNR STDERR', text);
        },

        // Successful completion is delivered only by postRun, after FS output is ready.
        postRun: function() {
            // Emscripten can finish normally without invoking onExit.
            // Preserve any explicit nonzero WASI exit instead of claiming success.
            if (exitCode !== null && exitCode !== 0)
                failOnce('NextPNR exited with code ' + exitCode + '; ' + diagnosticSummary());
            else
                handleSuccess();
        },

        onExit: function(code) {
            exitCode = code;
            // Only postRun can announce success: Emscripten may invoke onExit
            // before postRun has completed /out.fasm writes.
            if (code !== 0) failOnce(`NextPNR exited with code ${code}; ${diagnosticSummary()}`);
        },

        onAbort: function(what) {
            const reason = what ? String(what) : '(WASM invoked abort with empty reason)';
            recordDiagnostic('NEXTPNR ABORT STACK', new Error(reason).stack || reason);
            failOnce('NextPNR aborted: ' + reason + '; ' + diagnosticSummary());
        }
    };

    bootStage = 'loading nextpnr JavaScript runtime';
    try {
        importScripts(self._baseUrl + 'nextpnr-xilinx.js');
    } catch (err) {
        recordDiagnostic('RUNTIME LOAD ERROR', err && (err.stack || err.message) || err);
        failOnce(diagnosticSummary());
    }
}

// =============================================================================
// SUCCESS HANDLER
// =============================================================================
function handleSuccess() {
    // FIX 2: guard — only the first caller wins (postRun vs onExit race)
    if (successHandled || finished) return;
    successHandled = true;

    try {
        const rawFasm = self.FS.readFile('/out.fasm', { encoding: 'utf8' });

        // FIX 3: was using key 'message' — main thread listens for 'text'
        self.postMessage({ type: 'log', text: '[FASM] Generated ' + rawFasm.length + ' characters; full output available for download.' });

        if (!rawFasm.trim()) throw new Error('Empty FASM output');
        const fixedFasm = applyFasmFix(rawFasm);
        if (!fixedFasm.trim()) throw new Error('Empty FASM after filtering');
        self.postMessage({ type: 'fasm_fixed', data: fixedFasm });
        finished = true;
        self.postMessage({ type: 'done' });

    } catch (err) {
        failOnce('Failed to read output FASM: ' + err.toString());
    }
}

// =============================================================================
// FASM POST-PROCESSING
// Strips DRIVE / SLEW annotations from IN_ONLY IOBs, which nextpnr emits but
// the downstream bitstream assembler rejects.
//
// NOTE: the tile+IOB key is built as parts[0]+'.'+parts[1].  This is correct
// for standard XC7 FASM line format "TILE.IOB.FEATURE VALUE".  If a tile or
// IOB name ever contains a literal dot (not currently seen in xc7s50 databases)
// the key would be wrong — revisit if new device databases are added.
// =============================================================================
function applyFasmFix(fasmStr) {
    const lines = fasmStr.split('\n');

    // First pass: collect all tile.iob prefixes that have an IN_ONLY annotation
    const inOnlyTileIobs = new Set();
    for (const line of lines) {
        if (line.includes('IN_ONLY')) {
            const parts = line.trim().split('.');
            if (parts.length >= 2) {
                inOnlyTileIobs.add(parts[0] + '.' + parts[1]);
            }
        }
    }

    // Second pass: drop DRIVE / SLEW lines that belong to those IN_ONLY IOBs
    return lines.filter(line => {
        const trimmed = line.trim();
        if (!trimmed) return true;

        const parts    = trimmed.split('.');
        if (parts.length >= 2) {
            const tileIob = parts[0] + '.' + parts[1];
            if (
                inOnlyTileIobs.has(tileIob) &&
                (trimmed.includes('DRIVE') || trimmed.includes('SLEW'))
            ) {
                return false;
            }
        }
        return true;
    }).join('\n');
}