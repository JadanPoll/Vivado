import fs from 'fs';
import path from 'path';
import zlib from 'zlib';
import vm from 'vm';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);

const WORKSPACE_DIR = process.env.FPGA_ASSETS || 
    (fs.existsSync('/workspaces/Vivado/PRODUCTION_GRADE') ? 
     '/workspaces/Vivado/PRODUCTION_GRADE' : 
     `${process.env.HOME}/fpga_assets`);

const NEXTPNR_WASM = path.join(WORKSPACE_DIR, 'nextpnr-xilinx.wasm'); 
const NEXTPNR_JS = path.join(WORKSPACE_DIR, 'nextpnr-xilinx.js');
const CHIPDB_BR = path.join(WORKSPACE_DIR, 'xc7s50.bin.br');
const FASM_MAP_BR = path.join(WORKSPACE_DIR, 'xc7s50_fasm_map_v4.json.br');
const FRAMES2BIT_WASM = path.join(WORKSPACE_DIR, 'xc7frames2bit.wasm');
const FRAMES2BIT_JS = path.join(WORKSPACE_DIR, 'xc7frames2bit.js');
const PART_YAML = path.join(WORKSPACE_DIR, 'part.yaml');

// CLI arguments
const topVerilog = process.argv[2] || 'top.v';
const topXdc = process.argv[3] || 'top.xdc';
const outputBit = process.argv[4] || 'nextpnr_out.bit';
const topModule = process.argv[5] || 'top'; 

const timeout = setTimeout(() => {
    console.error('❌ NextPNR timeout after 5 minutes');
    process.exit(1);
}, 5 * 60 * 1000);

function readBrotliSync(filePath) {
    const cachePath = '/tmp/' + path.basename(filePath) + '_cache.bin';
    const fileStat = fs.statSync(filePath);
    try {
        if (fs.existsSync(cachePath) && fs.statSync(cachePath).mtimeMs >= fileStat.mtimeMs) {
            return fs.readFileSync(cachePath);
        }
    } catch(e) {}
    const compressed = fs.readFileSync(filePath);
    const decompressed = zlib.brotliDecompressSync(compressed);
    fs.writeFileSync(cachePath, decompressed);
    return decompressed;
}

// ---------------------------------------------------------
// [STEP 1] YoWASP Yosys Synthesis (ESM API)
// ---------------------------------------------------------
console.log('▶ [1/4] Running YoWASP Yosys Synthesis...');
try {
    const { runYosys } = await import('/home/nathan37/.nvm/versions/node/v20.20.0/lib/node_modules/@yowasp/yosys/gen/bundle.js');
    const verilogCode = fs.readFileSync(topVerilog, 'utf8');
    const topVerilogBasename = path.basename(topVerilog); 
    
    let result;
    try {
        result = await runYosys(
            ['-p', `synth_xilinx -flatten -abc9 -arch xc7 -top ${topModule}; write_json synth.json`, topVerilogBasename],
            { [topVerilogBasename]: verilogCode }
        );
    } catch(e) {
        result = e;
    }

    const json = result.files?.['synth.json'] ?? result['synth.json'];
    if (!json) { 
        console.error('❌ No synth.json produced'); 
        process.exit(1); 
    }
    const content = typeof json === 'string' ? json : new TextDecoder().decode(json);
    fs.writeFileSync('synth.json', content);
    console.log('✅ Synthesis complete');

} catch (e) {
    console.error('❌ Yosys Execution failed:', e);
    process.exit(1);
}

// ---------------------------------------------------------
// [STEP 2] XDC Filtering & NextPNR Execution
// ---------------------------------------------------------
console.log('▶ [2/4] Filtering XDC and Executing NextPNR WASM...');

const chipdbBuffer = readBrotliSync(CHIPDB_BR);
const jsonStr = fs.readFileSync('synth.json', 'utf8');
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

const filteredXdc = fs.readFileSync(topXdc, 'utf8').split('\n').map(line => {
    let trimmed = line.trim();
    if (trimmed.startsWith('#')) return trimmed;
    const hashIdx = trimmed.indexOf('#');
    if (hashIdx !== -1) trimmed = trimmed.substring(0, hashIdx).trim();
    if (trimmed.endsWith(';')) trimmed = trimmed.slice(0, -1).trim();
    return trimmed;
}).filter(trimmed => {
    if (trimmed.startsWith('#') || trimmed === '') return true;
    // Whitelist approach: nextpnr only supports get_ports-based constraints and create_clock.
    // Drop everything else silently so any Vivado XDC works without modification.
    // Supported: set_property ... [get_ports ...], create_clock ... [get_ports ...]
    // Dropped: get_cells, get_nets, get_clocks, get_iobanks, current_design, and all
    //          Vivado-only directives (CONFIG_VOLTAGE, CFGBVS, INTERNAL_VREF, etc.)
    const hasGetPorts = trimmed.includes('get_ports');
    const hasCreateClock = trimmed.startsWith('create_clock');
    if (!hasGetPorts && !hasCreateClock) {
        droppedDirectives++;
        return false;
    }
    const match = trimmed.match(/get_ports\s+(?:\{([^}]+)\}|([a-zA-Z0-9_]+(?:\[\d+\])?))/);
    if (match) {
        const fullPort = match[1] || match[2];
        const basePort = fullPort.replace(/\[\d+\]/g, '');
        const isUsed = validPorts.has(fullPort) || validPorts.has(basePort) || 
                       validPorts.has('\\' + fullPort) || validPorts.has('\\' + basePort);
        if (!isUsed) {
            droppedPorts.push(fullPort);
            return false;
        }
        appliedCount++;
        return true;
    }
    // create_clock with get_ports — keep it
    if (hasCreateClock && hasGetPorts) { appliedCount++; return true; }
    droppedDirectives++;
    return false;
}).join('\n');

