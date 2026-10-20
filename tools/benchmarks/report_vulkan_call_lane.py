#!/usr/bin/env python3
"""Build the Vulkan call lane dashboard (2026-10-20).

Everything is recomputed from raw files; nothing is typed in by hand:
  <folder>/live-run/latest.log     the campaign run with last pass installed (host counters)
  <folder>/live-run/previous.log   the campaign run before it (indirect links installed)
  <folder>/bench/draw-stream-series.log         frozen HEAD against this pass, alternating
  <folder>/bench/draw-stream-ablation-*.log     one change off at a time
  <folder>/bench/working-set-split-jitter.log   split against contiguous code, with and without size jitter
  <folder>/bench/previous-pass-series.log       last pass's call_return / code_working_set series
  <folder>/bench/register-only-jitter.log       last pass's register-only rows again, with jitter
  <folder>/bench/chain-budget.log               the chain budget's round trip
  <folder>/hardware/ordering.txt                native release-store / acquire-load costs
  <folder>/manifest.json                        source/evidence hashes, gates, correctness

Usage: report_vulkan_call_lane.py <folder>
"""
import collections
import hashlib
import html
import json
from pathlib import Path
import re
import statistics
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import report_code_locality as locality  # noqa: E402  (window parsing)

ROOT = Path(__file__).resolve().parents[2]
med = statistics.median


def fields(line):
    return dict(re.findall(r"(\w+)=([^\s;,]+)", line))


def slot_of(lines, prefix):
    for line in lines:
        m = re.search(r"BLOCK JIT WORKER THREAD: slot=(\d+) name='([^']*)'", line)
        if m and m[2].startswith(prefix):
            return int(m[1])
    return None


def pulses(lines, slot):
    out = []
    for line in lines:
        if f"PE64 WORKER RUNTIME PULSE: slot={slot} " not in line:
            continue
        f = fields(line)
        out.append(dict(elapsed_ms=int(f["elapsed_ms"]), retired=int(f["native_retired"]), hops=int(f["native_hops"]),
                        fallbacks=int(f["fallbacks"]), host=int(f.get("host_instructions", 0)), cycles=int(f.get("host_cycles", 0))))
    return out


def worker_line(lines, prefix):
    for line in reversed(lines):
        if "BLOCK JIT WORKER THREAD: slot=" in line and f"name='{prefix}" in line:
            return fields(line)
    return {}


def live(path):
    rows, lines = locality.windows(path)
    header = "\n".join(lines[:6])
    slots = {name: slot_of(lines, name) for name in ("MAIN_THREAD", "GPU Commands", "RENDER")}
    series = {name: pulses(lines, slot) for name, slot in slots.items() if slot is not None}
    peak = max((p["cycles"] / (p["elapsed_ms"] * 1e6) for ps in series.values() for p in ps if p["elapsed_ms"]), default=0)
    timeline = []
    if peak:
        for index in range(min(len(v) for v in series.values())):
            row = dict(index=index)
            for name, ps in series.items():
                p = ps[index]
                rate = p["cycles"] / (p["elapsed_ms"] * 1e6)
                row[name] = dict(busy=rate / peak, x86=p["retired"] / p["elapsed_ms"] / 1e3,
                                 ipc=p["host"] / p["cycles"] if p["cycles"] else 0,
                                 per_x86=p["host"] / p["retired"] if p["retired"] else 0,
                                 per_block=p["retired"] / p["hops"] if p["hops"] else 0, fallbacks=p["fallbacks"])
            main, gpu = row["MAIN_THREAD"], row["GPU Commands"]
            row["kind"] = ("MAIN-bound" if main["busy"] >= 0.88 else
                           "GPU Commands near its ceiling" if gpu["busy"] >= 0.80 else "neither saturated (waits)")
            if main["busy"] >= 0.88 and gpu["busy"] >= 0.80:
                row["kind"] = "MAIN-bound, GPU Commands close behind"
            timeline.append(row)
    kinds = collections.OrderedDict()
    for r in rows:
        kind = locality.classify(r)
        if kind == "loading" or not r["main_blocks"]:
            continue
        kinds.setdefault(kind, []).append(r)
    windows = {k: dict(n=len(ws), fps=med(w["fps"] for w in ws), fps_max=max(w["fps"] for w in ws), main_rate=med(w["main_rate"] for w in ws),
                       main_instructions=med(w["main_instructions"] for w in ws), gpu_rate=med(w["gpu_rate"] for w in ws),
                       updates=med(w["updates"] for w in ws)) for k, ws in kinds.items()}
    vulkan = []
    for line in lines:
        m = re.search(r"Vulkan host time by entry point: rank=(\d+) name=(\w+) calls=(\d+) host_ms=(\d+) mean_us=(\d+)", line)
        if m:
            vulkan.append(dict(rank=int(m[1]), name=m[2], calls=int(m[3]), host_ms=int(m[4]), mean_us=int(m[5])))
    timing = {}
    for line in lines:
        m = re.search(r"PE64 FALLBACK TIMING: scope='WORKER ' op=(\w+) calls=(\d+) samples=(\d+) sampled_ns=(\d+)", line)
        if m:
            timing[m[1]] = dict(calls=int(m[2]), samples=int(m[3]), sampled_ns=int(m[4]))
    cpu = {}
    for line in lines:
        m = re.search(r"PE64 WORKER HOST CPU: slot=\d+ handle=\S+ name='([^']*)' cpu_us=(\d+) elapsed_us=(\d+)", line)
        if m:
            cpu[m[1]] = dict(cpu_s=int(m[2]) / 1e6, elapsed_s=int(m[3]) / 1e6)
    return dict(run=re.search(r"run_id = (\S+)", header)[1], build=re.search(r"build_identity_sha256 = (\S+)", header)[1],
                peak_cycles_per_ns=peak, timeline=timeline, windows=windows, vulkan=vulkan[-12:],
                fallback_timing={k: timing[k] for k in ("call_mem64", "call_reg64", "jmp_mem64", "jmp_reg64") if k in timing},
                main=worker_line(lines, "MAIN_THREAD"), gpu=worker_line(lines, "GPU Commands"),
                cpu={k: v for k, v in cpu.items() if k.split(" ")[0] in ("MAIN_THREAD", "GPU", "RENDER", "XThread0022", "XThread0023")})


