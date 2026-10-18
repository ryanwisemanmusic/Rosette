#!/usr/bin/env python3
"""Record the helper identity produced by ``make shell-update``."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

from build_graph_sources import graph_source


def digest(path: Path) -> str | None:
    if not path.is_file():
        return None
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--census", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verification-mode", choices=("full", "incremental", "relink"), default="full")
    parser.add_argument("--verification-scope", default="all")
    parser.add_argument("--verification-check", action="append", default=[])
    args = parser.parse_args()
    root = args.root.resolve()

    helper = args.helper.resolve()
    installed_env = os.environ.get("ROSETTE_SHELL_HELPER")
    installed = Path(installed_env).expanduser() if installed_env else None
    if installed is None:
        installed_name = shutil.which("rosette-shell")
        installed = Path(installed_name).resolve() if installed_name else None
    if installed is None:
        home = os.environ.get("HOME")
        if home:
            installed = Path(home) / ".rosette" / "bin" / "rosette-shell"

    _, build_registration_files = graph_source(root / "build.zig")
    build_files = [*build_registration_files, root / "build" / "Makefile", args.source.resolve()]
    tree_hash = hashlib.sha256()
    for path in build_files:
        tree_hash.update(str(path.relative_to(root)).encode())
        tree_hash.update(b"\0")
        if path.is_file():
            tree_hash.update(path.read_bytes())
        tree_hash.update(b"\0")

    # Keep this digest identical to build_identity_manifest.tree_identity's
    # Rosette source-tree digest. Incremental verification is only admissible
    # for the exact source snapshot that was checked and installed.
    sys.path.insert(0, str(root / "tools"))
    from build_identity_manifest import hash_tree

    source_hash, _, source_missing = hash_tree(
        [root / name for name in ("ISA", "lib", "src", "pkg", "include")],
        "rosette-source",
    )
    output = args.output if args.output.is_absolute() else root / args.output
    census = args.census if args.census.is_absolute() else root / args.census
    output.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "schema_version": 2,
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "profile": os.environ.get("ROSETTE_EXECUTION_PROFILE", "authentic"),
        "manifest_hash": os.environ.get("ROSETTE_MANIFEST_HASH"),
        "source": str(args.source.resolve()),
        "source_sha256": digest(args.source.resolve()),
        "built_helper": str(helper),
        "built_helper_sha256": digest(helper),
        "installed_helper": str(installed) if installed else None,
        "installed_helper_sha256": digest(installed) if installed else None,
        "installed_matches_built": bool(installed and digest(installed) == digest(helper)),
        "test_census": str(census.resolve()),
        "test_census_sha256": digest(census.resolve()),
        "build_inputs_sha256": tree_hash.hexdigest(),
        "verification": {
            "mode": args.verification_mode,
            "scope": args.verification_scope,
            "source_tree_sha256": source_hash,
            "source_tree_complete": not source_missing,
            "checks": [
                {"name": item.rsplit("=", 1)[0], "exit_code": int(item.rsplit("=", 1)[1])}
                for item in args.verification_check
            ],
        },
    }
    output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "shell-update-record: installed={} matches={} output={}".format(
            record["installed_helper"], record["installed_matches_built"], output
        )
    )
    return 0 if record["installed_matches_built"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
