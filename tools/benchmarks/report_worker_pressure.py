#!/usr/bin/env python3
"""Hash-checked CPU scheduling evidence and phase-scoped Halo run analysis."""
import argparse
import hashlib
import html
import json
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LABELS = {"idle": "120 ms idle interval", "raw": "5 ms work gaps · raw memory polling", "notified": "5 ms work gaps · targeted notifications", "short": "200 µs work gaps", "productive": "Registers change on every yield"}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fields(line):
    return {k: (v == "true" if v in ("true", "false") else int(v)) for k, v in re.findall(r"\b(\w+)=(true|false|-?\d+)\b", line)}

def records(path, marker):
    return [fields(line) | {"line": i, "text": line} for i, line in enumerate(path.read_text().splitlines(), 1) if marker in line]

def benchmark(path, marker, modes):
    text = path.read_text()
    assert "3/3 steps succeeded" in text  # Build summary is authoritative.
    assert not any(int(n) for n in re.findall(r"(\d+) fail(?:ed)?\b", text)) and "compilation errors" not in text
    rows = []
    for line in text.splitlines():
        if not line.startswith(marker + " "):
            continue
        r = fields(line)
        mode = re.search(r"mode=(\w+)", line)
        r["mode"] = mode[1] if mode else "shader"
        rows.append(r)
    result = {}
    for mode in modes:
        subset = [r for r in rows if r["mode"] == mode]
        assert len(subset) == 14
        for pair in range(7):
            assert {r["enabled"] for r in subset if r["pair"] == pair} == {False, True}
        def median(key, on):
            return statistics.median(r[key] for r in subset if r["enabled"] == on)
        key = "cpu_ns" if marker == "WORKER_PRESSURE" else "peer_ns"
        before, after = median(key, False), median(key, True)
        result[mode] = {"before_ns": before, "after_ns": after, "ratio": before / after if after else None}
        if marker == "WORKER_PRESSURE":
            assert all(r["checked"] == (80 if mode in ("raw", "notified", "short") else 0) for r in subset)
            if mode in ("short", "productive"):
                assert all(r["parks"] == 0 for r in subset)
            for key in ("elapsed_ns", "p95_ns", "max_ns", "iterations", "parks"):
                result[mode][key] = {str(on): median(key, on) for on in (False, True)}
            result[mode]["largest_latency_ns"] = max(r["max_ns"] for r in subset if r["enabled"])
            result[mode]["pair_ratio_range"] = [min(next(r["cpu_ns"] for r in subset if r["pair"] == p and not r["enabled"]) / next(r["cpu_ns"] for r in subset if r["pair"] == p and r["enabled"]) for p in range(7)), max(next(r["cpu_ns"] for r in subset if r["pair"] == p and not r["enabled"]) / next(r["cpu_ns"] for r in subset if r["pair"] == p and r["enabled"]) for p in range(7))]
        else:
            assert all(r["result"] == -123 for r in subset)
            assert all("result=-123" in line for line in text.splitlines() if line.startswith(marker + " "))
            result[mode]["native_ns"] = {str(on): median("native_ns", on) for on in (False, True)}
    return {"samples": rows, "summary": result}

