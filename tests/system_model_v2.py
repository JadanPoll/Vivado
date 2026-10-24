#!/usr/bin/env python3
"""Compositional, bounded explicit-state model of the ZeroLabs browser FPGA stack.

Derived from FINAL/index.html (workspace discovery/load, build, JTAG),
PRODUCTION_GRADE/*-worker.js, asset-cache, urbana-ble.js, ftdi-jtag.js,
and DEFAULTS/stopwatch/top.v. Behavioral abstraction, NOT hardware execution.

Each event enumerates admissible scheduling/failure outcomes. States represent
actual versions, loaded bytes, pending jobs, artifact provenance, observed
information and the device. Assumptions and source anchors are reported below.

Run: python3 tests/system_model_v2.py [--depth 8] [--json]
"""
from dataclasses import dataclass, replace, asdict
from collections import deque
import argparse, json

NONE=-1
# Finite revisions and job IDs bound the model; domains aren't byte-accurate.
@dataclass(frozen=True)
class State:
    repo: int=0                 # true remote content revision
    discovery: int=NONE         # snapshot of GitHub tree
    discovery_pending: int=NONE
    workspace: int=NONE         # content commit actually loaded
    load_pending: int=NONE
    draft: int=NONE             # local unsaved source revision
    editor: int=NONE            # current effective input content
    observed_revision: int=NONE  # last revision shown to user
    build_stage: str="idle"     # idle/synth/pnr/fasm/frames/ready/failed
    build_source: int=NONE      # frozen effective input revision
    build_engine: int=0
    build_id: int=0
    bit_source: int=NONE
    bit_engine: int=NONE
    bit_valid: bool=False
    unmapped_fasm: bool=False
    cache_engine: int=0
    engine_selected: int=0
    flash_stage: str="idle"     # idle/usb/init/idcheck/program/failed/done
    flash_artifact: int=NONE
    flash_device: str="unknown" # unknown/compatible/wrong
    device_config: int=NONE
    device_done: bool=False
    board_connected: bool=False
    ble: bool=False
    uart_rx: str="idle"         # idle/partial/complete
    command: str="none"         # none/start/pause/time
    running: bool=False
    tx: str="idle"              # idle/queued/sending
    reply_delivered: bool=False
    logical_digits: tuple=(0,1,2,3)
    pin_mapping: tuple=(0,1,2,3)
    observation: tuple=(-1,-1,-1,-1)
    last_observation_version: int=NONE
    evidence: str="unknown"    # unknown/old/verified
    dismissed_warning: bool=False

# Explicit transitions may occur in any order; yielding multiple successors
# models nondeterministic success/failure, delay, retry, and partial execution.
def successors(s):
    def emit(name, **kw):
        return name,replace(s,**kw)
    if s.repo==0:
        yield emit("remote commit",repo=1)
    if s.discovery_pending==NONE:
        yield emit("begin discovery",discovery_pending=s.repo)
    else:
        yield emit("discovery response",discovery=s.discovery_pending,discovery_pending=NONE)
        yield emit("discovery request fails",discovery_pending=NONE)
    if s.discovery!=NONE and s.load_pending==NONE:
        yield emit("begin workspace file fetch",load_pending=s.discovery)
    if s.load_pending!=NONE:
        yield emit("all HDL and XDC files arrive",workspace=s.load_pending,editor=s.load_pending,
                   observed_revision=s.load_pending,load_pending=NONE)
        yield emit("one file fetch fails",load_pending=NONE)
    if s.workspace!=NONE and s.editor!=1:
        yield emit("local editor modification",editor=1,draft=1,evidence="old")
    if s.draft!=NONE:
        yield emit("save draft",draft=s.editor)
        yield emit("forget local draft",draft=NONE)
    if s.editor!=NONE and s.build_stage in ("idle","ready","failed"):
        yield emit("start build from current editor",build_stage="synth",build_source=s.editor,
                   build_engine=s.cache_engine,build_id=s.build_id+1,
                   bit_valid=False,bit_source=NONE,unmapped_fasm=False)
    if s.build_stage=="synth":
        yield emit("Yosys reports success",build_stage="pnr")
        yield emit("Yosys error or worker crash",build_stage="failed")
    if s.build_stage=="pnr":
        yield emit("nextpnr generates FASM",build_stage="fasm")
        yield emit("nextpnr routing failure",build_stage="failed")
    if s.build_stage=="fasm":
        yield emit("FASM entries all mapped",build_stage="frames")
        yield emit("FASM has unknown features but emits frames",build_stage="frames",unmapped_fasm=True)
        yield emit("FASM worker errors",build_stage="failed")
    if s.build_stage=="frames":
        yield emit("frames2bit completes",build_stage="ready",bit_source=s.build_source,
                   bit_engine=s.build_engine,bit_valid=True)
        yield emit("frames2bit abort",build_stage="failed")
    if s.engine_selected==0:
        yield emit("new engine version selected",engine_selected=1)
    if s.engine_selected!=s.cache_engine:
        yield emit("cache retrieves engine from current key",cache_engine=s.engine_selected)
        yield emit("cache delivers obsolete engine",cache_engine=0)
    if not s.board_connected:
        yield emit("USB board attached",board_connected=True)
    else:
        yield emit("USB board unplugged",board_connected=False)
    if s.bit_valid and s.flash_stage in ("idle","done","failed"):
        yield emit("click flash",flash_stage="usb",flash_artifact=s.bit_source,
                   flash_device="unknown",device_done=False)
    if s.flash_stage=="usb":
        yield emit("WebUSB permission granted",flash_stage="init")
        yield emit("USB permission denied",flash_stage="failed")
    if s.flash_stage=="init":
        yield emit("JTAG initialized",flash_stage="idcheck")
        yield emit("JTAG initialization error",flash_stage="failed")
    if s.flash_stage=="idcheck":
        yield emit("correct silicon IDCODE",flash_stage="program",flash_device="compatible")
        yield emit("wrong silicon IDCODE",flash_stage="failed",flash_device="wrong")
    if s.flash_stage=="program":
        yield emit("JTAG DONE asserted",flash_stage="done",device_config=s.flash_artifact,
                   device_done=True)
        yield emit("USB interrupted mid-configuration",flash_stage="failed",device_done=False)
        yield emit("JTAG DONE stays low",flash_stage="failed",device_done=False)
    if not s.ble:
        yield emit("BLE reconnect",ble=True)
    else:
        yield emit("BLE disconnect",ble=False)
        if s.uart_rx=="idle":
            yield emit("UART receives partial command",uart_rx="partial")
        if s.uart_rx=="partial":
            yield emit("newline completes command",uart_rx="complete",command="start")
        if s.uart_rx=="complete":
            yield emit("FPGA applies start command",uart_rx="idle",running=True,tx="queued")
    if s.tx=="queued":
        yield emit("UART transmitter begins",tx="sending")
    if s.tx=="sending":
        yield emit("UART response sent",tx="idle",reply_delivered=s.ble)
    if s.pin_mapping==(0,1,2,3):
        yield emit("edit only anode 0/1 pin names",pin_mapping=(1,0,2,3),evidence="old")
        yield emit("reverse all four physical anodes",pin_mapping=(3,2,1,0),evidence="old")
    if s.logical_digits==(0,1,2,3):
        yield emit("reverse digit selection in HDL",logical_digits=(3,2,1,0),evidence="old")
    if s.observation==(-1,-1,-1,-1):
        # Actual display is composed by logic then physical permutation, not
        # specified as 'incorrect' in the event. This is an observable result.
        visible=tuple(s.logical_digits[s.pin_mapping[i]] for i in range(4))
        yield emit("read four observed physical digits",observation=visible,
                   last_observation_version=s.editor,evidence="verified")
    if s.observation!=(-1,-1,-1,-1):
        yield emit("forget physical observation",observation=(-1,-1,-1,-1),evidence="unknown")
    if not s.dismissed_warning:
        yield emit("ignore FASM mapping warning",dismissed_warning=True)

