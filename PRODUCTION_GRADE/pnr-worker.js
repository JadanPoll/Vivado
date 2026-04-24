let lastError = "Unknown error during initialization.";
let successHandled = false;

self.onmessage = function(event) {
    const msg = event.data;
    if (msg.type === 'run') runNextpnr(msg);
};

function runNextpnr(msg) {
    self._baseUrl = msg.baseUrl;

    // --- XDC FILTERING LOGIC (Vivado Emulation) ---
// --- XDC FILTERING LOGIC (Vivado Emulation) ---
    let filteredXdc = msg.xdc;
    try {
        const jsonStr = new TextDecoder().decode(new Uint8Array(msg.jsonBuffer));
        const netlist = JSON.parse(jsonStr);
        const validPorts = new Set();
        
        if (netlist.modules) {
            for (const mod in netlist.modules) {
                if (netlist.modules[mod].ports) {
                    Object.keys(netlist.modules[mod].ports).forEach(p => validPorts.add(p));
                }
            }
        }

        let droppedPorts = [];
        let droppedDirectives = 0;
        let appliedCount = 0;

filteredXdc = msg.xdc.split('\n').map(line => {
            let trimmed = line.trim();
            // Preserve full-line comments as they are
            if (trimmed.startsWith('#')) return trimmed;
            
            // Strip inline comments
            const hashIdx = trimmed.indexOf('#');
            if (hashIdx !== -1) trimmed = trimmed.substring(0, hashIdx).trim();
            
            // Strip trailing semicolons
            if (trimmed.endsWith(';')) trimmed = trimmed.slice(0, -1).trim();
            
            return trimmed;
        }).filter(trimmed => {
            if (trimmed.startsWith('#') || trimmed === '') return true;
            
            // 1. Explicit blocklist for unsupported Vivado board/config directives
            if (trimmed.includes('get_iobanks') || 
                trimmed.includes('get_iobank') ||
                trimmed.includes('current_instance') ||
                trimmed.startsWith('current_design') ||
                trimmed.includes('INTERNAL_VREF') ||
                trimmed.includes('IO_BUFFER_TYPE') ||
                trimmed.includes('CFGBS') ||
                trimmed.includes('CFGBVS') ||
                trimmed.includes('CONFIG_VOLTAGE') ||
                trimmed.includes('SPI_buswidth') ||
                trimmed.includes('UNUSEDPIN') ||
                trimmed.includes('COMPRESS')) {
                droppedDirectives++;
                return false;
            }

            // 2. Safely capture the full port name
            const match = trimmed.match(/get_ports\s+(?:\{([^}]+)\}|([a-zA-Z0-9_]+(?:\[\d+\])?))/);
            if (match) {
                const fullPort = match[1] || match[2];
                const basePort = fullPort.replace(/\[\d+\]/g, ''); 
                
                const isUsed = validPorts.has(fullPort) || 
                               validPorts.has(basePort) || 
                               validPorts.has('\\' + fullPort) || 
                               validPorts.has('\\' + basePort);
                
                if (!isUsed) {
                    droppedPorts.push(fullPort);
                    return false;
                }
                appliedCount++;
                return true;
            }
            
            // 3. Keep everything else (like create_clock)
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
    // ----------------------------------------------
    // ----------------------------------------------
    // ----------------------------------------------

    self.Module = {
        noInitialRun: false,
        wasmBinary: msg.wasmBuffer,
        arguments: [
            '--chipdb', '/chipdb.bin',
            '--json', '/design.json',
            '--xdc', '/design.xdc',
            '--fasm', '/out.fasm',
            '--timing-allow-fail'
        ],
        preRun: function() {
            self.FS.writeFile('/chipdb.bin', new Uint8Array(msg.chipdbBuffer));
            self.FS.writeFile('/design.json', new Uint8Array(msg.jsonBuffer));
            self.FS.writeFile('/design.xdc', filteredXdc); // Write the filtered file
        },
        print: function(text) { self.postMessage({ type: 'log', text: text }); },
        printErr: function(text) {
            lastError = text;
            self.postMessage({ type: 'log', text: text });
        },
        postRun: function() { 
            handleSuccess(); 
        },
        onExit: function(code) {
            if (code === 0) handleSuccess();
            else {
                self.postMessage({ type: 'error', message: `NextPNR exited with code ${code}. Last error: ${lastError}` });
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

function handleSuccess() {
    if (successHandled) return;
    successHandled = true;
    try {
        console.log("art herre");
        const rawFasm = self.FS.readFile('/out.fasm', { encoding: 'utf8' });
        self.postMessage({ type: "log", message: "=== RAW FASM ===\n" + rawFasm });
        console.log(rawFasm);
        const fixedFasm = applyFasmFix(rawFasm);
        self.postMessage({ type: 'fasm_fixed', data: fixedFasm });
    } catch (err) {
        self.postMessage({ type: 'error', message: "Failed to read output FASM: " + err.toString() });
    }
    self.postMessage({ type: 'done' });
}

function applyFasmFix(fasmStr) {
    const lines = fasmStr.split('\n');
    const inOnlyTileIobs = new Set();
    for (const line of lines) {
        if (line.includes('IN_ONLY')) {
            const parts = line.trim().split('.');
            if (parts.length >= 2) inOnlyTileIobs.add(parts[0] + '.' + parts[1]);
        }
    }
    return lines.filter(line => {
        const trimmed = line.trim();
        if (!trimmed) return true;
        const parts = trimmed.split('.');
        if (parts.length >= 2) {
            const tileIob = parts[0] + '.' + parts[1];
            if (inOnlyTileIobs.has(tileIob) && (trimmed.includes('DRIVE') || trimmed.includes('SLEW'))) {
                return false;
            }
        }
        return true;
    }).join('\n');
}