def parse_run(record):
    path = Path(record["path"])
    assert sha(path) == record["sha256"]
    def latest(marker):
        return records(path, marker)[-1]
    def highest(marker, key):
        return max(records(path, marker), key=lambda r: (r[key], r["line"]))
    policy = highest("METAL COMMAND BUFFER POLICY:", "room_wait_ms")
    guard = highest("VULKAN FSI GUARD: armed=", "fsi_draws")
    reasons = latest("VULKAN FSI SPLIT REASONS:")
    recovery = highest("VULKAN FSI CPU ROUTE:", "synchronous_commands")
    queue = highest("FRAME HOST COST: stage=queue_submit", "total_us")
    cadence = latest("FRAME CADENCE JITTER:")
    # Some reports replay saved startup profiles at the end. Retain their
    # scope and greatest cumulative values rather than calling them final.
    holds = records(path, "PE64 RUNTIME LOCK HOLDS:")
    shader_holds = [r for r in holds if "call=vkCreateShaderModule " in r["text"]]
    shader_hold = max(shader_holds, key=lambda r: r["held_ms"]) if shader_holds else None
    shader_host = highest("name=vkCreateShaderModule calls=", "calls")
    scheduling = latest("nt_delay(parks/yields)")
    delay = re.search(r"nt_delay\(parks/yields\)=(\d+)/(\d+)", scheduling["text"])
    required = sum(reasons[k] for k in ("draw_only", "work_only", "draw_work", "isolation_only", "draw_isolation", "work_isolation", "all"))
    work = sum(reasons[k] for k in ("work_only", "draw_work", "work_isolation", "all"))
    live_yields = records(path, "PE64 WORKER YIELD BACKOFF:")
    live_shader = records(path, "PE64 NATIVE SHADER LOCK ROUTE:")
    return {"live_yield_backoff": max(live_yields, key=lambda r: r["explicit"]) if live_yields else None, "live_shader_lock": max(live_shader, key=lambda r: r["calls"]) if live_shader else None, "policy": policy, "guard": guard, "split_reasons": reasons, "recovery": recovery, "queue": queue, "cadence": cadence, "shader_hold_startup": shader_hold, "shader_host": shader_host, "nt_yields": int(delay[2]), "nt_parks": int(delay[1]), "work_boundary_percent": 100 * work / required}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    folder = parser.parse_args().evidence.resolve()
    manifest = json.loads((folder / "manifest.json").read_text())
    for file, identity in manifest["sources"].items():
        assert sha(ROOT / file) == identity, f"Source changed: {file}"
    for file, identity in manifest["evidence"].items():
        assert sha(folder / file) == identity, f"Evidence changed: {file}"
    for file in ("cpu-debug.log", "graphics-debug.log", "graphics-release.log"):
        assert re.search(r"Build Summary: (\d+)/\1 steps succeeded", (folder / file).read_text())
    results = {"workers": benchmark(folder / "worker-bench-final.log", "WORKER_PRESSURE", LABELS), "shader": benchmark(folder / "shader-lock-final.log", "SHADER_LOCK", ("shader",)), "runs": {name: parse_run(r) for name, r in manifest["runs"].items()}}
    (folder / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    ws, ss = results["workers"]["summary"], results["shader"]["summary"]["shader"]
    cpu_rows = "".join(f'<tr><td>{LABELS[k]}</td><td>{v["before_ns"]/1e6:.3f}</td><td>{v["after_ns"]/1e6:.3f}</td><td>{v["ratio"]:.2f}×</td><td>{v["p95_ns"]["False"]/1e6:.3f} → {v["p95_ns"]["True"]/1e6:.3f}</td><td>{v["largest_latency_ns"]/1e6:.3f}</td></tr>' for k, v in ws.items())
    run_rows = "".join(f'<tr><td>{name}</td><td>{r["nt_yields"]:,}</td><td>{r["policy"]["room_wait_ms"]/1000:.3f}</td><td>{r["queue"]["total_us"]/1e6:.3f}</td><td>{r["work_boundary_percent"]:.1f}%</td><td>{r["guard"]["cap_now"]}</td><td>{r["policy"]["adaptive_sample_work_cap"]:,}</td></tr>' for name, r in results["runs"].items())
    cadence_rows = "".join(f'<tr><td>{name}</td><td>{re.search(r"mean_ms=([\d.]+)", r["cadence"]["text"])[1]}</td><td>{re.search(r"p95_ms=([\d.]+)", r["cadence"]["text"])[1]}</td></tr>' for name, r in results["runs"].items())
    plot = [[LABELS[k], v["before_ns"] / 1e6, v["after_ns"] / 1e6] for k, v in ws.items()]
    buttons = "".join(f'<button data-case="{i}">{html.escape(LABELS[k])}</button>' for i, k in enumerate(ws))
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rosette · Worker pressure and shader lock availability</title><style>
body{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}main{max-width:1170px;margin:auto;padding:36px}h1{font-size:39px;line-height:1.2}h2{margin-top:36px}p{color:#bfccda}a{color:#8bdacf}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.card{background:#1b2838;padding:24px;border-radius:14px}.value{font-size:38px;color:#8bdacf;font-weight:750}.note{border-left:4px solid #8bdacf;background:#172230;padding:16px 22px}.scroll{overflow:auto}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}td,th{padding:12px;text-align:right;border-bottom:1px solid #304153}td:first-child,th:first-child{text-align:left}button{border:1px solid #455d73;border-radius:8px;background:#22374c;color:#e5edf7;padding:10px 14px;margin:4px;cursor:pointer}button[aria-pressed=true]{border-color:#8bdacf;background:#315653}code{color:#a9dacb}details{margin:16px 0}svg{width:100%;background:#162332;border-radius:10px}@media(max-width:780px){main{padding:20px}.cards{grid-template-columns:1fr}h1{font-size:30px}}
</style><main><h1>Rosette worker pressure &amp; shader lock availability</h1><p>Round 54 · two supplied runs · source changes with CPU-only production proofs</p><div class="note">Full Zig suite, shell update and installation remain pending. These are CPU and lock-availability measurements, not gameplay FPS multipliers. Xenia was never launched and no GPU work was dispatched.</div>
<div class="cards"><div class="card"><div class="value">IDLE×</div>less CPU in four idle pollers</div><div class="card"><div class="value">RAW×</div>less CPU with work every 5 ms</div><div class="card"><div class="value">PEER µs</div>peer lock wait during a 150 ms native stub</div></div>
<h2 id="worker-pressure">Repeated zero-delay yields now have bounded backoff</h2><p>The new runs contain 55.16 million and 45.82 million zero-delay NT yields. Faster dispatch makes waiting cheaper, but allows the waiting loops to poll more often. The startup-only fast-lane summary is not their final eligibility count.</p><p>Generic named Xbox workers qualify only after at least 2 ms at the same PC and stack, with unchanged register snapshot and frame, short retired-instruction gaps and frequent calls. Their own wake event can interrupt a requested 100–500 µs host wait. Main, render, GPU, audio, timer and unnamed workers retain ordinary yielding; timed/alertable calls and Xenia-global lock owners retain their prior route. Short waits and changing register state never parked in the controls.</p><p>Seven alternating pairs per case: four actual production workers, real host yields/events and thread CPU clocks. All 3,360 producer/consumer acknowledgements and checksums passed. Raw memory changes do not notify the event, so they can pay the additional bounded polling delay shown below. Actual host scheduling can overshoot the requested deadline.</p><div class="scroll"><table><tr><th>Fixture</th><th>Before CPU ms</th><th>After CPU ms</th><th>CPU reduction</th><th>p95 handoff ms</th><th>Largest after ms</th></tr>CPU_ROWS</table></div><p>CPU time sums four threads over a roughly 120 ms interval. It can exceed elapsed wall time. The short/progressing controls measure extra qualification overhead too; their polling iteration counts are in the raw data. Useful-work throughput and game-thread eligibility still need a normal run.</p><div>BUTTONS</div><svg id="comparison" viewBox="0 0 850 165" role="img" aria-label="Selected scheduling CPU comparison"></svg>
<h2 id="shader-lock">Long shader creation no longer pins every runtime import</h2><p>Custom Games’ saved startup lock profile names 61 shader creates holding the runtime lock for 47.303 s, including one 12.252 s hold. Its later Vulkan entry-point ledger records 471 module calls over 61.276 s including marshalling and compilation. Campaign’s saved shader hold total is only 0.656 s. These measurements have different phase scopes.</p><p>Rosette now owns the marshalled header and original SPIR-V before rewriting, then releases only dispatch-level runtime locks around the native driver call. Proofs, result publication and handle mapping occur after reacquisition. Pinned sections stay locked. Existing bounds, rectangle, HDR and pixel-frequency transforms retain their ordering and refusal behavior.</p><p>In seven alternating CPU-only stub comparisons, the peer wait fell from SHADER_BEFORE ms to SHADER_AFTER µs. Native elapsed medians remained NATIVE_BEFORE/NATIVE_AFTER ms. Every returned error was preserved; a peer memory mutation finished while the native call was a safepoint. Ownership tests overwrite the entire shared marshal arena and shared creation result during the call; original code, header and the caller’s returned result survive.</p><p>Concurrent native calls can finish out of order. The Windows Vulkan adapter now releases scratch stacks by their owned address rather than decrementing depth and reusing another call’s live slot. Sequential reuse, allocation refusal and out-of-order completion tests pass.</p>
<h2 id="fragmentation">The split ledger identifies a remaining bottleneck</h2><div class="scroll"><table><tr><th>Run</th><th>NT zero yields</th><th>Room wait s</th><th>Queue host s</th><th>Work-limited decisions</th><th>Draw cap</th><th>Sample-work cap</th></tr>RUN_ROWS</table></div><p>Room wait is already included in queue-submit host time; do not add them. These are host timings, not GPU execution time or utilization. Work limits explain most requested boundaries, with overlaps preserved. Campaign recorded two risk warnings and ended with a draw cap of four; GPU budgets, depth two, shader bounds and tessellation isolation remain intact.</p><p>The campaign recovery route did qualify: its greatest live census shows 2,523,667 synchronous commands, 150 fast groups and two recovery growths. Saved startup snapshots report zero. The parser selects greatest cumulative observations and keeps their source line numbers instead of mistaking a replayed startup report for the final state.</p><h2>Picture cadence still needs substantial improvement</h2><div class="scroll"><table><tr><th>Latest 32 picture gaps</th><th>Mean ms</th><th>p95 ms</th></tr>CADENCE_ROWS</table></div><p>Camera and scene labels are unmatched. The new CPU routes may free resources for useful work and avoid compilation stalls, but these inputs cannot establish an FPS prediction or a locked 30 FPS outcome.</p>
<h2>Delivery and the next ordinary run</h2><p>STATUS</p><p>The new live counters are <code>PE64 WORKER YIELD BACKOFF</code> and <code>PE64 NATIVE SHADER LOCK ROUTE</code>. The next run will show how often the conservative backoff actually qualifies, its host wait duration and whether shader calls released the lock. No special game flags are required. Audio, TSO, Fast Path and the 30 FPS ceiling are retained.</p><details><summary>Evidence and reproducibility</summary><p><a href="../results.json">All 84 measured samples and parsed runs</a> · <a href="../manifest.json">Source, binary, log and command identities</a> · <a href="../worker-bench-final.log">Worker CPU raw measurements</a> · <a href="../shader-lock-final.log">Native lock raw measurements</a> · <a href="../cpu-debug.log">CPU Debug checks</a> · <a href="../graphics-debug.log">Graphics Debug checks</a> · <a href="../graphics-release.log">Graphics ReleaseFast checks</a> · <a href="../source-size.log">Size audit</a> · <a href="../guest-context.log">Calling-context audit</a></p></details></main>
<script>const rows=PLOT;function show(i){let [name,b,a]=rows[i],scale=520/Math.max(b,a);document.getElementById('comparison').innerHTML=`<text x="20" y="28" fill="#e5edf7">${name}</text><text x="20" y="75" fill="#bfccda">Before</text><rect x="110" y="53" width="${b*scale}" height="30" fill="#75899f"/><text x="${120+b*scale}" y="75" fill="#e5edf7">${b.toFixed(3)} CPU ms</text><text x="20" y="125" fill="#bfccda">After</text><rect x="110" y="103" width="${a*scale}" height="30" fill="#8bdacf"/><text x="${120+a*scale}" y="125" fill="#e5edf7">${a.toFixed(3)} CPU ms</text>`;document.querySelectorAll('[data-case]').forEach(x=>x.setAttribute('aria-pressed',+x.dataset.case===i))}document.querySelectorAll('[data-case]').forEach(x=>x.onclick=()=>show(+x.dataset.case));show(0);</script></html>'''
    replace = {"IDLE": f'{ws["idle"]["ratio"]:.1f}', "RAW": f'{ws["raw"]["ratio"]:.2f}', "PEER": f'{ss["after_ns"]/1000:.0f}', "SHADER_BEFORE": f'{ss["before_ns"]/1e6:.3f}', "SHADER_AFTER": f'{ss["after_ns"]/1000:.0f}', "NATIVE_BEFORE": f'{ss["native_ns"]["False"]/1e6:.3f}', "NATIVE_AFTER": f'{ss["native_ns"]["True"]/1e6:.3f}', "CPU_ROWS": cpu_rows, "RUN_ROWS": run_rows, "CADENCE_ROWS": cadence_rows, "BUTTONS": buttons, "PLOT": json.dumps(plot), "STATUS": html.escape(manifest["status"])}
    for key in sorted(replace, key=len, reverse=True):
        page = page.replace(key, replace[key])
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(page)
    print(json.dumps({k: round(v["ratio"], 3) for k, v in ws.items()}))

if __name__ == "__main__":
    main()
