#!/usr/bin/env python3
"""Render hash-checked NT-yield comparisons and cumulative fence costs."""
import argparse
import hashlib
import html
import json
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LABELS = {
    "dynamic_register": "Dynamic call through a register",
    "dynamic_tail": "Call → jump through a register",
    "iat": "Call through a verified IAT slot",
    "iat_tail": "Call → jump through an IAT slot",
    "parallel": "Four concurrent import callers",
    "parallel_host_yield": "Four callers with actual host yields",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fields(line):
    return dict(value.split("=", 1) for value in line.split()[1:])


def measurements(folder):
    raw = (folder / "measurements-final.log").read_text()
    assert re.search(r"\d+ passed; \d+ skipped; 0 failed", raw), "Benchmarks did not complete"
    rows = []
    for line in raw.splitlines():
        marker = re.search(r"\b(nt_yield|nt_register|nt_concurrent) pair=", line)
        if marker is None:
            continue
        line = line[marker.start():]
        row = fields(line)
        if line.startswith("nt_concurrent "):
            case = "parallel_host_yield" if row["host_yield"] == "true" else "parallel"
        elif line.startswith("nt_register "):
            case = "dynamic_tail" if row["tail"] == "true" else "dynamic_register"
        else:
            case = "iat_tail" if row["tail"] == "true" else "iat"
        row = {k: (v == "true" if v in ("true", "false") else int(v)) for k, v in row.items()}
        row["case"] = case
        assert row["calls"] == 100000
        assert row["runtime_locks"] == (0 if row["enabled"] else row["calls"])
        if "yields" in row:
            assert row["yields"] == row["calls"]
        rows.append(row)
    summary = {}
    for case in LABELS:
        subset = [r for r in rows if r["case"] == case]
        assert len(subset) == 14 and {r["pair"] for r in subset} == set(range(7))
        for pair in range(7):
            assert {r["enabled"] for r in subset if r["pair"] == pair} == {True, False}
        before = statistics.median(r["elapsed_ns"] for r in subset if not r["enabled"])
        after = statistics.median(r["elapsed_ns"] for r in subset if r["enabled"])
        ratios = [next(r["elapsed_ns"] for r in subset if r["pair"] == p and not r["enabled"]) / next(r["elapsed_ns"] for r in subset if r["pair"] == p and r["enabled"]) for p in range(7)]
        summary[case] = {"before_ns": before, "after_ns": after, "ratio": before / after, "pair_min": min(ratios), "pair_max": max(ratios)}
    return {"basis": "Seven alternating ReleaseFast comparisons, lane disabled versus enabled; production adapters, CPU only. No GPU or Xenia dispatch and no FPS forecast.", "summary": summary, "samples": rows}


def parse_run(record):
    lines = Path(record["path"]).read_text().splitlines()
    def last(key):
        hits = [l for l in lines if key in l]
        assert hits, key
        return hits[-1]
    def number(line, key):
        return int(re.search(rf"\b{re.escape(key)}=(\d+)", line)[1])
    guard = last("VULKAN FSI GUARD: armed=")
    policy = last("METAL COMMAND BUFFER POLICY:")
    frame = last("FRAME HOST COST: present_intervals=")
    queue = last("FRAME HOST COST: stage=queue_submit")
    observer = last("VULKAN FSI ROOM OBSERVER:")
    delay = re.search(r"nt_delay\(parks/yields\)=(\d+)/(\d+)", last("nt_delay(parks/yields)"))
    pause = re.search(r"pause_hints\(serial_global/thread_sum\)=\d+/(\d+)", last("pause_hints(serial_global/thread_sum)"))
    cadence = []
    for line in lines:
        m = re.search(r"FRAME CADENCE JITTER: completed_content_intervals=(\d+) mean_ms=([\d.]+) p95_ms=([\d.]+) max_ms=([\d.]+)", line)
        if m:
            cadence.append(dict(count=int(m[1]), mean_ms=float(m[2]), p95_ms=float(m[3]), max_ms=float(m[4])))
    return dict(run_id=record["run_id"], draws=number(guard, "fsi_draws"), splits=number(guard, "splits"),
                groups=number(guard, "timing_groups_timed"), room_ms=number(policy, "room_wait_ms"),
                queue_ms=number(queue, "total_us") / 1000, intervals=number(frame, "present_intervals"),
                interval_ms=number(frame, "total_ms"), draw_cap=number(guard, "cap_now"), work_cap=number(policy, "adaptive_sample_work_cap"),
                inline=number(observer, "inline_completions"), watcher=number(observer, "watcher_waits"),
                nt_parks=int(delay[1]), nt_yields=int(delay[2]), pauses=int(pause[1]), cadence=cadence,
                split_reasons="unknown: this run predates the new reason ledger")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("evidence", type=Path)
    args = ap.parse_args()
    folder = args.evidence.resolve()
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, identity in manifest["sources"].items():
        assert sha(ROOT / name) == identity, f"Source changed: {name}"
    for name, identity in manifest["evidence"].items():
        assert sha(folder / name) == identity, f"Evidence changed: {name}"
    runs = json.loads((folder / "runs.json").read_text())
    for run in runs.values():
        assert sha(Path(run["path"])) == run["sha256"]
    result = measurements(folder)
    result["runs"] = {name: parse_run(record) for name, record in runs.items()}
    result["binary_sha256"] = sha(folder / "nt-yield-final-bench")
    (folder / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    table = "".join(f'<tr><td>{LABELS[c]}</td><td>{v["before_ns"]/1e6:.3f}</td><td>{v["after_ns"]/1e6:.3f}</td><td>{v["ratio"]:.2f}×</td><td>{v["pair_min"]:.2f}–{v["pair_max"]:.2f}×</td></tr>' for c, v in result["summary"].items())
    run_rows = "".join(f'<tr><td>{name.title()}</td><td>{r["draws"]:,}</td><td>{r["splits"]:,}</td><td>{r["groups"]:,}</td><td>{r["room_ms"]/1000:.3f}</td><td>{r["room_ms"]/r["groups"]:.3f}</td><td>{r["queue_ms"]/1000:.3f}</td></tr>' for name, r in result["runs"].items())
    cadence_rows = "".join(f'<tr><td>{name.title()}</td><td>{r["cadence"][-1]["mean_ms"]:.3f}</td><td>{r["cadence"][-1]["p95_ms"]:.3f}</td><td>{r["cadence"][-1]["max_ms"]:.3f}</td></tr>' for name, r in result["runs"].items())
    raw_rows = "".join(f'<tr><td>{LABELS[r["case"]]}</td><td>{r["pair"]+1}</td><td>{"Enabled" if r["enabled"] else "Disabled"}</td><td>{r["elapsed_ns"]/1e6:.3f}</td><td>{r["runtime_locks"]:,}</td></tr>' for r in result["samples"])
    buttons = "".join(f'<button data-case="{i}">{label}</button>' for i, label in enumerate(LABELS.values()))
    plot = [[LABELS[c], v["before_ns"]/1e6, v["after_ns"]/1e6] for c, v in result["summary"].items()]
    ratios = result["summary"]
    page = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Rosette yield overhead and fence costs</title>
<style>body{margin:0;background:#10161f;color:#e5edf7;font:17px/1.6 system-ui}main{max-width:1160px;margin:auto;padding:36px}h1{font-size:39px;line-height:1.15}h2{margin-top:36px;font-size:25px}p{color:#bcc9d8}a{color:#85dbcf}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.card{background:#1c2837;padding:22px;border-radius:14px}.value{font-size:37px;color:#85dbcf;font-weight:750}.note{background:#17212d;border-left:4px solid #85dbcf;padding:14px 20px}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}td,th{padding:10px 12px;text-align:right;border-bottom:1px solid #304052}td:first-child,th:first-child{text-align:left}tr:nth-child(even){background:#17212d}button{background:#27394c;color:#e5edf7;border:1px solid #61778b;border-radius:8px;padding:9px;margin:4px;font:inherit}svg{width:100%;height:auto}details{margin-top:18px}code{color:#aee8dd}@media(max-width:700px){.cards{grid-template-columns:1fr}main{padding:20px}h1{font-size:30px}td,th{font-size:13px}}</style></head><body><main>
<h1>Rosette yield overhead and fence costs</h1><p>October 13, 2026 · source-only pass · Custom Games and campaign logs</p>
<p class="note">The measured gain is in CPU import dispatch. <strong>It is not a gameplay FPS multiplier.</strong> All benchmarks run production Rosette code without Xenia or GPU dispatch. Seven alternating comparisons retain every requested yield. Full Zig gates and installation are deferred to your other agent.</p>
<div class="cards"><div class="card"><div class="value">REG_RATIO×</div>Dynamic register tail-jump path<br>The form behind the largest transfer count</div><div class="card"><div class="value">HOST_RATIO×</div>Four callers, actual host yields<br>100,000 checked calls per sample</div><div class="card"><div class="value">11.26 M</div>Observed Custom Games NT yields<br>35,052 timed parks retain ordinary dispatch</div></div>
<h2 id="cpu">A yield no longer needs the shared Windows runtime lock</h2><p>Custom Games recorded 11,296,717 NtDelayExecution imports and 11,261,666 NT scheduler yields. Campaign recorded 7,312,965 imports and 7,278,897 yields. Xenia’s read-only MaybeYield source calls NtDelayExecution with a literal zero interval. This makes zero-delay dispatch a concrete high-volume target; the logs alone do not identify the interval or global-lock ownership of every call.</p>
<p>Exact registered NT zero-delay imports now use the existing validated IAT or dynamic-stub adapters. The fast lane preserves the calling context, ABI return, LastError, store-buffer publication and host scheduling request. Nonzero, alertable, invalid-pointer, diagnostic, retired-instruction-clock and lock-owned calls continue through ordinary dispatch. It does not remove or batch host yields, change PAUSE scheduling, speed game time or bypass synchronization ownership.</p>
<h2 id="measurements">Quantified CPU comparisons</h2><p>ReleaseFast, seven alternating disabled/enabled pairs on the same final source. Dynamic register calls and register tail jumps exercise the registered heap-stub route used by Xenia; IAT forms provide separate controls. The translated loops have block JIT enabled in both variants. Dynamic register-transfer fallback counts may remain high: the registered import handler becomes cheaper even when a checked transfer is still required. Four concurrent callers retain independent guest contexts; the host-yield case invokes the host scheduler after every successful call. Every sample checks completion, results, stack or context, yield totals and lock counts.</p>
<div class="scroll"><table><thead><tr><th>Production fixture</th><th>Disabled ms</th><th>Enabled ms</th><th>Ratio of medians</th><th>Per-pair range</th></tr></thead><tbody>TABLE</tbody></table></div>
<p>Each 100,000-call sample changes from 100,000 runtime-lock acquisitions to zero. These small fixtures omit Halo’s working set and guest work between yields. They establish dispatch throughput, not the fraction of a moving frame spent here. The higher concurrent ratio includes relief from competing callers and host scheduling; it is not an isolated single-call latency measurement.</p>
<div>BUTTONS</div><svg id="comparison" viewBox="0 0 830 170" role="img" aria-label="Selected disabled versus enabled dispatch comparison"></svg>
<details><summary>All 84 checked samples</summary><div class="scroll"><table><thead><tr><th>Fixture</th><th>Pair</th><th>Lane</th><th>ms</th><th>Runtime locks</th></tr></thead><tbody>RAW</tbody></table></div></details>
<h2 id="fences">Small fence waits accumulate</h2><p>The previous FIFO and room-observer changes are live: Custom Games completed 113,204 fences inline, campaign 121,871. Barrier snapshots reached 249,735 and 93,236 respectively. The remaining queue-room durations are substantial despite the low average per group.</p>
<div class="scroll"><table><thead><tr><th>Run</th><th>FSI draws</th><th>Splits</th><th>Timing groups</th><th>Room wait s</th><th>Room ms/group</th><th>Queue-submit host s</th></tr></thead><tbody>RUNS</tbody></table></div>
<p>Room waits are included in queue-submit host time; do not add those columns. These are host durations, not GPU utilization or GPU execution time. The Custom Games aggregate contains 2,168 present intervals over 468.979 seconds; campaign contains 1,110 over 318.836 seconds. Introduction, menu and gameplay scenes are mixed. A low average fence time does not establish that submission overhead or GPU work is harmless.</p>
<h2 id="split-reasons">The next run will identify the fragmentation cause</h2><p>These two logs have no per-draw split-reason ledger. The dashboard therefore leaves the cause <strong>unknown</strong>. Custom Games ended at a draw cap of 32 and work cap of 32 Mi samples; campaign retained a post-risk draw cap of 8 and work cap of 8 Mi samples. Those snapshots alone cannot explain each boundary.</p>
<p>New <code>VULKAN FSI SPLIT REASONS</code> output records exact predicate masks: draw cap, sample-work cap and pipeline isolation, including overlapping reasons and oversized single draws. The decision returns the same cap samples used for its predicate, reducing duplicate atomic budget reads. Tests compare 10,000 randomized budgets and 2,112 monitor cases with the original predicate. No speedup is claimed for this bookkeeping change.</p>
<p>The ledger counts requested decisions, including deferred/refused boundaries, rather than declaring every request a completed split. The first oversized draw remains admitted as before. GPU budgets, risk and severe thresholds, tessellation isolation and maximum depth of two Metal command buffers are preserved.</p>
<h2 id="cadence">Recent picture cadence remains far from 30 FPS</h2><div class="scroll"><table><thead><tr><th>Latest 32 intervals</th><th>Mean ms</th><th>p95 ms</th><th>Max ms</th></tr></thead><tbody>CADENCE</tbody></table></div>
<p>These are recent accepted/completed picture gaps, without matched camera or scene labels. They are not simulation FPS or a before/after benchmark. Custom Games’ input bridge delivered 2,508 nonzero left-stick samples and reported zero invalid/disconnected polls. That establishes delivery, not latency. The new path removes a frequent serialization cost that can compete with input and render workers, but input responsiveness still needs a normal run to confirm.</p>
<p>Custom Games executed 5.54 billion PAUSE hints, campaign 3.93 billion. Those counts include idle waiting and cannot be treated as useful CPU work per frame. This pass deliberately preserves PAUSE cadence; making an idle loop execute more iterations per second would not itself demonstrate a frame-rate gain.</p>
<h2>Checks and delivery</h2><p>STATUS</p><p>No Xenia launch, ISO/vendor edits, GPU dispatch, full Zig suite, shell update or installation in this pass. Audio, TSO, Fast Path and the 30 FPS ceiling remain enabled. After your other agent installs this source, an ordinary run should produce <code>PE64 WINDOWS FAST NT YIELD</code> and the split-reason ledger. The next log must establish eligibility, actual cadence and input response.</p>
<p><a href="../results.json">Measurements and parsed runs</a> · <a href="../manifest.json">Source and evidence identities</a> · <a href="../measurements-final.log">Raw comparisons</a> · <a href="../runs.json">Log identities and line-numbered excerpts</a> · <a href="../xenia-yield-source.txt">Read-only yield-source excerpt</a> · <a href="../yield-release.log">ReleaseFast focused gates</a> · <a href="../yield-debug.log">Debug focused gates</a> · <a href="../fsi-release.log">ReleaseFast FSI gate</a></p>
</main><script>const rows=PLOT;function compare(i){const [name,b,a]=rows[i],scale=500/Math.max(b,a);document.getElementById('comparison').innerHTML=`<text x="10" y="25" fill="#e5edf7">${name}</text><text x="10" y="70" fill="#bbc9d8">Disabled</text><rect x="110" y="48" width="${b*scale}" height="30" fill="#74879b"/><text x="${120+b*scale}" y="70" fill="#e5edf7">${b.toFixed(3)} ms</text><text x="10" y="120" fill="#bbc9d8">Enabled</text><rect x="110" y="98" width="${a*scale}" height="30" fill="#85dbcf"/><text x="${120+a*scale}" y="120" fill="#e5edf7">${a.toFixed(3)} ms</text>`}document.querySelectorAll('[data-case]').forEach(b=>b.onclick=()=>compare(+b.dataset.case));compare(1);</script></body></html>'''
    for key, value in {"REG_RATIO": f'{ratios["dynamic_tail"]["ratio"]:.2f}', "HOST_RATIO": f'{ratios["parallel_host_yield"]["ratio"]:.2f}', "TABLE": table, "RUNS": run_rows, "CADENCE": cadence_rows, "RAW": raw_rows, "BUTTONS": buttons, "PLOT": json.dumps(plot), "STATUS": html.escape(manifest["status"])}.items():
        page = page.replace(key, value)
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(page)
    print(json.dumps({case: round(v["ratio"], 3) for case, v in ratios.items()}))
    print(folder / "final/report.html")


if __name__ == "__main__":
    main()
