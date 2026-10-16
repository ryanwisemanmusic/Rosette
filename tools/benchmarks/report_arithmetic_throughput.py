#!/usr/bin/env python3
"""Reproduce source-bound arithmetic/memory comparisons and timing inventory."""
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
        match = re.search(r"\b(arithmetic profile=|natural offset=)", line)
        if not match:
            continue
        values = {k: (v == "true" if v in ("true", "false") else int(v))
                  for k, v in re.findall(r"(\w+)=(\S+)", line[match.start():])}
        rows.append(dict(kind="arithmetic" if match[1].startswith("arithmetic") else "natural", **values))
    cases = [("arithmetic", p, False) for p in range(4)] + [
        ("natural", offset, store) for offset in (1, 2, 4, 8) for store in (False, True)]
    groups = []
    for kind, value, store in cases:
        selected = [r for r in rows if r["kind"] == kind and
                    (r.get("profile") == value if kind == "arithmetic" else
                     r.get("offset") == value and r.get("store") == store)]
        assert len(selected) == 14, (kind, value, store, len(selected))
        pairs = []
        for pair in range(7):
            a, b = [next(r for r in selected if r["pair"] == pair and r["enabled"] == flag)
                    for flag in (False, True)]
            expected = 100000 * (1 if kind == "arithmetic" and value == 3 else
                                 64 if kind == "arithmetic" else 32)
            assert a["operations"] == b["operations"] == 100000
            assert a["retired"] == b["retired"] == expected
            assert a["cpu_ns"] > 0 and b["cpu_ns"] > 0
            pairs.append(dict(pair=pair, before_ns=a["cpu_ns"], after_ns=b["cpu_ns"],
                              before_code=a["code_bytes"], after_code=b["code_bytes"],
                              operations=a["operations"], retired=expected))
        before = statistics.median(r["before_ns"] for r in pairs) / 1e6
        after = statistics.median(r["after_ns"] for r in pairs) / 1e6
        if kind == "arithmetic":
            names = ["Arithmetic · observer boundaries", "Arithmetic · fused 64-bit readers",
                     "Arithmetic · fused 32-bit readers", "Arithmetic · one-instruction block"]
            detail = ["100K entries × 32 arithmetic writers / 32 interpreter observer NOPs; same 6.4M retired.",
                      "100K entries × 32 writers/readers; most flags become dead. Same 6.4M retired; negative control.",
                      "100K entries × 32 writers/readers at 32 bits; same 6.4M retired; negative control.",
                      "100K complete native block entries, including full exit flag publication. Same 100K retired."][value]
            name = names[value]
        else:
            name = f"Scalar {'store' if store else 'load'} · offset {value}"
            detail = ("100K entries × 32 eight-byte accesses = 3.2M retired; complete native TLB/ordered access path. " +
                      ("Naturally aligned control." if value == 8 else "Odd-address byte control." if value == 1 else
                       "Four halfword lanes." if value == 2 else "Two word lanes."))
        groups.append(dict(kind=kind, variant=value, profile="observer" if kind == "arithmetic" and value == 0 else "native",
                           name=name, detail=detail, before_ms=before, after_ms=after,
                           ratio=before / after, samples=pairs))
    assert len(rows) == 168
    return groups


def generate(folder):
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    groups = comparisons((folder / "bench-final.log").read_text())
    lines = (folder / "input.log").read_text().splitlines()
    inventory = parse(lines, ticks_per_ms=1000)
    evidence = []
    for key in ("PRESENT CEILING:", "FRAME HOST COST: present_intervals=", "GRAPHICS PACING:",
                "xenia_gpu_render_settings =", "xenia_config_preflight =", "Vulkan host time by entry point:"):
        found = [dict(line=i, raw=l) for i, l in enumerate(lines, 1) if key in l]
        evidence.extend(found[-12:] if "entry point" in key else found[-2:])
    data = dict(groups=groups, inventory=inventory, evidence=evidence, gates=manifest["gates"],
                run=re.search(r"run_id\s*=\s*(\S+)", "\n".join(lines[:10]))[1],
                build=re.search(r"build_identity_sha256\s*=\s*(\S+)", "\n".join(lines[:10]))[1],
                wsi=[float(m[1]) for l in lines if (m := re.search(r"presented_fps=([\d.]+)", l))])
    (folder / "bench-results.json").write_text(json.dumps(groups, indent=2))
    (folder / "timing-inventory.json").write_text(json.dumps(inventory, indent=2))
    template = Path(__file__).with_name("arithmetic_throughput_report.html").read_text()
    (folder / "final" / "report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/")))
    print(json.dumps(dict(profiles=len(groups), samples=168, maxima=len(inventory["maxima"]),
                          results=[{k: g[k] for k in ("name", "before_ms", "after_ms", "ratio")} for g in groups]), indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
