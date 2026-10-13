#!/usr/bin/env python3
"""Seven alternating CPU-only production comparisons for recording and fences."""
import argparse
import hashlib
import json
import os
import statistics
import subprocess
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    folder = args.evidence.resolve()
    samples = []
    identities = {}
    for kind in ("bench", "flow"):
        for variant in ("before", "after"):
            binary = folder / f"{kind}-{variant}"
            identities[binary.name] = sha(binary)
    for pair in range(7):
        for variant in (("before", "after") if pair % 2 == 0 else ("after", "before")):
            for kind in ("bench", "flow"):
                binary = folder / f"{kind}-{variant}"
                raw = b""
                for case in (("mixed", "scalar") if kind == "flow" else ("all",)):
                    env = dict(os.environ, ROSETTE_BARRIER_BENCH_CASE=case)
                    result = subprocess.run([str(binary)], capture_output=True, timeout=60, env=env)
                    raw += result.stdout + result.stderr
                    if result.returncode:
                        raise RuntimeError(f"{binary.name}: exit {result.returncode}, {raw.decode()}")
                (folder / f"{kind}-pair-{pair}-{variant}.log").write_bytes(raw)
                for line in raw.decode().splitlines():
                    if not line.startswith(("room_observer ", "barrier_flow ")):
                        continue
                    fields = dict(value.split("=", 1) for value in line.split()[1:])
                    record = {key: (value if key == "case" else int(value)) for key, value in fields.items()}
                    record.update(pair=pair, variant=variant, kind=kind)
                    samples.append(record)
        print(f"Pair {pair + 1}/7: every retirement/callback checked", flush=True)
    summary = {}
    for case in sorted({s["case"] for s in samples}):
        by_variant = {v: [s for s in samples if s["case"] == case and s["variant"] == v] for v in ("before", "after")}
        assert all(len(records) == 7 for records in by_variant.values())
        entry = {v: {k: statistics.median(s[k] for s in records) for k in records[0] if k not in ("case", "pair", "variant", "kind")} for v, records in by_variant.items()}
        entry["speedup"] = entry["before"]["elapsed_ns"] / entry["after"]["elapsed_ns"]
        summary[case] = entry
    output = {"basis": "CPU-only production FIFO and fence monitor; timed stub fences, no GPU or Xenia, not FPS forecasts", "pairs": 7, "binary_sha256": identities, "summary": summary, "samples": samples}
    (folder / "results.json").write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({case: round(record["speedup"], 3) for case, record in summary.items()}))


if __name__ == "__main__":
    main()
