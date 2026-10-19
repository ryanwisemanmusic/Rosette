#!/usr/bin/env python3
"""Build the direct-links dashboard.

Everything is recomputed from raw files; nothing is typed in by hand:
  <folder>/bench/ws-series.log                 alternating before/after/after-nodirect rows
  <folder>/bench/expansion-{before,after}.log  ARM64 words of Xenia's RENDER function
  <folder>/hardware/hop-model-sweep.txt        native hop model (production / two direct designs)
  <folder>/hardware/indirect-vs-direct-sweep.txt  bare br vs b
  <folder>/live-run/latest.log                 the run with last pass installed
  <folder>/live-run/previous.log               the run before it
  <folder>/manifest.json                       source/evidence hashes, gates

Usage: report_direct_links.py <folder>
"""
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import report_code_locality as locality  # noqa: E402  (window parsing, live summaries)

VARIANTS = ("before", "after", "after-nodirect")


def source_sha(manifest, name):
    revision = manifest.get("source_revision")
    if revision:
        blob = subprocess.run(["git", "-C", str(ROOT), "show", f"{revision}:{name}"], capture_output=True)
        if blob.returncode == 0:
            return hashlib.sha256(blob.stdout).hexdigest()
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def series(text):
    rows = [locality.fields(l) for l in text.splitlines() if "series_pair=" in l and " blocks=" in l and " order=" in l]
    rows = [r for r in rows if r.get("split") == "false"]
    by_pair = {}
    for r in rows:
        by_pair.setdefault(r["series_pair"], set()).add(r["binary"])
    complete = {p for p, seen in by_pair.items() if set(VARIANTS) <= seen}
    points = {}
    for r in rows:
        if r["series_pair"] not in complete:
            continue
        key = (r["registers_only"] == "true", int(r["repeat"]), r["order"], int(r["blocks"]))
        points.setdefault(key, {}).setdefault(r["binary"], []).append(dict(
            pair=int(r["series_pair"]), ns=int(r["cpu_ns"]) / int(r["block_executions"]),
            retired=int(r["retired"]), executions=int(r["block_executions"]),
            hot=int(r["hot_bytes_per_block"]), hops=int(r.get("native_hops", 0)), entries=int(r.get("dispatch_entries", 0))))
    shapes = {}
    for (registers_only, repeat, order, blocks), variants in sorted(points.items()):
        name = "register-only, 8 instructions" if registers_only else f"Xenia-shaped, {8 * repeat + 1} instructions"
        entry = dict(blocks=blocks)
        for variant, samples in variants.items():
            entry[variant] = dict(median_ns=statistics.median(s["ns"] for s in samples), samples=samples, hot=samples[0]["hot"])
        if all(v in entry for v in VARIANTS):
            # The same program retires the same instructions in every binary.
            retired = {s["retired"] for v in VARIANTS for s in entry[v]["samples"]}
            assert len(retired) == 1, (name, order, blocks, retired)
            entry["ratio"] = entry["before"]["median_ns"] / entry["after"]["median_ns"]
            entry["direct_ratio"] = entry["after-nodirect"]["median_ns"] / entry["after"]["median_ns"]
        shapes.setdefault((name, order), dict(name=name, order=order, registers_only=registers_only,
                                              instructions=8 * repeat + 1 + (3 if order == "shuffled" else 0),
                                              curve=[]))["curve"].append(entry)
    return list(shapes.values()), sorted(int(p) for p in complete)


def hardware(folder):
    hop = {}
    for line in (folder / "hardware" / "hop-model-sweep.txt").read_text().splitlines():
        m = re.match(r"n=(\d+) pad=(\d+) mode=(\d+) ns_per_block=([\d.]+)", line)
        if m:
            hop.setdefault((int(m[2]), int(m[1])), {}).setdefault(int(m[3]), []).append(float(m[4]))
    model = []
    for (pad, n), modes in sorted(hop.items()):
        model.append(dict(pad=pad, blocks=n, production=statistics.median(modes[3]),
                          direct_self_proof=statistics.median(modes[4]), direct_generation=statistics.median(modes[5]),
                          samples={k: v for k, v in modes.items()}))
    bare = []
    for line in (folder / "hardware" / "indirect-vs-direct-sweep.txt").read_text().splitlines():
        m = re.match(r"n=(\d+) pad=(\d+) mode=(\d+) stride=\d+ ns_per_block=([\d.]+)", line)
        if m:
            bare.append(dict(blocks=int(m[1]), pad=int(m[2]), mode=int(m[3]), ns=float(m[4])))
    return dict(model=model, bare=bare)


