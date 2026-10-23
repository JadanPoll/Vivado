// Execute the repository's unmodified pnr-worker.js and Emscripten nextpnr in a Node worker.
// No browser, no DOM, no production changes.
const { parentPort, workerData } = require('node:worker_threads');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
globalThis.self = globalThis;
globalThis.location = {href:'file://' + path.resolve(workerData.engineDir,'pnr-worker.js')};
globalThis.postMessage = value => parentPort.postMessage(value);
globalThis.importScripts = (...urls) => {
  for(const url of urls) {
    const filename = path.join(workerData.engineDir,path.basename(url));
    vm.runInThisContext(fs.readFileSync(filename,'utf8'), {filename});
  }
};
try {
 vm.runInThisContext(fs.readFileSync(path.join(workerData.engineDir,'pnr-worker.js'),'utf8'),{filename:'pnr-worker.js'});
 const wasm=fs.readFileSync(workerData.wasm);
 const db=fs.readFileSync(workerData.chipdb);
 const netlist=fs.readFileSync(workerData.netlist);
 const xdc=fs.readFileSync(workerData.xdc,'utf8');
 self.onmessage({data:{type:'run',baseUrl:'',wasmBuffer:wasm.buffer.slice(wasm.byteOffset,wasm.byteOffset+wasm.byteLength),chipdbBuffer:db.buffer.slice(db.byteOffset,db.byteOffset+db.byteLength),jsonBuffer:netlist.buffer.slice(netlist.byteOffset,netlist.byteOffset+netlist.byteLength),xdc}});
} catch(err) {parentPort.postMessage({type:'error',message:String(err.stack||err)});}
