// pnr-worker.js
let lastError = "Unknown error during initialization.";
let successHandled = false;

self.onmessage = function(event) {
    const msg = event.data;
    if (msg.type === 'run') runNextpnr(msg);
};

function runNextpnr(msg) {
    self.Module = {
        noInitialRun: false, // Let Emscripten natively invoke main()
        wasmBinary: msg.wasmBuffer,
        arguments: [
            '--chipdb', '/chipdb.bin',
            '--json', '/design.json',
            '--xdc', '/design.xdc',
            '--fasm', '/out.fasm',
            '--timing-allow-fail'
        ],
        preRun: function() {
            // Write inputs to MEMFS instantly before main() executes
            self.FS.writeFile('/chipdb.bin', new Uint8Array(msg.chipdbBuffer));
            self.FS.writeFile('/design.json', new Uint8Array(msg.jsonBuffer));
            self.FS.writeFile('/design.xdc', msg.xdc);
        },
        print: function(text) { self.postMessage({ type: 'log', text: text }); },
        printErr: function(text) {
            lastError = text; 
            self.postMessage({ type: 'log', text: text });
        },
        postRun: function() { handleSuccess(); },
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

    function handleSuccess() {
        if (successHandled) return;
        successHandled = true;
        try {
            const rawFasm = self.FS.readFile('/out.fasm', { encoding: 'utf8' });
            self.postMessage({ type: 'fasm', data: rawFasm });
            const fixedFasm = applyFasmFix(rawFasm);
            self.postMessage({ type: 'fasm_fixed', data: fixedFasm });
        } catch (err) {
            self.postMessage({ type: 'error', message: "Failed to read output FASM: " + err.toString() });
        }
        self.postMessage({ type: 'done' });
    }

    importScripts('nextpnr-xilinx.js');
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
