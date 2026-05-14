self.onmessage = async function(e) {
    const { fasmStr, mapData } = e.data;
    try {
        const debugLog = (msg) => self.postMessage({ type: 'log', text: `[F2F-DEBUG] ${msg}` });
        debugLog("Initializing Hierarchical F2F Pipeline...");

        debugLog("FASM INPUT:\n" + fasmStr);
        const frameData = new Map();
        const grid = mapData.grid;
        const features = mapData.features;
        
        const missingTiles = new Map();
        const missingFeatures = new Map();

        // Derive dense address space
        const allAddresses = new Set();
        for (const tileName in grid) {
            const bases = grid[tileName].bases;
            for (const block in bases) {
                const [baseAddr, frames] = bases[block];
                for (let f = 0; f < frames; f++) allAddresses.add(baseAddr + f);
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

            const firstDot = left.indexOf('.');
            if (firstDot === -1) { unmappedCount++; continue; }
            
            const tileName = left.substring(0, firstDot);
            let featureFull = left.substring(firstDot + 1);

            const tileInfo = grid[tileName];
            if (!tileInfo) { 
                unmappedCount++; 
                missingTiles.set(tileName, (missingTiles.get(tileName) || 0) + 1);
                continue; 
            }

            const typeFeatures = features[tileInfo.type];
            if (!typeFeatures) continue;

            const rawFeatures = [];
            if (right && right.includes("'b")) {
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
                rawFeatures.push(featureFull);
            }

            for (const candidate of rawFeatures) {
                let coords = typeFeatures[candidate];

                // 0-padding fallback for buses
                if (!coords && candidate.endsWith(']')) {
                    const m = candidate.match(/^(.*)\[(\d+)\]$/);
                    if (m) {
                        coords = typeFeatures[`${m[1]}[${m[2].padStart(2, '0')}]`] || 
                                 typeFeatures[`${m[1]}[${m[2].padStart(3, '0')}]`];
                    }
                }

                if (!coords) { 
                    unmappedCount++; 
                    const missingKey = `${tileInfo.type} :: ${candidate}`;
                    missingFeatures.set(missingKey, (missingFeatures.get(missingKey) || 0) + 1);
                    continue; 
                }

                parsedCount++;
                const coordList = Array.isArray(coords[0]) ? coords : [coords];

                for (const [blockType, wordCol, wordIdx, bitIdx] of coordList) {
                    const blockInfo = tileInfo.bases[blockType];
                    if (!blockInfo) continue;
                    
                    // tile offset unused
                    const [baseAddr, frames, tileOffset, wordsPerFrame] = blockInfo;
                    const frameAddr = baseAddr + wordCol;
                    const absoluteWordIdx = tileOffset +  wordIdx;
                    
                    let words = frameData.get(frameAddr);
                    if (!words) { words = new Uint32Array(101); frameData.set(frameAddr, words); }
                    words[absoluteWordIdx] |= (1 << bitIdx);
                }
            }
        }

         // Output Telemetry
        if (missingFeatures.size > 0) {
            debugLog(`\n--- TOP 20 MISSING FEATURES ---`);
            const sortedFeats = [...missingFeatures.entries()].sort((a,b) => b[1] - a[1]).slice(0, 20);
            sortedFeats.forEach(([f, c]) => debugLog(`  ${f} (Occurrences: ${c})`));
        }

        // THE FIX: Space separation AND '0x' prefixes on all 101 words
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

        self.postMessage({ type: 'success', frames: outputStr, telemetry: `Parsed ${parsedCount}, Unmapped ${unmappedCount}, Dense frames: ${sortedAddresses.length}` });

    } catch (err) { self.postMessage({ type: 'error', message: err.toString() }); }
};