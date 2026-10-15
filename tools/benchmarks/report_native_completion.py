#!/usr/bin/env python3
"""Source-bound production CPU comparisons and a searchable maximum inventory."""
import hashlib
import json
import re
import statistics
from pathlib import Path
import sys
from timing_inventory import parse

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def comparisons(text):
    rows = []
    for line in text.splitlines():
        marker = line.find("native_completion case=")
        if marker < 0:
            continue
        line = line[marker:]
        row = {key: (value == "true" if value in ("true", "false") else int(value) if value.isdigit() else value)
               for key, value in re.findall(r"(\w+)=(\S+)", line)}
        rows.append(row)
    result = []
    for case in ("cwde", "div32", "movaps_load", "movaps_store", "madd"):
        group = [r for r in rows if r["case"] == case]
        old = [r for r in group if not r["enabled"]]
        new = [r for r in group if r["enabled"]]
        assert len(old) == len(new) == 7, case
        assert {r["pair"] for r in old} == {r["pair"] for r in new} == set(range(7))
        for pair in range(7):
            a = next(r for r in old if r["pair"] == pair)
            b = next(r for r in new if r["pair"] == pair)
            assert a["retired"] == b["retired"] and a["operations"] == b["operations"] == 100000
            assert a["fallbacks"] == 100000 and b["fallbacks"] == 0
        before = statistics.median(r["cpu_ns"] for r in old) / 1e6
        after = statistics.median(r["cpu_ns"] for r in new) / 1e6
        result.append(dict(case=case, before_ms=before, after_ms=after, ratio=before / after,
                           saved_pct=100 * (1 - after / before), samples=group))
    assert len(rows) == 70
    return result


def generate(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    bench = (folder / "native-bench-final.log").read_text()
    assert "22 passed; 2 skipped; 0 failed." in bench
    groups = comparisons(bench)
    lines = (folder / "input.log").read_text().splitlines()
    # Explicit source identity is part of the manifest. Wait-cost ticks use
    # Rosette's 1 MHz Windows guest clock, not Xenia's 50 MHz Xbox clock.
    clock = (ROOT / "lib/processor/ELF_processor/guest_clock.zig").read_text()
    assert "pub const hz: u64 = 1_000_000;" in clock
    inventory = parse(lines, ticks_per_ms=1000)
    (folder / "bench-results.json").write_text(json.dumps(groups, indent=2))
    (folder / "timing-inventory.json").write_text(json.dumps(inventory, indent=2))
    header = "\n".join(lines[:70])
    run = re.search(r"run_id\s*=\s*(\S+)", header)[1]
    build = re.search(r"build_identity_sha256\s*=\s*(\S+)", header)[1]
    wsi = [float(m[1]) for line in lines if (m := re.search(r"presented_fps=([\d.]+)", line))]
    data = dict(groups=groups, inventory=inventory, run=run, build=build, wsi=wsi[-1], gates=manifest["gates"])
    template = (Path(__file__).with_name("native_completion_report.html")).read_text()
    template = template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/"))
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(template)
    print(json.dumps(dict(comparisons=[dict(case=g["case"], ratio=g["ratio"], before_ms=g["before_ms"], after_ms=g["after_ms"]) for g in groups],
                         maxima=len(inventory["maxima"]), estimates=len(inventory["estimates"]), cpu=len(inventory["cpu"])), indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
