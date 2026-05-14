// =============================================================================
// asset-cache.js  —  In-memory cache for all heavy pipeline assets.
//
// Drop this into the main page as a module-level singleton.
// All pipeline assets are fetched + decompressed ONCE per page load,
// then handed to workers as cloned (not transferred) ArrayBuffers so the
// cache stays valid across multiple Build clicks.
//
// Usage (in the main HTML script):
//
//   import { assetCache } from './asset-cache.js';
//
//   // warm on page-load (optional but recommended):
//   assetCache.warmup(brotli, ENGINE_ASSETS, log);
//
//   // in the build pipeline, replace every fetch+decompress with:
//   const chipdbBuffer = await assetCache.get('chipdb', brotli, ENGINE_ASSETS, log);
//   const pnrWasm      = await assetCache.get('wasm',   brotli, ENGINE_ASSETS, log);
//   const framesWasm   = await assetCache.get('framesWasm', brotli, ENGINE_ASSETS, log);
//   const map          = await assetCache.get('fasmMap', brotli, ENGINE_ASSETS, log);
//
// Each .get() returns the fully-decoded value (ArrayBuffer or parsed object).
// Subsequent calls return the cached value instantly — no network, no decompress.
// =============================================================================

const _cache   = {};   // key → Promise<value>  (inflight dedup + settled cache)

// -----------------------------------------------------------------------------
// Internal loaders — one per asset type
// -----------------------------------------------------------------------------

async function _loadBrotliBuffer(url, brotli, label, log) {
    log(`[CACHE] Fetching ${label}...`, 'info');
    const t0  = performance.now();
    const raw = await fetch(url).then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${url}`);
        return r.arrayBuffer();
    });
    const dec = brotli.decompress(new Uint8Array(raw)).buffer;
    log(`[CACHE] ${label} ready in ${(performance.now()-t0).toFixed(0)}ms — ${(dec.byteLength/1024/1024).toFixed(2)} MB`, 'info');
    return dec;
}

async function _loadBrotliJson(url, brotli, label, log) {
    log(`[CACHE] Fetching ${label}...`, 'info');
    const t0  = performance.now();
    const raw = await fetch(url).then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${url}`);
        return r.arrayBuffer();
    });
    const dec  = brotli.decompress(new Uint8Array(raw));
    const obj  = JSON.parse(new TextDecoder().decode(dec));
    log(`[CACHE] ${label} ready in ${(performance.now()-t0).toFixed(0)}ms — ${(dec.byteLength/1024/1024).toFixed(2)} MB JSON`, 'info');
    return obj;
}

