// frames-worker.js
let successHandled = false;

self.onmessage = function(event) {
    const msg = event.data;
    if (msg.type === 'run') runFrames2Bit(msg);
};

function runFrames2Bit(msg) {
    self.Module = {
        noInitialRun: false,
        wasmBinary: msg.wasmBuffer,  // ADD THIS
        arguments: ['--part_file', '/part.yaml', '--frm_file', '/design.frames', '--output_file', '/design.bit'],
        preRun: function() {
            self.FS.writeFile('/part.yaml', new TextEncoder().encode(msg.partYaml));
            self.FS.writeFile('/design.frames', new TextEncoder().encode(msg.framesStr));
        },
        print: function(text) { self.postMessage({ type: 'log', text: text }); },
        printErr: function(text) { self.postMessage({ type: 'log', text: text }); },
        postRun: function() { handleSuccess(); },
        onExit: function(code) {
            if (code === 0) handleSuccess();
            else self.postMessage({ type: 'error', message: `xc7frames2bit exited with code ${code}` });
        },
        onAbort: function(what) {
            self.postMessage({ type: 'error', message: `xc7frames2bit aborted: ${what}` });
        }
    };

    function handleSuccess() {
        if (successHandled) return;
        successHandled = true;
        try {
            const rawBitstream = self.FS.readFile('/design.bit');
            // We MUST slice the buffer to detach it from the WASM memory heap before transferring!
            const bitstream = new Uint8Array(rawBitstream).slice();
            self.postMessage({ type: 'success', bitstream: bitstream }, [bitstream.buffer]);
        } catch (err) {
            self.postMessage({ type: 'error', message: "Failed to read design.bit: " + err.toString() });
        }
    }
    importScripts(msg.baseUrl + 'xc7frames2bit.js');
    
}
