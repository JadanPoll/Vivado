#!/usr/bin/env python3
import os,json,pathlib
name=os.environ["PNR_ONLY"]
required={"11_ramb36":["RAMB36E1"],"12_ram64m":["RAM64M"],"13_srlc32e":["SRLC32E"],"14_muxf78":["MUXF7","MUXF8"]}[name]
p=pathlib.Path("pnr-repro-output")/("DEFAULTS_"+name)/"synth.json"
types={}
for cell in json.loads(p.read_text())["modules"]["top"]["cells"].values():
  t=cell["type"]
  types[t]=types.get(t,0)+1
print("FINGERPRINT",name,types)
assert all(types.get(t,0)>0 for t in required),f"Missing expected primitive: {required}"
