#!/usr/bin/env python3
"""Show source-verified vector runtime measurements and the remaining frame gap."""
import argparse
import hashlib
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    "lib/processor/ELF_processor/block_jit.zig", "lib/processor/ELF_processor/block_jit/core.zig",
    "lib/processor/ELF_processor/block_jit/vector_permute.zig", "lib/processor/ELF_processor/block_jit/wide_unpacks.zig",
    "lib/processor/ELF_processor/block_jit/vector_expansion_tests.zig", "lib/processor/ELF_processor/process.zig",
    "lib/processor/ELF_processor/process/impl/windows_sync.zig", "lib/processor/ELF_processor/process/impl/worker_runtime_pulse.zig",
    "lib/processor/ELF_processor/process/tests/vector_expansion.zig", "lib/processor/build.zig",
    "tools/benchmarks/compare_vector_expansion.py", "tools/benchmarks/report_vector_expansion.py",
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
    result = json.loads((folder / "results.json").read_text())
    assert result["after_core_sha256"] == sha(ROOT / SOURCES[1])
    assert result["before_core_sha256"] == sha(folder / "core-before.zig")
    for variant, record in result["binaries"].items():
        assert sha(folder / ("bench-" + variant)) == record["binary_sha256"]
    run = json.loads((folder / "run-identity.json").read_text())
    assert sha(Path(run["path"])) == run["sha256"]
    labels = {"permute128": "128-bit permutation", "permute256": "256-bit permutation", "unpack256": "256-bit unpack", "quad-copy": "Ordered load → permute → store", "scalar-control": "Scalar control"}
    order = ["unpack256", "permute128", "permute256", "quad-copy", "scalar-control"]
    rows = "".join(f'<tr><td>{labels[k]}</td><td>{result["summary"][k]["before_ns"]/1e6:.3f}</td><td>{result["summary"][k]["after_ns"]/1e6:.3f}</td><td>{result["summary"][k]["speedup"]:.2f}×</td></tr>' for k in order)
    code = "".join(f'<tr><td>{labels[k]}</td><td>{result["summary"][k]["before_code_bytes"]:,}</td><td>{result["summary"][k]["after_code_bytes"]:,}</td></tr>' for k in order)
    raw = "".join(f'<tr><td>{labels[r["case"]]}</td><td>{r["pair"]+1}</td><td>{r["variant"]}</td><td>{r["elapsed_ns"]/1e6:.3f}</td><td>{r["unpack_fallbacks"]:,}</td></tr>' for r in result["samples"])
    scalar = result["summary"]["scalar-control"]
    control_delta = (scalar["after_ns"] / scalar["before_ns"] - 1) * 100
    control_description = f"{abs(control_delta):.1f}% {'slower' if control_delta >= 0 else 'faster'}"
    plots = [[labels[k], result["summary"][k]["before_ns"]/1e6, result["summary"][k]["after_ns"]/1e6] for k in order]
    buttons = "".join(f'<button data-case="{n}">{labels[k]}</button>' for n, k in enumerate(order))
    page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rosette vector runtime evidence</title>
