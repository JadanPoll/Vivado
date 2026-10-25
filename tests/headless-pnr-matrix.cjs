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
...fs.readdirSync(path.join(root,'PRODUCTION_GRADE/DEFAULTS'),{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>'PRODUCTION_GRADE/DEFAULTS/'+x.name),
...fs.readdirSync(path.join(root,'PRODUCTION_GRADE/TESTS'),{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>'PRODUCTION_GRADE/TESTS/'+x.name),
].filter(dir => !process.env.PNR_ONLY || dir.split('/').at(-1)===process.env.PNR_ONLY);
function synth(dir,slug){
 const scratch=path.join(outDir,slug);fs.mkdirSync(scratch,{recursive:true});
 const sourceName=fs.existsSync(path.join(root,dir,'top.v'))?'top.v':'hdmi.sv';
 const src=fs.readFileSync(path.join(root,dir,sourceName),'utf8');
 fs.writeFileSync(path.join(scratch,'source_0.v'),src);
 const topName=process.env.PNR_TOP || 'top';
 if(!/^[A-Za-z_][A-Za-z_0-9]*$/.test(topName))throw Error('Invalid PNR_TOP');
 const script=`read_verilog -sv source_0.v; hierarchy -top ${topName}; proc; opt; synth_xilinx -flatten -abc9 -arch xc7 -top ${topName}; write_json synth.json`;
 const r=cp.spawnSync('yowasp-yosys',['-p',script],{cwd:scratch,encoding:'utf8',timeout:180000,maxBuffer:32*1024*1024});
 fs.writeFileSync(path.join(scratch,'yosys.log'),(r.stdout||'')+'\nSTDERR\n'+(r.stderr||''));
 if(fs.existsSync(path.join(scratch,'synth.json'))){
   const json=JSON.parse(fs.readFileSync(path.join(scratch,'synth.json'),'utf8'));
   const top=json.modules?.[topName];
   if(top){ const totals={};for(const cell of Object.values(top.cells||{})) totals[cell.type]=(totals[cell.type]||0)+1;
     const summary={design:dir,flipflops:Object.entries(totals).filter(([t])=>/^FD/.test(t)).reduce((n,[,v])=>n+v,0),
       bram:Object.entries(totals).filter(([t])=>/^RAMB/.test(t)).reduce((n,[,v])=>n+v,0),
       luts:Object.entries(totals).filter(([t])=>/^LUT/.test(t)).reduce((n,[,v])=>n+v,0),cells:Object.values(totals).reduce((a,b)=>a+b,0)};
     console.log('SYNTH_RESOURCES '+JSON.stringify(summary));
     if(process.env.REQUIRE_BRAM==='1' && summary.bram===0) throw Error('Memory inference failure: no RAMB cells');
   }
 }
 if(r.error||r.status!==0||!fs.existsSync(path.join(scratch,'synth.json')))throw Error('Yosys failed '+String(r.error||r.status));
 return scratch;
}
function runPnr(dir,slug,variant='original',xdcText=null,frequencyMHz=null,extraArguments=null){
 return new Promise(resolve=>{
   let settled=false;
   const begin=performance.now(),messages=[];
   const scratch=path.join(outDir,slug);
   const xdcPath=path.join(scratch,variant+'.xdc');
   const preferred=process.env.PNR_XDC || 'top.xdc';
   if(!/^[A-Za-z_0-9.\-]+$/.test(preferred))throw Error('Invalid PNR_XDC');
   const originalXdc=fs.existsSync(path.join(root,dir,preferred))?path.join(root,dir,preferred):path.join(root,dir,'hdmi.xdc');
   fs.writeFileSync(xdcPath,xdcText===null?fs.readFileSync(originalXdc,'utf8'):xdcText);
   const worker=new Worker(path.join(__dirname,'headless-pnr-worker.cjs'),{workerData:{
     engineDir,frequencyMHz,extraArguments,wasm:path.join(engineDir,'nextpnr-xilinx.wasm'),
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
   const slug=dir.split('/').slice(-2).join('_');
   const begin=performance.now();
   try {synth(dir,slug);let r=await runPnr(dir,slug);r.synthesis_ms=Math.round(performance.now()-begin-r.elapsed_ms);summary.push(r);}
   catch(e){summary.push({design:dir,result:'SYNTH_FAIL',error:String(e.stack||e)});}
   console.log(JSON.stringify(summary.at(-1)));
 }
 if(process.env.PNR_ONLY){
   const passing=summary.filter(r=>r.variant==='original'&&r.result==='PASS');
   const allGood=passing.length===cases.length;
   console.log('SERV_TARGETED_SUMMARY '+JSON.stringify(summary));
   if(!allGood)process.exitCode=1;
   return;
 }
 // Diagnose parseXdc failures without resynthesizing or changing netlist.
 const blink='PRODUCTION_GRADE/DEFAULTS/04_blink';
 const blinkSlug='DEFAULTS_04_blink';
 const originalXdc=fs.readFileSync(path.join(root,blink,'top.xdc'),'utf8');
 const lines=originalXdc.split(/\r?\n/);
 const variants={
   no_create_clock:lines.filter(l=>!l.trim().startsWith('create_clock')).join('\n'),
 };
 for(const [variant,xdc] of Object.entries(variants)){
   const result=await runPnr(blink,blinkSlug,variant,xdc);
   summary.push(result);console.log(JSON.stringify(result));
 }
 const freqResult=await runPnr(blink,blinkSlug,'no_create_clock_freq100',variants.no_create_clock,100);
 summary.push(freqResult);console.log(JSON.stringify(freqResult));
 const fifo='PRODUCTION_GRADE/TESTS/fifo_slotmachine';
 const fifoRouter=await runPnr(fifo,'TESTS_fifo_slotmachine','router1',null,null,['--router','router1']);
 summary.push(fifoRouter);console.log(JSON.stringify(fifoRouter));
 for(const dir of [
   'PRODUCTION_GRADE/TESTS/srl32_led',
   'PRODUCTION_GRADE/TESTS/dsp_fibonacci',
   'PRODUCTION_GRADE/TESTS/fifo_slotmachine'
 ]){
   const slug=dir.split('/').slice(-2).join('_');
   for(const seed of [2,3,4]){
     const result=await runPnr(dir,slug,'seed_'+seed,null,null,['--seed',String(seed)]);
     summary.push(result);console.log(JSON.stringify(result));
     if(result.result==='PASS')break;
   }
 }
 fs.writeFileSync(path.join(outDir,'matrix.json'),JSON.stringify(summary,null,2));
 const counts=Object.fromEntries(['PASS','FAIL','SYNTH_FAIL','HARNESS_ERROR','TIMEOUT'].map(x=>[x,summary.filter(v=>v.result===x).length]));
 console.log('MATRIX',JSON.stringify(counts));
 const expected = summary.filter(x => x.variant==='original' || x.variant==='no_create_clock' || x.variant==='no_create_clock_freq100');
 const regressions=expected.filter(x=>x.result!=='PASS');
 const md=['# Headless nextpnr regression matrix','','| Design | Variant | Result | PNR ms |','|---|---|---|---:|',
   ...summary.map(x=>'| '+x.design.split('/').at(-1)+' | '+x.variant+' | '+x.result+' | '+x.elapsed_ms+' |'),
   '',regressions.length?'**REGRESSION:** '+regressions.length+' expected PASS cases failed.':'**All expected PASS cases passed.**'];
 fs.writeFileSync(path.join(outDir,'matrix.md'),md.join('\n'));
 if(process.env.GITHUB_STEP_SUMMARY)fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,md.join('\n')+'\n');
 if(regressions.length)process.exitCode=1;
})();
