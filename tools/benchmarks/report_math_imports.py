#!/usr/bin/env python3
"""Render checked production math-lane measurements and current delivery state."""
import argparse
import hashlib
import html
import json
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    "src/x64-ASM/windows_runtime.zig",
    "src/x64-ASM/windows_runtime/crt_math.zig",
    "src/x64-ASM/windows_runtime/fast_math.zig",
    "lib/processor/ELF_processor/process.zig",
    "lib/processor/ELF_processor/process/state.zig",
    "lib/processor/ELF_processor/process/impl/lifecycle.zig",
    "lib/processor/ELF_processor/process/impl/block_jit.zig",
    "lib/processor/ELF_processor/process/impl/windows_fast_math.zig",
    "lib/processor/ELF_processor/process/tests/windows_fast_math.zig",
    "lib/processor/ELF_processor/process/tests/vector_extract.zig",
    "lib/processor/ELF_processor/block_jit/core.zig",
    "build/folders/lib/processor.zig",
    "tools/benchmarks/report_math_imports.py",
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def measurements(text):
    grouped = {"call": [], "thunk": [], "parallel": []}
    for line in text.splitlines():
        if not line.startswith(("MATH_BENCH ", "MATH_PARALLEL ")):
            continue
        row = dict(re.findall(r"(\w+)=([^ ]+)", line))
        key = "parallel" if line.startswith("MATH_PARALLEL") else "thunk" if row["tail"] == "true" else "call"
        grouped[key].append({"pair": int(row["pair"]), "enabled": row["enabled"] == "true", "iterations": int(row["iterations"]), "ns": int(row["elapsed_ns"]), "steps": int(row["steps"]) if "steps" in row else None, "fast_calls": int(row["fast_calls"])})
    summary = {}
    for key, rows in grouped.items():
        assert len(rows) == 14 and len({r["pair"] for r in rows}) == 7, key
        for pair in range(7):
            matched = [r for r in rows if r["pair"] == pair]
            assert len(matched) == 2 and {r["enabled"] for r in matched} == {True, False}
        for row in rows:
            assert row["fast_calls"] == (row["iterations"] if row["enabled"] else 0)
        before = statistics.median(r["ns"] for r in rows if not r["enabled"])
        after = statistics.median(r["ns"] for r in rows if r["enabled"])
        summary[key] = {"before_ns": before, "after_ns": after, "speedup": before / after}
    return {"samples": grouped, "summary": summary}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    folder = args.evidence.resolve()
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, expected in manifest["sources"].items():
        assert digest(ROOT / name) == expected, f"Source changed: {name}"
    assert digest(folder / "bench.log") == manifest["bench_sha256"]
    run = json.loads((folder / "run-identity.json").read_text())
    assert digest(Path(run["path"])) == run["sha256"], "Run identity changed"
    log = (folder / "bench.log").read_text()
    assert "12/12 tests passed" in log
    data = measurements(log)
    (folder / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    titles = {"call": "Translated call [IAT]", "thunk": "Translated call → jmp [IAT]", "parallel": "Four concurrent CRT callers"}
    rows = "".join(f'<tr><td>{titles[k]}</td><td>{v["before_ns"]/1e6:.3f}</td><td>{v["after_ns"]/1e6:.3f}</td><td>{v["speedup"]:.2f}×</td></tr>' for k, v in data["summary"].items())
    raw = "".join(f'<tr><td>{titles[k]}</td><td>{r["pair"]+1}</td><td>{"Fast" if r["enabled"] else "General"}</td><td>{r["ns"]/1e6:.3f}</td><td>{r["steps"] if r["steps"] is not None else "—"}</td></tr>' for k, values in data["samples"].items() for r in values)
    chart = [[titles[k], v["before_ns"]/1e6, v["after_ns"]/1e6] for k, v in data["summary"].items()]
    buttons = "".join(f'<button data-choice="{n}">{html.escape(row[0])}</button>' for n, row in enumerate(chart))
    page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rosette CPU math evidence</title>
<style>body{{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:36px}}h1{{font-size:40px;line-height:1.15}}h2{{font-size:24px}}p{{color:#b9c7d6}}a{{color:#85dbcf}}.cards{{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}}.card{{background:#1c2837;padding:23px;border-radius:14px}}.value{{font-size:36px;color:#85dbcf;font-weight:750}}table{{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}}th,td{{padding:10px 12px;text-align:right;border-bottom:1px solid #304052}}td:first-child,th:first-child{{text-align:left}}tr:nth-child(even){{background:#17212d}}.note{{border-left:4px solid #85dbcf;padding:12px 20px;background:#17212d}}.scroll{{overflow:auto}}button{{color:#e5edf7;background:#27394c;border:1px solid #61778b;border-radius:8px;padding:10px;margin:4px;font:inherit}}svg{{width:100%;height:auto}}@media(max-width:700px){{.cards{{grid-template-columns:1fr}}main{{padding:20px}}h1{{font-size:31px}}td,th{{font-size:14px}}}}</style></head><body><main>
<h1>Rosette CPU math evidence</h1><p>October 12, 2026 · supplied run {run["run_id"]}</p>
<p class="note">Offline CPU tests of production CRT imports and translated loops. Xenia was not launched and these tests submit no GPU work. Measured path ratios are <strong>not Halo FPS forecasts</strong>.</p>
<div class="cards"><div class="card"><div class="value">{data['summary']['call']['speedup']:.2f}×</div>Translated math call loop<br>100,000 calls per trial</div><div class="card"><div class="value">{data['summary']['parallel']['speedup']:.2f}×</div>Four simultaneous callers<br>100,000 checked results per trial</div><div class="card"><div class="value">4,096</div>Exact numeric / ABI comparisons<br>Both widths, eight MXCSR modes</div></div>
<h2>The new run identifies an import bottleneck</h2><p>The sampled import histogram estimates 87.879 seconds in 15,060,762 <code>exp2</code> imports, averaging 5,835 ns. This timer is sampled and includes dispatch; it is not a wall-time partition or an isolated title-screen profile. The new lane handles those exact registered CRT imports without the shared runtime mutex, general import snapshots or interpreter dispatch. It uses the ordinary math implementation.</p>
<p>Last pass’s command snapshots are live: 1,870,511 descriptor binds and 120,801 push constants used owned payloads. Pending worker barriers per FSI draw fell from 0.5803 to 0.1941 across the two runs. The scenes and durations differ, so this supports route activity, not a causal FPS percentage. The latest FSI monitor recorded zero risk/severe events and at most two outstanding Metal buffers.</p>
<h2>Checked before / after measurements</h2><p>Seven alternating comparisons, medians in milliseconds. Baseline uses the ordinary dispatcher with only the new math lane disabled; the block translator stays enabled in both translated fixtures. Each parallel caller checks every result. The translated fixtures check loop completion, result, return stack, counters and an active native cache.</p><div class="scroll"><table><thead><tr><th>100,000-call fixture</th><th>General ms</th><th>Fast ms</th><th>Ratio</th></tr></thead><tbody>{rows}</tbody></table></div>
<div>{buttons}</div><svg id="chart" viewBox="0 0 780 180" role="img" aria-label="Selected CPU fixture elapsed milliseconds"></svg>
<details><summary>All alternating samples and dispatch steps</summary><div class="scroll"><table><thead><tr><th>Fixture</th><th>Pair</th><th>Route</th><th>ms</th><th>Steps</th></tr></thead><tbody>{raw}</tbody></table></div></details>
<h2>A measured missing native instruction</h2><p>The run recorded 8,606,066 <code>vextractps</code> fallbacks (sampled estimated interpreter time 8.735 seconds). VEX.128 extraction now shares the existing PEXTRD ARM64 bit-copy template. The raw-byte regression checks 512 lane outputs, high registers, ignored immediate bits, flags, GPR zero-extension, vector upper-state preservation and exact memory widths; the translated fixture has zero extraction fallbacks. No separate extraction speed ratio or game-FPS gain is claimed.</p>
<h2>Numeric and synchronization contract</h2><p>The pure-math lane serves only exp2/exp2f from three exact CRT DLL identities, verifies the live IAT or registered dynamic stub through the existing adapter, and declines ABI diagnostics, active memory traces, missing direct returns or recursive runtime-lock ownership. The return-stack pop, calling-thread XMM0 and LastError behavior remain unchanged. Runtime-call TSO stores drain and the bound store buffer is restored. Both routes share the same exp2 implementation; no approximation, gamma adjustment, GPU-budget change or audio reduction is introduced.</p>
<h2>Verification and delivery</h2><p id="delivery">{html.escape(manifest['status'])}</p><p><a href="../manifest.json">Source and delivery manifest</a> · <a href="../results.json">All measurements</a> · <a href="../bench.log">ReleaseFast test and benchmark log</a> · <a href="../focused-debug.log">Debug focused gate</a> · <a href="../run-evidence.txt">Run counters</a></p>
<h2>What the next normal run can establish</h2><p>The log adds <code>PE64 WINDOWS FAST MATH</code> with exp2/exp2f counts; remaining exp2 calls in the ordinary histogram identify ineligible cases. Compare a matched moving-camera section and Custom Games map. The user’s 12 FPS peak is progress, while locked 30 requires moving frames to consistently meet 33.3 ms. GPU backpressure, broader translation throughput and other missing templates remain; this evidence cannot establish a date or guarantee for locked 30 FPS.</p></main>
<script>const rows={json.dumps(chart)};function draw(i){{const [name,b,a]=rows[i],scale=540/Math.max(b,a);document.getElementById('chart').innerHTML=`<text x="10" y="26" fill="#e5edf7">${{name}}</text><text x="10" y="76" fill="#b9c7d6">General</text><rect x="100" y="52" width="${{b*scale}}" height="30" rx="5" fill="#6d8095"/><text x="${{110+b*scale}}" y="75" fill="#e5edf7">${{b.toFixed(2)}} ms</text><text x="10" y="126" fill="#b9c7d6">Fast</text><rect x="100" y="102" width="${{a*scale}}" height="30" rx="5" fill="#85dbcf"/><text x="${{110+a*scale}}" y="125" fill="#e5edf7">${{a.toFixed(2)}} ms</text>`;}}document.querySelectorAll('[data-choice]').forEach(b=>b.onclick=()=>draw(+b.dataset.choice));draw(0);</script></body></html>'''
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(page)
    print(folder / "final/report.html")


if __name__ == "__main__":
    main()
