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
    const source = msg.baseUrl + 'xc7frames2bit.js';
    try {
        importScripts(source);
    } catch (cdnError) {
        // jsDelivr may lag immutable GitHub commits; use the exact same revision.
        const revision = msg.baseUrl.split('@')[1]?.split('/')[0];
        if (!revision) {
            self.postMessage({ type: 'error', message: 'Frames2Bit script unavailable at ' + source + ': ' + cdnError });
            return;
        }
        const fallback = 'https://raw.githubusercontent.com/JadanPoll/Vivado/' + revision + '/PRODUCTION_GRADE/xc7frames2bit.js';
        self.postMessage({ type: 'log', text: '[ASSET] CDN script unavailable; trying matching GitHub revision ' + revision.slice(0, 7) });
        try {
            importScripts(fallback);
        } catch (rawError) {
            self.postMessage({ type: 'error', message: 'Frames2Bit script unavailable from CDN (' + cdnError + ') and GitHub (' + rawError + ')' });
        }
    }
    
}