console.log(`  ↳ XDC Filter: Applied ${appliedCount} active port constraints. Stripped ${droppedDirectives} unsupported directives.`);

global.self = global;
global.location = { href: import.meta.url };

const pnrWasmData = new Uint8Array(fs.readFileSync(NEXTPNR_WASM));

global.Module = {
    noInitialRun: false,
    wasmBinary: pnrWasmData,
    instantiateWasm: function(imports, successCallback) {
        WebAssembly.instantiate(pnrWasmData, imports).then(result => {
            successCallback(result.instance, result.module);
        }).catch(e => {
            console.error('❌ NextPNR WASM Instantiation failed:', e);
            process.exit(1);
        });
        return {};
    },
    arguments: [
        '--chipdb', '/chipdb.bin',
        '--json', '/design.json',
        '--xdc', '/design.xdc',  
        '--fasm', '/out.fasm',
        '--timing-allow-fail',
        '--top', topModule       
    ],
    preRun: function() {
        global.FS.writeFile('/chipdb.bin', chipdbBuffer);
        global.FS.writeFile('/design.json', fs.readFileSync('synth.json'));
        global.FS.writeFile('/design.xdc', filteredXdc);
    },
    print: (text) => console.log(`[NextPNR] ${text}`),
    printErr: (text) => console.error(`[NextPNR ERR] ${text}`),
    postRun: function() {
        runFasmToFrames(); 
    },
    onExit: function(code) {
        if (code !== 0) {
            console.error(`❌ NextPNR Execution crashed with code ${code}.`);
            process.exit(1);
        }
    }
};

require(NEXTPNR_JS);

// ---------------------------------------------------------
// [STEP 3] FASM Fix & FASM to Frames (Synchronous)
// ---------------------------------------------------------
let pnrDone = false; 

