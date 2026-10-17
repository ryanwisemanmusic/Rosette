#!/usr/bin/env python3
"""Build the critical-path dashboard: offline proofs and live frame model.

Inputs (all recomputed from raw files; nothing is typed in by hand):
  <folder>/bench-replay-final.log        Xenia register-write replay pairs
  <previous>/bench-final.log             Vulkan command-path pairs (2026-10-16)
  <previous>/live-run/custom.log          Custom Games run before
  <folder>/live-run/custom.log            Custom Games run after
  <folder>/manifest.json                  source/evidence hashes, gate results

Usage: report_critical_path.py <folder> <previous-folder>
"""
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
WINDOW_MS = 5000  # GRAPHICS ROUTE reports every five seconds


def fields(line):
    return dict(re.findall(r"(\w+)=(\S+)", line))


def replay_groups(text):
    rows = [fields(l) for l in text.splitlines() if "command_replay profile=" in l]
    groups = {}
    for r in rows:
        key = (int(r["profile"]), r["name"])
        groups.setdefault(key, []).append(r)
    out = []
    for (profile, name), rs in sorted(groups.items()):
        pairs = []
        for pair in sorted({int(r["pair"]) for r in rs}):
            a = next(r for r in rs if int(r["pair"]) == pair and r["enabled"] == "false")
            b = next(r for r in rs if int(r["pair"]) == pair and r["enabled"] == "true")
            assert a["register_writes"] == b["register_writes"]
            pairs.append(dict(pair=pair, before_ns=int(a["cpu_ns"]), after_ns=int(b["cpu_ns"]),
                              before_retired=int(a["retired"]), after_retired=int(b["retired"]),
                              before_blocks=int(a["blocks"]), after_blocks=int(b["blocks"]),
                              native=int(b["native_registers"]), gates=int(b["gate_calls"])))
        writes = int(rs[0]["register_writes"])
        before = statistics.median(p["before_ns"] for p in pairs)
        after = statistics.median(p["after_ns"] for p in pairs)
        out.append(dict(profile=profile, name=name, writes=writes, pairs=pairs,
                        before_ns_per_write=before / writes, after_ns_per_write=after / writes,
                        ratio=before / after, native_fraction=pairs[0]["native"] / writes))
    assert len(out) == 4 and all(len(g["pairs"]) == 7 for g in out)
    return out


