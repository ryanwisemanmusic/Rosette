#!/usr/bin/env python3
"""Reproduce CPU-only native chain/scalar path comparisons and both log inventories."""
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys
from timing_inventory import parse

ROOT = Path(__file__).resolve().parents[2]
CHAIN_NAMES = ["Eight-register chains", "Context load / modify / store", "Single-register chains",
               "Sixteen-register pressure", "Changing register usage", "High-register chains",
               "Interpreter observer chains", "Mixed image / generated-code chains", "One-block exit control", "Combined chain + scalar path"]
SCALAR_NAMES = ["Cached shifts · 64-bit", "Cached rotations · 32-bit", "NOT / NEG · nine-register pressure",
                "Observed flag outputs · control", "16-bit merge · control", "Short scalar block"]

def comparisons(text, kinds=("chains", "scalar")):
    rows = []
    for line in text.splitlines():
        match = re.search(r"\b(chains|scalar) profile=", line)
        if not match or match[1] not in kinds:
            continue
        fields = {k: (v == "true" if v in ("true", "false") else int(v))
                  for k, v in re.findall(r"(\w+)=(\S+)", line[match.end() - len("profile="):])}
        rows.append(dict(kind=match[1], **fields))
    groups = []
    for kind in kinds:
        for profile, name in enumerate((CHAIN_NAMES if kinds != ("chains",) else CHAIN_NAMES[:9]) if kind == "chains" else SCALAR_NAMES):
            selected = [r for r in rows if r["kind"] == kind and r["profile"] == profile]
            assert len(selected) == 14, (kind, profile, len(selected))
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
            detail = ("Four native blocks, 4,096-instruction budget per entry." if kind == "chains" and profile != 8 else
                      "One whole block, ordinary budget exit; no native hop." if kind == "chains" else
                      "64 scalar operations plus a flag writer per complete entry." if profile not in (3, 5) else
                      "64 writers, each with an interpreter observer, plus final flag writer." if profile == 3 else
                      "One scalar operation and a flag writer per complete entry.")
            groups.append(dict(kind=kind, variant=profile, profile="native", name=name, detail=detail,
                               before_ms=before, after_ms=after, ratio=before/after, samples=pairs))
    assert len(rows) == (9 if kinds == ("chains",) else len(CHAIN_NAMES) + 6)*14
    return groups

def generate(folder):
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    manifest = json.loads((folder / "manifest.json").read_text())
    for name, digest in manifest["source_sha256"].items():
        assert sha(ROOT / name) == digest, name
    for name, digest in manifest["evidence_sha256"].items():
        assert sha(folder / name) == digest, name
    groups = comparisons((folder / "bench-final.log").read_text())
    runs = []
    for file, name in (("custom.log", "Custom Games"), ("campaign.log", "Campaign")):
        lines = (folder / file).read_text().splitlines()
        inventory = parse(lines, ticks_per_ms=1000)
        evidence = []
        for key in ("PRESENT CEILING:", "FRAME HOST COST: present_intervals=", "FRAME CADENCE JITTER:",
                    "xenia_gpu_render_settings =", "xenia_config_preflight =", "Vulkan host time by entry point:",
                    "PE64 BLOCK JIT WORKER THREAD:", "PE64 NATIVE PATH TEMPLATES:"):
            found = [dict(line=i, raw=l) for i, l in enumerate(lines, 1) if key in l]
            evidence.extend(found[-12:] if "entry point" in key or "WORKER THREAD" in key else found[-2:])
        run = dict(name=name, inventory=inventory, evidence=evidence,
                   run=re.search(r"run_id\s*=\s*(\S+)", "\n".join(lines[:10]))[1],
                   build=re.search(r"build_identity_sha256\s*=\s*(\S+)", "\n".join(lines[:10]))[1],
                   wsi=[float(m[1]) for l in lines if (m:=re.search(r"presented_fps=([\d.]+)",l))])
        runs.append(run)
        (folder / (file.removesuffix(".log")+"-inventory.json")).write_text(json.dumps(inventory,indent=2))
    rejected = []
    for name in ("bench-candidate.log", "bench-cold-handoff.log"):
        rejected.append(dict(name=name, groups=comparisons((folder/name).read_text(), ("chains",))))
    data = dict(groups=groups, runs=runs, gates=manifest["gates"], rejected=rejected,
                qualification=manifest["qualification"])
    (folder / "bench-results.json").write_text(json.dumps(groups,indent=2))
    (folder / "rejected-results.json").write_text(json.dumps(rejected,indent=2))
    template = Path(__file__).with_name("register_chain_report.html").read_text()
    (folder / "final" / "report.html").write_text(template.replace("__REPORT_DATA__",json.dumps(data).replace("</","<\\/")))
    print(json.dumps(dict(profiles=len(groups), samples=sum(len(g["samples"])*2 for g in groups),
                          inventories=[dict(name=r["name"],maxima=len(r["inventory"]["maxima"])) for r in runs],
                          results=[{k:g[k] for k in ("name","before_ms","after_ms","ratio")} for g in groups]),indent=2))

if __name__ == "__main__":
    generate(Path(sys.argv[1]))
