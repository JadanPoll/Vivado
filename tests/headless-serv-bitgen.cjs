#!/usr/bin/env node
// Execute the SAME browser FASM2Frames and Frames2Bit scripts under Node.
// This is an integration exercise; programming silicon requires board testing.
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const zlib=require('node:zlib');
const root=path.resolve(__dirname,'..');
const base=path.join(root,'PRODUCTION_GRADE');
const dir=path.join(root,'pnr-repro-output/DEFAULTS_serv_blinky');
const fasm=fs.readFileSync(path.join(dir,'original.fasm'),'utf8');
const map=JSON.parse(zlib.brotliDecompressSync(fs.readFileSync(path.join(base,'xc7s50_fasm_map_v7.json.br'))).toString('utf8'));
let output=null,error=null;
const ctx={console,TextEncoder,TextDecoder,Uint8Array,Uint32Array,WebAssembly,URL,
           setTimeout,clearTimeout,fetch:globalThis.fetch};
ctx.self=ctx;
ctx.self.location={href:'file://'+path.join(base,'xc7frames2bit.js')};
ctx.self.postMessage=(data)=>{if(data.type==='success')output=data;else if(data.type==='error')error=data.message;
    else if(data.type==='log' && (/MISSING|Unmapped|Non-zero|SUMMARY|error/i.test(data.text)))console.log(data.text);};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(base,'fasm2frames2.js'),'utf8'),ctx,{filename:'fasm2frames2.js'});
ctx.self.onmessage({data:{fasmStr:fasm,mapData:map}});
if(error||!output?.frames)throw Error('FASM2Frames failed: '+(error||'no frames output'));
console.log('FASM2FRAMES '+output.telemetry);
fs.writeFileSync(path.join(dir,'design.frames'),output.frames);
const unmapped=Number(/Unmapped (\d+)/.exec(output.telemetry)?.[1]||0);
if(unmapped!==0){
 console.log('UNMAPPED_FEATURES '+unmapped+' - bitstream assembly withheld pending map coverage review');
 process.exitCode=2;
 returnEarly();
} else {
 console.log('FASM feature mapping reported zero missing entries');
 runFrames();
}
function returnEarly(){}
function runFrames(){
 const wasm=zlib.brotliDecompressSync(fs.readFileSync(path.join(base,'xc7frames2bit.opt.wasm.br')));
 const yaml=fs.readFileSync(path.join(base,'part.yaml'),'utf8');
 const result=new Promise((resolve,reject)=>{
   let done=false;
   ctx.self.postMessage=(data)=>{
      if(data.type==='success'){done=true;resolve(data);}
      if(data.type==='error'&&!done){done=true;reject(Error(data.message));}
      if(data.type==='log')console.log('[F2B]',data.text);
   };
   ctx.importScripts=(url)=>vm.runInContext(fs.readFileSync(path.join(base,'xc7frames2bit.js'),'utf8'),ctx,{filename:'xc7frames2bit.js'});
   vm.runInContext(fs.readFileSync(path.join(base,'frames-worker.js'),'utf8'),ctx,{filename:'frames-worker.js'});
   ctx.self.onmessage({data:{
     type:'run',baseUrl:'file://'+base+'/',partYaml:yaml,framesStr:output.frames,
     wasmBuffer:wasm.buffer.slice(wasm.byteOffset,wasm.byteOffset+wasm.byteLength)
   }});
 });
 result.then(msg=>{
   const arr=Buffer.from(msg.bitstream);
   if(arr.length<100000)throw Error('Bitstream implausibly short: '+arr.length);
   const bitPath=path.join(dir,'serv_blinky.bit');
   fs.writeFileSync(bitPath,arr);
   console.log('BITSTREAM '+JSON.stringify({bytes:arr.length,path:bitPath}));
 }).catch(err=>{console.error('BITSTREAM_ERROR '+String(err.stack||err));process.exitCode=1;});
}
