#!/usr/bin/env python3
"""Source-bound atomic CPU proofs, a log timing inventory and explicit FPS scenarios."""
import argparse, hashlib, html, json, re, statistics
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def pairs(text):
    rows=[]
    for l in text.splitlines():
        if not any(k in l for k in ('atomic_workers op=', 'atomic_compare enabled=', 'atomic_admission pair=')): continue
        row={k: (v=='true' if v in ('true','false') else int(v) if v.isdigit() else v) for k,v in re.findall(r'(\w+)=(\S+)',l)}
        row['kind']='workers' if 'atomic_workers' in l else 'compare' if 'atomic_compare' in l else 'admission'
        rows.append(row)
    groups=[]
    def key(r): return (r['kind'],r.get('op',''),r.get('threads',''),r.get('success',''))
    for k in sorted({key(r) for r in rows},key=str):
        g=[r for r in rows if key(r)==k]
        b=[r for r in g if not r['enabled']];a=[r for r in g if r['enabled']]
        for v in (a,b): assert len(v)==7 and {r['pair'] for r in v}==set(range(7)),k
        for p in range(7):
            x=next(r for r in b if r['pair']==p);y=next(r for r in a if r['pair']==p)
            assert x['operations']==y['operations'] and x['retired']==y['retired']
            if k[0]=='admission': assert x['fallbacks']==x['operations'] and y['fallbacks']==1
        old=statistics.median(r['cpu_ns'] for r in b);new=statistics.median(r['cpu_ns'] for r in a)
        name=(f"{k[1]} · {k[2]} workers" if k[0]=='workers' else f"CAS {'success' if k[3] else 'retry'} · disabled experiment" if k[0]=='compare' else 'Failed CAS · writable admission')
        groups.append(dict(name=name,kind=k[0],before_ns=old,after_ns=new,ratio=old/new,saved_pct=100*(1-new/old),samples=g,
                           wall_before_ns=statistics.median(r.get('elapsed_ns',r['cpu_ns']) for r in b),wall_after_ns=statistics.median(r.get('elapsed_ns',r['cpu_ns']) for r in a)))
    assert len(groups)==9 and len(rows)==126,(len(groups),len(rows))
    return groups

