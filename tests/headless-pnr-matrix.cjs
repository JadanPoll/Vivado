// Headless differential PNR: the exact deployed Emscripten engine without Chromium.
// Inputs are synthesized using the same script as FINAL/index.html by the workflow.
const { Worker } = require('node:worker_threads');
const fs=require('node:fs'),path=require('node:path');
const {performance}=require('node:perf_hooks');
const cp=require('node:child_process');
const root=path.resolve(__dirname,'..');
const engineDir=path.join(root,'PRODUCTION_GRADE');
const outDir=path.join(root,'pnr-repro-output');
fs.mkdirSync(outDir,{recursive:true});
const cases=[
 'PRODUCTION_GRADE/TESTS/example2',
 'PRODUCTION_GRADE/DEFAULTS/04_blink',
 'PRODUCTION_GRADE/DEFAULTS/08_led_chaser',
 'PRODUCTION_GRADE/DEFAULTS/05_binary_counter',
 'PRODUCTION_GRADE/DEFAULTS/09_pwm_brightness',
];
function synth(dir,slug){
 const scratch=path.join(outDir,slug);fs.mkdirSync(scratch,{recursive:true});
 const src=fs.readFileSync(path.join(root,dir,'top.v'),'utf8');
 fs.writeFileSync(path.join(scratch,'source_0.v'),src);
 const script='read_verilog -sv source_0.v; hierarchy -top top; proc; opt; memory; opt; synth_xilinx -flatten -abc9 -arch xc7 -top top; write_json synth.json';
 const r=cp.spawnSync('yowasp-yosys',['-p',script],{cwd:scratch,encoding:'utf8',timeout:180000,maxBuffer:32*1024*1024});
 fs.writeFileSync(path.join(scratch,'yosys.log'),(r.stdout||'')+'\nSTDERR\n'+(r.stderr||''));
 if(r.error||r.status!==0||!fs.existsSync(path.join(scratch,'synth.json')))throw Error('Yosys failed '+String(r.error||r.status));
 return scratch;
}
function runPnr(dir,slug,variant='original',xdcText=null){
 return new Promise(resolve=>{
   let settled=false;
   const begin=performance.now(),messages=[];
   const scratch=path.join(outDir,slug);
   const xdcPath=path.join(scratch,variant+'.xdc');
   fs.writeFileSync(xdcPath,xdcText===null?fs.readFileSync(path.join(root,dir,'top.xdc'),'utf8'):xdcText);
   const worker=new Worker(path.join(__dirname,'headless-pnr-worker.cjs'),{workerData:{
     engineDir,wasm:path.join(engineDir,'nextpnr-xilinx.wasm'),
     chipdb:path.join(outDir,'chipdb.bin'),netlist:path.join(scratch,'synth.json'),
     xdc:xdcPath
   }});
   const done=(result,detail)=>{
     if(settled)return;settled=true;
     fs.writeFileSync(path.join(scratch,variant+'.pnr.log'),messages.join('\n')+'\n'+(detail||''));
     if(result==='PASS'&&detail)fs.writeFileSync(path.join(scratch,variant+'.fasm'),detail);
     worker.terminate();resolve({design:dir,variant,result,elapsed_ms:Math.round(performance.now()-begin),tail:messages.slice(-6),detail: result==='FAIL'?String(detail).slice(0,600):undefined});
   };
   worker.on('message',m=>{if(m.type==='log')messages.push(m.text);else if(m.type==='error')done('FAIL',m.message);else if(m.type==='fasm_fixed')done('PASS',m.data);});
   worker.on('error',e=>done('HARNESS_ERROR',String(e.stack||e)));
   worker.on('exit',code=>{if(!settled)done('HARNESS_ERROR','Node worker exited '+code)});
   setTimeout(()=>done('TIMEOUT','Nextpnr exceeded 90000ms'),90000).unref();
 });
}
(async()=>{
 const summary=[];
 for(const dir of cases){
   const slug=dir.split('/').slice(-1)[0];
   const begin=performance.now();
   try {synth(dir,slug);let r=await runPnr(dir,slug);r.synthesis_ms=Math.round(performance.now()-begin-r.elapsed_ms);summary.push(r);}
   catch(e){summary.push({design:dir,result:'SYNTH_FAIL',error:String(e.stack||e)});}
   console.log(JSON.stringify(summary.at(-1)));
 }
 // Diagnose parseXdc failures without resynthesizing or changing netlist.
 const blink='PRODUCTION_GRADE/DEFAULTS/04_blink';
 const originalXdc=fs.readFileSync(path.join(root,blink,'top.xdc'),'utf8');
 const lines=originalXdc.split(/\\r?\\n/);
 const variants={
   no_create_clock:lines.filter(l=>!l.trim().startsWith('create_clock')).join('\\n'),
   clock_only:lines.filter(l=>l.includes('get_ports {clk}')||l.trim().startsWith('create_clock')).join('\\n'),
   led_only:lines.filter(l=>l.includes('get_ports {LED}')).join('\\n'),
   no_clock_pin:lines.filter(l=>!l.includes('PACKAGE_PIN N15')).join('\\n'),
   empty_xdc:'',
 };
 for(const [variant,xdc] of Object.entries(variants)){
   const result=await runPnr(blink,'04_blink',variant,xdc);
   summary.push(result);console.log(JSON.stringify(result));
 }
 fs.writeFileSync(path.join(outDir,'matrix.json'),JSON.stringify(summary,null,2));
 const counts=Object.fromEntries(['PASS','FAIL','SYNTH_FAIL','HARNESS_ERROR','TIMEOUT'].map(x=>[x,summary.filter(v=>v.result===x).length]));
 console.log('MATRIX',JSON.stringify(counts));
 if(summary.some(x=>x.result==='HARNESS_ERROR'||x.result==='SYNTH_FAIL'||x.result==='TIMEOUT'))process.exitCode=2;
})();
