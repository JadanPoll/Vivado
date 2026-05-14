// XC7S50CSGA324-1 calculates correct frame address space - 4970 addresses
// Source: prjxray fasm2frames native output studies
self.onmessage = async function(e) {
    const { fasmStr, mapData } = e.data;
    try {
        const frameData = new Map();
        const { types: typesMap, grid: gridMap } = mapData;
        

        // --- RIGOROUS DEBUG TRACKERS ---
        const debugLog = (msg) => self.postMessage({ type: 'log', text: `[F2F-DEBUG] ${msg}` });
        const missingTiles = new Map();
        const missingFeatures = new Map();
        let totalFasmLines = 0;
        let multiBitExpansions = 0;
        

                debugLog("FASM INPUT:\n" + fasmStr);
        debugLog("Initializing FASM-to-Frames pipeline...");

        // Derive complete address space from map grid — portable to any XC7 device
        const allAddresses = new Set();
        for (const [tileName, [bases, tileType]] of Object.entries(gridMap)) {
            for (const [blockName, [baseAddr, offset, frames]] of Object.entries(bases)) {
                for (let f = 0; f < frames; f++) {
                    allAddresses.add(baseAddr + f);
                }
            }
        }
        const sortedAddresses = Array.from(allAddresses).sort((a, b) => a - b);
        debugLog(`Allocated address space: ${sortedAddresses.length} dense frames.`);

        const lines = fasmStr.split('\n');
        let parsedCount = 0, unmappedCount = 0;

        for (let line of lines) {
            line = line.trim();
            if (!line || line.startsWith('#')) continue;
            totalFasmLines++;

            const eqIdx = line.indexOf('=');
            const left = (eqIdx === -1) ? line : line.substring(0, eqIdx).trim();
            const right = (eqIdx === -1) ? null : line.substring(eqIdx + 1).trim();

            const parts = left.split('.');
            const tileName = parts[0];
            const gridEntry = gridMap[tileName];

            if (!gridEntry) { 
                unmappedCount++; 
                missingTiles.set(tileName, (missingTiles.get(tileName) || 0) + 1);
                continue; 
            }

            const [bases, tileType] = gridEntry;
            const typeFeatures = typesMap[tileType];
            
            if (!typeFeatures) {
                // If the tile exists but the type isn't in our feature map
                unmappedCount++;
                const missingKey = `[MISSING_TILE_TYPE] ${tileType} (from ${tileName})`;
                missingFeatures.set(missingKey, (missingFeatures.get(missingKey) || 0) + 1);
                continue;
            }

            const rawFeatures = [];
            // Handle [63:0] bitstream expansions
            if (right && right.includes("'b")) {
                multiBitExpansions++;
                const featureFull = parts.slice(1).join('.');
                const bracketIdx = featureFull.indexOf('[');
                const featureBase = featureFull.substring(0, bracketIdx);
                
                // Regex to extract indices from [63:0]
                const rangeMatch = featureFull.match(/\[(\d+):(\d+)\]/);
                if (rangeMatch) {
                    const high = parseInt(rangeMatch[1], 10);
                    const valStr = right.substring(right.indexOf("'b") + 2);
                    for (let i = 0; i < valStr.length; i++) {
                        if (valStr[i] === '1') {
                            rawFeatures.push(`${featureBase}[${high - i}]`);
                        }
                    }
                }
            } else {
                rawFeatures.push(parts.slice(1).join('.'));
            }

            for (const feat of rawFeatures) {
                let coords = null;
                const subParts = feat.split('.');

                // --- Recursive Peel-and-Check with Robust Padding ---
                for (let start = 0; start < subParts.length; start++) {
                    const candidate = subParts.slice(start).join('.');
                    
                    // 1. Direct Lookup (e.g. SLICEL_X0.ALUT.INIT[63])
                    coords = typeFeatures[candidate];

                    // 2. Dynamic Padding Fallback (The Critical Path for [0] -> [00])
                    if (!coords && candidate.endsWith(']')) {
                        const m = candidate.match(/^(.*)\[(\d+)\]$/);
                        if (m) {
                            const baseName = m[1];
                            const index = m[2];
                            // Try 2-digit padding (PrjXray standard) and 3-digit padding
                            coords = typeFeatures[`${baseName}[${index.padStart(2, '0')}]`] || 
                                     typeFeatures[`${baseName}[${index.padStart(3, '0')}]`];
                        }
                    }

                    // 3. Prefix stripping fallbacks
                    if (!coords) {
                        const stripped = candidate.replace(tileType + '.', '')
                                                  .replace('CLBLL.', '').replace('CLBLM.', '')
                                                  .replace('CLBLL_', '').replace('CLBLM_', '');
                        coords = typeFeatures[stripped];
                    }

                    if (coords) break;
                }

                if (!coords) { 
                    unmappedCount++; 
                    // Track exactly what type and feature failed so we can check the Python script
                    const missingKey = `${tileType} :: ${feat}`;
                    missingFeatures.set(missingKey, (missingFeatures.get(missingKey) || 0) + 1);
                    continue; 
                }

                parsedCount++;
                // Apply the bit to the frame map
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

        // --- RIGOROUS DEBUG REPORT GENERATION ---
        debugLog(`Parse complete. Generating telemetry...`);
        debugLog(`Valid FASM lines parsed: ${totalFasmLines}`);
        debugLog(`Multi-bit [63:0] expansions fired: ${multiBitExpansions}`);

        if (missingTiles.size > 0) {
            debugLog(`\n--- TOP 10 MISSING TILES ---`);
            const sortedTiles = [...missingTiles.entries()].sort((a,b) => b[1] - a[1]).slice(0, 10);
            sortedTiles.forEach(([t, c]) => debugLog(`  ${t} (Occurrences: ${c})`));
        }

        if (missingFeatures.size > 0) {
            debugLog(`\n--- TOP 20 MISSING FEATURES ---`);
            debugLog(`(Format: TILE_TYPE :: FEATURE_PATH)`);
            const sortedFeats = [...missingFeatures.entries()].sort((a,b) => b[1] - a[1]).slice(0, 20);
            sortedFeats.forEach(([f, c]) => debugLog(`  ${f} (Occurrences: ${c})`));
        }

        // Generate output in PrjXray .frames format
        let outputStr = "";
        for (const addr of sortedAddresses) {
            const words = frameData.get(addr) || new Uint32Array(101);
            const wordStrs = [];
            for (let i = 0; i < 101; i++) {
                wordStrs.push('0x' + (words[i] >>> 0).toString(16).padStart(8, '0').toUpperCase());
            }
            outputStr += '0x' + addr.toString(16).padStart(8, '0') + ' ' + wordStrs.join(',') + '\n';
        }
        

        let nonZeroFrames = 0;
        for (const addr of sortedAddresses) {
            const words = frameData.get(addr);
            if (words) nonZeroFrames++;
        }
        debugLog("Non-zero frames: " + nonZeroFrames);
        self.postMessage({ 
            type: 'success', 
            frames: outputStr,
            telemetry: `Parsed ${parsedCount}, Unmapped ${unmappedCount}, Dense frames: ${sortedAddresses.length}`
        });

    } catch (err) { 
        // Send back full stack traces if the worker hits a logic error
        self.postMessage({ type: 'error', message: `${err.toString()}\n${err.stack}` }); 
    }
};