async function _loadText(url, label, log) {
    log(`[CACHE] Fetching ${label}...`, 'info');
    const t0  = performance.now();
    const txt = await fetch(url).then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${url}`);
        return r.text();
    });
    log(`[CACHE] ${label} ready in ${(performance.now()-t0).toFixed(0)}ms`, 'info');
    return txt;
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------

export const assetCache = {
    /**
     * Get a cached asset, loading it on first call.
     *
     * @param {string} key          - 'chipdb' | 'wasm' | 'framesWasm' | 'fasmMap' | 'yaml'
     * @param {object} brotli       - brotli-dec-wasm instance
     * @param {object} ENGINE_ASSETS - the asset manifest from the main page
     * @param {function} log        - the page's log() function
     * @returns {Promise<ArrayBuffer|object|string>}
     */
    async get(key, brotli, ENGINE_ASSETS, log) {
        if (_cache[key]) return _cache[key];   // return the same Promise (dedup inflight)

        switch (key) {
            case 'chipdb':
                _cache[key] = _loadBrotliBuffer(`./${ENGINE_ASSETS.chipdb}`, brotli, 'ChipDB', log);
                break;
            case 'wasm':
                _cache[key] = _loadBrotliBuffer(`./${ENGINE_ASSETS.wasm}`, brotli, 'NextPNR WASM', log);
                break;
            case 'framesWasm':
                _cache[key] = _loadBrotliBuffer(`./${ENGINE_ASSETS.framesWasm}`, brotli, 'Frames2Bit WASM', log);
                break;
            case 'fasmMap':
                _cache[key] = _loadBrotliJson(`./${ENGINE_ASSETS.fasmMap}`, brotli, 'FASM Map', log);
                break;
            case 'yaml':
                _cache[key] = _loadText(`./${ENGINE_ASSETS.yaml}`, 'Part YAML', log);
                break;
            default:
                throw new Error(`[CACHE] Unknown asset key: "${key}"`);
        }

        return _cache[key];
    },

    /**
     * Pre-warm all assets in parallel.  Call this on page load so the first
     * Build click doesn't pay the fetch cost.
     */
    async warmup(brotli, ENGINE_ASSETS, log) {
        log('[CACHE] Pre-warming pipeline assets in background...', 'info');
        await Promise.all([
            this.get('chipdb',     brotli, ENGINE_ASSETS, log),
            this.get('wasm',       brotli, ENGINE_ASSETS, log),
            this.get('framesWasm', brotli, ENGINE_ASSETS, log),
            this.get('fasmMap',    brotli, ENGINE_ASSETS, log),
            this.get('yaml',       brotli, ENGINE_ASSETS, log),
        ]).catch(err => log(`[CACHE] Warmup error (non-fatal): ${err}`, 'warn'));
        log('[CACHE] All assets warm.', 'info');
    },

    /** Manually invalidate a single key (e.g. if ENGINE_ASSETS changes). */
    invalidate(key) { delete _cache[key]; },

    /** Wipe everything. */
    clear() { Object.keys(_cache).forEach(k => delete _cache[k]); }
};


// =============================================================================
// PATCH for the main build pipeline
// =============================================================================
//
// In index.html, replace the Place & Route asset block:
//
// BEFORE (re-fetches + re-decompresses every build):
// ─────────────────────────────────────────────────
//   const [dbRaw, wasmRaw, brotli] = await Promise.all([
//       fetch(`./xc7s50.bin.br`).then(r => r.arrayBuffer()),
//       fetch(`./nextpnr-xilinx.opt.wasm.br`).then(r => r.arrayBuffer()),
//       brotliPromise
//   ]);
//   const dbDecomp   = brotli.decompress(new Uint8Array(dbRaw)).buffer;
//   const wasmDecomp = brotli.decompress(new Uint8Array(wasmRaw)).buffer;
//
//   ...
//
//   const mapRaw           = await fetch(`./xc7s50_fasm_map_v7.json.br`).then(r => r.arrayBuffer());
//   const decompressedMapRaw = brotli.decompress(new Uint8Array(mapRaw));
//   const map              = JSON.parse(new TextDecoder().decode(decompressedMapRaw));
//
//   ...
//
//   const framesWasmRaw   = await fetch(baseUrl + ENGINE_ASSETS.framesWasm).then(r => r.arrayBuffer());
//   const framesWasmDecomp = brotli.decompress(new Uint8Array(framesWasmRaw)).buffer;
//
//   ...
//
//   const partYaml = await fetch(baseUrl + ENGINE_ASSETS.yaml).then(r => r.text());
//
// AFTER (cached — instant on 2nd+ build):
// ─────────────────────────────────────────────────
//   const brotli = await brotliPromise;
//
//   const [dbDecomp, wasmDecomp, map, framesWasmDecomp, partYaml] = await Promise.all([
//       assetCache.get('chipdb',     brotli, ENGINE_ASSETS, log),
//       assetCache.get('wasm',       brotli, ENGINE_ASSETS, log),
//       assetCache.get('fasmMap',    brotli, ENGINE_ASSETS, log),
//       assetCache.get('framesWasm', brotli, ENGINE_ASSETS, log),
//       assetCache.get('yaml',       brotli, ENGINE_ASSETS, log),
//   ]);
//
// IMPORTANT: Workers receive ArrayBuffers via postMessage with transfer lists,
// which DETACH (zero out) the original buffer.  Since the cache holds the
// canonical copy, always CLONE before transferring:
//
//   // Instead of:
//   pnrWorker.postMessage({ wasmBuffer: wasmDecomp, ... }, [wasmDecomp]);
//
//   // Do:
//   const wasmClone = wasmDecomp.slice(0);   // .slice(0) = fast structural clone
//   pnrWorker.postMessage({ wasmBuffer: wasmClone, ... }, [wasmClone]);
//
// Same pattern for chipdbBuffer, framesWasm.  The fasmMap (JS object) and
// partYaml (string) are passed by value and need no special treatment.
// =============================================================================