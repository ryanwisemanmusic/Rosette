#!/usr/bin/env python3
"""Source-bound CPU-path comparisons and run telemetry, without FPS attribution."""
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys
from timing_inventory import parse
ROOT = Path(__file__).resolve().parents[2]
def comparisons(text):
    rows=[]
    for line in text.splitlines():
        if 'throughput kind=' not in line: continue
        data=line[line.index('throughput kind='):]
        rows.append({k:(v=='true' if v in ('true','false') else int(v) if v.isdigit() else v) for k,v in re.findall(r'(\w+)=(\S+)',data)})
    groups=[]
    cases=[('protection',64),('protection',4096),('same_page',None),('signal_index',None),('signal_clock',None),('log10',None),('rearrangement',False),('rearrangement',True)]
    for kind,variant in cases:
        samples=[r for r in rows if r['kind']==kind and (kind not in ('protection','rearrangement') or r['pages' if kind=='protection' else 'mixed']==variant)]
        assert len(samples)==14,(kind,variant,len(samples))
        a=[r for r in samples if not r['enabled']]; b=[r for r in samples if r['enabled']]
        assert {r['pair'] for r in a}=={r['pair'] for r in b}==set(range(7))
        ratios=[]
        for pair in range(7):
            x=next(r for r in a if r['pair']==pair);y=next(r for r in b if r['pair']==pair)
            assert x['operations']==y['operations'] and x['cpu_ns']>0 and y['cpu_ns']>0
            if kind=='log10':assert x['retired']==y['retired']==500001
            if kind=='rearrangement':assert x['retired']==y['retired']==9600000
            ratios.append(x['cpu_ns']/y['cpu_ns'])
        before=statistics.median(r['cpu_ns'] for r in a)/1e6;after=statistics.median(r['cpu_ns'] for r in b)/1e6
        names={'protection':f'Protection updates · {variant:,} pages' if kind=='protection' else '', 'same_page':'Same-page access classification', 'signal_index':'Signal ledger · 96 sites / mixed keys', 'signal_clock':'Complete producer-evidence notification', 'log10':'Complete translated log10 calls', 'rearrangement':'Native vector block · '+('mixed 12 forms' if variant else 'byte shuffles')}
        details={'protection':'2,048 alternating full-range restrictions. Same pages_changed and final protection counters. New packed-word stores retain the writer lock, atomic leaf words, epochs and reclamation.', 'same_page':'1,000,000 16-byte within-page classifications. Crossing/wrapping addresses keep both page checks. Same decisions; not a complete emulated load benchmark.', 'signal_index':'100,000 notifications, 96 ledger sites, 20% unmatched. First-key semantics, append/reset, counts and producer evidence checked. This overlaps the complete-notification profile.', 'signal_clock':'100,000 production notifications with the index enabled in both controls. Omits only the discarded clock snapshot/mutex; steps, caller evidence and guest clock unchanged. Uncontended fixture; live contention unmeasured.', 'log10':'100,000 real guest CALL/JIT/CRT/ABI operations, 500,001 identical retired instructions, no timed compilation. Same ordinary math implementation, FP semantics, TSO boundary and caller context.', 'rearrangement':'100,000 entries × 96 pure VEX.128 operations = 9.6 M identical retired instructions. Native on both sides, compilation excluded. Same registers, vectors, upper state and memory. Observer/helper/memory/legacy/wide boundaries retain publication.'}
        groups.append(dict(case=kind+str(variant),kind=kind,name=names[kind],before_ms=before,after_ms=after,ratio=before/after,saved_pct=100*(1-after/before),pair_ratio_min=min(ratios),pair_ratio_max=max(ratios),samples=samples,detail=details[kind]))
    assert len(rows)==112,len(rows)
    return groups

