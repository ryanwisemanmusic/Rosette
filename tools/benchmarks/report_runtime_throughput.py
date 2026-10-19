#!/usr/bin/env python3
"""Recompute this pass's report from complete paired CPU benchmark logs.

Usage: python3 tools/benchmarks/report_runtime_throughput.py EVIDENCE_FOLDER
No Xenia, ISO extraction, compilation or GPU dispatch is performed here.
"""
import hashlib
import json
from pathlib import Path
import re
import statistics as stats
import sys
from timing_inventory import parse


def fields(line):
    return dict(re.findall(r"(\w+)=([^ ]+)", line))


def read_series(folder, name, marker):
    rows = []
    for series, suffix in enumerate(("final", "repeat1", "repeat2")):
        path = folder / f"bench-{name}-{suffix}.log"
        text = path.read_text()
        assert re.search(r"All \d+ tests passed\.", text), path
        for number, line in enumerate(text.splitlines(), 1):
            if marker + " profile=" not in line:
                continue
            row = fields(line[line.index(marker + " profile="):])
            row.update(series=series, source=path.name, line=number)
            rows.append(row)
    return rows


def summarize(rows, variants, variant_key):
    out = []
    for profile in sorted({int(r["profile"]) for r in rows}):
        samples = [r for r in rows if int(r["profile"]) == profile]
        groups = {}
        for r in samples:
            key = (r["series"], r["pair"])
            group = groups.setdefault(key, {})
            assert r[variant_key] not in group, (profile, key)
            group[r[variant_key]] = r
        assert len(groups) == 21, (profile, len(groups))
        for group in groups.values():
            assert set(group) == set(variants)
            if variant_key == "variant":
                for field in ("retired", "blocks", "checksum", "code_bytes"):
                    assert len({r[field] for r in group.values()}) == 1
        medians = {}
        for v in variants:
            points = [r for r in samples if r[variant_key] == v]
            medians[v] = dict(cpu_ms=stats.median(int(r["cpu_ns"]) for r in points) / 1e6)
            if "elapsed_ns" in points[0]:
                medians[v]["elapsed_ms"] = stats.median(int(r["elapsed_ns"]) for r in points) / 1e6
            for field in ("syncs", "elided", "count", "data_slots", "separated", "requests", "bytes", "streams", "code_bytes"):
                if field in points[0]:
                    medians[v][field] = points[0][field]
        before, after = variants[0], variants[-1]
        ratios = [int(g[before]["cpu_ns"]) / int(g[after]["cpu_ns"]) for g in groups.values()]
        out.append(dict(profile=profile, medians=medians, ratio=medians[before]["cpu_ms"] / medians[after]["cpu_ms"],
                        paired_ratio=stats.median(ratios), min_pair=min(ratios), max_pair=max(ratios), samples=samples))
    return out


def evidence_line(lines, text):
    found = [(i, s) for i, s in enumerate(lines, 1) if text in s]
    assert found, text
    number, raw = found[-1]
    return dict(line=number, raw=raw)


def build(folder):
    log = (folder / "input.log").read_text()
    lines = log.splitlines()
    # Existing wait-cost ledger uses microsecond guest ticks (1000/ms),
    # distinct from thread CPU clocks. Preserve the parser's basis labels.
    inventory = parse(lines, ticks_per_ms=1000)
    (folder / "timing-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    far = summarize(read_series(folder, "far", "far_links"), ("0", "1", "2"), "variant")
    stdio = summarize(read_series(folder, "stdio", "stdio_flush"), ("false", "true"), "enabled")
    for row in stdio:
        for sample in row["samples"]:
            calls, streams = int(sample["requests"]), int(sample["streams"])
            expected = calls * streams if sample["enabled"] == "false" else calls if row["profile"] in (2, 3) else 0
            assert int(sample["syncs"]) == expected
    run = re.search(r"run_id\s*=\s*(\S+)", log)[1]
    data = dict(run=run, input_sha256=hashlib.sha256(log.encode()).hexdigest(), far=far, stdio=stdio, inventory=inventory,
                sources=dict(main=evidence_line(lines, "PE64 BLOCK JIT WORKER THREAD: slot=23 name='MAIN_THREAD"),
                             cadence=evidence_line(lines, "FRAME CADENCE JITTER:"),
                             flush=evidence_line(lines, "PE64 IMPORT TIMING: import=api-ms-win-crt-stdio-l1-1-0.dll!fflush")))
    # Source-only checks have their exact, independently retained logs.
    data["checks"] = {p.name: p.read_text() for p in (folder / "check-pool-debug-final.log", folder / "check-release-identities.log",
                      folder / "check-islands-debug.log", folder / "source-size.log", folder / "guest-context.log", folder / "parser-tests.log")}
    # The verbose compile commands are retained in the raw file; display the
    # compact gate summary instead of megabytes of dependency arguments.
    data["checks"]["check-release-identities.log"] = "\n".join(l for l in data["checks"]["check-release-identities.log"].splitlines() if len(l) < 300)
    final = folder / "final"
    final.mkdir(exist_ok=True)
    (final / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    template = Path(__file__).with_name("runtime_throughput_report.html").read_text()
    (final / "report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("<", "\\u003c")))
    print(json.dumps(dict(far_samples=sum(len(r["samples"]) for r in far), stdio_samples=sum(len(r["samples"]) for r in stdio),
                          far_ratios=[r["ratio"] for r in far], stdio_ratios=[r["ratio"] for r in stdio], report=str(final / "report.html")), indent=2))


if __name__ == "__main__":
    build(Path(sys.argv[1]))
