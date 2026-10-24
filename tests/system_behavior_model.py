#!/usr/bin/env python3
"""Auditable bounded abstract model of the ZeroLabs Vivado system.

Models relationships and scheduling, not JS, APIs, FPGA gates, or USB transfers.
The pair matrix is deliberately three-valued: evidenced (E), conditional (C),
unresolved (U). U means NOT justified impossible. Selected exclusions (X) must
name a source-backed scope argument. Run --report to emit full Markdown audit.
"""
from collections import deque, Counter
from dataclasses import dataclass, replace
from itertools import permutations
import argparse, json

# Level-0 inventory. Refinement decision is per property: neither purely
# recursive nor irreducible. No claim of complete system decomposition.
NODES = {
 'actor': ('Human/LLM action and belief', 'refine', 'Intent, interruptions, forgotten observations and edits can alter interactions'),
 'repo': ('Versioned GitHub repository', 'stop', 'Atomic commit snapshots assumed; GitHub internals out of scope'),
 'discover': ('Repository discovery and catalog', 'refine', 'Async ref resolution, tree fetch, catalog publication'),
 'workspace': ('Active source/XDC workspace', 'refine', 'Base URL, identity, selected files, edited bytes, revision guard'),
 'draft': ('Browser drafts/localStorage', 'refine', 'Save, restore, storage failure, wrong project key'),
 'build': ('Build coordinator', 'refine', 'Input snapshot, async stage completion, published artifact'),
 'cache': ('Pinned toolchain asset cache', 'refine', 'Pending/failure and buffer transfer semantics'),
 'yosys': ('Synthesis worker', 'stop', 'Success/error interface sufficient; internal synthesis outside this property'),
 'pnr': ('Placement/routing worker', 'stop', 'FASM/error interface sufficient; chip-level routing not modeled'),
 'fasm': ('FASM-to-frames mapping', 'refine', 'Success, warnings, errors affect pipeline provenance'),
 'frames': ('Frames-to-bitstream worker', 'stop', 'Completion/error boundary modeled; encoding not modeled'),
 'artifact': ('Compiled bitstream and provenance', 'refine', 'Selection at click, retention, replacement and warnings'),
 'usb': ('WebUSB/JTAG transaction', 'refine', 'Permission, IDCODE, transfer, DONE and failure'),
 'board': ('Urbana hardware', 'refine', 'Physical pin, active polarity, DONE, counter display, board state'),
 'serial': ('USB-UART transport', 'stop', 'Packet boundaries/errors abstracted at UART interface'),
 'ble': ('BLE client and serial bridge', 'refine', 'Connection, chunks, disconnect and delayed notifications'),
 'rtl': ('Stopwatch RTL and display decoder', 'refine', 'Clock, BCD carry, command parser, logical digit permutation'),
}
# Source-backed direct pair dependencies; a pair may have multiple labels.
# E = direct edge evidenced; C = conditional edge requiring stated condition.
RELATIONS = [
 ('actor','discover','E','click Discover','FINAL/index.html:854-859'),
 ('actor','workspace','E','edit URL, source or XDC','FINAL/index.html:632,908-919'),
 ('actor','draft','E','trigger save, reopen or dismiss confirmation','FINAL/index.html:392-403,645-663'),
 ('actor','build','E','click Build','FINAL/index.html:1084-1115'),
 ('actor','artifact','E','choose artifact for download or flash','FINAL/index.html:979-980,1249-1255'),
 ('actor','usb','E','request USB hardware access','FINAL/index.html:1257'),
 ('actor','ble','E','connect/disconnect/send command','FINAL/index.html:587-600'),
 ('actor','serial','E','connect/send terminal bytes','FINAL/index.html:563-600'),
 ('actor','actor','E','forget/refresh/revise prior observation','model: epistemic actor transitions'),
 ('repo','discover','C','resolve ref and fetch tree if network succeeds','FINAL/index.html:767-866'),
 ('repo','workspace','C','fetch specified commit files','FINAL/index.html:728-738,825-828'),
 ('discover','workspace','C','select project and initiate file fetch','FINAL/index.html:807-838,879-881'),
 ('discover','discover','C','pending fetch succeeds/fails/late','FINAL/index.html:854-885'),
 ('workspace','workspace','E','invalidate/switch/edit/reload','FINAL/index.html:705-720,807-845'),
 ('workspace','draft','C','save draft if storage writable','FINAL/index.html:645-655,915-918'),
 ('draft','workspace','C','merge matching identity if stored','FINAL/index.html:739-763'),
 ('workspace','build','C','snapshot selected HDL and XDC if ready','FINAL/index.html:1099-1115'),
 ('workspace','discover','E','base URL editing can invalidate active selection','FINAL/index.html:632,705-720'),
 ('build','yosys','C','launch synthesis worker','FINAL/index.html:1120-1133'),
 ('yosys','build','C','synthesis success/error response','FINAL/index.html:1123-1133'),
 ('build','cache','C','get pinned database/wasm/FASM assets','FINAL/index.html:1138-1144,1178-1182'),
 ('cache','build','C','return assets or reject promise','FINAL/index.html:283-310'),
 ('build','pnr','C','launch nextpnr worker','FINAL/index.html:1146-1172'),
 ('pnr','build','C','emit FASM or error','FINAL/index.html:1154-1172'),
 ('build','fasm','C','send FASM and map to worker','FINAL/index.html:1183-1197'),
 ('fasm','build','C','return frames, warning telemetry, or error','FINAL/index.html:1187-1198'),
 ('build','frames','C','send frames and part YAML','FINAL/index.html:1200-1227'),
 ('frames','build','C','return bitstream or error','FINAL/index.html:1211-1227'),
 ('build','artifact','C','publish bitstream when assembly succeeds','FINAL/index.html:1227-1238'),
 ('artifact','usb','C','capture selected bitstream at click','FINAL/index.html:1249-1264'),
 ('usb','board','C','JTAG program device after IDCODE check','PRODUCTION_GRADE/ftdi-jtag.js:160-199'),
 ('board','usb','C','provide silicon IDCODE and DONE status','PRODUCTION_GRADE/ftdi-jtag.js:124-157,192-199'),
 ('usb','actor','C','log flash success or error','FINAL/index.html:1264-1269'),
 ('board','rtl','E','clock and input signals drive HDL','stopwatch/top.v:top'),
 ('rtl','board','E','drive display segments, anodes and LEDs','stopwatch/top.v:hex_driver'),
 ('ble','rtl','C','delimit UART command with LF','stopwatch/top.v:BLE UART parser'),
 ('rtl','ble','C','return UART answer when requested','stopwatch/top.v:UART TX response'),
 ('ble','ble','E','connect/disconnect/chunk/receive notifications','PRODUCTION_GRADE/urbana-ble.js:34-124'),
 ('serial','rtl','C','UART bridge data to FPGA','stopwatch/top.v:UART_RXD'),
 ('rtl','serial','C','USB terminal monitors BLE incoming data','stopwatch/top.v:UART_RXD'),
 ('rtl','rtl','E','advance counters/scan digits/decode commands','stopwatch/top.v:hex_driver and counters'),
 ('artifact','artifact','E','retain earlier version across source edits','FINAL/index.html:410,1091,1227'),
 ('cache','cache','E','warmup, deduplicate promise, retry after rejection','FINAL/index.html:277-326'),
 ('draft','draft','E','persist/fail/restore local records','FINAL/index.html:645-655,888-905'),
 ('board','board','E','clock advances, reset, DONE can remain low','Urbana device behavior and stopwatch RTL'),
 ('usb','usb','E','permission, init, transfer, status, close','PRODUCTION_GRADE/ftdi-jtag.js:30-199'),
]
# A narrow set of genuinely excluded DIRECT edges in the implemented
# interface graph (not claims about indirect paths or hypothetical hardware).
# These can be challenged if an additional interface is found.
IMPOSSIBLE={
 ('board','repo'): 'Physical board has no direct GitHub network/API interface; only JTAG/UART pins',
 ('rtl','repo'): 'Synthesized stopwatch contains no network/GitHub client',
 ('ble','repo'): 'BLE GATT UART client has no repository write path',
 ('serial','repo'): 'FTDI UART driver has no repository write path',
 ('board','draft'): 'FPGA signals cannot directly mutate browser localStorage',
 ('rtl','draft'): 'HDL has no direct localStorage interface',
 ('frames','repo'): 'Frames2bit worker produces bitstream bytes, never repository writes',
 ('yosys','repo'): 'Yosys worker produces synthesis data, never repository writes',
 ('pnr','repo'): 'nextpnr worker produces FASM, never repository writes',
}
PAIRS={(a,b):[] for a in NODES for b in NODES}
for (a,b),why in IMPOSSIBLE.items():
    PAIRS[a,b].append(('X', 'No direct interface in this implementation',why))