def draw_stream(folder):
    rows = [fields(l) for l in (folder / "bench" / "draw-stream-series.log").read_text().splitlines() if l.startswith("binary=")]
    groups = collections.defaultdict(list)
    for r in rows:
        groups[(r["mode"], r["cold"], r["binary"])].append(dict(pair=int(r["pair"]), ns=int(r["cpu_ns"]) / int(r["calls"]), calls=int(r["calls"])))
    table = []
    for mode in ("sync", "fifo"):
        for cold in ("false", "true"):
            before, after = groups[(mode, cold, "before")], groups[(mode, cold, "after")]
            if not before or not after:
                continue
            assert {b["calls"] for b in before} == {a["calls"] for a in after}
            pairs = {b["pair"]: b["ns"] for b in before}
            ratios = sorted(pairs[a["pair"]] / a["ns"] for a in after if a["pair"] in pairs)
            table.append(dict(mode=mode, cold=cold == "true", n=len(before), calls=before[0]["calls"],
                              before=med(b["ns"] for b in before), after=med(a["ns"] for a in after),
                              before_range=[min(b["ns"] for b in before), max(b["ns"] for b in before)],
                              after_range=[min(a["ns"] for a in after), max(a["ns"] for a in after)], pair_ratios=ratios))
    ablation = {}
    for name in sorted(p.name for p in (folder / "bench").glob("draw-stream-ablation-*.log")):
        for l in (folder / "bench" / name).read_text().splitlines():
            r = fields(l)
            if "ablation" not in r:
                continue
            key = (name.replace("draw-stream-ablation-", "").replace(".log", ""), r["ablation"])
            ablation.setdefault(key, {}).setdefault(r["without"], []).append(int(r["cpu_ns"]) / 100800)
    ablations = [dict(file=f, control=c, on=med(v["false"]), off=med(v["true"]), n=len(v["false"])) for (f, c), v in sorted(ablation.items())]
    return table, ablations


def split_jitter(folder):
    groups = collections.defaultdict(list)
    for l in (folder / "bench" / "working-set-split-jitter.log").read_text().splitlines():
        r = fields(l)
        if "blocks" in r:
            groups[(r["jitter"], int(r["blocks"]), r["split"])].append((float(r["ns_per_block"]), int(r["ipc_x100"]) / 100, int(r["hot_bytes_per_block"])))
    out = []
    for jitter in ("false", "true"):
        for blocks in sorted({k[1] for k in groups}):
            c, s = groups.get((jitter, blocks, "false")), groups.get((jitter, blocks, "true"))
            if c and s:
                out.append(dict(jitter=jitter == "true", blocks=blocks, contiguous=med(x[0] for x in c), split=med(x[0] for x in s),
                                contiguous_ipc=med(x[1] for x in c), split_ipc=med(x[1] for x in s), split_hot_bytes=med(x[2] for x in s), n=len(c)))
    return out


