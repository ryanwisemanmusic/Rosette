#!/usr/bin/env python3
"""Source-bound CPU evidence for bounded trace admission and import-tail routing."""
import argparse
import hashlib
import html
import json
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse(folder):
    rows = []
    for filename, kinds in [('register-bench-final.log', ['register_tail', 'register_threads']),
                            ('pause-bench-final.log', ['pause_trace', 'pause_workers'])]:
        text = (folder / filename).read_text()
        assert '0 failed' in text or 'All 23 tests passed.' in text
        for match in re.finditer(r'\b(' + '|'.join(kinds) + r') (.*)', text):
            row = {'kind': match[1]}
            for key, value in re.findall(r'(\w+)=(\S+)', match[2]):
                row[key] = value == 'true' if value in ('true', 'false') else int(value) if value.isdigit() else value
            rows.append(row)
    assert len(rows) == 182, f'{len(rows)}/182 measurements'
    summaries = []
    for kind in ('register_tail', 'register_threads', 'pause_trace', 'pause_workers'):
        def case(r):
            if kind == 'register_tail':
                return r['name']
            if kind == 'pause_trace':
                return f"{r['bundle']} hints, host yield {r['host_yield']}"
            return r.get('mode', 'four workers with host yields')
        for key in sorted({case(r) for r in rows if r['kind'] == kind}):
            group = [r for r in rows if r['kind'] == kind and case(r) == key]
            before = [r for r in group if not r['enabled']]
            after = [r for r in group if r['enabled']]
            for variant in (before, after):
                assert len(variant) == 7 and {r['pair'] for r in variant} == set(range(7))
            metric = 'cpu_ns' if kind in ('register_threads', 'pause_workers') else 'elapsed_ns'
            b = statistics.median(r[metric] for r in before)
            a = statistics.median(r[metric] for r in after)
            summary = {'kind': kind, 'case': key, 'metric': metric, 'before_ns': b, 'after_ns': a,
                       'ratio': b / a, 'saved_percent': (1 - a / b) * 100, 'samples': group}
            for pair in range(7):
                old = next(r for r in before if r['pair'] == pair)
                new = next(r for r in after if r['pair'] == pair)
                fields = ('hints', 'retired', 'yields') if kind == 'pause_trace' else ('calls', 'yields') if kind == 'register_tail' else ('calls', 'actual_host_yields') if kind == 'register_threads' else ('handoffs',)
                for field in fields:
                    assert old[field] == new[field], (kind, key, pair, field)
            if kind in ('pause_workers', 'register_threads'):
                assert all(r['cpu_ns'] <= r['elapsed_ns'] * 4 + 5_000_000 for r in group)
                summary.update(wall_before_ns=statistics.median(r['elapsed_ns'] for r in before),
                               wall_after_ns=statistics.median(r['elapsed_ns'] for r in after))
            if kind == 'pause_workers':
                summary.update(p95_before_ns=statistics.median(r['p95_ns'] for r in before),
                               p95_after_ns=statistics.median(r['p95_ns'] for r in after),
                               max_after_ns=max(r['max_ns'] for r in after),
                               max_host_wait_ns=max(r['max_wait_ns'] for r in after),
                               parks=sum(r['parks'] for r in after))
                if key in ('productive', 'vector', 'short'):
                    assert all(r['parks'] == 0 for r in group)
            summaries.append(summary)
    result = {'summaries': summaries, 'samples': rows}
    (folder / 'bench-results.json').write_text(json.dumps(result, indent=2))
    return result