function runFasmToFrames() {
    if (pnrDone) return;
    pnrDone = true;
    clearTimeout(timeout); 

    console.log('▶ [3/4] Running FASM to Frames conversion...');
    
    const rawFasm = global.FS.readFile('/out.fasm', { encoding: 'utf8' });
    const lines = rawFasm.split('\n');
    const inOnlyTileIobs = new Set();
    for (const line of lines) {
        if (line.includes('IN_ONLY')) {
            const parts = line.trim().split('.');
            if (parts.length >= 2) inOnlyTileIobs.add(parts[0] + '.' + parts[1]);
        }
    }
    const fixedFasm = lines.filter(line => {
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
    fs.writeFileSync('out.fasm', fixedFasm);

    const fasmMapStr = readBrotliSync(FASM_MAP_BR).toString('utf8');
    const fasmMap = JSON.parse(fasmMapStr);
    const framesStr = generateFramesSync(fixedFasm, fasmMap);
    fs.writeFileSync('out.frames', framesStr);

    runFramesToBit(framesStr);
}

function generateFramesSync(fasmStr, mapData) {
    const frameData = new Map();
    const { types: typesMap, grid: gridMap } = mapData;
    const allAddresses = new Set();
    for (const [tileName, [bases, tileType]] of Object.entries(gridMap)) {
        for (const [blockName, [baseAddr, offset, frames]] of Object.entries(bases)) {
            for (let f = 0; f < frames; f++) { allAddresses.add(baseAddr + f); }
        }
    }
    const sortedAddresses = Array.from(allAddresses).sort((a, b) => a - b);
    const lines = fasmStr.split('\n');
    let parsedCount = 0, unmappedCount = 0;

    for (let line of lines) {
        line = line.trim();
        if (!line || line.startsWith('#')) continue;
        const eqIdx = line.indexOf('=');
        const left = (eqIdx === -1) ? line : line.substring(0, eqIdx).trim();
        const right = (eqIdx === -1) ? null : line.substring(eqIdx + 1).trim();
        const parts = left.split('.');
        const tileName = parts[0];
        const gridEntry = gridMap[tileName];
        
        if (!gridEntry) { unmappedCount++; continue; }
        const [bases, tileType] = gridEntry;
        const typeFeatures = typesMap[tileType];
        if (!typeFeatures) continue;

        const rawFeatures = [];
        if (right && right.includes("'b")) {
            const featureFull = parts.slice(1).join('.');
            const bracketIdx = featureFull.indexOf('[');
            const featureBase = featureFull.substring(0, bracketIdx);
            const rangeMatch = featureFull.match(/\[(\d+):(\d+)\]/);
            if (rangeMatch) {
                const high = parseInt(rangeMatch[1], 10);
                const valStr = right.substring(right.indexOf("'b") + 2);
                for (let i = 0; i < valStr.length; i++) {
                    if (valStr[i] === '1') rawFeatures.push(`${featureBase}[${high - i}]`);
                }
            }
        } else {
            rawFeatures.push(parts.slice(1).join('.'));
        }

        for (const feat of rawFeatures) {
            parsedCount++;
            let coords = null;
            const subParts = feat.split('.');
            for (let start = 0; start < subParts.length; start++) {
                const candidate = subParts.slice(start).join('.');
                coords = typeFeatures[candidate];
                if (!coords && candidate.endsWith(']')) {
                    const m = candidate.match(/^(.*)\[(\d+)\]$/);
                    if (m) {
                        const baseName = m[1], index = m[2];
                        coords = typeFeatures[`${baseName}[${index.padStart(2, '0')}]`] || 
                                 typeFeatures[`${baseName}[${index.padStart(3, '0')}]`];
                    }
                }
                if (!coords) {
                    const stripped = candidate.replace(tileType + '.', '')
                                              .replace('CLBLL.', '').replace('CLBLM.', '')
                                              .replace('CLBLL_', '').replace('CLBLM_', '');
                    coords = typeFeatures[stripped];
                }
                if (coords) break;
            }
            if (!coords) { unmappedCount++; continue; }
            
            const coordList = Array.isArray(coords[0]) ? coords : [coords];
            for (const [blockName, wordCol, wordIdx, bitIdx] of coordList) {
                const blockInfo = bases[blockName];
                if (blockInfo === undefined) continue;
                const [baseAddr, tileOffset, frames] = blockInfo;
                const frameAddr = baseAddr + wordCol;
                const absoluteWordIdx = tileOffset + wordIdx;
                let words = frameData.get(frameAddr);
                if (!words) { words = new Uint32Array(101); frameData.set(frameAddr, words); }
                words[absoluteWordIdx] |= (1 << bitIdx);
            }
        }
    }
    let outputStr = "";
    for (const addr of sortedAddresses) {
        const words = frameData.get(addr) || new Uint32Array(101);
        const wordStrs = [];
        for (let i = 0; i < 101; i++) {
            wordStrs.push('0x' + (words[i] >>> 0).toString(16).padStart(8, '0').toUpperCase());
        }
        outputStr += '0x' + addr.toString(16).padStart(8, '0') + ' ' + wordStrs.join(',') + '\n';
    }
    console.log(`  ↳ FASM2Frames Stats: Parsed ${parsedCount}, Unmapped ${unmappedCount}`);
    return outputStr;
}

// ---------------------------------------------------------
// [STEP 4] Frames to Bitstream
// ---------------------------------------------------------
let frames2bitDone = false; 

function runFramesToBit(framesStr) {
    if (frames2bitDone) return;
    frames2bitDone = true;

    console.log('▶ [4/4] Generating Bitstream via xc7frames2bit...');
    const partYaml = fs.readFileSync(PART_YAML);

    const f2bWasmData = new Uint8Array(fs.readFileSync(FRAMES2BIT_WASM));

    global.Module = {
        noInitialRun: false,
        wasmBinary: f2bWasmData,
        instantiateWasm: function(imports, successCallback) {
            WebAssembly.instantiate(f2bWasmData, imports).then(result => {
                successCallback(result.instance, result.module);
            }).catch(e => {
                console.error('❌ Frames2Bit WASM Instantiation failed:', e);
                process.exit(1);
            });
            return {};
        },
        arguments: ['--part_file', '/part.yaml', '--frm_file', '/design.frames', '--output_file', '/design.bit'],
        preRun: function() {
            global.f2bFS.writeFile('/part.yaml', new Uint8Array(partYaml));
            global.f2bFS.writeFile('/design.frames', new TextEncoder().encode(framesStr));
        },
        print: (text) => console.log(`[Frames2Bit] ${text}`),
        printErr: (text) => console.error(`[Frames2Bit ERR] ${text}`),
        postRun: function() {
            try {
                const bitData = global.f2bFS.readFile('/design.bit');
                fs.writeFileSync(outputBit, bitData);
                console.log(`✅ Done: Successfully generated ${outputBit}`);
                process.exit(0);
            } catch (err) {
                console.error("❌ Failed to read or save design.bit:", err);
                process.exit(1);
            }
        },
        onExit: function(code) {
            if (code !== 0) {
                console.error(`❌ xc7frames2bit Execution crashed with code ${code}.`);
                process.exit(1);
            }
        }
    };

    let f2bCode = fs.readFileSync(FRAMES2BIT_JS, 'utf8');
    // Inject global.f2bFS = FS directly into the script before createWasm() fires
    f2bCode = f2bCode.replace('createWasm();', 'global.f2bFS = FS; createWasm();');
    
    // Execute inside IIFE to isolate classes, but pass in the current Module
    vm.runInThisContext('(function(Module){\n' + f2bCode + '\n})(global.Module)');
}
