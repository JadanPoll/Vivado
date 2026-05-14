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

let lastError   = "Unknown error during initialization.";
let successHandled = false;

self.onmessage = function(event) {
    const msg = event.data;
    if (msg.type === 'run') runNextpnr(msg);
};

function runNextpnr(msg) {
    // --- FIX 1: Reset run-level state so a reused worker starts clean ----------
    successHandled = false;
    lastError      = "Unknown error during initialization.";
    // ---------------------------------------------------------------------------

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


    let cleanedJsonStr = new TextDecoder().decode(new Uint8Array(msg.jsonBuffer)); // fallback: raw


    try {
        const jsonStr   = new TextDecoder().decode(new Uint8Array(msg.jsonBuffer));
        const netlist   = JSON.parse(jsonStr);


    // Strip $scopeinfo cells — nextpnr-xilinx has no placer entry for them
    for (const modName in netlist.modules) {
        const cells = netlist.modules[modName].cells;
        for (const cellName in cells) {
            if (cells[cellName].type === '$scopeinfo') {
                delete cells[cellName];
            }
        }
    }
    cleanedJsonStr = JSON.stringify(netlist);

    const validPorts = new Set();



        
        if (netlist.modules) {
            for (const mod in netlist.modules) {
                if (netlist.modules[mod].ports) {
                    Object.keys(netlist.modules[mod].ports).forEach(p => validPorts.add(p));
                }
            }
        }

        let droppedPorts      = [];
        let droppedDirectives = 0;
        let appliedCount      = 0;

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
        self.postMessage({ type: 'log', text: `[PNR] XDC Filter bypassed (parse error): ${e.message}` });
    }
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
                // Intentional no-op: the Worker's onExit/postRun handle shutdown.
                // Do NOT call self.close() here — that would kill the worker
                // before handleSuccess can read /out.fasm from the virtual FS.
            };
            // ---------------------------------------------------------------------

            WebAssembly.instantiate(wasmBuffer, imports)   // FIX 4: local ref
                .then(function(output) {
                    successCallback(output.instance, output.module);
                })
                .catch(function(err) {
                    self.postMessage({ type: 'error', message: `WASM Boot Error: ${err}` });
                });

            return {};
        },
        // =====================================================================

        arguments: [
            '--chipdb', '/chipdb.bin',
            '--json',   '/design.json',
            '--xdc',    '/design.xdc',
            '--fasm',   '/out.fasm',
            '--timing-allow-fail'
        ],

        preRun: function() {
    self.FS.writeFile('/chipdb.bin', new Uint8Array(msg.chipdbBuffer));
    self.FS.writeFile('/design.json', cleanedJsonStr);  // $scopeinfo already stripped
    self.FS.writeFile('/design.xdc', filteredXdc);
        },

        print:    function(text) { self.postMessage({ type: 'log', text }); },
        printErr: function(text) {
            lastError = text;
            self.postMessage({ type: 'log', text });
        },

        // FIX 2: Both postRun and onExit(0) call handleSuccess().
        //         The successHandled guard (reset in FIX 1) makes this safe —
        //         whichever fires first wins; the second call is a no-op.
        postRun: function() { handleSuccess(); },

        onExit: function(code) {
            if (code === 0) {
                handleSuccess();
            } else {
                self.postMessage({
                    type: 'error',
                    message: `NextPNR exited with code ${code}. Last error: ${lastError}`
                });
                self.postMessage({ type: 'done' });
            }
        },

        onAbort: function(what) {
            self.postMessage({ type: 'error', message: `NextPNR aborted: ${what}` });
            self.postMessage({ type: 'done' });
        }
    };

    importScripts(self._baseUrl + 'nextpnr-xilinx.js');
}

// =============================================================================
// SUCCESS HANDLER
// =============================================================================
function handleSuccess() {
    // FIX 2: guard — only the first caller wins (postRun vs onExit race)
    if (successHandled) return;
    successHandled = true;

    try {
        const rawFasm = self.FS.readFile('/out.fasm', { encoding: 'utf8' });

        // FIX 3: was using key 'message' — main thread listens for 'text'
        self.postMessage({ type: 'log', text: "=== RAW FASM (debug) ===\n" + rawFasm });

        const fixedFasm = applyFasmFix(rawFasm);
        self.postMessage({ type: 'fasm_fixed', data: fixedFasm });

    } catch (err) {
        self.postMessage({
            type: 'error',
            message: "Failed to read output FASM: " + err.toString()
        });
    }

    self.postMessage({ type: 'done' });
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