<style>body{{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:36px}}h1{{font-size:40px;line-height:1.15}}h2{{font-size:24px}}p{{color:#b9c7d6}}a{{color:#85dbcf}}.cards{{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}}.card{{background:#1c2837;padding:23px;border-radius:14px}}.value{{font-size:36px;color:#85dbcf;font-weight:750}}table{{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}}th,td{{padding:10px 12px;text-align:right;border-bottom:1px solid #304052}}td:first-child,th:first-child{{text-align:left}}tr:nth-child(even){{background:#17212d}}.note{{border-left:4px solid #85dbcf;padding:12px 20px;background:#17212d}}.scroll{{overflow:auto}}button{{color:#e5edf7;background:#27394c;border:1px solid #61778b;border-radius:8px;padding:10px;margin:4px;font:inherit}}svg{{width:100%;height:auto}}@media(max-width:700px){{.cards{{grid-template-columns:1fr}}main{{padding:20px}}h1{{font-size:31px}}td,th{{font-size:14px}}}}</style></head><body><main>
<h1>Rosette vector runtime evidence</h1><p>Run {run["run_id"]} · offline source comparison</p>
<p class="note">Production CPU executor, block JIT enabled on both sides. Xenia was not launched, and the fixtures submit no GPU work. The path ratios below are <strong>not game FPS multipliers</strong>.</p>
<div class="cards"><div class="card"><div class="value">{result['summary']['unpack256']['speedup']:.2f}×</div>Wide-unpack loop speedup<br>Former interpreter fallback</div><div class="card"><div class="value">{result['summary']['quad-copy']['speedup']:.2f}×</div>Ordered load / permutation / store<br>All 32 output bytes checked</div><div class="card"><div class="value">2.60×</div>Throughput gap to 30<br>From the recent 11.6 FPS snapshot</div></div>
<h2>What changed in the supplied run</h2><p>The last 32 completed content intervals average <strong>86.537 ms</strong>, compared with 100.388 ms at the end of the previous run. The new p95 is 101.216 ms and maximum 133.488 ms. These windows have no matched map/camera marker; they agree with the user’s report of more views above 10 FPS but do not establish a causal FPS percentage. Native WSI cadence is a proxy, not Xbox simulation speed.</p>
<p>At 30 FPS each frame has 33.3 ms. The recent mean needs about 2.60× throughput; its p95/max gaps need about 3.04×/4.00×. Slower title-screen views can need more. This is arithmetic on the supplied snapshot, not a prediction that these edits close that gap.</p>
<h2>Two CPU changes</h2><p>Variable VPERMILPS now builds all sixteen byte indexes with integer vector arithmetic: 12 emitted ARM words instead of 40. The low two bits of every control dword select a complete source dword. Pure 128-bit register permutations also participate in the existing XMM residency cache, with publication at observer and control-flow boundaries.</p>
<p>Twelve VEX.256 register unpack forms now use two native ZIP operations, one per 128-bit lane. Both source halves are read before either result half is stored, preserving aliases, flags and upper state. Memory, EVEX and other unhandled forms keep their existing routes. The preceding complete CPU profile recorded 5.38 million vunpcklpd fallbacks; the latest run lacks final CPU totals, so its live count is unknown.</p>
<h2>Seven alternating source comparisons</h2><p>Two standalone binaries differ only in the saved core translator source. All other ELF sources and named production dependencies are identical. Each vector fixture performs 200,000 iterations with eight operation groups; the scalar control performs 2,000,000 iterations. Both use native translation, with the old interpreter handling only missing templates. Results, loop counters and active native caches are checked before each sample is accepted.</p><div class="scroll"><table><thead><tr><th>Fixture</th><th>Before ms</th><th>After ms</th><th>Ratio</th></tr></thead><tbody>{rows}</tbody></table></div>
<div>{buttons}</div><svg id="chart" viewBox="0 0 780 180" role="img" aria-label="Selected fixture before and after elapsed milliseconds"></svg>
<p>The scalar control is {control_description} in these medians; its emitted code is identical in size. This control is retained instead of treating every measurement as an improvement.</p>
<details><summary>Generated code bytes for the whole fixture</summary><div class="scroll"><table><thead><tr><th>Fixture</th><th>Before bytes</th><th>After bytes</th></tr></thead><tbody>{code}</tbody></table></div><p>These are fixture totals, not the whole game’s code cache. Interpreter helper bodies are not included.</p></details>
<details><summary>All 70 checked samples</summary><div class="scroll"><table><thead><tr><th>Fixture</th><th>Pair</th><th>Source</th><th>ms</th><th>Unpack fallbacks</th></tr></thead><tbody>{raw}</tbody></table></div></details>
<h2>What remains measurable and unknown</h2><p>The current run still accumulates 163.295 seconds of queue-submit host time, including 153.296 seconds waiting for FSI queue room. Those overlapping host timers are not GPU utilization or a frame critical-path partition. Watchdog risk/severe counts are zero, and the maximum outstanding Metal buffers remains two.</p>
<p>The log ends without final CPU summaries. New <code>PE64 WORKER RUNTIME PULSE</code> rows report own-worker native throughput, fallback deltas, code size and aggregate fast-math counts every five seconds at the existing publication boundary. This does not walk another worker’s cache, needs no special flags and survives ordinary window-close logs. Its wall intervals include waits/spins and are not frame critical-path profiles.</p>
<h2>Correctness and delivery</h2><p>Tests cover 512 randomized permutation programs, 384 unpack programs across twelve forms and source/destination aliases, whole-register preservation, lane-local selection and excluded forms. Existing native SSE and production VPERMILPS checks remain in the focused gate. Audio, CPU memory ordering, Fast Path, GPU budgets and the 30 FPS ceiling are retained.</p><p id="delivery">{html.escape(manifest['status'])}</p>
<p><a href="../manifest.json">Source / gate / install identities</a> · <a href="../results.json">Measurements and compiler arguments</a> · <a href="../run-evidence.txt">Run excerpts</a> · <a href="../production-release.log">ReleaseFast focused gate</a> · <a href="../focused-debug.log">Debug focused gates</a></p>
<h2>Next normal run</h2><p>Compare the same map and moving camera, and inspect worker pulses for remaining unpacks and math counts. The local template gains are proven. Sustained 30 FPS still requires heavier scenes to meet the frame budget; these tests cannot promise a date or a whole-game multiplier.</p></main>
<script>const rows={json.dumps(plots)};function draw(i){{const [name,b,a]=rows[i],scale=540/Math.max(b,a);document.getElementById('chart').innerHTML=`<text x="10" y="26" fill="#e5edf7">${{name}}</text><text x="10" y="76" fill="#b9c7d6">Before</text><rect x="100" y="52" width="${{b*scale}}" height="30" rx="5" fill="#6d8095"/><text x="${{110+b*scale}}" y="75" fill="#e5edf7">${{b.toFixed(2)}} ms</text><text x="10" y="126" fill="#b9c7d6">After</text><rect x="100" y="102" width="${{a*scale}}" height="30" rx="5" fill="#85dbcf"/><text x="${{110+a*scale}}" y="125" fill="#e5edf7">${{a.toFixed(2)}} ms</text>`;}}document.querySelectorAll('[data-case]').forEach(b=>b.onclick=()=>draw(+b.dataset.case));draw(0);</script></body></html>'''
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(page)
    print(folder / "final/report.html")


if __name__ == "__main__":
    main()
