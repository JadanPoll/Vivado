import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repository = path.dirname(here);
const source = path.resolve(process.argv[2] || path.join(repository, 'PRODUCTION_GRADE'));
const output = path.resolve(process.argv[3] || path.join(repository, 'Frontier_Grade'));
const staging = `${output}.staging-${process.pid}`;

if (!fs.statSync(source).isDirectory()) throw new Error(`Not a directory: ${source}`);
if (fs.existsSync(output)) throw new Error(`Refusing to replace existing output: ${output}`);

const runtimeFiles = [
  'index.html',
  'pnr-worker.js',
  'synth-worker.js',
  'nextpnr-xilinx.js',
  'frames-worker.js',
  'xc7frames2bit.js',
  'fasm2frames2.js',
  'ftdi-jtag.js',
  'ftdi-uart.js',
  'urbana-ble.js',
  'part.yaml'
];
const fixtureDirectories = ['DEFAULTS', 'TESTS'];
const compressedAssets = [
  { name: 'nextpnr-xilinx.opt.wasm.br', raw: 'nextpnr-xilinx.opt.wasm', kind: 'wasm' },
  { name: 'xc7frames2bit.opt.wasm.br', raw: 'xc7frames2bit.opt.wasm', kind: 'wasm' },
  { name: 'xc7s50.bin.br', raw: 'xc7s50.bin', kind: 'chipdb' },
  { name: 'xc7s50_fasm_map_v7.json.br', raw: 'xc7s50_fasm_map_v7.json', kind: 'fasm-map' }
];

const identity = data => crypto.createHash('sha256').update(data).digest('hex').slice(0, 16);
const digest = data => crypto.createHash('sha256').update(data).digest('hex');
const copy = relative => {
  const from = path.join(source, relative);
  if (!fs.existsSync(from)) throw new Error(`Missing runtime input: ${from}`);
  fs.cpSync(from, path.join(staging, relative), { recursive: true });
};

try {
  fs.mkdirSync(staging, { recursive: false });
  runtimeFiles.forEach(copy);
  fixtureDirectories.forEach(copy);

  const sourceLock = JSON.parse(fs.readFileSync(path.join(here, 'source-lock.json'), 'utf8'));
  const assets = {};
  for (const asset of compressedAssets) {
    const rawPath = path.join(source, asset.raw);
    const packedPath = path.join(source, asset.name);
    const raw = fs.existsSync(rawPath)
      ? fs.readFileSync(rawPath)
      : zlib.brotliDecompressSync(fs.readFileSync(packedPath));
    if (asset.kind === 'wasm' && !WebAssembly.validate(raw)) {
      throw new Error(`${asset.name} does not contain valid WebAssembly`);
    }
    if (asset.kind === 'chipdb' && raw.length < 1024) {
      throw new Error(`${asset.name} is implausibly small`);
    }
    if (asset.kind === 'fasm-map') {
      const map = JSON.parse(raw.toString('utf8'));
      if (!map.grid || !map.features) throw new Error(`${asset.name} is not the v7 features/grid schema`);
      const expected = sourceLock.browserAssets?.fasmMapV7?.rawSha256;
      if (expected && digest(raw) !== expected) throw new Error(`${asset.name} does not match the pinned generator inputs`);
    }
    const packed = zlib.brotliCompressSync(raw, { params: {
      [zlib.constants.BROTLI_PARAM_MODE]: zlib.constants.BROTLI_MODE_GENERIC,
      [zlib.constants.BROTLI_PARAM_QUALITY]: 11,
      [zlib.constants.BROTLI_PARAM_SIZE_HINT]: raw.length
    }});
    if (!zlib.brotliDecompressSync(packed).equals(raw)) {
      throw new Error(`${asset.name} failed Brotli round-trip`);
    }
    fs.writeFileSync(path.join(staging, asset.name), packed);
    assets[asset.name] = {
      rawBytes: raw.length,
      brotliBytes: packed.length,
      contentId: identity(raw)
    };
  }

  fs.writeFileSync(path.join(staging, 'frontier-manifest.json'), `${JSON.stringify({
    schema: 1,
    target: sourceLock.target,
    sourceLock,
    assets
  }, null, 2)}\n`);
  fs.renameSync(staging, output);
  console.log(`FRONTIER_PACKAGE=${output}`);
  console.log(`FRONTIER_ASSET_BYTES=${Object.values(assets).reduce((n, x) => n + x.brotliBytes, 0)}`);
} catch (error) {
  fs.rmSync(staging, { recursive: true, force: true });
  throw error;
}