for a,b,kind,label,source in RELATIONS:
    PAIRS[a,b].append((kind,label,source))

@dataclass(frozen=True)
class S:
    selected: int=0              # URL's current requested project
    base_generation: int=0
    discovered: int=-1
    discover_request: int=-1
    workspace: int=-1            # committed workspace origin
    content: int=-1              # HDL's actual origin, not its label
    xdc: int=-1                  # XDC's actual origin
    identity: int=-1             # workspace key used for drafts/builds
    pending_hdl: int=-1          # request's captured origin
    pending_xdc: int=-1
    ready: bool=False
    saved_draft: int=-1
    observation: int=-1
    build: str='idle'
    build_input: int=-1
    bitstream: int=-1
    flash: str='idle'
    clicked_bitstream: int=-1
    programmed: int=-1
    done: int=-1
    flash_claim_success: bool=False
    ble: bool=False
    partial_command: bool=False
    reply_pending: bool=False
    reply_received: bool=False
    hour_tens: int=0
    hour_ones: int=0
    pins: tuple=(0,1,2,3)
    digits: tuple=(0,1,2,3)
    observed_digits: tuple=()

# Events derive from actual public handlers; minimal abstract revision domain.
# User intent is represented by 'selected'; an old explicitly selected
# workspace is legal. The violation is mislabeling A's bytes as B's workspace.
def events(s, guarded=False):
    def e(domain,name,**kw): return (domain,name,replace(s,**kw))
    if s.selected==0:
        yield e('workspace','user switches project URL from A to B',selected=1,base_generation=1,
                workspace=-1,content=-1,xdc=-1,identity=-1,ready=False)
    if s.discover_request==-1:
        yield e('discover','start project discovery',discover_request=s.selected)
    else:
        if not guarded or s.discover_request==s.selected:
            yield e('discover','discovery response arrives',discovered=s.discover_request,
                    discover_request=-1)
        else:
            yield e('discover','discard obsolete discovery response',discover_request=-1)
        yield e('discover','discovery request fails',discover_request=-1)
    if s.discovered!=-1 and s.workspace!=s.discovered:
        if guarded and s.discovered!=s.selected:
            yield e('workspace','ignore stale discovery selection',discovered=-1)
        else:
            yield e('workspace','load selected project atomically',workspace=s.discovered,
                content=s.discovered,xdc=s.discovered,identity=s.discovered,ready=True,
                observed_digits=())
    if s.pending_hdl==-1:
        yield e('workspace','begin Fetch HDL at current URL',pending_hdl=s.selected)
    else:
        if guarded and s.pending_hdl!=s.selected:
            yield e('workspace','discard obsolete HDL response',pending_hdl=-1)
        else:
            yield e('workspace','Fetch HDL response commits into current workspace',
                    content=s.pending_hdl, identity=s.selected,pending_hdl=-1,
                    ready=(s.xdc!=-1))
        yield e('workspace','Fetch HDL fails',pending_hdl=-1)
    if s.pending_xdc==-1:
        yield e('workspace','begin Fetch XDC at current URL',pending_xdc=s.selected)
    else:
        if guarded and s.pending_xdc!=s.selected:
            yield e('workspace','discard obsolete XDC response',pending_xdc=-1)
        else:
            yield e('workspace','Fetch XDC response updates editor',xdc=s.pending_xdc,
                    pending_xdc=-1,ready=False)
        yield e('workspace','Fetch XDC fails',pending_xdc=-1)
    if s.content!=-1:
        if s.saved_draft!=s.content:
            yield e('draft','save current source as local draft',saved_draft=s.content)
        if s.observation!=s.content:
            yield e('actor','inspect visible source',observation=s.content)
    if s.ready and s.content!=-1 and s.build in ('idle','ready','error'):
        yield e('build','start compilation of captured HDL',build='yosys',build_input=s.content,
                bitstream=-1)
    if s.build=='yosys':
        yield e('build','Yosys succeeds',build='pnr')
        yield e('build','Yosys fails',build='error')
    if s.build=='pnr':
        yield e('build','nextpnr succeeds',build='fasm')
        yield e('build','nextpnr fails',build='error')
    if s.build=='fasm':
        yield e('build','FASM mapping returns frames',build='frames')
        yield e('build','FASM mapping error',build='error')
    if s.build=='frames':
        yield e('build','bitstream ready',build='ready',bitstream=s.build_input)
        yield e('build','bitstream assembly fails',build='error')
    if s.bitstream!=-1 and s.flash in ('idle','error','complete'):
        yield e('usb','user selects current bitstream for flash',flash='permission',
                clicked_bitstream=s.bitstream,flash_claim_success=False,done=-1)
    if s.flash=='permission':
        yield e('usb','USB permission accepted',flash='idcode')
        yield e('usb','USB denied',flash='error')
    if s.flash=='idcode':
        yield e('usb','device IDCODE matches',flash='program')
        yield e('usb','device IDCODE mismatch',flash='error')
    if s.flash=='program':
        yield e('usb','DONE asserted after flashing selected bitstream',flash='complete',
                programmed=s.clicked_bitstream,done=1,flash_claim_success=True)
        yield e('usb','DONE remains low and operation rejects',flash='error',done=0)
        yield e('usb','transport interrupted',flash='error')
    if not s.ble:
        yield e('ble','Bluetooth connects',ble=True)
    else:
        yield e('ble','Bluetooth disconnects',ble=False)
        if not s.partial_command:
            yield e('ble','receive start character without newline',partial_command=True)
        else:
            yield e('ble','newline delivers start command',partial_command=False,
                    reply_pending=True)
    if s.reply_pending:
        yield e('ble','reply attempted',reply_pending=False,reply_received=s.ble)
    # Explicitly allow stale observations, old build artifacts, disconnects.
    if not s.observed_digits:
        observed=tuple(s.digits[s.pins[k]] for k in range(4))
        yield e('board','user observes digits',observed_digits=observed)
    if s.pins==(0,1,2,3):
        yield e('actor','engineer swaps physical anodes',pins=(1,0,2,3))
    if s.digits==(0,1,2,3):
        yield e('rtl','engineer changes digit-order logic',digits=(3,2,1,0))
    if s.hour_ones<9:
        yield e('rtl','hour carry',hour_ones=s.hour_ones+1)
    elif s.hour_tens<9:
        yield e('rtl','hour carry',hour_tens=s.hour_tens+1,hour_ones=0)
    else:
        yield e('rtl','decimal hours wrap',hour_tens=0,hour_ones=0)

