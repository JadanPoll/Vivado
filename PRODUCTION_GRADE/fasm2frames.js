self.onmessage = async function(e) {
    const { fasmStr, mapData } = e.data;
    try {
        const frameData = new Map();
        const { types: typesMap, grid: gridMap } = mapData;
        const lines = fasmStr.split('\n');

        let parsedCount = 0, unmappedCount = 0, unmappedSample = "";

        for (let line of lines) {
            line = line.trim();
            if (!line || line.startsWith('#')) continue;
            
            const eqIdx = line.indexOf('=');
            const left = (eqIdx === -1) ? line : line.substring(0, eqIdx).trim();
            const right = (eqIdx === -1) ? null : line.substring(eqIdx + 1).trim();
            
            const parts = left.split('.');
            const tileName = parts[0];
            const gridEntry = gridMap[tileName];
            
            if (!gridEntry) { 
                unmappedCount++; 
                unmappedSample = tileName; 
                continue; 
            }

            const [bases, tileType] = gridEntry;
            const typeFeatures = typesMap[tileType];
            if (!typeFeatures) continue;

            const rawFeatures = [];
            if (right && right.includes("'b")) {
                const featureFull = parts.slice(1).join('.');
                const bracketIdx = featureFull.indexOf('[');
                const featureBase = featureFull.substring(0, bracketIdx);
                const high = parseInt(featureFull.match(/\[(\d+):(\d+)\]/)[1], 10);
                const valStr = right.substring(right.indexOf("'b") + 2);
                for (let i = 0; i < valStr.length; i++) {
                    if (valStr[i] === '1') rawFeatures.push(`${featureBase}[${high - i}]`);
                }
            } else {
                rawFeatures.push(parts.slice(1).join('.'));
            }

            for (const feat of rawFeatures) {
                parsedCount++;
                let coords = null;
                
                // --- Recursive Peel-and-Check ---
                const subParts = feat.split('.');
                for (let start = 0; start < subParts.length; start++) {
                    const candidate = subParts.slice(start).join('.');
                    
                    // 1. Direct Lookup
                    coords = typeFeatures[candidate] || 
                             typeFeatures[candidate.replace(tileType + '.', '')] ||
                             typeFeatures[candidate.replace('CLBLL.', '').replace('CLBLM.', '')] ||
                             typeFeatures[candidate.replace('CLBLL_', '').replace('CLBLM_', '')];
                    
                    // 2. Dynamic Padding Fallback
                    if (!coords && candidate.endsWith(']')) {
                        const m = candidate.match(/^(.*)\[(\d+)\]$/);
                        if (m) {
                            const b = m[1], n = m[2];
                            coords = typeFeatures[`${b}[${n.padStart(2, '0')}]`] || 
                                     typeFeatures[`${b}[${n.padStart(3, '0')}]`];
                        }
                    }
                    if (coords) break;
                }

                if (!coords) { unmappedCount++; unmappedSample = feat; continue; }
                
                const coordList = Array.isArray(coords[0]) ? coords : [coords];
                for (const [blockName, wordCol, wordIdx, bitIdx] of coordList) {
                    const baseAddr = bases[blockName];
                    if (baseAddr === undefined) continue;
                    const frameAddr = baseAddr + wordCol;
                    let words = frameData.get(frameAddr);
                    if (!words) { words = new Uint32Array(101); frameData.set(frameAddr, words); }
                    words[wordIdx] |= (1 << bitIdx);
                }
            }
        }

        let outputStr = "";
        const sortedAddresses = Array.from(frameData.keys()).sort((a, b) => a - b);
        for (const addr of sortedAddresses) {
            let line = "0x" + addr.toString(16).padStart(8, '0');
            const words = frameData.get(addr);
            for (let i = 0; i < 101; i++) {
                line += " " + (words[i] >>> 0).toString(16).padStart(8, '0');
            }
            outputStr += line + "\n";
        }

        self.postMessage({ type: 'success', frames: outputStr, 
            telemetry: `Parsed ${parsedCount}. Unmapped: ${unmappedCount} (e.g. ${unmappedSample})` });
    } catch (err) { self.postMessage({ type: 'error', message: err.toString() }); }
};
