#!/usr/bin/env python3
"""Build the translated-code locality dashboard.

Everything is recomputed from raw files; nothing is typed in by hand:
  <folder>/bench/ws-series.log           alternating before/after working-set pairs
  <folder>/bench/expansion-*.log         ARM64 words of Xenia's RENDER function
  <folder>/live-run/custom.log           the supplied run (this build)
  <folder>/live-run/previous.log         the previous pass's run
  <folder>/manifest.json                 source/evidence hashes, gates

Usage: report_code_locality.py <folder>
"""
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
WINDOW_MS = 5000


def fields(line):
    return dict(re.findall(r"(\w+)=(\S+)", line))


def series(text):
    rows = [fields(l) for l in text.splitlines() if "series_pair=" in l and " blocks=" in l and " split=" in l]
    # Only pairs whose before and after runs both finished.
    complete = {p for p in {r["series_pair"] for r in rows} if {"before", "after"} <= {r["binary"] for r in rows if r["series_pair"] == p}}
    rows = [r for r in rows if r["series_pair"] in complete]
    shapes = {}
    for r in rows:
        # After = production (block-named links, hot code first in each
        # block); split = the same binary with cold paths placed apart.
        variant = "before" if r["binary"] == "before" else ("split" if r["split"] == "true" else "after")
        key = (r["registers_only"] == "true", int(r["repeat"]))
        point = shapes.setdefault(key, {}).setdefault(int(r["blocks"]), {})
        point.setdefault(variant, []).append(dict(pair=int(r["series_pair"]), ns=int(r["cpu_ns"]) / int(r["block_executions"]),
                                                   hot=int(r["hot_bytes_per_block"]), cold=int(r["cold_bytes_per_block"]),
                                                   retired=int(r["retired"]), executions=int(r["block_executions"])))
    out = []
    for (registers_only, repeat), points in sorted(shapes.items()):
        name = "register-only, 8 instructions" if registers_only else f"Xenia-shaped, {8 * repeat + 1} instructions"
        curve = []
        for blocks, variants in sorted(points.items()):
            entry = dict(blocks=blocks)
            for variant, samples in variants.items():
                entry[variant] = dict(median_ns=statistics.median(s["ns"] for s in samples), samples=samples,
                                      hot=samples[0]["hot"], cold=samples[0]["cold"])
            if "before" in entry and "after" in entry:
                assert all(a["retired"] == b["retired"] for a, b in zip(entry["before"]["samples"], entry["after"]["samples"]))
                entry["ratio"] = entry["before"]["median_ns"] / entry["after"]["median_ns"]
            curve.append(entry)
        out.append(dict(name=name, registers_only=registers_only, repeat=repeat,
                        instructions=8 * repeat + 1, curve=curve))
    return out


def slots(lines):
    """Worker slots by thread name, from the run's own CPU lines."""
    found = {}
    for line in lines:
        m = re.search(r"PE64 WORKER HOST CPU: slot=(\d+) handle=\S+ name='([^']*)'", line)
        if m:
            found[m[2]] = int(m[1])
    main = next(v for k, v in found.items() if k.startswith("MAIN_THREAD"))
    gpu = next(v for k, v in found.items() if k.startswith("GPU Commands"))
    return main, gpu


def windows(path):
    lines = path.read_text(errors="replace").splitlines()
    main_slot, gpu_slot = slots(lines)
    pulse, previous, rows = {}, None, []
    for number, line in enumerate(lines, 1):
        m = re.search(r"WORKER RUNTIME PULSE: slot=(\d+) elapsed_ms=(\d+) native_retired=(\d+) native_instructions_per_second=\d+ fallbacks=(\d+) vunpcklpd_fallbacks=\d+ native_hops=(\d+)", line)
        if m:
            pulse[int(m[1])] = tuple(map(int, m.groups()[1:]))
            continue
        m = re.search(r"GRAPHICS ROUTE: descriptors\(updates/native_writes/binds_forwarded/binds_rejected\)=(\d+)/(\d+)/(\d+)/\d+ presented_sources\(sampled/transfer/upload/unresolved\)=(\d+)", line)
        if not m:
            continue
        current = tuple(map(int, m.groups()))
        if previous and current[3] > previous[3] and main_slot in pulse and gpu_slot in pulse:
            frames = current[3] - previous[3]
            main, gpu = pulse[main_slot], pulse[gpu_slot]
            rows.append(dict(line=number, fps=frames * 1000 / WINDOW_MS, frame_ms=WINDOW_MS / frames,
                             updates=(current[0] - previous[0]) / frames,
                             main_instructions=main[1] / frames, main_blocks=main[3] / frames, main_fallbacks=main[2] / frames,
                             main_rate=main[1] / main[0] / 1000 if main[0] else 0,
                             gpu_instructions=gpu[1] / frames, gpu_blocks=gpu[3] / frames,
                             gpu_rate=gpu[1] / gpu[0] / 1000 if gpu[0] else 0))
        previous, pulse = current, {}
    return rows, lines


