#!/usr/bin/env python3
"""Render source-bound PAUSE dispatch and idle-pressure CPU evidence."""
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


def summarize(folder):
    rows = []
    for line in (folder / 'bench-final.log').read_text().splitlines():
        if not line.startswith(('pause_trace ', 'pause_workers ')):
            continue
        row = {'kind': line.split()[0]}
        for key, val in re.findall(r'(\w+)=(\S+)', line):
            row[key] = val == 'true' if val in ('true', 'false') else int(val) if val.isdigit() else val
        rows.append(row)
    assert len(rows) == 140, f'Incomplete benchmark: {len(rows)}/140 samples'
    summary = []
    for kind in ('pause_trace', 'pause_workers'):
        def case(r):
            return (r['bundle'], r['host_yield']) if kind == 'pause_trace' else (r['mode'],)
        for key in sorted({case(r) for r in rows if r['kind'] == kind}):
            subset = [r for r in rows if r['kind'] == kind and case(r) == key]
            before = [r for r in subset if not r['enabled']]
            after = [r for r in subset if r['enabled']]
            assert len(before) == len(after) == 7
            for group in (before, after):
                assert {r['pair'] for r in group} == set(range(7))
            metric = 'elapsed_ns' if kind == 'pause_trace' else 'cpu_ns'
            b = statistics.median(r[metric] for r in before)
            a = statistics.median(r[metric] for r in after)
            item = {'kind': kind, 'case': key, 'before_ns': b, 'after_ns': a, 'ratio': b / a, 'samples': len(subset)}
            if kind == 'pause_trace':
                for pair in range(7):
                    old = next(r for r in before if r['pair'] == pair)
                    new = next(r for r in after if r['pair'] == pair)
                    for field in ('hints', 'retired', 'yields'):
                        assert old[field] == new[field], (key, pair, field)
                item.update(steps_before=before[0]['steps'], steps_after=after[0]['steps'])
            else:
                item.update(
                    elapsed_before_ns=statistics.median(r['elapsed_ns'] for r in before),
                    elapsed_after_ns=statistics.median(r['elapsed_ns'] for r in after),
                    p95_before_ns=statistics.median(r['p95_ns'] for r in before),
                    p95_after_ns=statistics.median(r['p95_ns'] for r in after),
                    max_before_ns=max(r['max_ns'] for r in before),
                    max_after_ns=max(r['max_ns'] for r in after),
                    largest_host_wait_ns=max(r['max_wait_ns'] for r in after),
                    parks=sum(r['parks'] for r in after),
                    handoffs=sum(r['handoffs'] for r in subset),
                )
                assert all(r['cpu_ns'] <= r['elapsed_ns'] * 4 + 5_000_000 for r in subset)
                if key in (('productive',), ('vector',)):
                    assert item['parks'] == 0
            summary.append(item)
    result = {'summary': summary, 'samples': rows}
    (folder / 'bench-results.json').write_text(json.dumps(result, indent=2))
    return result