def kinds(rows):
    out = {}
    for r in rows:
        kind = locality.classify(r)
        if kind == "loading" or not r["main_blocks"]:
            continue
        out.setdefault(kind, []).append(r)
    summary = {}
    for kind, ws in out.items():
        med = lambda key: statistics.median(w[key] for w in ws)
        summary[kind] = dict(windows=len(ws), fps=med("fps"), main_instructions=med("main_instructions"),
                             main_rate=med("main_rate"), gpu_rate=med("gpu_rate"),
                             instructions_per_block=statistics.median(w["main_instructions"] / w["main_blocks"] for w in ws),
                             ns_per_block=statistics.median(w["frame_ms"] * 1e6 / w["main_blocks"] for w in ws))
    return summary


def worker_line(lines, slot):
    for line in reversed(lines):
        if f"BLOCK JIT WORKER THREAD: slot={slot} " in line:
            return locality.fields(line)
    return {}


def generate(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert source_sha(manifest, name) == digest, name
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    shapes, pairs = series((folder / "bench" / "ws-series.log").read_text())
    runs = []
    for name, label in (("previous.log", "Before last pass (20261019T000531Z)"), ("latest.log", "Last pass installed (20261019T034008Z)")):
        rows, lines = locality.windows(folder / "live-run" / name)
        main_slot, gpu_slot = locality.slots(lines)
        summary = locality.run_summary(folder / "live-run" / name, label)
        runs.append(dict(label=label, run=summary["run"], build=summary["build"], windows=summary["windows"],
                         kinds=kinds(rows), cpu=summary["cpu"], main_worker=worker_line(lines, main_slot),
                         gpu_worker=worker_line(lines, gpu_slot)))
    expansions = {p.stem.split("-")[1]: locality.expansion(p.read_text()) for p in sorted((folder / "bench").glob("expansion-*.log"))}
    # `ldrb w9, [x22]`: the abort-flag load every hot-path abort check starts with.
    abort_checks = {}
    for p in sorted((folder / "bench").glob("expansion-*.log")):
        counts = [sum(1 for w in m[1].split() if int(w, 16) == 0x394002C9)
                  for m in re.finditer(r"BLOCK JIT BENCH CODE: rip=0x[0-9a-f]+ words=([0-9a-f ]+)", p.read_text())]
        abort_checks[p.stem.split("-")[1]] = counts
    # Last pass's realized fraction: projected vs measured fall in MAIN's
    # time per block in the light Custom Games windows.
    light = "light (Custom Games)"
    predicted = manifest["last_pass_projection"]["light_reduction"]
    measured = 1 - runs[1]["kinds"][light]["ns_per_block"] / runs[0]["kinds"][light]["ns_per_block"]
    calibration = dict(predicted=predicted, measured=measured, fraction=measured / predicted)
    data = dict(shapes=shapes, pairs=pairs, hardware=hardware(folder), runs=runs, expansions=expansions,
                calibration=calibration,
                abort_checks=f"{' and '.join(map(str, abort_checks.get('before', [])))} to {' and '.join(map(str, abort_checks.get('after', [])))}",
                last_pass_projection=manifest["last_pass_projection"], user_report=manifest["user_report"],
                gates=manifest["gates"], correctness=manifest["correctness"], hashes=manifest["evidence_sha256"],
                binaries=manifest.get("binaries", {}), revision=manifest.get("source_revision"))
    (folder / "bench-results.json").write_text(json.dumps(dict(shapes=shapes, pairs=pairs, hardware=data["hardware"], calibration=calibration, abort_checks=abort_checks), indent=2))
    print(f"calibration: predicted {predicted:.3f} measured {measured:.3f} fraction {calibration['fraction']:.2f}; abort checks {abort_checks}")
    template = Path(__file__).with_name("direct_links_report.html").read_text()
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final" / "report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/")))
    for s in shapes:
        for p in s["curve"]:
            if "ratio" in p:
                print(f'{s["name"]:31s} {s["order"]:10s} blocks={p["blocks"]:6d} before={p["before"]["median_ns"]:7.2f} '
                      f'after={p["after"]["median_ns"]:7.2f} nodirect={p["after-nodirect"]["median_ns"]:7.2f} '
                      f'ratio={p["ratio"]:.3f} direct={p["direct_ratio"]:.3f}')
    for run in runs:
        for kind, k in run["kinds"].items():
            print(f'{run["run"][:16]} {kind:24s} n={k["windows"]:3d} fps={k["fps"]:5.1f} main_ns/block={k["ns_per_block"]:5.1f} instr/frame={k["main_instructions"] / 1e6:5.1f}M')


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
