#!/usr/bin/env python3
"""Source-bound comparisons for deferred PAUSE and scalar XMM residency."""
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
        marker = line.find("critical_cpu kind=")
        if marker < 0:
            continue
        row = {key: (value == "true" if value in ("true", "false") else int(value) if value.isdigit() else value)
               for key, value in re.findall(r"(\w+)=(\S+)", line[marker:])}
        row["case"] = ("pause" + str(row["bundle"]) if row["kind"] == "pause"
                       else "scalar_ind" if row["independent"] else "scalar_dep")
        rows.append(row)
    groups = []
    for case in ("pause1", "pause8", "scalar_dep", "scalar_ind"):
        group = [r for r in rows if r["case"] == case]
        old = [r for r in group if not r["enabled"]]
        new = [r for r in group if r["enabled"]]
        assert len(old) == len(new) == 7, case
        assert {r["pair"] for r in old} == {r["pair"] for r in new} == set(range(7))
        for pair in range(7):
            a = next(r for r in old if r["pair"] == pair)
            b = next(r for r in new if r["pair"] == pair)
            assert a["retired"] == b["retired"] and a["operations"] == b["operations"]
            if case.startswith("pause"):
                assert a["operations"] == a["bundle"] * 100000
                assert a["yields"] == b["yields"] and b["dispatches"] < a["dispatches"]
            else:
                assert a["retired"] == a["operations"] == 9600000
                assert b["code_bytes"] < a["code_bytes"]
        before = statistics.median(r["cpu_ns"] for r in old) / 1e6
        after = statistics.median(r["cpu_ns"] for r in new) / 1e6
        detail = (f"{old[0]['operations']:,} hints; identical retired instructions and yields. "
                  f"Dispatches {old[0]['dispatches']:,} → {new[0]['dispatches']:,}."
                  if case.startswith("pause") else
                  f"9,600,000 operations; full registers and vectors match. Code {old[0]['code_bytes']:,} → {new[0]['code_bytes']:,} bytes; "
                  f"new forwarded loads / elided stores: {new[0]['forwarded_loads']} / {new[0]['elided_stores']} per compiled block.")
        ratios = [next(r for r in old if r["pair"] == p)["cpu_ns"] /
                  next(r for r in new if r["pair"] == p)["cpu_ns"] for p in range(7)]
        groups.append(dict(case=case, kind=old[0]["kind"], before_ms=before, after_ms=after,
                           ratio=before / after, saved_pct=100 * (1 - after / before),
                           pair_ratio_min=min(ratios), pair_ratio_max=max(ratios), detail=detail, samples=group))
    assert len(rows) == 56
    return groups


def generate(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    bench = (folder / "critical-bench-final.log").read_text()
    assert "20 passed; 3 skipped; 0 failed." in bench
    groups = comparisons(bench)
    lines = (folder / "input.log").read_text().splitlines()
    clock = (ROOT / "lib/processor/ELF_processor/guest_clock.zig").read_text()
    assert "pub const hz: u64 = 1_000_000;" in clock
    inventory = parse(lines, ticks_per_ms=1000)
    header = "\n".join(lines[:70])
    run = re.search(r"run_id\s*=\s*(\S+)", header)[1]
    build = re.search(r"build_identity_sha256\s*=\s*(\S+)", header)[1]
    wsi = [float(m[1]) for line in lines if (m := re.search(r"presented_fps=([\d.]+)", line))]
    # Match the captured TimerQueue instruction stream, not a guessed opcode.
    timer = next((dict(line=i, raw=line, bytes=re.search(r"bytes=(\w+)", line)[1])
                  for i, line in enumerate(lines, 1) if "x86_code rip=0x140130070 " in line), None)
    assert timer and timer["bytes"].startswith("f390" * 8 + "83c1f875eb")
    data = dict(groups=groups, inventory=inventory, run=run, build=build, wsi=wsi[-1],
                gates=manifest["gates"], timer=timer)
    (folder / "bench-results.json").write_text(json.dumps(groups, indent=2))
    (folder / "timing-inventory.json").write_text(json.dumps(inventory, indent=2))
    (folder / "timer-code-evidence.json").write_text(json.dumps(timer, indent=2))
    template = Path(__file__).with_name("critical_cpu_report.html").read_text()
    template = template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/"))
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(template)
    print(json.dumps(dict(comparisons=[{k: g[k] for k in ("case", "ratio", "before_ms", "after_ms")} for g in groups],
                         maxima=len(inventory["maxima"]), estimates=len(inventory["estimates"]),
                         cpu=len(inventory["cpu"]), merged_aliases=len(inventory["aliases"])), indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
