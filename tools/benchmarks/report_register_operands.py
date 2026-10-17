#!/usr/bin/env python3
"""Reproduce cached operand CPU results and the supplied runtime timing inventory."""
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys
from timing_inventory import parse

ROOT = Path(__file__).resolve().parents[2]
NAMES = ["Variable shift · 64-bit", "Variable rotation · 32-bit", "High-byte sign extension · 64-bit",
         "32 → 64-bit sign extension", "Signed product · 64-bit", "Endian load · unchanged admitted control",
         "Combined · mixed registers and memory", "Observed flags · unchanged control",
         "16-bit shift · unchanged control", "One-operation block", "Endian load · unchanged helper control"]

def comparisons(text):
    rows = []
    for line in text.splitlines():
        if "operands profile=" not in line:
            continue
        fields = {k: (v == "true" if v in ("true", "false") else int(v))
                  for k, v in re.findall(r"(\w+)=(\S+)", line.split("operands ", 1)[1])}
        rows.append(fields)
    assert len(rows) == len(NAMES) * 14, len(rows)
    groups = []
    for profile, name in enumerate(NAMES):
        selected = [r for r in rows if r["profile"] == profile]
        pairs = []
        for pair in range(7):
            a, b = [next(r for r in selected if r["pair"] == pair and r["enabled"] == flag)
                    for flag in (False, True)]
            assert a["entries"] == b["entries"] and a["retired"] == b["retired"] > 0
            assert a["cpu_ns"] > 0 and b["cpu_ns"] > 0
            pairs.append(dict(pair=pair, before_ns=a["cpu_ns"], after_ns=b["cpu_ns"],
                              before_code=a["code_bytes"], after_code=b["code_bytes"],
                              entries=a["entries"], retired=a["retired"]))
        before = statistics.median(p["before_ns"] for p in pairs) / 1e6
        after = statistics.median(p["after_ns"] for p in pairs) / 1e6
        detail = ("One operation plus final flag writer." if profile == 9 else
                  "64 operations, each followed by an interpreter observer, plus final flag writer." if profile == 7 else
                  "64 operations plus final flag writer; complete block entry, exit and state publication.")
        groups.append(dict(variant=profile, name=name, detail=detail, before_ms=before,
                           after_ms=after, ratio=before/after, samples=pairs))
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
    keys = ("PRESENT CEILING:", "FRAME HOST COST:", "FRAME CADENCE JITTER:", "xenia_gpu_render_settings =",
            "xenia_config_preflight =", "Vulkan host time by entry point:", "Vulkan host time:",
            "PE64 BLOCK JIT WORKER THREAD:", "PE64 NATIVE PATH TEMPLATES:", "PE64 DIRECT REGISTER OPERANDS:", "VULKAN FSI EVIDENCE IO:")
    evidence = []
    for key in keys:
        found = [dict(line=i, raw=l) for i, l in enumerate(lines, 1) if key in l]
        evidence.extend(found[-39:] if key in ("PE64 NATIVE PATH TEMPLATES:", "PE64 DIRECT REGISTER OPERANDS:") else found[-12:] if key in ("Vulkan host time by entry point:", "FRAME HOST COST:", "PE64 BLOCK JIT WORKER THREAD:") else found[-3:])
    run = dict(name="Supplied run · scene unspecified", inventory=inventory, evidence=evidence,
               run=re.search(r"run_id\s*=\s*(\S+)", "\n".join(lines[:10]))[1],
               build=re.search(r"build_identity_sha256\s*=\s*(\S+)", "\n".join(lines[:10]))[1],
               wsi=[float(m[1]) for l in lines if (m:=re.search(r"presented_fps=([\d.]+)",l))])
    data = dict(groups=groups, runs=[run], gates=manifest["gates"], qualification=manifest["qualification"])
    (folder / "bench-results.json").write_text(json.dumps(groups, indent=2))
    (folder / "timing-inventory.json").write_text(json.dumps(inventory, indent=2))
    template = Path(__file__).with_name("register_operand_report.html").read_text()
    (folder / "final" / "report.html").write_text(template.replace("__REPORT_DATA__", json.dumps(data).replace("</", "<\\/")))
    print(json.dumps(dict(profiles=len(groups), samples=len(groups)*14, maxima=len(inventory["maxima"]),
                          results=[{k:g[k] for k in ("name", "before_ms", "after_ms", "ratio")} for g in groups]), indent=2))

if __name__ == "__main__":
    generate(Path(sys.argv[1]))