def properties(s):
    # Safety of claims and provenance, rather than pre-labeling actions as bugs.
    if s.bit_valid and s.bit_source!=s.editor:
        yield "ARTIFACT_STALE_VS_VISIBLE_EDITOR"
    if s.bit_valid and s.bit_engine!=s.engine_selected:
        yield "ARTIFACT_BUILT_WITH_DIFFERENT_ENGINE"
    if s.build_stage=="ready" and s.unmapped_fasm:
        yield "READY_WITH_UNMAPPED_FEATURES"
    if s.flash_stage=="done" and s.flash_artifact!=s.editor:
        yield "FLASHED_DIFFERENT_SOURCE_THAN_VISIBLE"
    if s.flash_stage=="done" and not s.device_done:
        yield "FLASH_REPORTED_DONE_WITHOUT_DEVICE_DONE"
    if s.flash_stage=="program" and not s.board_connected:
        yield "PROGRAMMING_WITH_BOARD_DISCONNECTED"
    if s.reply_delivered and not s.ble:
        # A delivered reply may outlive a connection; do not incorrectly flag.
        pass
    if s.tx=="sending" and not s.ble:
        yield "REPLY_IN_FLIGHT_WHILE_BLE_DISCONNECTED"
    if s.evidence=="verified" and s.last_observation_version!=s.editor:
        yield "OBSERVATION_PROVENANCE_STALE"
    if s.observation!=(-1,-1,-1,-1) and tuple(s.logical_digits[s.pin_mapping[i]]
        for i in range(4))!=s.observation:
        yield "PHYSICAL_OBSERVATION_NO_LONGER_MATCHES_MAPPING"
    if s.flash_stage=="done" and s.unmapped_fasm:
        yield "FLASHED_BITSTREAM_WITH_UNMAPPED_FEATURES"

def explore(limit=9,max_states=180000):
    root=State(); queue=deque([root]); parent={root:None}; depth={root:0}
    found={}; edges=0; truncated=False
    while queue:
        s=queue.popleft();d=depth[s]
        for p in properties(s):
            if p not in found:
                trace=[];cur=s
                while parent[cur] is not None:
                    prev,event=parent[cur];trace.append(event);cur=prev
                found[p]={"depth":d,"events":trace[::-1],"end_state":asdict(s)}
        if d==limit:continue
        for name,n in successors(s):
            edges+=1
            if n not in parent:
                if len(parent)>=max_states:
                    truncated=True;break
                parent[n]=(s,name);depth[n]=d+1;queue.append(n)
        if truncated:break
    return {"depth":limit,"state_count":len(parent),"edge_count":edges,
        "truncated":truncated,"counterexamples":found,
        "model": "repository-derived bounded abstraction, not proof of implementation"}
if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--depth",type=int,default=9)
    parser.add_argument("--json",action="store_true")
    a=parser.parse_args();r=explore(a.depth)
    if a.json:print(json.dumps(r,indent=2))
    else:
        print(f"states={r['state_count']} edges={r['edge_count']} depth={r['depth']} truncated={r['truncated']}")
        for k,v in r["counterexamples"].items():
            print("\n"+k+" depth="+str(v["depth"]))
            print("  "+" -> ".join(v["events"]))
    if r["state_count"]<1000:raise SystemExit("Insufficient exploration")