def logdata(p):
    ls=p.read_text().splitlines(); rows=[]; refs=[]
    def last(key):
        a=[(i+1,l) for i,l in enumerate(ls) if key in l];return a[-1] if a else (0,'')
    def add(label,kind,line,total,maxval=None,calls=None):
        rows.append(dict(label=label,kind=kind,line=line,total_ms=total,max_ms=maxval,calls=calls))
    for key,prefix in [('FRAME HOST COST: stage=','Frame / '),('VULKAN SHADER HOST STAGE: stage=','Shader / ')]:
        stages={}
        for i,l in enumerate(ls):
            if key not in l:continue
            d=dict(re.findall(r'(\w+)=(\d+|[a-z_]+)',l));stages[d['stage']]=(i+1,d,l)
        for stage,(i,d,l) in stages.items():
            add(prefix+stage,'elapsed',i,int(d['total_us'])/1000,int(d['max_us'])/1000,int(d['calls']));refs.append(dict(line=i,text=l))
    i,l=last('VULKAN FSI RECORDING RETIREMENT:');d=dict(re.findall(r'(\w+)=(\d+)',l))
    if d: add('Continuation retirement','elapsed',i,int(d['total_us'])/1000,int(d['max_us'])/1000,int(d['calls']));refs.append(dict(line=i,text=l))
    for key,prefix in [('PE64 BLOCK JIT FALLBACK OPS:','Owner fallback / '),('PE64 BLOCK JIT WORKER FALLBACK OPS:','Workers fallback / ')]:
        i,l=last(key)
        for op,calls,ns,n in re.findall(r'(\w+)=(\d+)\([^)]*?estimated_ns=(\d+),samples=(\d+)\)',l): add(prefix+op,'estimate',i,int(ns)/1e6 if int(n) else None,calls=int(calls))
        refs.append(dict(line=i,text=l))
    imports={}
    for i,l in enumerate(ls):
        if 'PE64 IMPORT HISTOGRAM:' not in l:continue
        m=re.search(r'import=(\S+) calls=(\d+).*mean_ns=(\d+) estimated_ms=(\d+)',l)
        if m: imports[m[1]]=(i+1,m)
    for name,(i,m) in imports.items(): add('Import / '+name,'estimate',i,int(m[4]),calls=int(m[2]))
    # True CPU counters are present only after this source is installed.
    cpus={}
    for i,l in enumerate(ls):
        if 'PE64 WORKER HOST CPU:' in l:
            m=re.search(r"slot=(\d+).*name='([^']*)' cpu_us=(\d+) elapsed_us=(\d+)",l)
            if m: cpus[m[1]]=(i+1,m)
    for slot,(i,m) in cpus.items(): add('Host worker / '+m[2],'cpu',i,int(m[3])/1000)
    # Work shares are displayed separately; they are not CPU-time shares.
    work=[]
    for i,l in enumerate(ls):
        if 'PE64 FRAME COST:   thread=' in l:
            m=re.search(r"thread='([^']+)'.*instructions_since_first_swap=(\d+) share=(\d+)% per_swap=(\d+)",l)
            if m: work.append(dict(name=m[1],instructions=int(m[2]),share=int(m[3]),per_swap=int(m[4]),line=i+1))
    hotspot=[]
    for i,l in enumerate(ls):
        if 'PE64 CPU HOTSPOT:' not in l or "name='XThread002" not in l or 'region=0x14035ce00' not in l: continue
        m=re.search(r"name='([^']+)'.*samples=(\d+) count_lower/upper=(\d+)/(\d+)",l)
        if m: hotspot.append(dict(name=m[1],samples=int(m[2]),lower=int(m[3]),upper=int(m[4]),line=i+1))
    i,frame=last('PE64 FRAME COST: swaps=');i2,wsi=last('FRAME HUD RATE:');m=re.search(r'presented_fps=([\d.]+)',wsi)
    owner=last('PE64 BLOCK JIT FALLBACK LEDGER:');workers=last('PE64 BLOCK JIT WORKER FALLBACK LEDGER:')
    def estimate(row):
        m=re.search(r'estimated_interpreter_ns=(\d+)',row[1]);return int(m[1])/1e9 if m else None
    for key in ['VULKAN FSI GUARD: armed=', 'VULKAN FSI GUARD:   ','PE64 PAUSE BACKOFF:', 'Vulkan device lost:', 'FRAME HOST COST: present_intervals=']:
        ix,l=last(key);refs.append(dict(line=ix,text=l))
    header='\n'.join(ls[:70]);duration=re.search(r'elapsed_seconds\s*=\s*(\d+)',header)
    return dict(path=str(p),sha256=sha(p),run_id=re.search(r'run_id\s*=\s*(\S+)',header)[1],build=re.search(r'build_identity_sha256\s*=\s*(\S+)',header)[1],
                scenario='unspecified',fps=float(m[1]) if m else None,timings=rows,work=work,hotspots=hotspot[-2:],refs=refs,
                owner_estimate_s=estimate(owner),worker_estimate_s=estimate(workers),frame=frame,device_loss=bool(last('Vulkan device lost:')[1]))

def generate(folder,inputs):
    manifest=json.loads((folder/'manifest.json').read_text())
    for filename,digest in manifest['source_sha256'].items(): assert sha(ROOT/filename)==digest,filename
    for filename,digest in manifest['evidence_sha256'].items(): assert sha(folder/filename)==digest,filename
    text=(folder/'atomic-bench-final.log').read_text(); assert 'All ' in text and 'tests passed.' in text
    groups=pairs(text);runs=[logdata(p) for p in inputs]
    for r in runs: assert manifest['inputs'][r['path']]==r['sha256']
    (folder/'bench-results.json').write_text(json.dumps(groups,indent=2))
    (folder/'run-analysis.json').write_text(json.dumps(runs,indent=2))
    e=html.escape
    table=''.join(f'<tr><td>{e(g["name"])}</td><td>{g["before_ns"]/1e6:.3f}</td><td>{g["after_ns"]/1e6:.3f}</td><td>{g["ratio"]:.3f}×</td><td>{g["saved_pct"]:.1f}%</td><td>{g["wall_before_ns"]/1e6:.3f} → {g["wall_after_ns"]/1e6:.3f}</td></tr>' for g in groups)
    runrows=''.join(f'<tr><td>{e(r["run_id"])}</td><td>{r["fps"]}</td><td>{r["owner_estimate_s"]:.3f}s</td><td>{r["worker_estimate_s"]:.3f}s</td><td>{"reported" if r["device_loss"] else "none logged"}</td></tr>' for r in runs)
    refs=''.join(f'<details><summary>{e(r["run_id"])} · source lines</summary>'+''.join(f'<p class="small"><b>Line {x["line"]}</b> <code>{e(x["text"])}</code></p>' for x in r['refs'] if x['line'])+'</details>' for r in runs)
    page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rosette · Atomic throughput and timing map</title>