# Only real cross-component semantic contradictions, not stale/partial states.
def contracts(s):
    if s.ready and s.identity>=0 and s.content!=-1 and s.identity!=s.content:
        yield 'WRONG_SOURCE_ASSOCIATION'
    if s.ready and s.identity>=0 and s.xdc!=-1 and s.identity!=s.xdc:
        yield 'WRONG_XDC_ASSOCIATION'
    if s.flash_claim_success and (s.done!=1 or s.programmed!=s.clicked_bitstream):
        yield 'FLASH_SUCCESS_MISREPRESENTED'

# Bounded BFS; shortest traces in number of events. No hand-constructed paths.
def explore(domains, initial=None, depth=9, guarded=False, cap=250000):
    start=initial if initial is not None else S()
    q=deque([start]); visited={start:(0,None,'')}
    errors={}; edges=0; reached=Counter(); truncated=False
    def witness(s):
        result=[]
        while visited[s][1] is not None:
            d,p,name=visited[s];result.append(name);s=p
        return result[::-1]
    while q:
        s=q.popleft();d=visited[s][0];reached[d]+=1
        for k in contracts(s):
            errors.setdefault(k, {'depth':d,'trace':witness(s),
                                  'end':{'selected':s.selected,'identity':s.identity,
                                         'source_origin':s.content,'xdc_origin':s.xdc}})
        if d==depth:continue
        for domain,label,n in events(s,guarded):
            if domain not in domains:continue
            edges+=1
            if n not in visited:
                if len(visited)>=cap:
                    truncated=True;break
                visited[n]=(d+1,s,label);q.append(n)
        if truncated:break
    return {'states':len(visited),'transitions':edges,'depth':depth,
            'truncated':truncated,'counterexamples':errors,
            'frontier_at_limit':reached[depth]}

