#!/usr/bin/env python3
"""Source-checked frame-transition evidence, with real controls and raw samples."""
import argparse
import hashlib
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    "lib/gpu/vulkan/async_command_worker.zig", "lib/gpu/vulkan/queued_command.zig",
    "lib/gpu/vulkan/barrier_payload.zig", "lib/gpu/vulkan/barrier_flow_tests.zig",
    "lib/gpu/vulkan/fsi/timing.zig", "lib/gpu/vulkan/fsi/observer_route.zig",
    "lib/gpu/vulkan/fsi/observer_route_tests.zig", "lib/gpu/vulkan/fsi/root.zig",
    "lib/linker/dyld/forwarder/vulkan_objects.zig", "lib/linker/dyld/forwarder/owned_argument_tests.zig",
    "lib/linker/dyld/forwarder/barrier_argument_tests.zig",
    "tools/benchmarks/fsi_room_observer.zig", "tools/benchmarks/vulkan_barrier_flow.zig",
    "tools/benchmarks/compare_frame_jitter.py", "tools/benchmarks/report_frame_jitter.py",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    folder = args.evidence.resolve()
    manifest = json.loads((folder / "manifest.json").read_text())
    for path, expected in manifest["sources"].items():
        assert sha(ROOT / path) == expected, f"Source changed: {path}"
    for path, expected in manifest["evidence"].items():
        assert sha(folder / path) == expected, f"Evidence changed: {path}"
    result = json.loads((folder / "results.json").read_text())
    for binary, expected in result["binary_sha256"].items():
        assert sha(folder / binary) == expected, f"Binary changed: {binary}"
    run = json.loads((folder / "run-identity.json").read_text())
    assert sha(Path(run["path"])) == run["sha256"]
    analysis = json.loads((folder / "run-analysis.json").read_text())
    summary = result["summary"]
    labels = {"draw-barrier-draw": "Draw → barrier → draw", "scalar-control": "Scalar draw control", "pending-short": "20 µs pending fence", "record-overlap": "Recording overlaps a 20 µs fence", "pending-medium": "250 µs pending fence", "pending-long": "2 ms pending fence", "ready-control": "Already-ready fence control"}
    order = list(labels)
    rows = "".join(f'<tr><td>{labels[c]}</td><td>{summary[c]["before"]["elapsed_ns"]/1e6:.3f}</td><td>{summary[c]["after"]["elapsed_ns"]/1e6:.3f}</td><td>{summary[c]["speedup"]:.3f}×</td></tr>' for c in order)
    raw = "".join(f'<tr><td>{labels[s["case"]]}</td><td>{s["pair"]+1}</td><td>{s["variant"]}</td><td>{s["elapsed_ns"]/1e6:.3f}</td></tr>' for s in result["samples"])
    flow = summary["draw-barrier-draw"]
    controls = " · ".join(f'{labels[c]}: {(summary[c]["after"]["elapsed_ns"] / summary[c]["before"]["elapsed_ns"] - 1)*100:+.1f}% elapsed time' for c in ("scalar-control", "ready-control", "record-overlap"))
    buttons = "".join(f'<button data-case="{i}">{labels[c]}</button>' for i, c in enumerate(order))
    plots = [[labels[c], summary[c]["before"]["elapsed_ns"]/1e6, summary[c]["after"]["elapsed_ns"]/1e6] for c in order]
    pending = [summary[c] for c in ("pending-short", "pending-medium", "pending-long")]
    watcher_before = sum(r["before"]["cond_waits"] for r in pending)
    watcher_after = sum(r["after"]["cond_waits"] for r in pending)
    page = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Rosette draw and frame transitions</title>