def supplemental(text):
    rows=[]
    for line in text.splitlines():
        if not line.startswith(('frozen_protection ', 'frozen_signal ', 'frozen_signal_distinct ')): continue
        rows.append(dict(kind=line.split()[0],**{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}))
    result=[]
    for pages in (1,4,16,32,64,4096,None,"distinct"):
        samples=[r for r in rows if (r.get('pages')==pages and r['kind']=='frozen_protection') or (pages is None and r['kind']=='frozen_signal') or (pages=='distinct' and r['kind']=='frozen_signal_distinct')]
        assert len(samples)==7 and {r['pair'] for r in samples}==set(range(7))
        before=statistics.median(r['before_ns'] for r in samples)/1e6;after=statistics.median(r['after_ns'] for r in samples)/1e6
        result.append(dict(name=f'Frozen-source protection · {pages:,} pages' if isinstance(pages,int) else 'Run-weighted signals · '+('distinct missing keys' if pages=='distinct' else 'repeated missing key'),pages=pages,before_ms=before,after_ms=after,ratio=before/after,operations=samples[0]['operations'],samples=samples))
    assert len(rows)==56
    return result

def generate(folder):
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    manifest=json.loads((folder/'manifest.json').read_text())
    for f,h in manifest['source_sha256'].items():assert sha(ROOT/f)==h,f
    for f,h in manifest['evidence_sha256'].items():assert sha(folder/f)==h,f
    groups=comparisons((folder/'bench-final.log').read_text()); controls=supplemental((folder/'supplemental-final.log').read_text()+'\n'+(folder/'supplemental-distinct-final.log').read_text())
    lines=(folder/'input.log').read_text().splitlines();inventory=parse(lines,ticks_per_ms=1000)
    pipeline=[];waits={};routes=[]
    for i,line in enumerate(lines,1):
        if 'VULKAN PIPELINE NATIVE CALL:' in line:
            row={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)};pipeline.append(dict(**row,line=i,raw=line))
        if 'PE64 WAIT LOOKUP:' in line:
            row={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)};waits[row['slot']]=row
        if 'Vulkan ABI route facts:' in line:routes.append(dict(line=i,raw=line))
    header='\n'.join(lines[:45]);wsi=[float(m[1]) for l in lines if (m:=re.search(r'presented_fps=([\d.]+)',l))]
    pipeline_summary=dict(calls=len(pipeline),elapsed_ms=sum(r['max_native_elapsed_ns'] for r in pipeline)/1e6,cpu_ms=sum(r['max_native_cpu_ns'] for r in pipeline)/1e6,rows=pipeline)
    evidence={key:[dict(line=i,raw=l) for i,l in enumerate(lines,1) if key in l][-6:] for key in ('xenia_gpu_render_settings =','xenia_config_preflight =','fsi_render_target_path:','Vulkan host time by entry point:','PE64 WAIT COST: sites=','PE64 BLOCK JIT WORKER THREAD: slot=23')}
    totals={key:sum(r[key] for r in waits.values()) for key in ('lookups','hits','scanned')}
    data=dict(groups=groups,controls=controls,inventory=inventory,pipeline=pipeline_summary,evidence=evidence,waits=totals,routes=routes,gates=manifest['gates'],delivery=manifest['delivery'],run=re.search(r'run_id\s*=\s*(\S+)',header)[1],build=re.search(r'build_identity_sha256\s*=\s*(\S+)',header)[1],wsi=wsi[-1])
    (folder/'bench-results.json').write_text(json.dumps(groups,indent=2));(folder/'supplemental-results.json').write_text(json.dumps(controls,indent=2));(folder/'timing-inventory.json').write_text(json.dumps(inventory,indent=2));(folder/'telemetry.json').write_text(json.dumps(dict(pipeline=pipeline_summary,waits=totals,routes=routes),indent=2))
    template=Path(__file__).with_name('cpu_throughput_report.html').read_text();(folder/'final').mkdir(exist_ok=True)
    (folder/'final/report.html').write_text(template.replace('__REPORT_DATA__',json.dumps(data).replace('</','<\\/')))
    print(json.dumps(dict(results=[{k:g[k] for k in ('name','before_ms','after_ms','ratio')} for g in groups],maxima=len(inventory['maxima']),pipeline=pipeline_summary|{'rows':'see telemetry.json'},waits=totals),indent=2))
if __name__=='__main__':generate(Path(sys.argv[1]))
