// synth-worker.js
importScripts('https://cdn.jsdelivr.net/npm/@yowasp/yosys/gen/bundle.js');

self.onmessage = async (e) => {
    const { type, topModule, verilogCode } = e.data;

    if (type !== 'run') return;

    try {
        self.postMessage({ type: 'log', text: `Starting Yosys synthesis for top module '${topModule}'...` });

        const yosysScript = [
            'read_verilog -sv input.v',
            `synth_xilinx -flatten -abc9 -nobram -arch xc7 -top ${topModule}`,
            'write_json synth.json'
        ].join('; ');

        // The Yosys Wasm API expects an object of input files
        const inputs = { 'input.v': verilogCode };

        // Run the WebAssembly Yosys engine
        const filesOut = await runYosys(
            ['-p', yosysScript],
            inputs,
            { 
                stdout: b => b && self.postMessage({ type: 'log', text: new TextDecoder().decode(b).trimEnd() }), 
                stderr: b => b && self.postMessage({ type: 'log', text: '[WARN] ' + new TextDecoder().decode(b).trimEnd() }) 
            }
        );

        if (!filesOut['synth.json']) {
             throw new Error("Yosys failed to generate synth.json. Check your Verilog syntax.");
        }

        // Return the raw byte array of the JSON file
        self.postMessage({ type: 'success', jsonBuffer: filesOut['synth.json'].buffer });

    } catch (err) {
        self.postMessage({ type: 'error', message: err.message });
    }
};