def command_path(text):
    rows = [fields(l) for l in text.splitlines() if "draw_stream profile=" in l]
    out = {}
    for profile in ("hot", "cold"):
        rs = [r for r in rows if r["profile"] == profile]
        before = statistics.median(int(r["cpu_ns"]) for r in rs if r["enabled"] == "false")
        after = statistics.median(int(r["cpu_ns"]) for r in rs if r["enabled"] == "true")
        calls = int(rs[0]["calls"])
        out[profile] = dict(calls=calls, before_us=before / calls / 1000, after_us=after / calls / 1000,
                            ratio=before / after, pairs=len(rs) // 2)
    calibration = [int(fields(l)["cpu_ns"]) / int(fields(l)["calls"]) for l in text.splitlines() if "scrub_calibration" in l]
    out["scrub_us"] = statistics.median(calibration) / 1000 if calibration else None
    ablation = []
    for control in ("fifo_handoff", "pipeline_memo", "trace_setting", "scratch_slots", "duration_clocks", "vulkan_stub_early_out"):
        rs = [fields(l) for l in text.splitlines() if f"ablation={control} " in l]
        without = statistics.median(int(r["cpu_ns"]) for r in rs if r["without"] == "true")
        with_ = statistics.median(int(r["cpu_ns"]) for r in rs if r["without"] == "false")
        ablation.append(dict(control=control, saves_ns=(without - with_) / int(rs[0]["calls"])))
    out["ablation"] = ablation
    return out


def windows(lines):
    """Five-second windows: presented frames and draw work per frame, and
    each hot thread's translated-instruction rate in the same window."""
    pulse, previous, rows = {}, None, []
    # Natively written registers, cumulative, from the register-write pulse
    # (runs from this pass's build onward); None before it existed.
    registers, registers_at_window = None, None
    for number, line in enumerate(lines, 1):
        m = re.search(r"PE64 XENIA REGISTER WRITES PULSE: native_registers\(type0/ring/memory\)=(\d+)/(\d+)/(\d+)", line)
        if m:
            registers = sum(map(int, m.groups()))
        m = re.search(r"PE64 WORKER RUNTIME PULSE: slot=(\d+) elapsed_ms=(\d+) native_retired=(\d+)", line)
        if m:
            pulse[int(m[1])] = (int(m[2]), int(m[3]))
        m = re.search(r"GRAPHICS ROUTE: descriptors\(updates/native_writes/binds_forwarded/binds_rejected\)=(\d+)/(\d+)/(\d+)/\d+ presented_sources\(sampled/transfer/upload/unresolved\)=(\d+)", line)
        if not m:
            continue
        current = tuple(map(int, m.groups()))
        if previous and current[3] > previous[3]:
            frames = current[3] - previous[3]
            rate = lambda slot: pulse[slot][1] / pulse[slot][0] / 1000 if slot in pulse and pulse[slot][0] else 0.0
            native = (registers - registers_at_window) / frames if registers is not None and registers_at_window is not None else None
            rows.append(dict(line=number, frames=frames, fps=frames * 1000 / WINDOW_MS, frame_ms=WINDOW_MS / frames,
                             updates=(current[0] - previous[0]) / frames, binds=(current[2] - previous[2]) / frames,
                             gpu=rate(6), main=rate(23), render=rate(36), native_registers=native, raw=line))
        previous, pulse, registers_at_window = current, {}, registers
    return rows


def fit(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    a = my - b * mx
    residual = sum((y - a - b * x) ** 2 for x, y in zip(xs, ys))
    total = sum((y - my) ** 2 for y in ys)
    return dict(intercept=a, slope=b, r2=1 - residual / total, n=n)


def entry_points(lines):
    out = {}
    for line in lines:
        m = re.search(r"Vulkan host time by entry point: rank=\d+ name=(\w+) calls=(\d+) host_ms=(\d+)", line)
        if m:
            out[m[1]] = dict(calls=int(m[2]), host_ms=int(m[3]), mean_us=int(m[3]) * 1000 / int(m[2]))
    total = next((fields(l) for l in reversed(lines) if "Vulkan host time: calls=" in l), None)
    return out, total


def last(lines, marker):
    for number in range(len(lines), 0, -1):
        if marker in lines[number - 1]:
            return dict(line=number, raw=lines[number - 1])
    return None


def run(path, name):
    lines = path.read_text(errors="replace").splitlines()
    rows = windows(lines)
    gameplay = [r for r in rows if r["updates"] > 100 and r["gpu"] > 0]
    saturated = max(r["gpu"] for r in gameplay)
    work = fit([r["updates"] for r in gameplay], [r["gpu"] * r["frame_ms"] / 1000 for r in gameplay])
    busy = fit([r["updates"] for r in gameplay], [r["gpu"] / saturated * r["frame_ms"] for r in gameplay])
    frame = fit([r["updates"] for r in gameplay], [r["frame_ms"] for r in gameplay])
    heavy = [r for r in gameplay if r["updates"] > 1800]
    light = [r for r in gameplay if r["updates"] < 400]
    entries, total = entry_points(lines)
    header = "\n".join(lines[:6])
    cpu = {}
    for line in lines:
        m = re.search(r"PE64 WORKER HOST CPU: slot=\d+ handle=\S+ name='([^']*)' cpu_us=(\d+) elapsed_us=(\d+)", line)
        if m:
            cpu[m[1]] = dict(cpu_s=int(m[2]) / 1e6, elapsed_s=int(m[3]) / 1e6)
    evidence = [e for e in (last(lines, marker) for marker in (
        "VULKAN COMMAND HANDOFF", "hybrid_command_worker=enabled", "Vulkan host time: calls=",
        "PE64 BLOCK JIT WORKER THREAD: slot=6", "PE64 GPU RING:   indirect buffer", "PE64 GPU RING:   Xenia executed",
        "PE64 IMPORT HISTOGRAM:   rank=10", "PE64 LOCK CONTENTION:   lock=0x141c50000", "PE64 XENIA REGISTER WRITES")) if e]
    return dict(name=name, run=re.search(r"run_id = (\S+)", header)[1], build=re.search(r"build_identity_sha256 = (\S+)", header)[1],
                windows=rows, gameplay_windows=len(gameplay), saturated_gpu=saturated, work_fit=work, busy_fit=busy, frame_fit=frame,
                heavy=dict(count=len(heavy), fps=statistics.mean(r["fps"] for r in heavy), updates=statistics.mean(r["updates"] for r in heavy)) if heavy else None,
                light=dict(count=len(light), fps=statistics.mean(r["fps"] for r in light), frame_ms=statistics.mean(r["frame_ms"] for r in light), main=statistics.mean(r["main"] for r in light), gpu=statistics.mean(r["gpu"] for r in light)) if light else None,
                peak_fps=max(r["fps"] for r in gameplay), entries=entries, total=total, cpu=cpu, evidence=evidence)


def generate(folder, previous):
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    replay = replay_groups((folder / "bench-replay-final.log").read_text())
    vulkan = command_path((previous / "bench-final.log").read_text())
    before = run(previous / "live-run" / "custom.log", "Before (previous build)")
    after = run(folder / "live-run" / "custom.log", "After (current installed build)")
    data = dict(replay=replay, vulkan=vulkan, runs=[before, after], gates=manifest["gates"],
                correctness=manifest["correctness"], generated_from=manifest["evidence_sha256"])
    (folder / "bench-results.json").write_text(json.dumps(dict(replay=replay, vulkan=vulkan), indent=2))
    (folder / "live-model.json").write_text(json.dumps([{k: v for k, v in r.items() if k != "windows"} for r in (before, after)], indent=2))
    template = Path(__file__).with_name("critical_path_report.html").read_text()
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final" / "report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/")))
    print(json.dumps(dict(
        replay=[{k: round(g[k], 3) if isinstance(g[k], float) else g[k] for k in ("name", "before_ns_per_write", "after_ns_per_write", "ratio", "native_fraction")} for g in replay],
        vulkan={k: v for k, v in vulkan.items() if k in ("hot", "cold")},
        fits=[dict(run=r["name"], work=r["work_fit"], busy=r["busy_fit"], heavy=r["heavy"], light=r["light"]) for r in (before, after)]), indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]), Path(sys.argv[2]))
