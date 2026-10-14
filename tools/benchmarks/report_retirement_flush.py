#!/usr/bin/env python3
"""Render source-bound recording-retirement and cache-invalidation CPU proofs."""
import argparse
import hashlib
import html
import importlib.util
import json
import re
import statistics
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def fields(line): return {k: v == 'true' if v in ('true','false') else int(v) for k,v in re.findall(r'\b(\w+)=(true|false|\d+)\b',line)}
def samples(p, markers):
    text=p.read_text()
    assert re.search(r'Build Summary: (\d+)/\1 steps succeeded',text)
    assert not any(int(n) for n in re.findall(r'(\d+) fail(?:ed)?\b',text))
    return [fields(line)|{'kind':line.split()[0]} for line in text.splitlines() if any(line.startswith(m+' ') for m in markers)]
def summarize(rows, key):
    out={}
    for r in rows: out.setdefault(key(r),[]).append(r)
    for name,rs in list(out.items()):
        assert len(rs)==14
        for pair in range(7): assert {r['enabled'] for r in rs if r['pair']==pair}=={False,True}
        med=lambda on: statistics.median(r['ns'] for r in rs if r['enabled']==on)
        b,a=med(False),med(True)
        ratios=[next(r['ns'] for r in rs if r['pair']==p and not r['enabled'])/next(r['ns'] for r in rs if r['pair']==p and r['enabled']) for p in range(7)]
        out[name]={'before_ns':b,'after_ns':a,'ratio':b/a,'pair_min':min(ratios),'pair_max':max(ratios),'checked':rs[0]['checked']}
    return out

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('evidence',type=Path);f=ap.parse_args().evidence.resolve()
    m=json.loads((f/'manifest.json').read_text())
    for p,h in m['sources'].items(): assert sha(ROOT/p)==h, 'Source changed: '+p
    for p,h in m['evidence'].items(): assert sha(f/p)==h, 'Evidence changed: '+p
    for p in ('focused-debug.log','focused-release.log'): assert '15/15 steps succeeded' in (f/p).read_text()
    recycle=samples(f/'recycle-final.log',('RECYCLE','RETIRE_RECORDING'));tlb=samples(f/'tlb-final.log',('TLB_FLUSH','TLB_FILL'))
    def rkey(r): return ('recording_' if r['kind']=='RETIRE_RECORDING' else 'lifecycle_')+str(r['entries'])
    def tkey(r): return ('fill_varied' if r['varied'] else 'fill_same') if r['kind']=='TLB_FILL' else f"range_{r['pages']}_{'saturated' if r['saturated'] else 'sparse'}"
    rs,ts=summarize(recycle,rkey),summarize(tlb,tkey)
    module=ROOT/'tools/benchmarks/report_worker_pressure.py';spec=importlib.util.spec_from_file_location('worker_report',module);old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
    runs={k:old.parse_run(record) for k,record in m['runs'].items()}
    for label,r in runs.items():
        lines=Path(m['runs'][label]['path']).read_text().splitlines()
        matches=[l for l in lines if 'PE64 BLOCK JIT TLB INVALIDATION WORK:' in l]
        r['historical_tlb_work']=max((fields(l) for l in matches),key=lambda x:x['range_calls'])
        r['host_stages']={}
        for line in lines:
            found=re.search(r'FRAME HOST COST: stage=(\w+)',line)
            if found:r['host_stages'][found[1]]=fields(line)
        r['live_retirement']=None;r['live_recycling']=None
        for line in lines:
            if 'VULKAN FSI RECORDING RETIREMENT:' in line:r['live_retirement']=fields(line)
            if 'VULKAN FSI RECYCLING WORK:' in line:r['live_recycling']=fields(line)
    result={'recycle_samples':recycle,'tlb_samples':tlb,'recycle_summary':rs,'tlb_summary':ts,'runs':runs}
    (f/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    labels={'lifecycle_32':'32-buffer lifecycle · 1,000 batches','lifecycle_2509':'2,509-buffer lifecycle · 20 batches','lifecycle_4095':'4,095-buffer lifecycle · 20 batches','recording_2509':'Release and full recording clear · 40 batches','range_1_sparse':'1 page · 1 of 16 tables admitted','range_64_sparse':'64 pages · 1 of 16 tables admitted','range_512_sparse':'512 pages · 1 of 16 tables admitted','range_512_saturated':'512 pages · saturated filter control','range_1024_saturated':'1,024 pages · full-flush control','fill_same':'200,000 fills · same region','fill_varied':'200,000 fills · varying regions'}
    def table(summary): return ''.join(f'<tr><td>{labels[k]}</td><td>{v["before_ns"]/1e6:.3f}</td><td>{v["after_ns"]/1e6:.3f}</td><td>{v["ratio"]:.2f}×</td><td>{v["pair_min"]:.2f}–{v["pair_max"]:.2f}×</td></tr>' for k,v in summary.items())
    run_rows=''.join(f'<tr><td>{k}</td><td>{r["policy"]["room_wait_ms"]/1000:.3f}</td><td>{r["queue"]["total_us"]/1e6:.3f}</td><td>{r["historical_tlb_work"]["range_calls"]:,}</td><td>{r["historical_tlb_work"]["tag_slots_touched"]:,}</td><td>{r["live_yield_backoff"]["parks"]:,}</td></tr>' for k,r in runs.items())
    plot=[[labels[k],v['before_ns']/1e6,v['after_ns']/1e6] for k,v in (rs|ts).items()]
    buttons=''.join(f'<button data-case="{i}">{html.escape(r[0])}</button>' for i,r in enumerate(plot))
    page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rosette · Recording retirement and cache flush work</title><style>
body{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}main{max-width:1170px;margin:auto;padding:36px}h1{font-size:38px;line-height:1.2}h2{margin-top:36px}p{color:#bfccda}a{color:#8bdacf}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.card{background:#1b2838;padding:22px;border-radius:14px}.value{font-size:37px;color:#8bdacf;font-weight:750}.note{border-left:4px solid #8bdacf;background:#172230;padding:16px 22px}.scroll{overflow:auto}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}td,th{padding:10px;text-align:right;border-bottom:1px solid #304153}td:first-child,th:first-child{text-align:left}button{border:1px solid #455d73;border-radius:8px;background:#22374c;color:#e5edf7;padding:9px 12px;margin:4px;cursor:pointer}button[aria-pressed=true]{border-color:#8bdacf;background:#315653}code{color:#a9dacb}svg{width:100%;background:#162332;border-radius:10px}@media(max-width:780px){main{padding:20px}.cards{grid-template-columns:1fr}h1{font-size:30px}}
</style><main><h1>Rosette recording retirement &amp; cache flush work</h1><p>Round 55 · source-only performance pass · CPU measurements with preserved resource custody</p><div class="note">Full suite, shell update and installation remain deferred. These ratios describe checked CPU paths, not FPS multipliers. No Xenia launch or GPU dispatch.</div>
<div class="cards"><div class="card"><div class="value">RETIRE_RATIO×</div>faster full recording retirement fixture</div><div class="card"><div class="value">POOL_RATIO×</div>faster 2,509-buffer lifecycle fixture</div><div class="card"><div class="value">TLB_RATIO×</div>faster sparse 512-page invalidation fixture</div></div>
<h2 id="retirement">Frame disposal: release bookkeeping was repeatedly scanning the pool</h2><p>The supplied runs retained 2,265 and 2,509 continuation buffers. Acquisition, submit stamping and release each searched from the beginning of the pool. Releasing a large recording repeatedly scanned the same entries, giving quadratic work.</p><p>The pool now uses a fixed handle index and two-level availability bitmap. Ascending bit order preserves the original lowest-ready choice. Release still waits for the last submission serial to complete; poisoned buffers remain quarantined. This is host bookkeeping around frame retirement, not a change to GPU completion requirements.</p><p>Seven alternating comparisons against the frozen pre-pass implementation. The complete release plus recording clear for 2,509 chunks took RETIRE_BEFORE → RETIRE_AFTER ms per recording. The original full clear remains. Twenty thousand randomized custody transitions, zero/duplicate/absent handles, capacity exhaustion and incomplete serials match the old entries and results.</p><div class="scroll"><table><tr><th>CPU fixture</th><th>Before ms</th><th>After ms</th><th>Speed ratio</th><th>Pair range</th></tr>RECYCLE_TABLE</table></div>
<h2 id="flushes">Avoid scans in worker caches that never admitted the region</h2><p>Narrow mapping/protection invalidations currently visit every executor’s cache. The new monotonic region summary can reject read or write directions that have no possible member. Collisions and stale bits cause extra scans; they cannot authorize stale memory access. The summary publishes before the tag, and the original global epoch and raced-fill retirement remain.</p><p>Read/write probe-array offsets, tag/delta layout, page hashing, admission rules and emitted probes are unchanged. Wide invalidations keep their full flush. Summary bits persist until the whole table is safely reinitialized; an owner hint avoids atomic metadata work for repeated fills in the same region.</p><p>Seven alternating pairs over 16 real cache tables. Sparse cases have one affected table; saturated controls deliberately remove the filtering advantage. All tags and deltas match the frozen implementation across random fills, range boundaries, high addresses, direction changes and overflow. Concurrent publication/recheck, real native protection faults, write watch, mapped aliases and message passing pass focused checks.</p><div class="scroll"><table><tr><th>CPU fixture</th><th>Before ms</th><th>After ms</th><th>Speed ratio</th><th>Pair range</th></tr>TLB_TABLE</table></div><p>Fill controls disclose the metadata cost: ratios below 1 mean slower. These are hot fill fixtures, not complete memory-helper timings. The live summary may become saturated over a long session and lose filtering benefit; the next run’s skipped-direction count measures actual usefulness.</p><div>BUTTONS</div><svg id="comparison" viewBox="0 0 850 165" role="img" aria-label="Selected retirement or invalidation CPU comparison"></svg>
<h2 id="runs">What your new logs establish</h2><div class="scroll"><table><tr><th>Run</th><th>Room wait s</th><th>Queue host s</th><th>Range invalidations</th><th>Old modeled tag visits</th><th>Backoff parks</th></tr>RUN_ROWS</table></div><p>Run 1 = dfbb069b2569; run 2 = 7a387d5d4479. Room wait is included in queue-submit host time and is not GPU execution time. Camera/scene labels are unmatched; the supplied logs cannot isolate a causal FPS change.</p><p>The previous backoff barely qualified: 436/440 parks among roughly 55/47 million explicit yields, only 202/206 ms of total host waiting. Its idle CPU fixture gains therefore did not imply a large live benefit. Shader-lock release was active, but most module host time now lies outside the released native callback: CPU transformations and bookkeeping remain possible hitch sources.</p><p>The old invalidation counter modeled both read and write directions, including one-direction requests. The new <code>tag_slots_touched</code> measures actual tag-slot visits and <code>membership_skipped_directions</code> reports skipped directions. Historical and new counts have different definitions.</p><p>Shadow upload and direct WSI/present-completion stages are small in these logs. Native queue-room waits remain substantial and campaign still records a risk event. Watchdog budgets, depth two, tessellation isolation, shader bounds, TSO, audio, Fast Path and the 30 FPS ceiling are retained.</p>
<h2>Next-run evidence and delivery</h2><p>STATUS</p><p>New live panels are ready to read <code>VULKAN FSI RECORDING RETIREMENT</code> (total/max host release-and-clear time) and <code>VULKAN FSI RECYCLING WORK</code> (candidate checks and hash probes). Neither marker is present in the supplied pre-change logs, so live retirement cost remains unmeasured. No special game flags are required after your other agent runs the full gates and installs this source.</p><p><a href="../results.json">All 154 measured samples and line-numbered run evidence</a> · <a href="../manifest.json">Source, binary, command and log identities</a> · <a href="../recycle-final.log">Retirement raw samples</a> · <a href="../tlb-final.log">Cache raw samples</a> · <a href="../focused-debug.log">Debug focused checks</a> · <a href="../focused-release.log">ReleaseFast focused checks</a> · <a href="../source-size.log">Size audit</a> · <a href="../reference-equivalence.log">Frozen-reference extraction proof</a></p></main>
<script>const rows=PLOT;function show(i){const [name,b,a]=rows[i],scale=520/Math.max(b,a);document.getElementById('comparison').innerHTML=`<text x="20" y="28" fill="#e5edf7">${name}</text><text x="20" y="75" fill="#bfccda">Before</text><rect x="110" y="53" width="${b*scale}" height="30" fill="#75899f"/><text x="${120+b*scale}" y="75" fill="#e5edf7">${b.toFixed(3)} ms</text><text x="20" y="125" fill="#bfccda">After</text><rect x="110" y="103" width="${a*scale}" height="30" fill="#8bdacf"/><text x="${120+a*scale}" y="125" fill="#e5edf7">${a.toFixed(3)} ms</text>`;document.querySelectorAll('[data-case]').forEach(x=>x.setAttribute('aria-pressed',+x.dataset.case===i))}document.querySelectorAll('[data-case]').forEach(x=>x.onclick=()=>show(+x.dataset.case));show(3);</script></html>'''
    replacements={'RETIRE_RATIO':f'{rs["recording_2509"]["ratio"]:.1f}','POOL_RATIO':f'{rs["lifecycle_2509"]["ratio"]:.1f}','TLB_RATIO':f'{ts["range_512_sparse"]["ratio"]:.1f}','RETIRE_BEFORE':f'{rs["recording_2509"]["before_ns"]/40/1e6:.3f}','RETIRE_AFTER':f'{rs["recording_2509"]["after_ns"]/40/1e6:.3f}','RECYCLE_TABLE':table(rs),'TLB_TABLE':table(ts),'RUN_ROWS':run_rows,'BUTTONS':buttons,'PLOT':json.dumps(plot),'STATUS':html.escape(m['status'])}
    for key in sorted(replacements,key=len,reverse=True):page=page.replace(key,replacements[key])
    (f/'final').mkdir(exist_ok=True);(f/'final/report.html').write_text(page)
    print(json.dumps({k:round(v['ratio'],3) for k,v in (rs|ts).items()}))
if __name__=='__main__':main()