def classify(row):
    if row["updates"] < 100:
        return "loading"
    if row["updates"] >= 900:
        return "camera moving (title)"
    if row["updates"] >= 450:
        return "camera still (title)"
    return "light (Custom Games)"


def interpolate(curve, variant, n):
    """Per-instruction ns on a measured curve at n hot blocks, log-linear."""
    points = [(math.log(p["blocks"]), p[variant]["median_ns"]) for p in curve if variant in p]
    x = math.log(max(n, 1))
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return points[-1][1]


def equivalent(curve, ns):
    """The working set at which the before curve costs `ns` per block."""
    points = [(math.log(p["blocks"]), p["before"]["median_ns"]) for p in curve]
    if ns <= points[0][1]:
        return math.exp(points[0][0])
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if ns <= y1:
            return math.exp(x0 + (x1 - x0) * (ns - y0) / (y1 - y0))
    return math.exp(points[-1][0])


def project(rows, shape, ceiling_ms=1000 / 30):
    """Per window: MAIN's measured time per block, placed on the before
    curve (scaled to MAIN's instructions per block), and the after curve at
    that working set. A model: see the dashboard's assumptions."""
    curve = shape["curve"]
    out = []
    for r in rows:
        if r["main_blocks"] == 0 or r["updates"] < 100:
            continue
        per_block = r["frame_ms"] * 1e6 / r["main_blocks"]
        scale = (r["main_instructions"] / r["main_blocks"]) / shape["instructions"]
        n = equivalent(curve, per_block / scale)
        after = interpolate(curve, "after", n) * scale
        main_ms = r["main_blocks"] * after / 1e6
        gpu_ms = r["frame_ms"] * min(1.0, r["gpu_rate"] / max(gpu_saturated(rows), 1))
        out.append(dict(r, kind=classify(r), measured_ns_per_block=per_block, equivalent_blocks=n,
                        projected_ns_per_block=after, projected_main_ms=main_ms, gpu_busy_ms=gpu_ms,
                        projected_fps=1000 / max(main_ms, gpu_ms, ceiling_ms)))
    return out


def gpu_saturated(rows):
    return max((r["gpu_rate"] for r in rows if r["updates"] > 100), default=1)


def last(lines, marker):
    for number in range(len(lines), 0, -1):
        if marker in lines[number - 1]:
            return dict(line=number, raw=lines[number - 1])
    return None