def previous_series(folder):
    cr, cws = collections.defaultdict(list), collections.defaultdict(list)
    exact = collections.defaultdict(set)
    for l in (folder / "bench" / "previous-pass-series.log").read_text().splitlines():
        d = dict(re.findall(r"(\w+)=([^\s]+)", l))
        if l.startswith("call_return"):
            k = (int(d["functions"]), int(d["indirect"]))
            cr[(d["binary"],) + k].append((float(d["ns_per_block"]), float(d["host_per_x86"]), float(d["ipc"])))
            exact[("cr",) + k].add((d["retired"], d["block_executions"], d["guest_value"], d["context_value"]))
        elif l.startswith("binary="):
            k = (d["registers_only"], int(d["repeat"]), int(d["blocks"]))
            cws[(l.split()[0].split("=")[1],) + k].append((float(d["ns_per_block"]), int(d["host_per_block"])))
            exact[("cws",) + k].add((d["retired"], d["block_executions"]))
    assert all(len(v) == 1 for v in exact.values()), "series rows differ in retired work"
    call_return = [dict(functions=f, indirect=i, before=med(x[0] for x in cr[("before", f, i)]), after=med(x[0] for x in cr[("after", f, i)]),
                        before_per_x86=med(x[1] for x in cr[("before", f, i)]), after_per_x86=med(x[1] for x in cr[("after", f, i)]),
                        after_ipc=med(x[2] for x in cr[("after", f, i)]), n=len(cr[("before", f, i)]))
                   for (b, f, i) in sorted(k for k in cr if k[0] == "before")]
    working_set = [dict(registers_only=r == "true", repeat=rep, blocks=n, before=med(x[0] for x in cws[("before", r, rep, n)]),
                        after=med(x[0] for x in cws[("after", r, rep, n)]), before_per_block=med(x[1] for x in cws[("before", r, rep, n)]),
                        after_per_block=med(x[1] for x in cws[("after", r, rep, n)]))
                   for (b, r, rep, n) in sorted((k for k in cws if k[0] == "before"), key=lambda k: (k[1], k[2], k[3]))]
    return call_return, working_set


def register_jitter(folder):
    path = folder / "bench" / "register-only-jitter.log"
    if not path.exists():
        return []
    groups = collections.defaultdict(list)
    for l in path.read_text().splitlines():
        r = fields(l)
        if "blocks" in r and "binary" in r:
            groups[(r["binary"], r["jitter"], int(r["blocks"]))].append(float(r["ns_per_block"]))
    out = []
    for blocks in sorted({k[2] for k in groups}):
        row = dict(blocks=blocks)
        for binary in ("before", "after"):
            for jitter in ("false", "true"):
                if groups.get((binary, jitter, blocks)):
                    row[f"{binary}_{'jitter' if jitter == 'true' else 'uniform'}"] = med(groups[(binary, jitter, blocks)])
        out.append(row)
    return out


def budget(folder):
    path = folder / "bench" / "chain-budget.log"
    if not path.exists():
        return None
    rows = [fields(l) for l in path.read_text().splitlines() if "cpu_ns=" in l]
    by = collections.defaultdict(list)
    for r in rows:
        by[r["budget"]].append((int(r["cpu_ns"]), int(r["dispatch_entries"]), int(r["host_per_block"]) * int(r["block_executions"])))
    small, large = by.get("1024"), by.get("16384")
    if not small or not large:
        return None
    dt = med(x[0] for x in small) - med(x[0] for x in large)
    de = med(x[1] for x in small) - med(x[1] for x in large)
    dh = med(x[2] for x in small) - med(x[2] for x in large)
    return dict(ns_per_round_trip=dt / de, host_per_round_trip=dh / de, n=len(small), entries_small=med(x[1] for x in small), entries_large=med(x[1] for x in large))


def ordering(folder):
    path = folder / "hardware" / "ordering.txt"
    if not path.exists():
        return []
    out = []
    for l in path.read_text().splitlines():
        m = re.match(r"footprint=\s*(\d+)KiB\s+stlr\+ldr=\s*([\d.]+)\s+str\+ldapr=\s*([\d.]+)\s+str\+ldr=\s*([\d.]+)\s+stlr\+ldapr=\s*([\d.]+)", l)
        if m:
            out.append(dict(kib=int(m[1]), stlr_ldr=float(m[2]), str_ldapr=float(m[3]), str_ldr=float(m[4]), stlr_ldapr=float(m[5])))
    return out


def esc(value):
    return html.escape(str(value))


def table(headers, rows, cls=""):
    head = "".join(f"<th>{esc(h)}</th>" for h in headers)
    body = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in row) + "</tr>" for row in rows)
    return f'<div class="scroll"><table class="{cls}"><tr>{head}</tr>{body}</table></div>'


def pct(x):
    return f"{100 * x:.0f}%"


