#!/usr/bin/env python3
"""Bounded explicit-state exploration of the Vivado browser/FPGA system.

This is an ABSTRACTION, not execution of JS, RTL, WASM, USB or hardware.
State includes true and believed revisions, build identity, UART framing,
board programming, asynchronous work, stale observations and human actions.

Run: python3 tests/system_state_explorer.py
Optional: --json prints machine-readable counterexamples.
"""
from __future__ import annotations
from collections import deque
from dataclasses import dataclass, replace
from typing import Optional
import argparse
import json

# Two abstract source revisions, two compilation epochs, two board revisions.
# Work is bounded deliberately; every explored state and edge is counted.
@dataclass(frozen=True)
class S:
    source: int = 0
    xdc: int = 0
    loaded_source: int = -1
    loaded_xdc: int = -1
    engine: int = 0
    compiled: tuple[int, int, int] = (-1, -1, -1)
    ready: bool = False
    build_pending: tuple[int, int, int] = (-1, -1, -1)
    programmed: tuple[int, int, int] = (-1, -1, -1)
    observed_source: int = -1
    observed_xdc: int = -1
    believed_compiled: tuple[int, int, int] = (-1, -1, -1)
    ble: bool = False
    command_buffer: str = ""
    running: bool = False
    pending_reply: bool = False
    tx_owner: str = "usb"
    mapping: int = 0  # 0 canonical; 1 logical reversed; 2 XDC pin permutation
    knowledge_mapping: int = -1
    display_verified: bool = False

NONE=(-1,-1,-1)

def events(s: S):
    """Nondeterministic events, including omission, delay and out-of-order completion."""
    # Edits can occur without reload, even while compilation is pending.
    if s.source == 0:
        yield "remote HDL edit", replace(s, source=1)
    if s.xdc == 0:
        yield "remote XDC edit", replace(s, xdc=1)
    if (s.loaded_source,s.loaded_xdc)!=(s.source,s.xdc):
        yield "load GitHub workspace", replace(s,loaded_source=s.source,loaded_xdc=s.xdc,
                                              observed_source=s.source,observed_xdc=s.xdc)
    if (s.loaded_source,s.loaded_xdc)!=( -1,-1) and s.build_pending==NONE:
        tag=(s.loaded_source,s.loaded_xdc,s.engine)
        yield "begin async compilation", replace(s,build_pending=tag)
    if s.build_pending!=NONE:
        yield "compilation finishes late", replace(s,compiled=s.build_pending,ready=True,
                                                    believed_compiled=s.build_pending,build_pending=NONE)
        yield "compilation interrupted", replace(s,build_pending=NONE)
    if s.ready:
        yield "flash cached bitstream", replace(s,programmed=s.compiled)
    if not s.ble:
        yield "BLE reconnect", replace(s,ble=True)
    if s.ble:
        yield "BLE disconnect", replace(s,ble=False,command_buffer="")
        if not s.command_buffer:
            yield "type s without newline", replace(s,command_buffer="s")
        else:
            yield "newline reaches UART", replace(s,command_buffer="",running=True,
                                                    pending_reply=True)
    if s.pending_reply:
        yield "UART reply starts", replace(s,pending_reply=False,tx_owner="fpga")
    if s.tx_owner=="fpga":
        yield "UART reply finishes", replace(s,tx_owner="usb")
    # Engineer can misremember orientation, or make arbitrary fixes.
    if s.knowledge_mapping != 0:
        yield "observe board mapping", replace(s,knowledge_mapping=0,display_verified=True)
    if s.mapping==0:
        yield "LLM swaps physical anodes", replace(s,mapping=2,display_verified=False)
        yield "LLM reverses logical digits", replace(s,mapping=1,display_verified=False)
    if s.mapping!=0:
        yield "restore canonical display mapping", replace(s,mapping=0,display_verified=False)
    if s.observed_source!=-1:
        yield "forget source observation", replace(s,observed_source=-1)
    if s.observed_xdc!=-1:
        yield "forget XDC observation", replace(s,observed_xdc=-1)

def violations(s: S):
    # Design-level invariants vs operator-process guarantees.
    if s.programmed != NONE and s.programmed != (s.source,s.xdc,s.engine):
        yield "FLASH_STALE: programmed artifact differs from current source/XDC/engine"
    if s.mapping==2:
        yield "XDC_PIN_DRIFT: application altered immutable physical pin map"
    if s.display_verified and s.mapping!=s.knowledge_mapping:
        yield "OBSERVATION_DRIFT: known mapping disagrees with modified implementation"
    if s.tx_owner=="fpga" and s.ble is False:
        yield "REPLY_LOST: UART response emitted while BLE disconnected"
    if s.ready and s.compiled != (s.loaded_source,s.loaded_xdc,s.engine):
        yield "STALE_BUILD: ready bitstream does not match loaded workspace"

def guarded_events(s: S):
    """Proposed guards, not claims about current implementation."""
    for label,n in events(s):
        if label=="flash cached bitstream" and s.compiled!=(s.source,s.xdc,s.engine):
            continue
        if label=="LLM swaps physical anodes":
            continue
        if label=="LLM reverses logical digits" and not s.display_verified:
            continue
        if label=="UART reply starts" and not s.ble:
            continue
        if label=="BLE disconnect" and s.tx_owner=="fpga":
            continue
        if label=="compilation finishes late" and s.build_pending!=(s.loaded_source,s.loaded_xdc,s.engine):
            continue
        if label in ("remote HDL edit","remote XDC edit") and s.build_pending!=NONE:
            # The real solution is fingerprinted build and invalidation, not locking edits.
            continue
        yield label,n

def explore(max_depth=8, guarded=False):
    root=S()
    todo=deque([root])
    depth={root:0}
    parent={}
    examples={}
    edges=0
    transition=guarded_events if guarded else events
    while todo:
        s=todo.popleft()
        d=depth[s]
        for v in violations(s):
            if v not in examples:
                path=[]
                cur=s
                while cur in parent:
                    prev,event=parent[cur]
                    path.append(event)
                    cur=prev
                examples[v]={"events":list(reversed(path)),"depth":d,"state":str(s)}
        if d>=max_depth:
            continue
        for name,n in transition(s):
            edges+=1
            if n not in depth:
                depth[n]=d+1
                parent[n]=(s,name)
                todo.append(n)
    return {"depth_limit":max_depth,"guarded":guarded,"states":len(depth),
            "transitions":edges,"counterexamples":examples}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--depth",type=int,default=8)
    p.add_argument("--json",action="store_true")
    args=p.parse_args()
    raw=explore(args.depth)
    result={"model_scope":"bounded, abstract, nondeterministic; not full hardware proof",
            "baseline":raw}
    if args.json:
        print(json.dumps(result,indent=2))
    else:
        print("ABSTRACT SYSTEM EXPLORER depth",args.depth)
        print("Reachable states:",raw["states"],"edges:",raw["transitions"])
        for name,x in raw["counterexamples"].items():
            print("\n",name,"at depth",x["depth"])
            for i,event in enumerate(x["events"],1):
                print(" ",i,event)
    assert raw["states"]>100
    assert "FLASH_STALE: programmed artifact differs from current source/XDC/engine" in raw["counterexamples"]
    assert "XDC_PIN_DRIFT: application altered immutable physical pin map" in raw["counterexamples"]

if __name__=="__main__":
    main()