def run(depth=9):
    # Full project discovery/fetch interaction and independent build/JTAG
    # projection; all domains reuse exactly the same transitions.
    slices={
        'workspace_original': explore({'workspace','discover','draft','actor'},depth=depth),
        'workspace_guarded': explore({'workspace','discover','draft','actor'},depth=depth,guarded=True),
        'build_program': explore({'workspace','discover','build','usb'},depth=depth+5,cap=250000),
        'transport_display': explore({'ble','board','rtl','actor'},depth=depth),
    }
    # All 24 permutations of each component, hence 576 possibilities, no
    # inferred board orientation from labels alone.
    pairs=Counter(tuple(d[p[i]] for i in range(4)) for p in permutations(range(4))
                  for d in permutations(range(4)))
    digit_orders=Counter(tuple(d[p[i]] for i in range(4))
                         for p in permutations(range(4)) for d in permutations(range(4)))
    matrix=Counter('U' if not spec else ('E' if any(x[0]=='E' for x in spec) else ('C' if any(x[0]=='C' for x in spec) else 'X'))
                   for spec in PAIRS.values())
    return {'nodes':len(NODES),'audited_ordered_pairs':len(PAIRS),
            'pair_classification':dict(matrix),'refine':sum(x[1]=='refine' for x in NODES.values()),
            'stop':sum(x[1]=='stop' for x in NODES.values()),
            'projections':slices,'digit_mapping_pairs':sum(pairs.values()),
            'distinct_digit_orders':len(pairs),
            'all_display_permutations':sum(digit_orders.values()),
            'display_orders_seen':len(digit_orders),
            'limitations':['No complete verification of FPGA gates or routing',
                           'Unresolved node pairs cannot be claimed impossible',
                           'Bounded interleavings, not all infinite traces',
                           'Actor and hardware outcomes abstracted by labels']}