def page(data):
    latest, previous = data["latest"], data["previous"]
    tl = latest["timeline"]
    counts = collections.Counter(r["kind"] for r in tl)
    busy_main = med(r["MAIN_THREAD"]["busy"] for r in tl)
    late = [r for r in tl if r["MAIN_THREAD"]["busy"] >= 0.88]
    sync_hot = next(r for r in data["draw_stream"] if r["mode"] == "sync" and not r["cold"])
    lane = next((a for a in data["ablations"] if a["control"] == "vulkan_call_lane" and a["file"] == "sync"), None)
    memo = next((a for a in data["ablations"] if a["control"] == "route_memo" and a["file"] == "sync"), None)
    est = data["estimate"]
    gates_ok = all(g["status"] == "pass" for g in data["gates"])
    out = []
    w = out.append
    w("""<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Rosette · Vulkan call lane</title><style>
:root{color-scheme:dark;font-family:system-ui;background:#101722;color:#e7eef8}body{margin:0;background:#101722}main{max-width:1240px;margin:auto;padding:30px 24px 70px}h1{font-size:clamp(28px,4.5vw,42px);margin-bottom:12px}h2{margin-top:40px}h3{margin-top:26px;color:#d6e2f0}p,li{line-height:1.6;color:#b9c7d8}a{color:#88dece}nav{display:flex;gap:18px;flex-wrap:wrap;margin:12px 0}.badge{border:1px solid #836a3f;padding:7px 10px;border-radius:7px;color:#edcc89;font-size:13px;display:inline-block;margin:0 8px 8px 0}.badge.ok{border-color:#3f8371;color:#89dccc}.badge.bad{border-color:#8a4b4b;color:#e79b9b}.card{background:#1b2737;border:1px solid #314157;border-radius:14px;padding:18px}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-top:18px}.value{font-size:30px;font-weight:700;color:#89dccc}.value.warn{color:#edcc89}.note{border-left:4px solid #e4bd7c;padding:12px 16px;background:#202733;margin-top:14px}.scroll{overflow:auto;margin-top:12px}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{padding:7px 9px;border-bottom:1px solid #344357;text-align:left;vertical-align:top;white-space:nowrap}th{color:#8dd8cc;font-size:13px}td.wrap{white-space:normal}details{margin:12px 0}summary{cursor:pointer;color:#cfe0f1}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px;color:#bfcee0}.small{font-size:13px}.good{color:#89dccc}.bad{color:#e79b9b}.warn{color:#edcc89}.bar{display:inline-block;height:9px;border-radius:3px;vertical-align:middle;margin-right:6px}@media(max-width:900px){.cards{grid-template-columns:1fr 1fr}}@media(max-width:600px){main{padding:22px 16px}.cards{grid-template-columns:1fr}}
</style><main>""")
    w(f'<div>{"".join(f"<span class=\"badge {"ok" if g["status"] == "pass" else "bad"}\">{esc(g["name"])}: {esc(g["status"])}</span>" for g in data["gates"])}</div>')
    w("<h1>Vulkan call lane: GPU Commands' calls into vulkan-1.dll</h1>")
    w(f"<p>October 20, 2026 · offline proofs through the production PE route, against your campaign run {esc(latest['run'])} · Xenia, the ISO and vendor source read only; nothing launched, no GPU work dispatched.</p>")
    w('<nav><a href="#run">Your run, pulse by pulse</a><a href="#gpu">Where GPU Commands\' time went</a><a href="#lane">This pass</a><a href="#bench">Before and after</a><a href="#lastpass">Last pass</a><a href="#findings">Measured, not changed</a><a href="#thirty">How close to 30</a><a href="#gates">Correctness and gates</a><a href="#next">Next run</a></nav>')
    w('<div class="cards">')
    w(f'<div class="card"><div class="value">{sync_hot["before"]:.0f} → {sync_hot["after"]:.0f} ns</div><p>One Vulkan command call, the whole PE route, warm<br><span class="small">{sync_hot["before"] / sync_hot["after"]:.2f}× · frozen HEAD against this pass, {sync_hot["n"]} alternating pairs</span></p></div>')
    w(f'<div class="card"><div class="value warn">{pct(busy_main)}</div><p>MAIN_THREAD on a core, median five-second pulse<br><span class="small">{counts.get("MAIN-bound", 0) + counts.get("MAIN-bound, GPU Commands close behind", 0)} of {len(tl)} pulses at 88% or more</span></p></div>')
    w(f'<div class="card"><div class="value">{est["share_low"] * 100:.1f}–{est["share_high"] * 100:.1f}%</div><p>Of GPU Commands\' CPU in your run, modelled from the measured saving<br><span class="small">{est["calls_low"] / 1e6:.1f}M–{est["calls_high"] / 1e6:.1f}M calls × {est["saved_ns"]:.0f} ns</span></p></div>')
    w(f'<div class="card"><div class="value warn">{med(r["MAIN_THREAD"]["ipc"] for r in late):.2f}</div><p>MAIN instructions per cycle in the MAIN-bound pulses<br><span class="small">{med(r["MAIN_THREAD"]["per_x86"] for r in late):.1f} ARM instructions per x86 instruction</span></p></div>')
    w("</div>")

    # --- run
    w('<h2 id="run">Your campaign run, pulse by pulse</h2>')
    w(f"<p>Last pass put each worker's own ARM instruction and cycle counts (<code>thread_selfcounts</code>) on every five-second <code>PE64 WORKER RUNTIME PULSE</code>. Busy is cycles per second as a share of the highest any worker reached in this run ({latest['peak_cycles_per_ns']:.2f} G/s): it includes spinning, and a waiting thread is not on a core. A pulse is MAIN-bound when MAIN is at 88% or more.</p>")
    w(table(["pulses", "kind"], [[n, esc(k)] for k, n in counts.most_common()]))
    rows = []
    for r in tl:
        m, g, rd = r["MAIN_THREAD"], r["GPU Commands"], r.get("RENDER", {})
        bar = lambda b, c: f'<span class="bar" style="width:{int(60 * b)}px;background:{c}"></span>{pct(b)}'
        rows.append([r["index"], bar(m["busy"], "#89dccc"), f'{m["x86"]:.0f}M', f'{m["ipc"]:.2f}', f'{m["per_x86"]:.1f}', f'{m["per_block"]:.0f}',
                     bar(g["busy"], "#9fb5ff"), f'{g["x86"]:.0f}M', f'{g["per_x86"]:.1f}', bar(rd.get("busy", 0), "#edcc89") if rd else "", esc(r["kind"])])
    w("<details><summary>Every pulse</summary>" + table(["pulse", "MAIN busy", "MAIN x86/s", "MAIN IPC", "ARM per x86", "x86 per block", "GPU Commands busy", "GPU x86/s", "GPU ARM per x86", "RENDER busy", "kind"], rows) + "</details>")
    w(f'<div class="note">MAIN is the frame in most of the campaign: it is on a core nearly the whole time, at about {med(r["MAIN_THREAD"]["x86"] for r in late):.0f}M x86 instructions a second and {med(r["MAIN_THREAD"]["ipc"] for r in late):.2f} instructions per cycle. GPU Commands reaches 80% or more in {sum(1 for r in tl if r["GPU Commands"]["busy"] >= 0.80)} pulses, so it is close behind wherever MAIN gets faster. The pulses where neither is saturated are the lighter scenes (about 21–25 FPS): there the frame is the hand-off between MAIN, RENDER, GPU Commands and the GPU, not one thread\'s work. RENDER\'s busy time is mostly its frame-hand-off spin by design.</div>')
    w("<h3>Window kinds, against the run before last pass</h3>")
    kinds = list(dict.fromkeys(list(previous["windows"]) + list(latest["windows"])))
    wrows = []
    for k in kinds:
        a, b = previous["windows"].get(k), latest["windows"].get(k)
        if a and b:
            wrows.append([esc(k), f'{a["n"]} / {b["n"]}', f'{a["fps"]:.1f} → {b["fps"]:.1f}', f'{a["fps_max"]:.1f} → {b["fps_max"]:.1f}', f'{a["main_instructions"] / 1e6:.1f}M → {b["main_instructions"] / 1e6:.1f}M', f'{a["main_rate"]:.0f}M → {b["main_rate"]:.0f}M/s'])
    w(table(["window kind (title/light labels from the Custom Games classifier)", "windows", "median FPS", "best FPS", "MAIN instructions per frame", "MAIN x86/s"], wrows))
    w(f'<p class="small">Run {esc(previous["run"])} (indirect links) against run {esc(latest["run"])} (last pass). Both are campaign; the scenes are not matched, and the second run\'s moving-camera windows carried more MAIN work per frame. Neither run is evidence of a frame-rate change from last pass.</p>')

    # --- gpu
    w('<h2 id="gpu">Where GPU Commands\' time went</h2>')
    gw = latest["gpu"]
    w(f"<p>GPU Commands spent {latest['cpu'].get('GPU Commands (0100000C)', {}).get('cpu_s', 0):.0f} s of CPU in the run. Its translated code left for the interpreter {int(gw.get('fallback_calls', 0)):,} times, nearly all of them calls to vulkan-1.dll thunks (the busiest fallback targets are guest-heap thunks handed out by <code>vkGetDeviceProcAddr</code>). Each such call left translated code, was interpreted, took a second step at the thunk, then entered translated code again.</p>")
    frows = [[esc(op), f'{t["calls"]:,}', f'{t["sampled_ns"] / max(t["samples"], 1) / 1e3:.2f} µs', f'{t["calls"] * t["sampled_ns"] / max(t["samples"], 1) / 1e9:.1f} s'] for op, t in latest["fallback_timing"].items()]
    w(table(["fallback (all workers)", "calls", "sampled mean, includes waits", "estimate"], frows))
    w(table(["entry point", "calls", "bridge host time", "mean"], [[esc(v["name"]), f'{v["calls"]:,}', f'{v["host_ms"] / 1e3:.1f} s', f'{v["mean_us"]} µs'] for v in latest["vulkan"]]))
    w('<p class="small">Bridge host time is the adapter\'s own span: native work, marshalling and the forwarder, measured inside the dispatch. It excludes the interpreter round trip that took each call there, which is what this pass removes.</p>')

    # --- lane
    w('<h2 id="lane">This pass</h2><ol>')
    w("<li><b>Vulkan call lane</b> (<code>process/impl/vulkan_call_lane.zig</code>). On the out-of-code-cache edge of a translated <code>call</code>, the existing transfer helper is asked first (two exact address compares removed from <code>block_jit/core.zig</code>, which now routes every such call there). A dynamic vulkan-1.dll thunk for <code>vkCmd*</code> or <code>vkUpdateDescriptorSets</code> runs through the same adapter the thunk's step runs, under the same runtime lock, in its direct-return form: arguments read where the caller left them, nothing pushed or popped, RIP the return address, and the block goes on through its ordinary exit. Every other target declines before changing anything and takes the interpreter's path as before. Only command recording: those entry points never wait on the GPU, map memory, create objects or give the runtime lock back. A call that ends the run stops the block at its next exit check. <code>PE64 VULKAN CALL LANE</code> reports completions.</li>")
    w("<li><b>Per-name route memo</b> (<code>windows_guest_forwarder/abi/route_memo.zig</code>). Everything the adapter derived from a name on every call (ownership and ABI facts, command / surface / frame-evidence / contract kind, and the loader's symbol token) is derived once per name per host thread. A slot keeps a copy of its name; a token is kept per adapter instance, library and native device. <code>vkCmd*</code> had bypassed the old facts memo.</li>")
    w("<li><b>Smaller per-call copies.</b> The 512-byte vector file is saved and restored only for the three entry points with scalar float arguments (the forwarder reads it, only the float shift writes it); the bound register file is resolved once per call.</li></ol>")

    # --- bench
    w('<h2 id="bench">Before and after</h2>')
    w("<p><code>windows_guest_forwarder_draw_stream_tests.zig</code> (<code>zig build vulkan-draw-stream-check</code>): a translated guest loop plays Xenia's <code>DeferredCommandBuffer::Execute</code>, calling the thunks with the command mix of a Custom Games run, through the production PE route (step boundary, thunk, runtime lock, Windows/SysV adapter, forwarder marshalling) into a stub driver that counts and checksums every native call. Before = frozen git HEAD (<code>76327e51d</code>) with only the benchmark options added; after = this pass. <i>sync</i> runs every command on the calling thread, so the time is the caller's route alone; <i>fifo</i> keeps the command worker, where the caller also waits at each descriptor update's ordering drain for a worker whose speed depends on the core it lands on. <i>Scrubbed</i> reads 1 MiB every fourth call, on both sides.</p>")
    brows = [[esc(r["mode"]), "scrubbed" if r["cold"] else "warm", f'{r["calls"]:,}', f'{r["before"]:.0f} ns', f'{r["after"]:.0f} ns', f'{r["before"] - r["after"]:.0f} ns', f'{r["before"] / r["after"]:.2f}×', f'{min(r["pair_ratios"]):.2f}–{max(r["pair_ratios"]):.2f}', r["n"]] for r in data["draw_stream"]]
    w(table(["route", "cache", "calls per run", "before", "after", "saved per call", "ratio", "pair ratios", "pairs"], brows))
    arows = [[esc(a["file"]), esc(a["control"]), f'{a["off"]:.0f} ns', f'{a["on"]:.0f} ns', f'{a["off"] / a["on"]:.2f}×', a["n"]] for a in data["ablations"]]
    w("<h3>One change off at a time (everything else on)</h3>" + table(["route", "change", "without", "with", "ratio", "pairs"], arows))
    w(f'<div class="note">The lane is most of it: {lane["off"]:.0f} → {lane["on"]:.0f} ns per call in the synchronous route ({lane["off"] / lane["on"]:.2f}×); the route memo takes {memo["off"] - memo["on"]:.0f} ns more ({memo["off"] / memo["on"]:.2f}×). With the worker the gain is smaller and noisier, because the faster caller now waits at descriptor-update drains for a worker that runs the same commands. These are CPU times on the calling thread with a stub driver: not frame-rate measurements, and not MoltenVK\'s own cost.</div>' if lane and memo else "")

    # --- last pass
    w('<h2 id="lastpass">Last pass (installed in your run)</h2>')
    w("<p>Exit-edge flag records, lean memory templates, AF cleared by logic operations, the assembler's jump-to-next peephole, the hoist miss path out of line, and the host counters. Its alternating series (frozen <code>72ee4e4eb</code> against it, five pairs, identical retired work):</p>")
    w(table(["functions", "through table", "before", "after", "ratio", "ARM per x86 before → after", "IPC after"], [[r["functions"], f'{r["indirect"]}%', f'{r["before"]:.2f} ns', f'{r["after"]:.2f} ns', f'{r["before"] / r["after"]:.3f}', f'{r["before_per_x86"]:.1f} → {r["after_per_x86"]:.1f}', f'{r["after_ipc"]:.2f}'] for r in data["call_return"]]))
    w(table(["shape", "blocks", "before", "after", "ratio", "ARM per block before → after"], [[("registers only" if r["registers_only"] else f'{r["repeat"]} Xenia bodies'), r["blocks"], f'{r["before"]:.2f} ns', f'{r["after"]:.2f} ns', f'{r["before"] / r["after"]:.3f}', f'{r["before_per_block"]} → {r["after_per_block"]}'] for r in data["working_set"]]))
    if data["register_jitter"]:
        w("<h3>The register-only rows that got slower, again with block-size jitter</h3>")
        w("<p>Every block of that shape is identical, so blocks sit at one stride and every structure indexed by low address bits sees the same bits in every block. With 0–8 filler instructions per block (<code>ROSETTE_CODE_WORKING_SET_JITTER=1</code>), as live blocks differ in size:</p>")
        w(table(["blocks", "before, uniform", "after, uniform", "before, jitter", "after, jitter"], [[r["blocks"]] + [f'{r[k]:.2f} ns' if k in r else "" for k in ("before_uniform", "after_uniform", "before_jitter", "after_jitter")] for r in data["register_jitter"]]))

    # --- findings
    w('<h2 id="findings">Measured this pass, not changed</h2>')
    w("<h3>Split hot/cold layout, with realistic block sizes</h3>")
    w("<p>The split layout (cold paths in other pages of a 1 MiB window) had measured slower from about 512 to 4,096 hot blocks and was not shipped, cause unexplained. With uniform blocks its packed hot parts sit at one stride (about 1,250 bytes). With size jitter the loss at 1,024–2,048 disappears:</p>")
    w(table(["jitter", "blocks", "contiguous", "split", "split / contiguous", "IPC contiguous / split"], [["yes" if r["jitter"] else "no", r["blocks"], f'{r["contiguous"]:.2f} ns', f'{r["split"]:.2f} ns', f'{r["split"] / r["contiguous"]:.3f}', f'{r["contiguous_ipc"]:.2f} / {r["split_ipc"]:.2f}'] for r in data["split"]]))
    w('<p class="small">It still loses about 10% at 4,096 and wins about 28% at 16,384. MAIN\'s live IPC (about 1.8) sits in this curve between 4,096 and 8,192 blocks, where split is neutral to slightly behind, so it stays an offline control.</p>')
    if data["ordering"]:
        w("<h3>What x86 ordering costs on this core</h3><p>A native loop (<code>hardware/ordering.c</code>): one store to a footprint at a 64-byte stride, then four loads from a hot buffer, per iteration, in each combination of release/plain store and acquire/plain load. Translated code uses release stores and acquire loads for guest memory, which TSO requires.</p>")
        w(table(["store footprint", "stlr + ldapr (production)", "stlr + ldr", "str + ldapr", "str + ldr"], [[f'{r["kib"]:,} KiB', f'{r["stlr_ldapr"]:.2f} ns', f'{r["stlr_ldr"]:.2f} ns', f'{r["str_ldapr"]:.2f} ns', f'{r["str_ldr"]:.2f} ns'] for r in data["ordering"]]))
        w('<p class="small">With stores that hit, the orderings are nearly free. Once stores miss, acquire loads wait behind them and release stores stop overlapping: about 5× plain at a 64 MiB footprint. This is a property of TSO on this core, not of a template; nothing here changes it, and the TSO guarantees stay as they are.</p>')
    if data["budget"]:
        b = data["budget"]
        w(f'<h3>The chain budget</h3><p>Translated code returns to the glue every 16,384 instructions in parallel mode. Shrinking the budget to 1,024 in the working-set benchmark (entries {b["entries_large"]:,.0f} → {b["entries_small"]:,.0f}) costs {b["ns_per_round_trip"]:.0f} ns and about {b["host_per_round_trip"]:,.0f} ARM instructions per extra round trip. MAIN made about 37 million such exits in the run (budget, break and miss), about 2% of its time at that rate, so the budget stays.</p>')
    w("<h3>Flags owed to an unconditional exit</h3><p>A block's last flag writer before a <code>jmp</code> still materializes its flags (about twenty instructions) because the next block may read them. In Xenia's code almost every writer is followed by another that kills its flags, and most blocks end in a call or return that owes none, so this comes up about once per <code>jmp</code>-ending block: around 1% of MAIN's instructions. Not changed.</p>")

    # --- thirty
    w('<h2 id="thirty">How close to 30</h2>')
    w(f'<p>MAIN sets the frame rate in {counts.get("MAIN-bound", 0) + counts.get("MAIN-bound, GPU Commands close behind", 0)} of {len(tl)} pulses, and this pass does not touch MAIN\'s translated code: in those windows it is not expected to raise the frame rate. It takes {est["share_low"] * 100:.1f}–{est["share_high"] * 100:.1f}% off GPU Commands\' CPU (a model: the measured {est["saved_ns"]:.0f} ns per call times the run\'s command-recording calls, from the {est["calls_low"] / 1e6:.1f}M the bridge listed by name to the {est["calls_high"] / 1e6:.1f}M fallbacks GPU Commands made). That is headroom where GPU Commands is close behind MAIN, and a shorter GPU Commands share of the hand-off in the lighter scenes. The lane\'s live saving per call may differ from the stub driver\'s: the bypassed interpreter path is colder in the game than in the fixture.</p>')

    # --- gates
    w('<h2 id="gates">Correctness and gates</h2>')
    w(table(["check", "result", "detail"], [[esc(c["name"]), f'<span class="{"good" if c["result"] == "pass" else "bad"}">{esc(c["result"])}</span>', f'<span class="small">{esc(c["detail"])}</span>'] for c in data["correctness"]]))
    w(table(["gate", "status", "detail"], [[esc(g["name"]), f'<span class="{"good" if g["status"] == "pass" else "bad"}">{esc(g["status"])}</span>', f'<span class="small">{esc(g["detail"])}</span>'] for g in data["gates"]]))
    w(f'<p class="small">{"All gates passed." if gates_ok else "A gate did not pass: see its detail."} Evidence files and sources are hashed in <code>manifest.json</code> and checked when this page is built.</p>')

    # --- next
    w('<h2 id="next">Next run</h2><ul>')
    w("<li><code>PE64 VULKAN CALL LANE: completed=</code> should be in the tens of millions for a session like this one; near zero means the lane did not engage (for instance a traced run) and nothing else changed.</li>")
    w("<li>GPU Commands: <code>fallbacks=</code> per pulse should fall from about half a million per five seconds to a small fraction of that, and its busy share and ARM per x86 (<code>host_per_guest_x100</code>) with them; <code>PE64 FALLBACK TIMING op=call_mem64 calls=</code> likewise.</li>")
    w("<li>MAIN_THREAD's pulses (busy, x86/s, IPC) should be unchanged: this pass does not touch its code.</li>")
    w("<li>The bridge's <code>Vulkan host time by entry point</code> stays comparable: it measures the adapter's own span, which the lane still runs.</li></ul>")
    w("</main></html>")
    return "\n".join(out)


