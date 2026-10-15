#!/usr/bin/env python3
"""Source-bound ordinary import comparisons and live timing evidence."""
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys
from timing_inventory import parse

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def comparisons(text):
    rows = []
    for line in text.splitlines():
        marker = line.find("frame_work kind=")
        if marker < 0:
            continue
        row = {k: (v == "true" if v in ("true", "false") else int(v) if v.isdigit() else v)
               for k, v in re.findall(r"(\w+)=(\S+)", line[marker:])}
        rows.append(row)
    groups = []
    for size in (64, 1024, 4096):
        for memory in (False, True):
            samples = [r for r in rows if r["size"] == size and r["memory"] == memory]
            old = [r for r in samples if not r["enabled"]]
            new = [r for r in samples if r["enabled"]]
            assert len(old) == len(new) == 7
            assert {r["pair"] for r in old} == {r["pair"] for r in new} == set(range(7))
            ratios = []
            for p in range(7):
                a = next(r for r in old if r["pair"] == p)
                b = next(r for r in new if r["pair"] == p)
                assert a["retired"] == b["retired"] == 400001
                assert a["calls"] == b["calls"] == 100000
                assert a["stub_hits"] == a["site_hits"] == 0
                assert b["stub_hits"] > 99900 and b["site_hits"] > 99900
                assert b["scanned"] < 10 * size and b["rebuilds"] < 10
                ratios.append(a["cpu_ns"] / b["cpu_ns"])
            before = statistics.median(r["cpu_ns"] for r in old) / 1e6
            after = statistics.median(r["cpu_ns"] for r in new) / 1e6
            groups.append(dict(case=f"{size}_{int(memory)}", size=size, memory=memory,
                               name=f"{size:,} dynamic entries · {'memory' if memory else 'register'} CALL",
                               before_ms=before, after_ms=after, ratio=before / after,
                               saved_pct=100 * (1 - after / before), samples=samples,
                               pair_ratio_min=min(ratios), pair_ratio_max=max(ratios),
                               detail="100,000 ordinary production import handlers; same checksum, "
                               "full registers/flags/upper vectors/stack and 400,001 retired instructions. "
                               "Block JIT and ABI work retained; no timed compilation. "
                               "CPU-only callback, not a native Vulkan driver or game frame."))
    assert len(rows) == 84
    return groups


def generate(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    bench = (folder / "frame-work-bench-final.log").read_text()
    assert "All 23 tests passed." in bench
    groups = comparisons(bench)
    retention = re.search(r"retained_stub_bytes=(\d+) retained_callsite_bytes=(\d+)", bench)
    assert retention
    lines = (folder / "input.log").read_text().splitlines()
    assert "pub const hz: u64 = 1_000_000;" in (ROOT / "lib/processor/ELF_processor/guest_clock.zig").read_text()
    inventory = parse(lines, ticks_per_ms=1000)
    header = "\n".join(lines[:70])
    wsi = [float(m[1]) for line in lines if (m := re.search(r"presented_fps=([\d.]+)", line))]
    # Keep the exact line for every additional claim, not guessed stage attribution.
    evidence = {}
    for key, needle in {
        "transfers": "PE64 BLOCK JIT WORKER TRANSFER FALLBACK",
        "timer": "PE64 PAUSE POLICY RECHECK:",
        "guard": "VULKAN FSI GUARD:",
        "room": "METAL COMMAND BUFFER POLICY:",
    }.items():
        evidence[key] = [dict(line=i, raw=line) for i, line in enumerate(lines, 1) if needle in line][-12:]
    data = dict(groups=groups, inventory=inventory, evidence=evidence,
                run=re.search(r"run_id\s*=\s*(\S+)", header)[1],
                build=re.search(r"build_identity_sha256\s*=\s*(\S+)", header)[1],
                wsi=wsi[-1], gates=manifest["gates"],
                retention=dict(stubs=int(retention[1]), callsites=int(retention[2])))
    (folder / "bench-results.json").write_text(json.dumps(groups, indent=2))
    (folder / "timing-inventory.json").write_text(json.dumps(inventory, indent=2))
    template = Path(__file__).with_name("frame_work_report.html").read_text()
    output = template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/"))
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(output)
    print(json.dumps(dict(results=[{k: g[k] for k in ("case", "before_ms", "after_ms", "ratio")} for g in groups],
                         maxima=len(inventory["maxima"]), estimates=len(inventory["estimates"]),
                         workers=len(inventory["cpu"]), aliases=len(inventory["aliases"]),
                         retention=data["retention"]), indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