def render(folder, data):
    manifest = json.loads((folder / 'manifest.json').read_text())
    for name, digest in manifest['sources'].items():
        assert sha(ROOT / name) == digest, 'Source changed: ' + name
    for name, digest in manifest['evidence'].items():
        assert sha(folder / name) == digest, 'Evidence changed: ' + name
    runs = json.loads((folder / 'run-analysis.json').read_text())
    for run in runs:
        assert sha(Path(run['path'])) == run['sha256']
    for gate in ('focused-debug.log', 'focused-release.log'):
        assert '15/15 steps succeeded; 138/150 tests passed (12 skipped)' in (folder / gate).read_text()
    groups = data['summaries']
    esc = html.escape
    tables = []
    for kind, title in [('register_tail', '100,000 imported calls'), ('register_threads', 'Four bound workers · real host yields'),
                        ('pause_trace', 'PAUSE traces · closed memory-write trace'), ('pause_workers', 'Four translated pollers · actual thread CPU')]:
        body = ''
        for r in groups:
            if r['kind'] == kind:
                body += f'<tr><td>{esc(r["case"])}</td><td>{r["before_ns"]/1e6:.3f}</td><td>{r["after_ns"]/1e6:.3f}</td><td>{r["ratio"]:.3f}×</td><td>{r["saved_percent"]:.1f}%</td></tr>'
        tables.append(f'<h3>{title}</h3><div class="scroll"><table><thead><tr><th>Case</th><th>Before ms</th><th>After ms</th><th>Ratio</th><th>Time saved</th></tr></thead><tbody>{body}</tbody></table></div>')
    run_rows = ''
    evidence_rows = ''
    for run in runs:
        name = run['header'][1].split(' = ')[1]
        pause_line = run['lines']['PE64 PAUSE BACKOFF:'][-1]
        vals = dict(re.findall(r'(\w+)=(\d+)', pause_line['text']))
        targets = run['lines']['PE64 BLOCK JIT WORKER TRANSFER FALLBACKS:']
        tail = [r for r in targets if 'rank=1 ' in r['text']][-1]
        n = int(re.search(r'calls=(\d+)', tail['text'])[1])
        run_rows += f'<tr><td><code>{esc(name)}</code></td><td>{int(vals["yields"]):,} / {int(vals["excluded"]):,}</td><td>{vals["parks"]}</td><td>{n:,}</td><td>0</td></tr>'
        for key in ('PE64 Windows dynamic import:', 'METAL COMMAND BUFFER POLICY:', 'FRAME HOST COST:'):
            lines = run['lines'].get(key, [])
            if key == 'FRAME HOST COST:':
                lines = [r for r in lines if 'stage=queue_submit' in r['text']][-1:]
            else:
                lines = lines[-1:]
            for row in lines:
                evidence_rows += f'<li><b>{esc(name)}, line {row["line"]}</b><br><code>{esc(row["text"])}</code></li>'
    buttons = ''.join(f'<button data-case="{i}">{esc(r["case"])}</button>' for i, r in enumerate(groups))
    cards = [next(r for r in groups if r['kind'] == 'pause_trace' and r['case'] == '1 hints, host yield False'),
             next(r for r in groups if r['kind'] == 'pause_workers' and r['case'] == 'idle'),
             next(r for r in groups if r['kind'] == 'register_threads')]
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rosette · CPU admission and import routing</title><style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#10161e;color:#e5edf7}body{margin:0}main{max-width:1200px;margin:auto;padding:32px 24px 64px}h1{font-size:clamp(28px,4vw,46px);margin:8px 0 12px}h2{margin-top:42px}h3{margin:25px 0 12px}p,li{line-height:1.6;color:#b8c8da}a{color:#86dbcd}code{overflow-wrap:anywhere}nav{display:flex;gap:20px;flex-wrap:wrap;margin-top:22px}.badge{font-size:13px;border:1px solid #725932;color:#eacb88;padding:6px 10px;border-radius:7px}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-top:26px}.card,.panel{background:#1a2432;border:1px solid #2a394b;padding:22px;border-radius:16px}.value{font-size:44px;font-weight:700;color:#86dbcd}.card p{margin-bottom:0}.note{border-left:4px solid #eacb88;padding:10px 18px;background:#1b222b}.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:15px}td,th{padding:12px;text-align:left;border-bottom:1px solid #2b394b;white-space:nowrap}th{color:#86dbcd}td:first-child{white-space:normal}button,select{color:#d9e8f4;background:#1a293c;border:1px solid #3c5270;border-radius:8px;padding:9px 12px;margin:4px;cursor:pointer}button[aria-pressed=true]{border-color:#86dbcd;color:#86dbcd}svg{width:100%;height:auto;background:#131b26;border-radius:10px}details{margin-top:20px}summary{cursor:pointer;color:#86dbcd}.raw li{margin:14px 0;font-size:13px}.raw code{color:#a9bdcf}.small{font-size:14px}.status{color:#eacb88}@media(max-width:700px){main{padding:22px 16px}.cards{grid-template-columns:1fr}.value{font-size:36px}td,th{padding:9px}}
</style><main><span class="badge">SOURCE ONLY · installation pending</span><h1>CPU gains that can reach the normal run</h1>
<p>October 14, 2026 · M2 Max · seven alternating comparisons per case · 182 measured samples · no Xenia or GPU workload launched.</p>
<p class="note">The latest runs excluded every PAUSE backoff attempt and reported no translated PAUSE. The bounded memory-write trace had a flag that stayed enabled after its budget closed. This pass checks its actual liveness, retains active diagnostics, and fuses qualified register import thunks with their existing handlers.</p>
<nav><a href="#admission">Live admission gap</a><a href="#measurements">CPU measurements</a><a href="#latency">Wake-up latency</a><a href="#limits">Remaining bottlenecks</a><a href="#evidence">Proof files</a></nav>
<div class="cards"><div class="card"><div class="value">TRACE_RATIO×</div><p>PAUSE dispatch path speed<br>exact hints, retired work and yields</p></div><div class="card"><div class="value">IDLE_SAVED%</div><p>idle thread CPU saved<br>four qualified translated pollers</p></div><div class="card"><div class="value">THREAD_SAVED%</div><p>thread CPU saved on NT thunks<br>four bound workers, real host yields</p></div></div>
<h2 id="admission">The improvement was being refused</h2><p>Both logs enable <code>windows_memory_trace = 1</code>. PAUSE previously tested that flag directly. The existing tracing subsystem closes at its event or instruction budget; the updated PAUSE paths use that same liveness decision. Live tracing, instruction-clock execution, memory verification, ABI diagnostics, spin captures and pending TSO stores retain their exclusions.</p>
<div class="scroll"><table><thead><tr><th>Run · scenario unspecified in header</th><th>PAUSE yields / excluded</th><th>Parks</th><th>NT register tail jumps</th><th>Translated PAUSE rows</th></tr></thead><tbody>RUN_ROWS</tbody></table></div>
<p>The first-ranked target <code>0x14313a910</code> is logged as <code>ntdll.dll!NtDelayExecution</code>. It sits outside this PE image, so the fixtures also put proc-address stubs outside the image. The old and new import handlers remain enabled in both variants.</p>
<h2 id="measurements">Equivalent work, fewer dispatches</h2><p>Times are medians of seven samples. PAUSE and import traces measure CPU-only path elapsed time; worker cases measure summed <code>THREAD_CPUTIME_ID</code> across four threads. These ratios are not Halo FPS forecasts.</p>
TABLES
<h3>Inspect each comparison</h3><div class="panel"><div>BUTTONS</div><p id="metric" class="small"></p><svg role="img" aria-label="Before and after measured time" viewBox="0 0 950 170" id="chart"></svg><p id="comparison-text"></p><div class="scroll"><table id="pairs"></table></div></div>
<h2 id="latency">CPU saved while jobs still arrive</h2><p>Each raw, notified and short-job sample checks all 80 handoffs and checksums. Together: 3,360 handoffs. Integer-progress, vector-progress and short-job controls never park. The backoff requests 100 µs; operating-system scheduling can exceed that request.</p>
<div class="scroll"><table><thead><tr><th>Jobs</th><th>p95 before µs</th><th>p95 after µs</th><th>Largest after observation µs</th><th>Largest host wait µs</th></tr></thead><tbody>LATENCY_ROWS</tbody></table></div>
<h2 id="limits">CPU time saved is an opportunity, not a frame-rate guarantee</h2><p>Less polling and dispatch leaves a busy core more room for useful guest execution or command production. No thread assignment was changed. A frame still waits for its slowest dependent work.</p>
<p>Queue-submit elapsed time was 768.401 s and 171.764 s, including 747.563 s and 159.965 s of room waits. Those are overlapping host elapsed scopes, not exclusive CPU computation or GPU utilization. This pass does not establish the GPU critical-path fraction. Native pipeline costs, guest critical-section trampolines and <code>bsearch</code> remain candidates; call counts and sampled import estimates do not prove their frame-critical CPU share.</p>
<p>The user reports small FPS improvements, but these runs have no matched camera/scene labels. Sustained 30 FPS remains unproven. Zero parks in the next run means no live backoff benefit; the per-worker <code>PE64 TRANSLATED PAUSE</code> and <code>PE64 REGISTER IMPORT TAIL</code> rows show whether the other changes actually execute.</p>
<p class="status">Focused Debug and ReleaseFast: 15/15 steps each, 138/150 test executions each, 12 optional skips. Filters overlap. Full Zig suite, bare root make shell-update, installation and matched Halo verification remain deferred.</p>
<h2 id="evidence">Source-bound evidence</h2><p>1,024 narrow/full-dispatch ABI comparisons cover all four admitted handlers. Production tests cover exact first/256-hint yields, code replacement, bound contexts, queued stores, trace budgets, IAT rebinding, hooks, verification exclusion, flags, stack restoration and concurrent per-worker counters. Active memory-verification profiles use ordinary import transfers, so import side effects are not replayed by a register-only verifier.</p>
<p><a href="../bench-results.json">182 raw samples and summaries</a> · <a href="../manifest.json">Source, input, binary and command identities</a> · <a href="../focused-debug.log">Debug checks</a> · <a href="../focused-release.log">ReleaseFast checks</a> · <a href="../register-bench-final.log">Import benchmark</a> · <a href="../pause-bench-final.log">PAUSE benchmark</a> · <a href="../run-analysis.json">Live log lines</a></p>
<details><summary>Exact live evidence and scope</summary><ul class="raw">EVIDENCE_ROWS</ul></details>
</main><script>const data=DATA;function show(i){const r=data[i],b=r.before_ns/1e6,a=r.after_ns/1e6,scale=560/Math.max(b,a);document.getElementById('metric').textContent=r.kind+' · '+r.case+' · '+(r.metric==='cpu_ns'?'summed thread CPU':'CPU-only path elapsed time');document.getElementById('chart').innerHTML=[['Before',b,'#8da2bc'],['After',a,'#86dbcd']].map(([label,value,color],j)=>`<text x="25" y="${55+j*65}" fill="#c6d4e2">${label}</text><rect x="150" y="${32+j*65}" width="${value*scale}" height="32" fill="${color}"/><text x="${163+value*scale}" y="${55+j*65}" fill="#e5edf7">${value.toFixed(3)} ms</text>`).join('');document.getElementById('comparison-text').textContent=r.ratio.toFixed(3)+'× path ratio; '+r.saved_percent.toFixed(1)+'% time saved.';let body='<thead><tr><th>Pair</th><th>Before ms</th><th>After ms</th><th>Ratio</th></tr></thead><tbody>';for(let p=0;p<7;p++){const old=r.samples.find(x=>x.pair===p&&!x.enabled),next=r.samples.find(x=>x.pair===p&&x.enabled);body+=`<tr><td>${p+1}</td><td>${(old[r.metric]/1e6).toFixed(3)}</td><td>${(next[r.metric]/1e6).toFixed(3)}</td><td>${(old[r.metric]/next[r.metric]).toFixed(3)}×</td></tr>`}document.getElementById('pairs').innerHTML=body+'</tbody>';document.querySelectorAll('[data-case]').forEach(b=>b.setAttribute('aria-pressed',+b.dataset.case===i))}document.querySelectorAll('[data-case]').forEach(b=>b.onclick=()=>show(+b.dataset.case));show(0);</script></html>'''
    latency = ''.join(f'<tr><td>{esc(r["case"])}</td><td>{r["p95_before_ns"]/1e3:.0f}</td><td>{r["p95_after_ns"]/1e3:.0f}</td><td>{r["max_after_ns"]/1e3:.0f}</td><td>{r["max_host_wait_ns"]/1e3:.0f}</td></tr>' for r in groups if r['kind'] == 'pause_workers' and r['case'] in ('raw', 'notified', 'short'))
    replacements = {'TRACE_RATIO': f'{cards[0]["ratio"]:.1f}', 'IDLE_SAVED': f'{cards[1]["saved_percent"]:.1f}',
                    'THREAD_SAVED': f'{cards[2]["saved_percent"]:.1f}', 'RUN_ROWS': run_rows, 'TABLES': ''.join(tables),
                    'BUTTONS': buttons, 'LATENCY_ROWS': latency, 'EVIDENCE_ROWS': evidence_rows, 'DATA': json.dumps(groups)}
    for key in sorted(replacements, key=len, reverse=True):
        page = page.replace(key, replacements[key])
    (folder / 'final').mkdir(exist_ok=True)
    (folder / 'final/report.html').write_text(page)
    print('Dashboard rendered; source, evidence and input hashes verified.')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('folder', type=Path)
    ap.add_argument('--summarize-only', action='store_true')
    args = ap.parse_args()
    folder = args.folder.resolve()
    data = parse(folder)
    if not args.summarize_only:
        render(folder, data)


if __name__ == '__main__':
    main()