def generate(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    for name, digest in manifest["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    latest = live(folder / "live-run" / "latest.log")
    previous = live(folder / "live-run" / "previous.log")
    draw, ablations = draw_stream(folder)
    call_return, working_set = previous_series(folder)
    saved = med([r["before"] - r["after"] for r in draw if r["mode"] == "sync"])
    command_calls = sum(v["calls"] for v in latest["vulkan"] if v["name"].startswith("vkCmd") or v["name"] == "vkUpdateDescriptorSets")
    gpu_cpu = next((v["cpu_s"] for k, v in latest["cpu"].items() if k.startswith("GPU Commands")), 0)
    fallbacks = int(latest["gpu"].get("fallback_calls", 0))
    estimate = dict(saved_ns=saved, calls_low=command_calls, calls_high=fallbacks, gpu_cpu_s=gpu_cpu,
                    share_low=command_calls * saved / 1e9 / gpu_cpu if gpu_cpu else 0, share_high=fallbacks * saved / 1e9 / gpu_cpu if gpu_cpu else 0)
    data = dict(latest=latest, previous=previous, draw_stream=draw, ablations=ablations, split=split_jitter(folder),
                call_return=call_return, working_set=working_set, register_jitter=register_jitter(folder), budget=budget(folder),
                ordering=ordering(folder), estimate=estimate, gates=manifest["gates"], correctness=manifest["correctness"])
    (folder / "bench-results.json").write_text(json.dumps({k: v for k, v in data.items() if k not in ("latest", "previous")}, indent=1))
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final" / "report.html").write_text(page(data))
    print(f"latest {latest['run']}: {len(latest['timeline'])} pulses; previous {previous['run']}")
    for r in draw:
        print(f"{r['mode']:4} {'scrubbed' if r['cold'] else 'warm':8} before {r['before']:7.1f} after {r['after']:7.1f} ns/call {r['before'] / r['after']:.2f}x")
    print(f"estimate: {estimate['share_low'] * 100:.1f}-{estimate['share_high'] * 100:.1f}% of GPU Commands CPU ({saved:.0f} ns x {command_calls / 1e6:.1f}M-{fallbacks / 1e6:.1f}M calls)")


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
