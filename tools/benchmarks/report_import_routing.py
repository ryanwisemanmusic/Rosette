#!/usr/bin/env python3
"""Source-bound synchronization and Vulkan ABI comparisons."""
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys
from timing_inventory import parse

ROOT = Path(__file__).resolve().parents[2]


def comparisons(text):
    rows = []
    for line in text.splitlines():
        marker = line.find("routing kind=")
        if marker < 0:
            continue
        rows.append({k: (v == "true" if v in ("true", "false") else int(v) if v.isdigit() else v)
                     for k, v in re.findall(r"(\w+)=(\S+)", line[marker:])})
    groups = []
    cases = [("wait_lookup", size) for size in (64, 474, 1800)] + [(k, None) for k in
             ("NtWaitForSingleObject", "NtSetEventBoostPriority", "route_draw", "route_update")]
    for kind, size in cases:
        samples = [r for r in rows if r["kind"] == kind and (size is None or r["size"] == size)]
        old = [r for r in samples if not r["enabled"]]
        new = [r for r in samples if r["enabled"]]
        assert len(old) == len(new) == 7, (kind, size, len(old), len(new))
        assert {r["pair"] for r in old} == {r["pair"] for r in new} == set(range(7))
        ratios = []
        for p in range(7):
            a = next(r for r in old if r["pair"] == p)
            b = next(r for r in new if r["pair"] == p)
            assert a["operations"] == b["operations"] == 100000
            if "retired" in a:
                assert a["retired"] == b["retired"] == 400001
            if "hits" in b:
                assert b["hits"] == (0 if kind == "route_draw" else 100000) if kind.startswith(("wait_lookup", "route_")) else b["hits"] > 0
            ratios.append(a["cpu_ns"] / b["cpu_ns"])
        before = statistics.median(r["cpu_ns"] for r in old) / 1e6
        after = statistics.median(r["cpu_ns"] for r in new) / 1e6
        name = f"Wait-table lookup · {size:,} entries" if size else {
            "NtWaitForSingleObject": "Complete ordinary NT wait · 474 entries",
            "NtSetEventBoostPriority": "Complete ordinary NT event · 474 entries",
            "stack_payload": "128-byte scratch writer · real PE memory",
            "vulkan_adapter": "Complete Vulkan draw adapter · scratch writer",
            "route_draw": "Complete Vulkan draw adapter · route facts",
            "route_update": "Complete descriptor update adapter · route facts",
        }[kind]
        groups.append(dict(case=kind + (str(size) if size else ""), kind=kind, name=name,
                           before_ms=before, after_ms=after, ratio=before / after,
                           saved_pct=100 * (1 - after / before), samples=samples,
                           pair_ratio_min=min(ratios), pair_ratio_max=max(ratios),
                           detail="100,000 equal operations. Controls disable only the named change; previous caches remain enabled. "
                           + ("Real guest CALL/JIT/import/ABI/runtime lock; same 400,001 retired instructions, status, stack and registers."
                              if kind.startswith("Nt") else "CPU-only lookup or full adapter with counted native-function stubs; no GPU commands submitted. Command-draw cache is bypassed in both controls.")))
    assert len(rows) == 98, len(rows)
    return groups


def generate(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    for name, value in manifest["source_sha256"].items():
        assert sha(ROOT / name) == value, name
    for name, value in manifest["evidence_sha256"].items():
        assert sha(folder / name) == value, name
    groups = comparisons((folder / "routing-bench-final.log").read_text())
    lines = (folder / "input.log").read_text().splitlines()
    inventory = parse(lines, ticks_per_ms=1000)
    metadata = {}
    for i, line in enumerate(lines, 1):
        if "PE64 IMPORT METADATA:" in line:
            row = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", line)}
            metadata[row["slot"]] = dict(**row, line=i, raw=line)
    totals = {key: sum(row[key] for row in metadata.values()) for key in
              ("stub_lookups", "stub_hits", "stub_scanned", "callsites", "callsite_hits", "callsite_rebuilds")}
    totals["dynamic_entries_peak"] = max(row["dynamic_entries_peak"] for row in metadata.values())
    evidence = {key: [dict(line=i, raw=line) for i, line in enumerate(lines, 1) if key in line][-8:]
                for key in ("xenia_gpu_render_settings =", "xenia_config_preflight =", "fsi_render_target_path:", "PE64 guest scheduling health:", "Vulkan host time by entry point:")}
    header = "\n".join(lines[:45])
    wsi = [float(m[1]) for line in lines if (m := re.search(r"presented_fps=([\d.]+)", line))]
    data = dict(groups=groups, inventory=inventory, evidence=evidence,
                run=re.search(r"run_id\s*=\s*(\S+)", header)[1], build=re.search(r"build_identity_sha256\s*=\s*(\S+)", header)[1],
                wsi=wsi[-1], gates=manifest["gates"], metadata=totals)
    (folder / "bench-results.json").write_text(json.dumps(groups, indent=2))
    (folder / "timing-inventory.json").write_text(json.dumps(inventory, indent=2))
    template = Path(__file__).with_name("import_routing_report.html").read_text()
    (folder / "final").mkdir(exist_ok=True)
    (folder / "final/report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/")))
    print(json.dumps(dict(results=[{k: g[k] for k in ("case", "before_ms", "after_ms", "ratio")} for g in groups],
                         maxima=len(inventory["maxima"]), estimates=len(inventory["estimates"]), workers=len(inventory["cpu"]),
                         aliases=len(inventory["aliases"]), metadata=totals), indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