def run_summary(path, name):
    rows, lines = windows(path)
    header = "\n".join(lines[:6])
    cpu = {}
    for line in lines:
        m = re.search(r"PE64 WORKER HOST CPU: slot=\d+ handle=\S+ name='([^']*)' cpu_us=(\d+) elapsed_us=(\d+)", line)
        if m:
            cpu[m[1]] = dict(cpu_s=int(m[2]) / 1e6, elapsed_s=int(m[3]) / 1e6)
    pause = {}
    for line in lines:
        m = re.search(r"PE64 TRANSLATED PAUSE: slot=\d+ name='([^']*)' hints=(\d+)", line)
        if m:
            pause[m[1]] = int(m[2])
    jit = {}
    for line in lines:
        m = re.search(r"BLOCK JIT WORKER THREAD: slot=\d+ name='([^']*)' table=\d+ growths=\d+ live=(\d+) compiled=\d+ evictions=\d+ hotness_replacements=\d+ resets=\d+ code_mib\(used/reserved\)=(\d+)/\d+ executions=(\d+) retired=(\d+)", line)
        if m:
            jit[m[1]] = dict(live=int(m[2]), code_mib=int(m[3]), executions=int(m[4]), retired=int(m[5]))
    evidence = [e for e in (last(lines, marker) for marker in (
        "PE64 XENIA REGISTER WRITES:", "PE64 GUEST ACCESS VIOLATIONS:   raised", "PE64 XMA REGISTERS: faults",
        "PE64 GPU WRITE WATCH", "BLOCK JIT WORKER THREAD: slot=23 ", "BLOCK JIT WORKER THREAD: slot=6 ",
        "PE64 WORKER HOST CPU: slot=23 ", "PE64 WORKER HOST CPU: slot=6 ", "IMPORT HISTOGRAM:   rank=12 ",
        "IMPORT HISTOGRAM:   rank=2 ", "Vulkan host time: calls=")) if e]
    return dict(name=name, run=re.search(r"run_id = (\S+)", header)[1], build=re.search(r"build_identity_sha256 = (\S+)", header)[1],
                windows=[dict(r, kind=classify(r)) for r in rows], cpu=cpu, jit=jit, pause=pause, evidence=evidence)


def expansion(text):
    blocks = []
    for m in re.finditer(r"BLOCK JIT EXPANSION: rip=0x([0-9a-f]+) x86=(\d+) arm64_words=(\d+)(?: cold_words=(\d+))?", text):
        blocks.append(dict(rip=m[1], x86=int(m[2]), hot=int(m[3]), cold=int(m[4] or 0)))
    return blocks


def source_sha(manifest, name):
    """A source as the manifest recorded it: at `source_revision` when the
    manifest names one (the pass's committed sources; later work may have
    moved the tree on), from the tree for a file that revision lacks."""
    revision = manifest.get("source_revision")
    if revision:
        import subprocess
        blob = subprocess.run(["git", "-C", str(ROOT), "show", f"{revision}:{name}"], capture_output=True)
        if blob.returncode == 0:
            return hashlib.sha256(blob.stdout).hexdigest()
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def generate(folder):
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert source_sha(manifest, name) == digest, name
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    shapes = series((folder / "bench" / "ws-series.log").read_text())
    current = run_summary(folder / "live-run" / "custom.log", "This run (build with last pass's changes)")
    previous = run_summary(folder / "live-run" / "previous.log", "Previous run")
    xenia_shape = next(s for s in shapes if not s["registers_only"] and s["repeat"] == 3)
    projection = project(windows(folder / "live-run" / "custom.log")[0], xenia_shape)
    expansions = {p.stem: expansion(p.read_text()) for p in sorted((folder / "bench").glob("expansion-*.log"))}
    data = dict(shapes=shapes, runs=[previous, current], projection=projection, expansions=expansions,
                gates=manifest["gates"], correctness=manifest["correctness"], hashes=manifest["evidence_sha256"],
                binaries=manifest.get("binaries", {}))
    (folder / "bench-results.json").write_text(json.dumps(dict(shapes=shapes, projection=projection), indent=2))
    template = Path(__file__).with_name("code_locality_report.html").read_text()
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final" / "report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/")))
    summary = []
    for s in shapes:
        for p in s["curve"]:
            if "ratio" in p:
                summary.append(f'{s["name"]:34s} blocks={p["blocks"]:6d} before={p["before"]["median_ns"]:7.2f} after={p["after"]["median_ns"]:7.2f} '
                               f'split={p.get("split", {}).get("median_ns", float("nan")):7.2f} ratio={p["ratio"]:.3f}')
    print("\n".join(summary))
    kinds = {}
    for p in projection:
        kinds.setdefault(p["kind"], []).append(p)
    for kind, ps in kinds.items():
        print(f'{kind:24s} windows={len(ps):2d} fps={statistics.median(p["fps"] for p in ps):5.2f} '
              f'main_ns/block={statistics.median(p["measured_ns_per_block"] for p in ps):6.1f} N_eq={statistics.median(p["equivalent_blocks"] for p in ps):7.0f} '
              f'projected_main_ms={statistics.median(p["projected_main_ms"] for p in ps):6.1f} projected_fps={statistics.median(p["projected_fps"] for p in ps):5.2f}')


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
