#!/usr/bin/env python3
"""Build the indirect-links dashboard.

Everything is recomputed from raw files; nothing is typed in by hand:
  <folder>/live-run/latest.log            the run with direct and far links installed
  <folder>/live-run/previous.log          the run before them
  <folder>/bench/cr-series.log            alternating before/after/after-off rows (call_return, xbox_cs)
  <folder>/hardware/callret-sweep.txt     native call/return model (callret.c)
  <folder>/manifest.json                  source/evidence hashes, gates, correctness

Usage: report_indirect_links.py <folder>
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
import report_code_locality as locality  # noqa: E402  (window parsing, classification)

VARIANTS = ("before", "after", "after-off")


def source_sha(manifest, name):
    revision = manifest.get("source_revision")
    if revision:
        blob = subprocess.run(["git", "-C", str(ROOT), "show", f"{revision}:{name}"], capture_output=True)
        if blob.returncode == 0:
            return hashlib.sha256(blob.stdout).hexdigest()
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def thread_slots(lines):
    found = {}
    for line in lines:
        m = re.search(r"PE64 WORKER HOST CPU: slot=(\d+) handle=\S+ name='([^']*)' cpu_us=(\d+) elapsed_us=(\d+)", line)
        if m:
            found[m[2]] = dict(slot=int(m[1]), cpu_s=int(m[3]) / 1e6, elapsed_s=int(m[4]) / 1e6)
    return found


def render_rates(lines, slot):
    """RENDER's instructions per frame and rate per report window, in the
    same window order as `locality.windows`."""
    pulse, previous, out = {}, None, []
    for line in lines:
        m = re.search(r"WORKER RUNTIME PULSE: slot=(\d+) elapsed_ms=(\d+) native_retired=(\d+)", line)
        if m:
            pulse[int(m[1])] = (int(m[2]), int(m[3]))
            continue
        m = re.search(r"GRAPHICS ROUTE: descriptors\(updates/native_writes/binds_forwarded/binds_rejected\)=(\d+)/\d+/\d+/\d+ presented_sources\(sampled/transfer/upload/unresolved\)=(\d+)", line)
        if not m:
            continue
        current = (int(m[1]), int(m[2]))
        if previous and current[1] > previous[1]:
            frames = current[1] - previous[1]
            elapsed, retired = pulse.get(slot, (0, 0))
            out.append(dict(render_instructions=retired / frames, render_rate=retired / elapsed / 1000 if elapsed else 0))
        previous, pulse = current, {}
    return out


def worker_line(lines, name_prefix):
    for line in reversed(lines):
        if "BLOCK JIT WORKER THREAD: slot=" in line and f"name='{name_prefix}" in line:
            return locality.fields(line)
    return {}


def last_match(lines, pattern):
    for line in reversed(lines):
        m = re.search(pattern, line)
        if m:
            return m
    return None


def live(path, label):
    rows, lines = locality.windows(path)
    slots = thread_slots(lines)
    render = next((v["slot"] for k, v in slots.items() if k.startswith("RENDER")), None)
    rates = render_rates(lines, render) if render is not None else []
    gpu_peak = max((r["gpu_rate"] for r in rows if r["updates"] > 100), default=1)
    windows = []
    for index, r in enumerate(rows):
        kind = locality.classify(r)
        w = dict(index=index, kind=kind, fps=r["fps"], frame_ms=r["frame_ms"], updates=r["updates"],
                 main_instructions=r["main_instructions"], main_blocks=r["main_blocks"], main_rate=r["main_rate"],
                 gpu_instructions=r["gpu_instructions"], gpu_rate=r["gpu_rate"], gpu_share=r["gpu_rate"] / gpu_peak,
                 ns_per_block=r["frame_ms"] * 1e6 / r["main_blocks"] if r["main_blocks"] else 0)
        if index < len(rates):
            w.update(rates[index])
        windows.append(w)
    kinds = {}
    for w in windows:
        if w["kind"] == "loading" or not w["main_blocks"]:
            continue
        kinds.setdefault(w["kind"], []).append(w)
    summary = {}
    for kind, ws in kinds.items():
        med = lambda key: statistics.median(x[key] for x in ws)
        summary[kind] = dict(windows=len(ws), fps=med("fps"), fps_max=max(x["fps"] for x in ws), main_instructions=med("main_instructions"),
                             ns_per_block=med("ns_per_block"), main_rate=med("main_rate"), gpu_share=med("gpu_share"),
                             frame_ms=med("frame_ms"), instructions_per_block=statistics.median(x["main_instructions"] / x["main_blocks"] for x in ws))
    header = "\n".join(lines[:6])
    cs = {}
    for line in lines:
        m = re.search(r"PE64 XBOX CRITICAL SECTION BRIDGE: export=(\w+) trampoline=\S+ handled=(\d+) native_fallbacks=(\d+) jit_direct_observations=(\d+)", line)
        if m:
            cs[m[1]] = dict(handled=int(m[2]), fallbacks=int(m[3]), jit_direct=int(m[4]))
    hotspots = []
    for line in lines:
        m = re.search(r"PE64 CPU HOTSPOT: thread=\S+ name='MAIN_THREAD[^']*' rank=(\d+) region=(0x[0-9a-f]+) at=(\S+) samples=(\d+) count_lower/upper=(\d+)/(\d+)", line)
        if m:
            hotspots.append(dict(rank=int(m[1]), region=m[2], at=m[3][:90], samples=int(m[4]), lower=int(m[5]), upper=int(m[6])))
    vulkan = []
    for line in lines:
        m = re.search(r"Vulkan host time by entry point: rank=(\d+) name=(\w+) calls=(\d+) host_ms=(\d+) mean_us=(\d+)", line)
        if m:
            vulkan.append(dict(rank=int(m[1]), name=m[2], calls=int(m[3]), host_ms=int(m[4]), mean_us=int(m[5])))
    busiest = last_match(lines, r"busiest: (\w+) with (\d+) call")
    return dict(label=label, run=re.search(r"run_id = (\S+)", header)[1], build=re.search(r"build_identity_sha256 = (\S+)", header)[1],
                windows=windows, kinds=summary, gpu_peak=gpu_peak, cpu=slots,
                main_worker=worker_line(lines, "MAIN_THREAD"), gpu_worker=worker_line(lines, "GPU Commands"),
                critical_sections=cs, hotspots=hotspots[:3], vulkan=vulkan[-12:],
                busiest_kernel_call=dict(name=busiest[1], calls=int(busiest[2])) if busiest else None)


def series(text):
    rows = [locality.fields(l) for l in text.splitlines() if l.startswith("call_return ")]
    by_pair = {}
    for r in rows:
        by_pair.setdefault(r["series_pair"], set()).add(r["binary"])
    complete = sorted({p for p, seen in by_pair.items() if set(VARIANTS) <= seen}, key=int)
    points = {}
    for r in rows:
        if r["series_pair"] not in complete:
            continue
        key = (int(r["indirect"]), int(r["utilities"]), int(r["functions"]))
        points.setdefault(key, {}).setdefault(r["binary"], []).append(dict(
            pair=int(r["series_pair"]), ns=int(r["cpu_ns"]) / int(r["block_executions"]), retired=int(r["retired"]),
            executions=int(r["block_executions"]), compiled=int(r["compiled"]), misses=int(r["chain_misses"]),
            entries=int(r["dispatch_entries"]), hot=int(r.get("hot_bytes_per_block", 0)),
            guest=int(r["guest_value"]), context=int(r["context_value"])))
    shapes = {}
    for (indirect, utilities, functions), variants in sorted(points.items()):
        entry = dict(functions=functions)
        for variant, samples in variants.items():
            entry[variant] = dict(median_ns=statistics.median(s["ns"] for s in samples), samples=samples)
        if all(v in entry for v in VARIANTS):
            # Every binary retires the same instructions and leaves the same
            # guest values for the same program.
            for field in ("retired", "guest", "context", "executions"):
                values = {s[field] for v in VARIANTS for s in entry[v]["samples"]}
                assert len(values) == 1, (indirect, functions, field, values)
            entry["ratio"] = entry["before"]["median_ns"] / entry["after"]["median_ns"]
            entry["off_ratio"] = entry["after-off"]["median_ns"] / entry["after"]["median_ns"]
            entry["pair_ratios"] = sorted(b["ns"] / a["ns"] for b in entry["before"]["samples"] for a in entry["after"]["samples"] if a["pair"] == b["pair"])
        shapes.setdefault((indirect, utilities), dict(indirect=indirect, utilities=utilities, curve=[]))["curve"].append(entry)
    cs = {}
    for l in text.splitlines():
        if l.startswith("xbox_cs "):
            r = locality.fields(l)
            if r["series_pair"] in complete:
                cs.setdefault(r["completion"], []).append(dict(pair=int(r["series_pair"]), ns=float(r["ns_per_pair"]), entries=int(r["dispatch_entries"])))
    cs_summary = {k: dict(median_ns=statistics.median(s["ns"] for s in v), samples=v) for k, v in cs.items()}
    return list(shapes.values()), [int(p) for p in complete], cs_summary


def hardware(folder):
    points = {}
    for line in (folder / "hardware" / "callret-sweep.txt").read_text().splitlines():
        m = re.match(r"F=(\d+) D=(\d+) blocks=(\d+) pad=(\d+) mode=(\d+) executions=(\d+) ns_per_block=([\d.]+)", line)
        if m and int(m[6]) > 1000:
            points.setdefault((int(m[4]), int(m[1]), int(m[3])), {}).setdefault(int(m[5]), []).append(float(m[7]))
    model = []
    for (pad, functions, blocks), modes in sorted(points.items()):
        if not all(k in modes for k in (0, 1, 2)):
            continue
        model.append(dict(pad=pad, functions=functions, blocks=blocks,
                          production=statistics.median(modes[0]), paired=statistics.median(modes[1]),
                          paired_checked=statistics.median(modes[2]), samples={k: v for k, v in modes.items()}))
    return model


def generate(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert source_sha(manifest, name) == digest, name
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    runs = [live(folder / "live-run" / "previous.log", "Before direct links (20261019T034008Z)"),
            live(folder / "live-run" / "latest.log", "Direct and far links installed (20261019T165211Z)")]
    shapes, pairs, cs = series((folder / "bench" / "cr-series.log").read_text())
    model = hardware(folder)
    # How much of a predicted per-block fall last pass realized live: its
    # hardware model (production hop against the shipped direct entry, ~1 KB
    # blocks, 4,096 hot) against MAIN's light-window time per block.
    calibration = manifest["calibration"]
    light = "light (Custom Games)"
    measured = 1 - runs[1]["kinds"][light]["ns_per_block"] / runs[0]["kinds"][light]["ns_per_block"]
    calibration["measured_light"] = measured
    calibration["realized"] = measured / calibration["predicted_per_hop"]
    data = dict(runs=runs, shapes=shapes, pairs=pairs, critical_sections=cs, hardware=model, calibration=calibration,
                gates=manifest["gates"], correctness=manifest["correctness"], hashes=manifest["evidence_sha256"],
                binaries=manifest.get("binaries", {}), revision=manifest.get("source_revision"), user_report=manifest["user_report"])
    (folder / "bench-results.json").write_text(json.dumps(dict(shapes=shapes, pairs=pairs, critical_sections=cs, hardware=model, calibration=calibration), indent=2))
    template = Path(__file__).with_name("indirect_links_report.html").read_text()
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final" / "report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/")))
    print(f"calibration: predicted per hop {calibration['predicted_per_hop']:.3f} measured light {measured:.3f} realized {calibration['realized']:.2f}; pairs {pairs}")
    for s in shapes:
        for p in s["curve"]:
            if "ratio" in p:
                print(f'indirect={s["indirect"]:3d}% utilities={s["utilities"]:3d} functions={p["functions"]:5d} before={p["before"]["median_ns"]:6.2f} '
                      f'after={p["after"]["median_ns"]:6.2f} off={p["after-off"]["median_ns"]:6.2f} ratio={p["ratio"]:.3f} off_ratio={p["off_ratio"]:.3f}')
    for key, value in cs.items():
        print(f"critical sections completion={key} ns_per_pair={value['median_ns']:.1f} n={len(value['samples'])}")
    for run in runs:
        for kind, k in run["kinds"].items():
            print(f'{run["run"][:16]} {kind:24s} n={k["windows"]:3d} fps={k["fps"]:5.1f} max={k["fps_max"]:5.1f} main_ns/block={k["ns_per_block"]:5.1f} instr/frame={k["main_instructions"] / 1e6:5.1f}M gpu={100 * k["gpu_share"]:3.0f}%')


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