def render(folder, result):
    manifest = json.loads((folder / 'manifest.json').read_text())
    for name, digest in manifest['sources'].items():
        assert sha(ROOT / name) == digest, 'Source changed: ' + name
    for name, digest in manifest['evidence'].items():
        assert sha(folder / name) == digest, 'Evidence changed: ' + name
    run = json.loads((folder / 'run-analysis.json').read_text())
    assert sha(Path(run['path'])) == run['sha256']
    for gate in ('focused-debug.log', 'focused-release.log'):
        assert '12/12 steps succeeded; 113/125 tests passed (12 skipped)' in (folder / gate).read_text()
    assert '3/3 steps succeeded; 37/40 tests passed (3 skipped)' in (folder / 'bench-final.log').read_text()
    trace = [s for s in result['summary'] if s['kind'] == 'pause_trace']
    pressure = [s for s in result['summary'] if s['kind'] == 'pause_workers']
    trace_rows = ''.join(f'<tr><td>{s["case"][0]} hints / turn, host yield {str(s["case"][1]).lower()}</td><td>{s["before_ns"]/1e6:.3f}</td><td>{s["after_ns"]/1e6:.3f}</td><td>{s["ratio"]:.2f}×</td><td>{s["steps_before"]:,} → {s["steps_after"]:,}</td></tr>' for s in trace)
    pressure_rows = ''.join(f'<tr><td>{s["case"][0]}</td><td>{s["before_ns"]/1e6:.3f}</td><td>{s["after_ns"]/1e6:.3f}</td><td>{s["ratio"]:.2f}×</td><td>{s["elapsed_before_ns"]/1e6:.3f} → {s["elapsed_after_ns"]/1e6:.3f}</td><td>{s["p95_before_ns"]/1e3:.0f} → {s["p95_after_ns"]/1e3:.0f}</td><td>{s["max_after_ns"]/1e3:.0f}</td></tr>' for s in pressure)
    evidence = ''.join(f'<li>Line {row["line"]}: <code>{html.escape(row["text"])}</code></li>' for marker in ('VULKAN FSI EVIDENCE IO:', 'VULKAN FSI ROOM OBSERVER:', 'METAL COMMAND BUFFER POLICY:', 'VULKAN FSI RECORDING RETIREMENT:') for row in run['lines'][marker][-1:])
    native = next(s for s in trace if s['case'] == (1, False) or s['case'] == [1, False])
    idle = next(s for s in pressure if s['case'][0] == 'idle')
    raw = next(s for s in pressure if s['case'][0] == 'raw')
    buttons = ''.join(f'<button data-case="{n}">{html.escape(s["case"][0])}</button>' for n, s in enumerate(pressure))
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rosette · PAUSE pressure</title><style>
body{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}main{max-width:1180px;margin:auto;padding:32px}h1{font-size:38px;line-height:1.2}h2{margin-top:36px}p{color:#bfccda}a{color:#8bdacf}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}.card{background:#1b2838;padding:20px;border-radius:12px}.value{font-size:36px;color:#8bdacf;font-weight:750}.note{border-left:4px solid #8bdacf;background:#172230;padding:16px 22px}.scroll{overflow:auto}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}td,th{padding:10px;text-align:right;border-bottom:1px solid #304153}td:first-child,th:first-child{text-align:left}code{overflow-wrap:anywhere;color:#a9dacb;font-size:14px}button{border:1px solid #455d73;border-radius:8px;background:#22374c;color:#e5edf7;padding:9px 12px;margin:4px;cursor:pointer}button[aria-pressed=true]{background:#315653;border-color:#8bdacf}svg{width:100%;background:#162332;border-radius:10px}@media(max-width:780px){main{padding:20px}.cards{grid-template-columns:1fr}h1{font-size:30px}svg text{font-size:28px}}
</style><main><h1>Rosette campaign · PAUSE pressure</h1><p>Round 57 · campaign 80f1e7d03898 · offline CPU proofs · source-only delivery</p><div class="note">The previous shader-entry freeze is resolved in this log. This pass reduces repeated PAUSE dispatch and qualified idle CPU pressure. Path ratios measure specific CPU fixtures, not gameplay FPS. The reported transition averages 2.4 FPS; sustained 30 FPS remains unproven.</div>
<div class="cards"><div class="card"><div class="value">NATIVE_RATIO×</div>single-hint CPU loop throughput</div><div class="card"><div class="value">IDLE_RATIO×</div>less CPU time in four idle translated pollers</div><div class="card"><div class="value">2.4 FPS</div>user-reported campaign transition average · peak 2.6</div></div>
<h2 id="evidence">What changed in the real run</h2><p>All 966 shader evidence writes saved successfully. Ten shader caller stages total 517.544 ms across 483 calls, with every individual stage maximum below 1 ms. The writer spends 6.423 s separately, maximum 450.060 ms. No global concurrency-stall snapshot appears. Your reported disappearance of the old freeze agrees with these counters; these are unmatched runs and differently scoped timers, so no before/after FPS ratio is implied.</p><p>Rendering still waits substantially: queue submission host stages total 496.111 s, including 476.904 s of queue-room waits. The 599,258 FSI split boundaries and 303,624 driver queue calls remain. Fence completion observation includes CPU scheduling delay; it cannot establish GPU utilization. Recording retirement is just 31.902 ms for the entire run. CPU spin pressure and GPU fragmentation are separate candidates; the safety limits were retained.</p><p>RENDER interpreted 401,103,555 refused steps; the dominant refused region contains eight PAUSE instructions. MAIN has 332,806,384 refused steps in the same region; XThread0022/0023 have 310,436,681 / 330,226,645 in a single-hint region. The sampled regions identify where steps occur, not their wall-time share. Large retired-instruction totals include idle spins and cannot establish how much useful CPU work 30 FPS needs. The two 512-byte input regions and their exact hint offsets are retained in <a href="../spin-inputs.json">spin inputs</a>.</p>
<h2 id="translated">Keep idle hints inside a translated trace</h2><p>The production collector now admits exact F3 90 PAUSE instructions for parallel, host-clock workers. A focused scheduling helper runs inside the trace and retains the existing first-hint / 256-hint cadence, flags, current worker context, source-generation checks, spin captures and stall assists. Every scheduling request or capture ends the trace at that exact hint. Cooperative, traced, memory-verification and instruction-clock collection retains the old boundary.</p><p>Seven alternating pairs for single and eight-hint loops, both with and without actual host yields. The block JIT is enabled in both variants; only new PAUSE admission changes. These fixed byte-code loops match the hint shapes seen in the log, not the full Halo working set. All hint counts, retired instructions, yield requests, registers and flags are checked. Caches are warmed before timing.</p><div class="scroll"><table><tr><th>100,000 loop turns</th><th>Before ms</th><th>After ms</th><th>CPU path ratio</th><th>Step dispatches</th></tr>TRACE_ROWS</table></div>
<h2 id="backoff">Give productive work more CPU room</h2><p>After an exact PAUSE yield, all roles can qualify for a requested 100 µs host wait after 16 identical yields and at least 2 ms of quiet state. All GPRs, vector/opmask/x87 state, flags, MXCSR, RIP, RSP and frame number must match; gaps and retired work are bounded. Changed state or a notification resets qualification. This is a heuristic for idle work, not proof that no external task is waiting. There is no guest wait-status or deadline change. Diagnostics, spin captures and pending buffered stores retain ordinary host yielding.</p><p>Notifications and shutdown interrupt the worker's epoch wait. Raw guest writes need no new notification mechanism: the worker polls again after the deadline. The requested 100 µs is not an OS scheduling guarantee. In these tests, raw handoff p95 changes from RAW_BEFORE to RAW_AFTER µs and its largest measured handoff is RAW_MAX µs. The largest observed host wait in the idle fixture is IDLE_MAX_WAIT µs; that fixture has no arriving jobs. A superseded variant recorded one 4.810 ms raw observation whose cause was not isolated; <a href="../bench-before-vector-snapshots.json">its earlier results</a> are retained. Final figures here use full architectural-state qualification.</p><p>Four actual translated polling workers, with production memory loads and the production yield route, run seven alternating pairs per mode. A common start barrier excludes compilation and earlier workers waiting for later setup. Thread CPU time is summed across four workers. Every one of the 3,360 job handoffs and checksums is checked. Both variants have translated PAUSE enabled, isolating the backoff change. Initial runs that included setup overlap are superseded and not used here.</p><div class="scroll"><table><tr><th>Mode</th><th>CPU before ms</th><th>CPU after ms</th><th>Ratio</th><th>Wall ms before → after</th><th>Handoff p95 µs</th><th>After max µs</th></tr>PRESSURE_ROWS</table></div><p>The productive controls change either a guest integer register or XMM0 via real translated PADDQ instructions, and never park. Short jobs arrive about every 200 µs; the raw/notified jobs arrive about every 5 ms. Polling iterations and hints deliberately fall when parked; fewer idle instructions are not lost gameplay work. These fixtures do not measure Halo useful throughput, end-to-end latency, GPU time or an FPS multiplier.</p>BUTTONS<svg id="comparison" viewBox="0 0 900 215" role="img" aria-label="Selected CPU and wall time comparison"></svg>
<h2 id="delivery">Verification and the next normal campaign run</h2><p>Focused Debug and ReleaseFast each pass 113/125 test executions (12 optional skips), 12/12 steps. Filters overlap; this is not a count of 113 distinct new tests. Final measured run passes 37/40 (three optional skips), 3/3 steps. Checks include first/256/near-overflow hint boundaries, source-byte replacement, bound-context isolation, precise spin capture and subsequent interpreted reads, TSO pending-store refusal, actual concurrent raw/notified handoffs, progress controls and stopping. The source-size and context audits pass.</p><p>Full suite, bare root <code>make shell-update</code>, installation and a matched campaign test remain deferred. The installed runtime is unchanged. After your other agent installs this source, use a normal campaign run: no flags are required. Read <code>PE64 TRANSLATED PAUSE</code> per worker, <code>PE64 PAUSE BACKOFF</code> qualification/parks/wait maxima and the same transition's cadence. A zero park count means this heuristic did not help that live episode. Compare queue-room time as well; it remains the largest separately observed host cost.</p><p>Fast Path, audio, TSO, shader correctness, watchdog limits, tessellation isolation, maximum two outstanding Metal command buffers and the 30 FPS ceiling were preserved. Xenia, ISO and vendor files were not changed; no emulator launch or GPU dispatch was used. More stable rendering and removal of the earlier freeze are real progress, but locked 30 FPS still needs useful-work and queue critical-path measurements.</p><details><summary>Selected line-numbered run evidence</summary><ul>EVIDENCE</ul></details><p><a href="../bench-results.json">All 140 measured samples</a> · <a href="../bench-final.log">Raw benchmark</a> · <a href="../run-analysis.json">Run lines and shader stages</a> · <a href="../manifest.json">Source, input, command and binary identities</a> · <a href="../focused-debug.log">Debug checks</a> · <a href="../focused-release.log">ReleaseFast checks</a></p></main><script>
const samples=PLOT;function show(i){const r=samples[i],items=[['CPU before',r.before_ns/1e6,'#75899f'],['CPU after',r.after_ns/1e6,'#8bdacf'],['Wall before',r.elapsed_before_ns/1e6,'#75899f'],['Wall after',r.elapsed_after_ns/1e6,'#8bdacf']],scale=500/Math.max(...items.map(x=>x[1]));document.getElementById('comparison').innerHTML=items.map(([name,time,color],n)=>`<text x="18" y="${36+n*46}" fill="#bfccda">${name}</text><rect x="195" y="${17+n*46}" width="${time*scale}" height="25" fill="${color}"/><text x="${205+time*scale}" y="${36+n*46}" fill="#e5edf7">${time.toFixed(3)} ms</text>`).join('');document.querySelectorAll('[data-case]').forEach(b=>b.setAttribute('aria-pressed',+b.dataset.case===i))}document.querySelectorAll('[data-case]').forEach(b=>b.onclick=()=>show(+b.dataset.case));show(0);
</script></html>'''
    replace = {'NATIVE_RATIO': f'{native["ratio"]:.1f}', 'IDLE_RATIO': f'{idle["ratio"]:.1f}', 'TRACE_ROWS': trace_rows, 'PRESSURE_ROWS': pressure_rows, 'BUTTONS': buttons, 'EVIDENCE': evidence, 'PLOT': json.dumps(pressure), 'RAW_BEFORE': f'{raw["p95_before_ns"]/1e3:.0f}', 'RAW_AFTER': f'{raw["p95_after_ns"]/1e3:.0f}', 'RAW_MAX': f'{raw["max_after_ns"]/1e3:.0f}', 'IDLE_MAX_WAIT': f'{idle["largest_host_wait_ns"]/1e3:.0f}'}
    for key in sorted(replace, key=len, reverse=True):
        page = page.replace(key, replace[key])
    (folder / 'final').mkdir(exist_ok=True)
    (folder / 'final/report.html').write_text(page)
    print('PAUSE pressure dashboard rendered; source/evidence identities verified.')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('folder', type=Path)
    ap.add_argument('--summarize-only', action='store_true')
    args = ap.parse_args()
    folder = args.folder.resolve()
    result = summarize(folder)
    if not args.summarize_only:
        render(folder, result)


if __name__ == '__main__':
    main()
