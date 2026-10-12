#!/usr/bin/env python3
"""Enforce owned Zig file budgets, including comments and session notes."""
import argparse
import json
from pathlib import Path
import subprocess

ROOTS = {"ISA", "lib", "src", "app", "build", "pkg", "include"}
VENDOR = ("pkg/vendor/", "lib/Assemblers/nasm/", "lib/Assemblers/yasm/", "lib/Assemblers/JWasm/")


def owned_paths(root: Path) -> list[str]:
    result = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "*.zig"], cwd=root, check=True, stdout=subprocess.PIPE)
    return sorted({p for p in result.stdout.decode().split("\0") if p.endswith(".zig") and p.split("/", 1)[0] in ROOTS and not p.startswith(VENDOR) and (root / p).is_file()})


def violations(root: Path, paths: list[str], policy: dict) -> list[str]:
    failures = []
    for relative in paths:
        count = len((root / relative).read_text(encoding="utf-8").splitlines())
        limit = policy["limits"].get(relative, policy["default_max_lines"])
        if count > limit:
            failures.append(f"{relative}: {count} lines exceeds {limit}; extract a module or move notes to docs")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    policy = json.loads((args.root / "build/source-size-policy.json").read_text())
    paths = owned_paths(args.root)
    errors = violations(args.root, paths, policy)
    for error in errors:
        print("source size: FAIL " + error)
    print(f"source size: {'FAIL' if errors else 'PASS'} ({len(paths)} owned Zig files; new files <= {policy['default_max_lines']} lines; existing large files have fixed ceilings)")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
