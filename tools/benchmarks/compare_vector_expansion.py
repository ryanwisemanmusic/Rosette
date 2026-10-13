#!/usr/bin/env python3
"""Compare production ELF executor binaries using an exact pre-edit core snapshot."""
import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import statistics
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--reuse-snapshot", action="store_true", help="Recompile a preserved snapshot after a format-only fixture update")
    args = parser.parse_args()
    folder = args.evidence.resolve()
    verbose = (folder / "production-release.log").read_text()
    command = next(line for line in verbose.splitlines() if "/bin/zig test " in line)
    argv = shlex.split(command)
    # Preserve every production dependency/target/optimization argument. The
    # run-step IPC and unrelated correctness filters do not belong in these
    # standalone fixture binaries.
    clean = []
    index = 0
    while index < len(argv):
        if argv[index] == "--test-filter":
            index += 2
            continue
        if argv[index].startswith("--listen="):
            index += 1
            continue
        clean.append(argv[index])
        index += 1
    clean += ["--test-filter", "vector expansion benchmark", "--test-no-exec"]
    baseline = folder / "before-source"
    if baseline.exists() and not args.reuse_snapshot:
        raise SystemExit("Use a new evidence directory or --reuse-snapshot for the managed snapshot")
    if not baseline.exists():
        shutil.copytree(ROOT / "lib/processor/ELF_processor", baseline)
    else:
        shutil.copy2(ROOT / "lib/processor/ELF_processor/process/tests/vector_expansion.zig", baseline / "process/tests/vector_expansion.zig")
    shutil.copy2(folder / "core-before.zig", baseline / "block_jit/core.zig")
    shutil.copy2(ROOT / "lib/processor/ELF_processor/block_jit/core.zig", folder / "core-after.zig")
    records = {}
    for variant in ("before", "after"):
        binary = folder / ("bench-" + variant)
        compilation = list(clean)
        if variant == "before":
            compilation = ["-Mroot=" + str(baseline / "process.zig") if arg.startswith("-Mroot=") else arg for arg in compilation]
        compilation += ["-femit-bin=" + str(binary)]
        with (folder / ("compile-" + variant + ".log")).open("w") as output:
            subprocess.run(compilation, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)
        records[variant] = {"argv": compilation, "binary_sha256": sha(binary)}
    samples = []
    for pair in range(7):
        for variant in (("before", "after") if pair % 2 == 0 else ("after", "before")):
            env = os.environ.copy()
            env.update(ROSETTE_VECTOR_EXPANSION_BENCH="1", ROSETTE_VECTOR_VARIANT=variant)
            output = subprocess.run([str(folder / ("bench-" + variant))], cwd=ROOT / "build", env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=True).stdout
            (folder / f"pair-{pair}-{variant}.log").write_text(output)
            rows = []
            for line in output.splitlines():
                if not line.startswith("VECTOR_EXPANSION "):
                    continue
                values = dict(re.findall(r"(\w+)=([^ ]+)", line))
                rows.append({"case": values["case"], "pair": pair, "variant": variant, **{key: int(value) for key, value in values.items() if key not in ("case", "variant")}})
            assert len(rows) == 5, (variant, pair)
            assert all(row["native_executions"] > 0 for row in rows)
            samples.extend(rows)
    summaries = {}
    for case in sorted({row["case"] for row in samples}):
        rows = [row for row in samples if row["case"] == case]
        before = statistics.median(row["elapsed_ns"] for row in rows if row["variant"] == "before")
        after = statistics.median(row["elapsed_ns"] for row in rows if row["variant"] == "after")
        summaries[case] = {"before_ns": before, "after_ns": after, "speedup": before / after,
                           "before_code_bytes": rows[0]["code_bytes"],
                           "after_code_bytes": next(row["code_bytes"] for row in rows if row["variant"] == "after")}
        print(case, f"{before/1e6:.3f}→{after/1e6:.3f} ms ({before/after:.2f}×)", flush=True)
    result = {"before_core_sha256": sha(folder / "core-before.zig"), "after_core_sha256": sha(folder / "core-after.zig"), "binaries": records, "samples": samples, "summary": summaries,
              "scope": "CPU-only production executor; block JIT enabled both sides; before uses exact saved core source, all other ELF sources/dependencies identical; not gameplay FPS"}
    (folder / "results.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
