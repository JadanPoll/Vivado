#!/usr/bin/env node
// Classify every nominally unmapped SERV FASM feature against pinned
// Spartan-7 Project X-Ray segbits and ppips databases. Read-only analysis.
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const zlib=require('node:zlib');
const root=path.resolve(__dirname,'..');
const base=path.join(root,'PRODUCTION_GRADE');
const dir=path.join(root,'pnr-repro-output/DEFAULTS_serv_blinky');
const map=JSON.parse(zlib.brotliDecompressSync(fs.readFileSync(path.join(base,'xc7s50_fasm_map_v7.json.br'))));
const fasm=fs.readFileSync(path.join(dir,'original.fasm'),'utf8');
const REV='0a0addedd73e7e4139d52a6d8db4258763e0f1f3';
const missing=new Map();
let noTile=0,noType=0, mapped=0;
for(const raw of fasm.split('\n')){
 const line=raw.trim();if(!line||line.startsWith('#'))continue;
 const eq=line.indexOf('=');
 const left=eq<0?line:line.slice(0,eq).trim();
 const value=eq<0?'':line.slice(eq+1).trim();
 const dot=left.indexOf('.');if(dot<0){noTile++;continue}
 const tile=left.slice(0,dot), feature=left.slice(dot+1);
 const info=map.grid[tile];if(!info){noTile++;continue}
 const kind=info.type;
 const dict=map.features[kind];if(!dict){noType++;continue}
 const keys=[];
 if(value.includes("'b")&&/\[(\d+):(\d+)\]/.test(feature)){
   const hi=Number(/\[(\d+):(\d+)\]/.exec(feature)[1]);
   const bits=value.slice(value.indexOf("'b")+2).replaceAll('_','');
   const basename=feature.slice(0,feature.indexOf('['));
   for(let i=0;i<bits.length;i++)if(bits[i]==='1')keys.push(basename+'['+(hi-i)+']');
 }else keys.push(feature);
 for(const key of keys){
   let hit=dict[key];
   if(!hit&&key.endsWith(']')){
     const a=/^(.*)\[(\d+)\]$/.exec(key);
     if(a)hit=dict[a[1]+'['+a[2].padStart(2,'0')+']']||dict[a[1]+'['+a[2].padStart(3,'0')+']'];
   }
   if(hit){mapped++;continue}
   const full=kind+'.'+key;
   missing.set(full,(missing.get(full)||0)+1);
 }
}
const kinds=[...new Set([...missing.keys()].map(x=>x.split('.',1)[0]))];
async function fetchDb(type,kind){
 const u='https://raw.githubusercontent.com/f4pga/prjxray-db/'+REV+'/spartan7/'+type+'_'+kind.toLowerCase()+'.db';
 const response=await fetch(u);
 if(response.status===404)return '';
 if(!response.ok)throw Error('database HTTP '+response.status+' '+u);
 return response.text();
}
(async()=>{
 const db=new Map();
 for(const type of kinds){
   const [ppips,segbits]=await Promise.all([fetchDb('ppips',type),fetchDb('segbits',type)]);
   const pp=new Map();
   for(const line of ppips.split('\n')){const s=line.trim().split(/\s+/);if(s.length>=2)pp.set(s[0],s[1]);}
   const sg=new Map();
   for(const line of segbits.split('\n')){const s=line.trim().split(/\s+/);if(s.length>=2)sg.set(s[0],s.slice(1));}
   db.set(type,{pp,sg});
 }
 const counts={mapped,zero_only:0,pseudo_always:0,pseudo_default:0,pseudo_hint:0,unknown:0,noTile,noType};
 const unknown=new Map(),examples={};
 for(const [name,n] of missing){
   const type=name.split('.',1)[0];
   const {pp,sg}=db.get(type);
   let klass;
   if(pp.has(name))klass='pseudo_'+pp.get(name);
   else if(sg.has(name)&&sg.get(name).every(x=>x.startsWith('!')))klass='zero_only';
   else klass='unknown';
   counts[klass]=(counts[klass]||0)+n;
   if(klass==='unknown')unknown.set(name,n);
   if(!examples[klass])examples[klass]=[];
   if(examples[klass].length<12)examples[klass].push({name,count:n});
 }
 const output={source_revision:REV,total_missing:[...missing.values()].reduce((a,b)=>a+b,0),
   classes:counts,example_by_class:examples,unknown_top:[...unknown].sort((a,b)=>b[1]-a[1]).slice(0,60).map(([name,count])=>({name,count}))};
 fs.writeFileSync(path.join(dir,'fasm-coverage-audit.json'),JSON.stringify(output,null,2));
 console.log('FASM_COVERAGE '+JSON.stringify(output));
 if(counts.noTile||counts.noType||counts.unknown)process.exitCode=2;
})().catch(e=>{console.error('FASM_COVERAGE_ERROR '+(e.stack||e));process.exitCode=1});