<style>body{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}main{max-width:1150px;margin:auto;padding:35px}h1{font-size:40px;line-height:1.15}h2{margin-top:38px;font-size:25px}p{color:#bcc9d8}a{color:#85dbcf}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.card{background:#1c2837;padding:22px;border-radius:14px}.value{font-size:37px;color:#85dbcf;font-weight:750}.note{background:#17212d;border-left:4px solid #85dbcf;padding:14px 20px}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}td,th{padding:10px 12px;text-align:right;border-bottom:1px solid #304052}td:first-child,th:first-child{text-align:left}tr:nth-child(even){background:#17212d}button{background:#27394c;color:#e5edf7;border:1px solid #61778b;border-radius:8px;padding:9px;margin:4px;font:inherit}svg{width:100%;height:auto}.video{width:100%;border-radius:10px}details{margin-top:18px}code{color:#aee8dd}@media(max-width:700px){.cards{grid-template-columns:1fr}main{padding:20px}h1{font-size:30px}td,th{font-size:13px}}</style></head><body><main>
<h1>Rosette draw and frame transitions</h1><p>October 13, 2026 · run RUN · source-only performance pass</p>
<p class="note">The main target is CPU waiting between ordered draw commands. These comparisons use the production recording FIFO and fence monitor with checked CPU callbacks and timed stub fences. <strong>No Xenia launch or GPU dispatch. Path ratios are not FPS multipliers.</strong></p>
<div class="cards"><div class="card"><div class="value">FLOW_RATIO×</div>Draw / barrier / draw path<br>Seven alternating comparisons</div><div class="card"><div class="value">206.27 s</div>Observed queue-room waiting<br>147,198 timing groups in the log</div><div class="card"><div class="value">879 ms</div>Latest 32-frame mean<br>Recent p95 1,238 ms, max 1,570 ms</div></div>
<h2 id="command-flow">Pipeline barriers stay in the recording FIFO</h2><p>The supplied run contains 184,761 <code>vkCmdPipelineBarrier</code> calls and 217,272 worker ordering barriers with pending work. Previously every pipeline-barrier call drained the worker before recording the native command. Small barriers now copy validated arguments into owned storage and run in the existing FIFO between draws. The GPU still receives the same stage masks, access masks, layout transitions and queue-family ownership transfers.</p>
<p>The snapshot handles up to two memory barriers, four buffer barriers and two image barriers, with no extension pointers. Larger lists use the existing synchronous route. This is not evidence that all 184,761 calls qualify: the new <code>VULKAN BARRIER COMMAND FLOW</code> ledger measures that on the next normal run. Command buffers, descriptors and resources retain their original update/free/reset/destroy/submit and FSI continuation drains.</p>
<p>In the representative fixture, 20,000 draw / barrier / draw groups preserve all 60,000 callbacks and their checksum. Arguments are overwritten immediately after admission. The median host recording time changes from FLOW_BEFORE to FLOW_AFTER ms. Scalar job size stays 560 bytes and the payload slab does not grow. Admission borrows only through its synchronous copy into owned storage, avoids an unnecessary whole-union copy and keeps the queue lock aligned to a CPU cache line.</p>
<h2 id="fence-route">Queue-room waits observe fences directly</h2><p>The latest log's zero-time ready route tried 147,198 fences and completed zero of them. A room waiter may now claim the FIFO head and call the same bounded native fence wait directly, with the Windows runtime mutex released. One custody record prevents concurrent watcher / submitter observation or double reset. A full two-info group gives the room waiter one scheduling opportunity through a requested 1 ms relative wait; the watcher takes over when no waiter arrives.</p>
<p>Eligible pending-fence controls reduce producer condition waits from WAITS_BEFORE to WAITS_AFTER. Most elapsed-time gains here are modest; the table retains the ready and recording-overlap controls. There is no polling spin. Queue depth stays at two Metal command buffers, and successful reset is still required before retirement or reuse. Shutdown waits for active observers before loader teardown.</p>
<p class="note">The 200 ms risk / 350 ms severe watchdog thresholds, draw/work ceilings, post-risk reduction, shader bounds and tessellation isolation are unchanged. The supplied run's one 219 ms upper-bound observation reduced its draw cap to eight; this pass does not undo that protection.</p>
<h2 id="measurements">Offline comparisons</h2><p>ReleaseFast, seven alternating before/after pairs. Every fence serial, callback order, translated argument, completed count and checksum is checked. The scalar control runs in a separate process from the faster mixed case. Both recording cases warm the worker for 70 ms before timing. Fence delay and encoding work are controlled CPU substitutes; they do not measure Metal shader time.</p><div class="scroll"><table><thead><tr><th>Fixture</th><th>Before ms</th><th>After ms</th><th>Before / after</th></tr></thead><tbody>ROWS</tbody></table></div><p>CONTROLS</p>
<div>BUTTONS</div><svg id="comparison" viewBox="0 0 780 170" aria-label="Selected before and after comparison" role="img"></svg>
<details><summary>All 98 checked samples</summary><div class="scroll"><table><thead><tr><th>Fixture</th><th>Pair</th><th>Source</th><th>ms</th></tr></thead><tbody>RAW</tbody></table></div></details>
<h2 id="jitter">What the run actually says about jitter</h2><p>Queue-submit host time is 217.18 seconds, including 206.27 seconds waiting for room. These timers overlap other threads and are not GPU utilization. Recent accepted content intervals are uneven, as the curve below shows. The x-axis is reporting-window order, not a scene or camera-motion label.</p><svg id="cadence" viewBox="0 0 950 270" role="img" aria-label="Recent mean, p95 and maximum content intervals across log windows"></svg>
<p>The final window needs about 26× lower frame time to fit 33.3 ms, but that is one heavy window, not an overall throughput forecast. The CPU profile also includes long busy waits from RENDER and two title workers; aggregate instruction counts cannot be treated as useful work per frame. This pass attacks two concrete command-transition costs. It does not establish the fraction of a moving frame that they consume.</p>
<h2 id="videos">Reviewed recordings</h2><p>The title-screen samples show approximately 1.8–3.2 FPS; the Custom Games samples range from about 2.0 to 8.1 FPS as the view changes. Campaign remains slow with recognizable lighting and materials plus visible mesh-line artifacts. These are manually reviewed samples, not a matched benchmark. No scene or camera timing markers link these clips to the log windows, so they are not assigned to individual reporting windows.</p>
<details><summary>Title screen contact sheet</summary><img class="video" src="../title-sheet.png" alt="Seven sampled views of the title-screen camera"></details><details><summary>Custom Games contact sheet</summary><img class="video" src="../custom-sheet.png" alt="Seven sampled custom-game camera views"></details><details><summary>Campaign contact sheet</summary><img class="video" src="../campaign-sheet.png" alt="Seven sampled campaign views"></details>
<h2>Correctness and delivery</h2><p>STATUS</p><p>Focused checks cover guest marshalling, handle translation, overwritten caller arrays, maximum/empty barrier lists, FIFO wrapping and overflow fallback; observer custody, concurrent room waiters, risk/severe recovery, terminal wait/reset failures, an unclaimed watcher route and shutdown during an active native wait. Existing FSI and 30 FPS ceiling checks remain in the gate.</p>
<p>No full Zig suite, shell update or install was run in this pass, as requested. Your other agent must build/install these source changes before a normal Halo run can measure their live effect. Audio, Fast Path, TSO, Xenia and ISO contents are retained.</p>
<p><a href="../manifest.json">Source / evidence hashes and compiler commands</a> · <a href="../results.json">All measurements</a> · <a href="../run-analysis.json">Parsed run windows</a> · <a href="../run-evidence.txt">Run excerpts with line numbers</a> · <a href="../fsi-release.log">Focused ReleaseFast gate</a> · <a href="../fsi-debug.log">Focused Debug gate</a></p>
<p>Native fence waits use the Vulkan completion/reset contract; requested nanosecond timeouts may be rounded by the driver. <a href="https://docs.vulkan.org/refpages/latest/refpages/source/vkWaitForFences.html">Khronos vkWaitForFences reference</a>.</p>
</main><script>const measurements=PLOTS;function compare(i){const [name,b,a]=measurements[i],scale=510/Math.max(b,a);document.getElementById('comparison').innerHTML=`<text x="10" y="25" fill="#e5edf7">${name}</text><text x="10" y="70" fill="#bbc9d8">Before</text><rect x="100" y="48" width="${b*scale}" height="30" fill="#74879b"/><text x="${110+b*scale}" y="70" fill="#e5edf7">${b.toFixed(3)} ms</text><text x="10" y="120" fill="#bbc9d8">After</text><rect x="100" y="98" width="${a*scale}" height="30" fill="#85dbcf"/><text x="${110+a*scale}" y="120" fill="#e5edf7">${a.toFixed(3)} ms</text>`}document.querySelectorAll('[data-case]').forEach(b=>b.onclick=()=>compare(+b.dataset.case));compare(0);
const cadence=CADENCE,max=Math.max(...cadence.map(x=>x.max_ms)),w=820,h=185,x=i=>70+i*w/Math.max(cadence.length-1,1),y=v=>230-h*v/max;let content=`<text x="70" y="20" fill="#bbc9d8">Content interval ms · mean / p95 / max</text>`;for(let i=0;i<4;i++){let v=max*i/3;content+=`<line x1="70" x2="900" y1="${y(v)}" y2="${y(v)}" stroke="#304052"/><text x="4" y="${y(v)+5}" fill="#bbc9d8">${v.toFixed(0)}</text>`}for(const [key,color] of [['max_ms','#73879d'],['p95_ms','#e3ba76'],['mean_ms','#85dbcf']])content+=`<polyline fill="none" stroke="${color}" stroke-width="2.5" points="${cadence.map((v,i)=>`${x(i)},${y(v[key])}`).join(' ')}"/>`;document.getElementById('cadence').innerHTML=content;</script></body></html>'''
    replacements = {"RUN": html.escape(run["run_id"]), "FLOW_RATIO": f'{flow["speedup"]:.2f}', "FLOW_BEFORE": f'{flow["before"]["elapsed_ns"]/1e6:.3f}', "FLOW_AFTER": f'{flow["after"]["elapsed_ns"]/1e6:.3f}', "WAITS_BEFORE": str(int(watcher_before)), "WAITS_AFTER": str(int(watcher_after)), "ROWS": rows, "RAW": raw, "BUTTONS": buttons, "CONTROLS": controls, "PLOTS": json.dumps(plots), "CADENCE": json.dumps(analysis["jitter"]), "STATUS": html.escape(manifest["status"])}
    for key, value in replacements.items():
        page = page.replace(key, value)
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(page)
    print(folder / "final/report.html")


if __name__ == "__main__":
    main()