def report(res):
    ids=list(NODES)
    print('# Vivado: recursive combinatorial system audit\n')
    print('Scope: `FINAL/index.html`, `PRODUCTION_GRADE` worker/JTAG/BLE modules, and stopwatch RTL.\n')
    print('## Depth 0: node selection and refinement obligations\n')
    print('|ID|Element|Decision|Justification|\n|---|---|---|---|')
    for id,(label,decision,why) in NODES.items():
        print(f'|`{id}`|{label}|{decision}|{why}|')
    print('\n## Ordered-pair matrix\n')
    print('**E** evidenced, **C** conditional, **X** excluded direct interface with stated justification, **U** unresolved; unresolved pairs are not impossible. Rows are source; columns are target.\n')
    print('|Source\\Target|'+'|'.join(ids)+'|')
    print('|'+'---|'*(len(ids)+1))
    for a in ids:
        print('|'+a+'|'+'|'.join(('E' if any(x[0]=='E' for x in PAIRS[a,b]) else ('C' if any(x[0]=='C' for x in PAIRS[a,b]) else 'X')) if PAIRS[a,b] else 'U' for b in ids)+'|')
    print('\n## Labeled relation evidence\n')
    print('|Source → Target|Class|Event/condition|Source|\n|---|---|---|---|')
    for a,b,k,label,source in RELATIONS:print(f'|{a} → {b}|{k}|{label}|`{source}`|')
    for (a,b),why in IMPOSSIBLE.items():print(f'|{a} → {b}|X|No direct interface at modeled depth|{why}|')
    print('\nUnresolved pairs require follow-up, not exclusion. Pairwise coverage is an **audit of knowledge**, not proof of transition completeness.\n')
    print('## Computed reachability and shortest counterexamples\n')
    for name,v in res['projections'].items():
        print(f'### {name}\n\nStates: {v["states"]}; edges: {v["transitions"]}; depth: {v["depth"]}; truncated: {v["truncated"]}.\n')
        for label,ce in v['counterexamples'].items():
            print(f'**{label}** (shortest depth {ce["depth"]}): ' + ' → '.join(ce['trace'])+f'. End state: `{ce["end"]}`.\n')
        if not v['counterexamples']:print('No modeled contract violation reached within this projection and bound.\n')
    print('## Model limitations\n')
    for x in res['limitations']:print('- '+x)

if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--depth',type=int,default=9)
    p.add_argument('--json',action='store_true')
    p.add_argument('--report',action='store_true')
    args=p.parse_args();r=run(args.depth)
    assert r['audited_ordered_pairs']==len(NODES)**2
    assert r['all_display_permutations']==576
    assert not r['projections']['workspace_guarded']['counterexamples']
    assert 'WRONG_SOURCE_ASSOCIATION' in r['projections']['workspace_original']['counterexamples']
    assert 'WRONG_XDC_ASSOCIATION' in r['projections']['workspace_original']['counterexamples']
    if args.report:report(r)
    elif args.json:print(json.dumps(r,indent=2))
    else:
        print(json.dumps({k:v for k,v in r.items() if k!='projections'},indent=2))
        for name,v in r['projections'].items():print(name,v['states'],v['transitions'],v['counterexamples'])
