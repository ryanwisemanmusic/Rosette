#!/usr/bin/env python3
"""Render saved CPU command-flow measurements, with explicit delivery state."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    'lib/gpu/vulkan/async_command_worker.zig',
    'lib/gpu/vulkan/owned_command_payloads.zig',
    'lib/gpu/vulkan/queued_command.zig',
    'lib/gpu/vulkan/command_flow_tests.zig',
    'lib/gpu/vulkan/handle_map_registry.zig',
    'lib/gpu/vulkan/handle_lookup_tests.zig',
    'lib/linker/dyld/forwarder/vulkan_objects.zig',
    'lib/linker/dyld/forwarder/loader_symbols.zig',
    'lib/linker/dyld/forwarder/owned_argument_tests.zig',
    'lib/linker/dyld/forwarder/tests.zig',
    'tools/benchmarks/vulkan_handle_registry.zig',
    'tools/benchmarks/vulkan_command_worker.zig',
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--run-log', type=Path, required=True)
    args = parser.parse_args()
    p = args.evidence
    flow = json.loads((p / 'flow-results.json').read_text())
    registry = json.loads((p / 'registry-results.json').read_text())
    scalar = json.loads((p / 'scalar-results.json').read_text())
    log = args.run_log.read_text()
    interval_rows = re.findall(r'FRAME HOST COST: present_intervals=(\d+) total_ms=(\d+)', log)
    queue_rows = re.findall(r'FRAME HOST COST: stage=queue_submit calls=(\d+) total_us=(\d+)', log)
    intervals = int(interval_rows[-1][0]) - int(interval_rows[-2][0])
    interval_ms = int(interval_rows[-1][1]) - int(interval_rows[-2][1])
    queue_ms = (int(queue_rows[-1][1]) - int(queue_rows[-2][1])) / 1000
    room_rows = re.findall(r'room_waits=(\d+) room_wait_ms=(\d+)', log)
    room_ms = int(room_rows[-1][1]) - int(room_rows[-2][1])
    observed = dict(intervals=intervals, interval_ms=interval_ms,
                    queue_submit_ms=queue_ms, room_wait_ms=room_ms,
                    scope='Last two cumulative checkpoints; mixed late-run window, not an isolated gameplay benchmark')
    manifest_path = p / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    current_sources = {s: sha(ROOT / s) for s in SOURCES}
    if manifest.get('sources') and manifest['sources'] != current_sources:
        raise SystemExit('Source changed since the saved measurements; regenerate the proofs before promoting this dashboard.')
    manifest.update(run_log=dict(path=str(args.run_log), sha256=sha(args.run_log)),
                    sources=current_sources,
                    benchmarks={'flow': flow, 'registry': registry, 'scalar_control': scalar},
                    observed=observed, xenia_launched=False, gpu_benchmarks=False,
                    exit_139='User closed the window; excluded from crash investigation',
                    user_observations={'intro': 'Nearly locked 30 FPS', 'custom_game_start': 'About 0.6 FPS',
                                       'floor_view_peak': '10.5 FPS', 'input': 'More responsive keyboard'})
    manifest.setdefault('status', 'Offline proofs passed; full gates and install pending')
    manifest.setdefault('installed', False)
    manifest['artifacts'] = {name: sha(p / name) for name in
                             ['flow-test', 'registry-before', 'registry-after', 'scalar-before', 'scalar-after',
                              'bench-final.log', 'registry-results.json', 'scalar-results.json']}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    rows = [('Descriptor + constants FIFO', flow['summary']['drained'], flow['summary']['owned'], flow['speedup']),
            *[(f'Handle lookup · {name}', v['before_ns'], v['after_ns'], v['speedup']) for name, v in registry['summary'].items()],
            ('Scalar-only FIFO control', scalar['summary']['before'], scalar['summary']['after'], scalar['speedup'])]
    table = ''.join(f'<tr><td>{html.escape(name)}</td><td>{b/1e6:.3f}</td><td>{a/1e6:.3f}</td><td>{ratio:.2f}×</td></tr>'
                    for name, b, a, ratio in rows)
    samples = ''.join(f'<tr><td>{i+1}</td><td>{next(v["ns"] for v in flow["samples"] if v["sample"]==i and v["route"]=="drained")/1e6:.3f}</td><td>{next(v["ns"] for v in flow["samples"] if v["sample"]==i and v["route"]=="owned")/1e6:.3f}</td></tr>' for i in range(7))
    page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Rosette command-flow evidence · October 12</title>
<style>body{{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:36px}}h1{{line-height:1.15;font-size:40px}}h2{{font-size:24px}}p{{color:#b9c7d6}}a{{color:#85dbcf}}.cards{{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}}.card{{background:#1c2837;padding:23px;border-radius:14px}}.value{{font-size:36px;color:#85dbcf;font-weight:750}}table{{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}}td,th{{padding:10px 12px;text-align:right;border-bottom:1px solid #304052}}td:first-child,th:first-child{{text-align:left}}tr:nth-child(even){{background:#17212d}}.note{{border-left:4px solid #85dbcf;padding:12px 20px;background:#17212d}}.scroll{{overflow:auto}}button{{color:#e5edf7;background:#27394c;border:1px solid #61778b;border-radius:8px;padding:10px;margin:4px;font:inherit}}svg{{width:100%;height:auto}}@media(max-width:700px){{.cards{{grid-template-columns:1fr}}main{{padding:20px}}h1{{font-size:31px}}td,th{{font-size:14px}}}}</style></head>
<body><main><h1>Rosette command-flow evidence</h1><p>October 12, 2026 · run 20261012T204221Z-be6cf0b308ad · saved source snapshot</p>
<p class="note">CPU-only measurements of production FIFO and handle-map code. Every timed output is checked. Xenia was not launched; no benchmark dispatches GPU work. Ratios below are <strong>not Halo FPS forecasts</strong>.</p>
<div class="cards"><div class="card"><div class="value">{flow['speedup']:.2f}×</div>Draw / descriptor / constants fixture<br>80,000 ordered callbacks per trial</div><div class="card"><div class="value">{registry['summary']['cold']['speedup']:.2f}×</div>Cold Vulkan handle lookup<br>Recorded before / after binaries</div><div class="card"><div class="value">{queue_ms/1000:.1f} s</div>Observed late-window queue-submit time<br>Includes {room_ms/1000:.1f} s waiting for queue space</div></div>
<h2>Where the current run spends time</h2><p>The last two checkpoints cover {intervals:,} present intervals and {interval_ms/1000:.3f} seconds. Host queue-submit calls accumulated {queue_ms/1000:.3f} seconds ({queue_ms/interval_ms*100:.1f}% of that interval sum). These timers can overlap other work; this is not GPU utilization. The run made 1,050,167 descriptor bindings, 62,844 push-constant calls and 400,203 worker ordering barriers with pending work.</p>
<p>The run’s final monitor saw zero risk/severe events, 84,566 submit infos and a maximum of two outstanding Metal command buffers. Exit 139 was the user closing the window. The reported 10.5 FPS floor view is encouraging, but it is not a matched camera benchmark.</p>
<h2>What changed</h2><p>Descriptor bindings and push constants now carry owned argument snapshots through the same FIFO as draws. Ordinary update, free, reset, destruction, submission and FSI continuation boundaries still drain prior work. A separate bounded payload slab keeps scalar queue entries small; the worker copies owned arrays into its batch before releasing slots for reuse.</p><p>Cached handle lookup returns its first validated snapshot. Cold scans load only the candidate key until a match needs full seqlock validation. Native identities, publication ordering and invalidation remain checked.</p>
<h2>Offline before and after</h2><p>Seven alternating comparisons, median milliseconds per fixture. Row workloads differ, so compare within each row. The scalar control exposes the cost of the new queue layout instead of hiding it.</p><div class="scroll"><table><thead><tr><th>Fixture</th><th>Before ms</th><th>After ms</th><th>Ratio</th></tr></thead><tbody>{table}</tbody></table></div>
<div><button type="button" data-route="0">Descriptor FIFO</button><button type="button" data-route="1">Cold lookup</button><button type="button" data-route="2">Cached lookup</button><button type="button" data-route="4">Scalar control</button></div><svg id="chart" viewBox="0 0 760 180" role="img" aria-label="Selected fixture before and after elapsed milliseconds"></svg>
<details><summary>All seven FIFO comparisons</summary><div class="scroll"><table><thead><tr><th>Pair</th><th>Drained ms</th><th>Owned FIFO ms</th></tr></thead><tbody>{samples}</tbody></table></div></details>
<h2>Verification and delivery</h2><p>Tests cover delayed execution with caller-memory reuse, maximum and empty payloads, repeated FIFO slot reuse, native guest marshalling, synchronous boundaries and fallback, cached replacement/removal/clear, and concurrent map creation and slot reuse.</p><p id="delivery">{html.escape(manifest['status'])}</p>
<p><a href="../manifest.json">Manifest and source hashes</a> · <a href="../flow-results.json">FIFO measurements</a> · <a href="../registry-results.json">Lookup A/B logs</a> · <a href="../scalar-results.json">Scalar control</a> · <a href="../zig-check.log">Full Zig gate</a></p>
<h2>What remains</h2><p>GPU shader cost and {room_ms/1000:.1f} seconds of queue backpressure remain. These edits target CPU recording and identity lookup, and do not raise work budgets or queue depth. Audio, Fast Path, rendering protection and the 30 FPS ceiling are retained. A normal Custom Games run must measure the actual FPS change; the available evidence does not establish a 2–5× game speedup or locked 30 FPS.</p><p>The next log adds <code>VULKAN OWNED COMMAND FLOW</code> with descriptor/push snapshot counts. Compare those counts, worker ordering waits, queue host costs and a matched moving-camera section.</p></main>
<script>const rows={json.dumps(rows)};function draw(i){{const [name,b,a]=rows[i],scale=540/Math.max(b,a);document.getElementById('chart').innerHTML=`<text x="10" y="26" fill="#e5edf7">${{name}}</text><text x="10" y="76" fill="#b9c7d6">Before</text><rect x="100" y="52" width="${{b*scale}}" height="30" rx="5" fill="#6d8095"/><text x="${{110+b*scale}}" y="75" fill="#e5edf7">${{(b/1e6).toFixed(2)}} ms</text><text x="10" y="126" fill="#b9c7d6">After</text><rect x="100" y="102" width="${{a*scale}}" height="30" rx="5" fill="#85dbcf"/><text x="${{110+a*scale}}" y="125" fill="#e5edf7">${{(a/1e6).toFixed(2)}} ms</text>`;}}document.querySelectorAll('[data-route]').forEach(b=>b.onclick=()=>draw(+b.dataset.route));draw(0);</script></body></html>'''
    (p / 'final').mkdir(exist_ok=True)
    (p / 'final/report.html').write_text(page)
    print(p / 'final/report.html')


if __name__ == '__main__':
    main()