<style>:root{color-scheme:dark;font-family:system-ui;background:#0f1620;color:#e7eef8}body{margin:0}main{max-width:1200px;margin:auto;padding:30px 24px 65px}h1{font-size:clamp(30px,5vw,45px);margin-bottom:10px}h2{margin-top:38px}p,li{line-height:1.55;color:#b5c5d7}a{color:#88ddcf}nav{display:flex;gap:18px;flex-wrap:wrap}.badge{display:inline-block;padding:6px 10px;border:1px solid #715f3c;border-radius:7px;color:#ebc981;font-size:13px}.panel,.card{border:1px solid #2b3d50;border-radius:14px;padding:20px;background:#192535;margin-top:20px}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}.value{color:#89dbcb;font-size:36px;font-weight:700}.note{border-left:4px solid #ebc981;padding:12px 16px;background:#1c232d}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{padding:10px;text-align:left;border-bottom:1px solid #304052;white-space:nowrap}th{color:#89dbcb;font-size:13px}td:first-child{white-space:normal}code{overflow-wrap:anywhere}.small{font-size:13px}button,select,input{background:#22364c;color:#e7eef8;border:1px solid #4e627a;border-radius:6px;padding:8px;margin:6px 10px 6px 0}input[type=range]{width:220px}button[aria-pressed=true]{border-color:#89dbcb}svg{width:100%;background:#131e2b}label{display:inline-block;margin:10px 20px 10px 0}.bar{height:10px;border-radius:8px;background:#83cabb}.muted{color:#a6b6c9}@media(max-width:720px){main{padding:22px 16px}.cards{grid-template-columns:1fr}.value{font-size:32px}}</style>
<main><span class="badge">SOURCE ONLY · full gates and installation pending</span><h1>Atomic throughput and timing map</h1><p>October 14, 2026 · equivalent CPU work · seven alternating pairs per case · no Xenia or GPU workload launched.</p>
<nav><a href="#measurements">Offline results</a><a href="#inventory">Timing inventory</a><a href="#forecast">FPS scenarios</a><a href="#next">Next run</a></nav>
<div class="cards">CARDS</div>
<p class="note">The owner-only fallback estimate misses the workers. Both scopes are included below. Sampled host elapsed time, CPU time, guest instruction counts and GPU completion latency answer different questions; they cannot be added into a frame budget.</p>
<h2>What the new logs establish</h2><div class="scroll"><table><tr><th>Run · scenario unspecified</th><th>Latest WSI FPS</th><th>Owner fallback estimate</th><th>Workers fallback estimate</th><th>Device loss near end</th></tr>RUNROWS</table></div>
<p>Translated PAUSE and registered import tails are active. The repeat lock-acquisition region is still a candidate; its samples count guest instruction locations, not host CPU milliseconds. The existing GPU budgets, ordering fences, bounds protection, audio, Fast Path and 30 FPS ceiling are retained.</p>
<h2 id="measurements">Faster equivalent atomic work</h2><p>CAS flag fusion remains disabled by default after mixed retry results; its two rows are experimental, not live gains. Counter cases execute actual emitted production ARM64 templates, with private guest state and shared atomic data. All counters, per-worker checksums and retired counts are checked. Compilation, thread setup and warm-up are outside the timed interval. CPU totals sum the participating host threads. The admission test runs the production process and interpreter with JIT enabled in both variants.</p>
<div class="scroll"><table><tr><th>Case</th><th>Before CPU ms</th><th>After CPU ms</th><th>Ratio</th><th>CPU saved</th><th>Elapsed ms before → after</th></tr>TABLE</table></div>
<div class="panel"><label>Raw comparison <select id="case"></select></label><svg id="chart" viewBox="0 0 900 150" role="img" aria-label="Measured CPU time before and after"></svg><p id="comparison"></p><div class="scroll"><table id="pairs"></table></div></div>
<h2 id="inventory">Inventory of logged timing scopes</h2><p>Every frame-host stage, shader-host stage, listed fallback operation and import timing estimate available in these logs is mapped here. The latest available row per named scope replaces earlier rows. Some imports leave ranked lists, so their last observed value can precede the final snapshot. This is a timing inventory, not a complete profiler or a measured dependency timeline. Missing CPU and GPU timings stay unknown. Long imports can include waits.</p>
<div class="panel"><label>Run <select id="run"></select></label><label>Scope <select id="kind"><option value="all">All logged scopes</option><option value="elapsed">Measured host elapsed</option><option value="estimate">Sampled host estimates</option><option value="cpu">Actual thread CPU</option></select></label><p id="coverage"></p><div class="scroll"><table id="timings"></table></div><h3>Worker instruction work · not CPU time</h3><div class="scroll"><table id="work"></table></div></div>
<h2 id="forecast">FPS scenarios with an explicit unknown</h2><p>Amdahl model: <code>FPS′ = min(30, FPS ÷ ((1 − f) + f ÷ r))</code>. <code>f</code> is the fraction of the frame's serial critical path affected; <code>r</code> is a selected offline path ratio. Neither CPU shares nor a count-weighted elapsed estimate establishes <code>f</code>. These are conditional scenarios, not calibrated predictions. Dependencies, GPU work and scheduler pressure can change the outcome.</p>
<div class="panel"><label>Baseline FPS <input type="number" id="fps" min="0.1" max="30" step="0.1" value="0.8"></label><label>Measured path <select id="speed"></select></label><label>Assumed critical fraction <input id="fraction" type="range" min="0" max="100" value="10"><span id="fraction-label"></span></label><p class="value" id="prediction"></p><p id="required"></p><p class="small">A frame at 0.8 FPS takes 1,250 ms; 4 FPS requires 250 ms. A modest optimization of a small share cannot remove the required 1,000 ms. This pass does not promise a 4–5 FPS floor or locked 30 FPS by the end of the week.</p></div>
<h2 id="next">Make the next ordinary run more informative</h2><p>New <code>PE64 WORKER HOST CPU</code> rows report actual host thread CPU separately from elapsed lifetime. They sample only at existing five-second progress boundaries and exit; no per-instruction timer is added. CPU includes this worker's compute and kernel CPU; it excludes parked/off-core time. It does not identify useful guest work or GPU time. Completed workers are included; the UI owner and native library worker threads remain unmeasured.</p>
<p><code>PE64 ATOMIC COMPARE ADMISSION</code> counts successful and refused writable proofs after failed comparisons. Protected, watched, executable, unbacked and invalidated pages retain guards. The optimization performs the same compare-exchange; it removes repeated interpreter trips after a safe page has been proved.</p>
<p>Focused checks: GATES. Full Zig tests, bare root <code>make shell-update</code>, installation and a matched Halo run are pending. Source hashes are checked before the report is generated. Offline ratios are not game FPS multipliers.</p>
<details><summary>Evidence and exact log lines</summary><p><a href="../manifest.json">Manifest</a> · <a href="../atomic-bench-final.log">Raw offline output</a> · <a href="../bench-results.json">Parsed comparisons</a> · <a href="../run-analysis.json">Timing inventory</a> · <a href="../focused-debug-final.log">Focused Debug</a> · <a href="../focused-release-final.log">Focused ReleaseFast</a></p>REFS</details></main>
<script>
const groups=GROUPS,runs=RUNS,$=id=>document.getElementById(id),ms=n=>(n/1e6).toFixed(3),escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
for(let i=0;i<groups.length;i++){$('case').add(new Option(groups[i].name,i));if(groups[i].kind!=='compare')$('speed').add(new Option(groups[i].name,i));}
function compare(){const g=groups[$('case').value],max=Math.max(g.before_ns,g.after_ns);$('chart').innerHTML=`<text x="20" y="35" fill="#ccd8e7">Before ${ms(g.before_ns)} ms</text><rect x="20" y="45" width="${800*g.before_ns/max}" height="25" fill="#b5c6dd"/><text x="20" y="100" fill="#ccd8e7">After ${ms(g.after_ns)} ms</text><rect x="20" y="110" width="${800*g.after_ns/max}" height="25" fill="#89dbcb"/>`;$('comparison').textContent=`${g.ratio.toFixed(3)}× path ratio; ${g.saved_pct.toFixed(1)}% CPU saved. Seven alternating pairs; equivalent retired operations. This is not an FPS ratio.`;$('pairs').innerHTML='<tr><th>Pair</th><th>Before CPU ms</th><th>After CPU ms</th><th>Ratio</th></tr>'+Array.from({length:7},(_,p)=>{const b=g.samples.find(r=>r.pair===p&&!r.enabled),a=g.samples.find(r=>r.pair===p&&r.enabled);return `<tr><td>${p+1}</td><td>${ms(b.cpu_ns)}</td><td>${ms(a.cpu_ns)}</td><td>${(b.cpu_ns/a.cpu_ns).toFixed(3)}×</td></tr>`}).join('');}
for(let i=0;i<runs.length;i++)$('run').add(new Option(runs[i].run_id,i));
function inventory(){const r=runs[$('run').value],k=$('kind').value,rows=r.timings.filter(x=>k==='all'||x.kind===k).sort((a,b)=>(b.total_ms??-1)-(a.total_ms??-1));$('coverage').textContent=`${rows.length} logged scopes shown. Actual thread CPU rows: ${r.timings.filter(x=>x.kind==='cpu').length}. GPU execution time: unknown. Timings overlap; do not sum.`;$('timings').innerHTML='<tr><th>Process / stage</th><th>Basis</th><th>Cumulative ms</th><th>Max ms</th><th>Calls</th><th>Log line</th></tr>'+rows.map(x=>`<tr><td>${escape(x.label)}</td><td>${escape(x.kind)}</td><td>${x.total_ms==null?'unknown':x.total_ms.toFixed(3)}</td><td>${x.max_ms==null?'unknown':x.max_ms.toFixed(3)}</td><td>${x.calls==null?'unknown':x.calls.toLocaleString()}</td><td>${x.line}</td></tr>`).join('');$('work').innerHTML='<tr><th>Worker</th><th>Guest instruction share</th><th>Per lifetime present</th><th>Host CPU ms</th></tr>'+r.work.map(x=>`<tr><td>${escape(x.name)}</td><td>${x.share}%</td><td>${x.per_swap.toLocaleString()}</td><td>unknown</td></tr>`).join('');}
function predict(){const base=Math.max(.1,Math.min(30,+$('fps').value||.8)),r=groups[$('speed').value].ratio,f=+$('fraction').value/100,mult=1/(1-f+f/r);$('fraction-label').textContent=(100*f).toFixed(0)+'%';$('prediction').textContent=`Conditional ${Math.min(30,base*mult).toFixed(2)} FPS · ${mult.toFixed(2)}×`;$('required').textContent=[1.5,2].map(target=>{const need=(1-1/target)/(1-1/r);return need>1||r<=1?`${target}× frame gain cannot follow from this one measured ratio alone.`:`${target}× frame gain needs at least ${(need*100).toFixed(1)}% of the critical path affected.`}).join(' ');}
$('case').onchange=compare;$('run').onchange=inventory;$('kind').onchange=inventory;for(const id of ['fps','speed','fraction'])$(id).oninput=predict;compare();inventory();predict();
</script></html>'''
    lead=next(g for g in groups if g['kind']=='admission');shared=max((g for g in groups if g['kind']=='workers' and '4 workers' in g['name']),key=lambda g:g['ratio'])
    cards=f'<div class="card"><div class="value">{lead["ratio"]:.2f}×</div><p>Failed-CAS production path<br>same comparisons and retired work</p></div><div class="card"><div class="value">{shared["ratio"]:.2f}×</div><p>Shared counter CPU throughput<br>four actual translated workers</p></div><div class="card"><div class="value">126</div><p>Measured samples<br>nine cases · seven paired comparisons</p></div>'
    payload=json.dumps(groups).replace('</','<\\/');rp=json.dumps(runs).replace('</','<\\/')
    for key,value in [('CARDS',cards),('RUNROWS',runrows),('TABLE',table),('REFS',refs),('GROUPS',payload),('RUNS',rp),('GATES',manifest['gates'])]:page=page.replace(key,value)
    (folder/'final').mkdir(exist_ok=True);(folder/'final/report.html').write_text(page)
    print(json.dumps([dict(name=g['name'],ratio=g['ratio'],before_ms=g['before_ns']/1e6,after_ms=g['after_ns']/1e6) for g in groups],indent=2))
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('folder',type=Path);ap.add_argument('inputs',type=Path,nargs='+');args=ap.parse_args();generate(args.folder,args.inputs)
