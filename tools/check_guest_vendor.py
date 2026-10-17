#!/usr/bin/env python3
"""Verify Rosette's commit-pinned Xenia third-party source snapshot.

This is a source-integrity audit only. It never builds or launches Xenia and
does not require the upstream checkout unless ``--xenia-root`` is supplied.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "pkg/vendor"
LOCK = VENDOR / "canary.lock.json"


def hash_tree(root: Path) -> tuple[str, int]:
    files = [p for p in root.rglob("*") if p.is_file() or p.is_symlink()]
    digest = hashlib.sha256()
    for path in sorted(files, key=lambda p: p.relative_to(root).as_posix()):
        digest.update(path.relative_to(root).as_posix().encode() + b"\0")
        if path.is_symlink():
            digest.update(b"L\0" + os.readlink(path).encode())
        else:
            digest.update(b"F\0")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
    return digest.hexdigest(), len(files)


def run_git(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args], check=False, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def is_safe_vendor_path(value: str) -> bool:
    path = Path(value)
    return bool(value) and not path.is_absolute() and all(part not in {"", ".", ".."} for part in path.parts)


def upstream_dependencies(root: Path, commit: str) -> dict[str, tuple[str, str]]:
    output = subprocess.run(
        ["git", "-C", str(root), "ls-tree", "-z", f"{commit}:third_party"],
        check=True, stdout=subprocess.PIPE,
    ).stdout
    found: dict[str, tuple[str, str]] = {}
    for raw in output.split(b"\0"):
        if not raw:
            continue
        metadata, name = raw.split(b"\t", 1)
        mode, _kind, object_id = metadata.decode("ascii").split()
        if mode in {"040000", "160000"}:
            found[name.decode("utf-8", "surrogateescape")] = (mode, object_id)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xenia-root", type=Path, help="optional upstream checkout for lock comparison")
    args = parser.parse_args()
    lock: dict[str, Any] = json.loads(LOCK.read_text(encoding="utf-8"))
    deps = lock.get("dependencies", [])
    errors: list[str] = []
    if lock.get("schema_version") != 1:
        errors.append("unsupported lock schema")
    if lock.get("dependency_count") != len(deps):
        errors.append("dependency_count does not match the lock entries")
    if len({item.get("id") for item in deps}) != len(deps):
        errors.append("dependency ids are not unique")

    source_root_value = lock.get("source_root", "")
    source_root = VENDOR / source_root_value
    if not is_safe_vendor_path(source_root_value) or not source_root.is_dir():
        errors.append(f"invalid or missing source root: {source_root_value!r}")
    license_value = lock.get("repository", {}).get("license_file", "")
    license_path = VENDOR / license_value
    if not is_safe_vendor_path(license_value) or not license_path.is_file():
        errors.append(f"Xenia repository license is absent or unsafe: {license_value!r}")
    if (VENDOR / "sources" / "xenia-canary").exists():
        errors.append("repository-specific wrapper remains under pkg/vendor/sources")
    seen: set[str] = set()
    review_count = 0
    for item in deps:
        source_dir = VENDOR / item.get("source_dir", "")
        try:
            relative = source_dir.relative_to(ROOT).as_posix()
        except ValueError:
            relative = ""
        if not relative or relative in seen or ".." in Path(relative).parts:
            errors.append(f"unsafe or duplicate source path: {item.get('source_dir')!r}")
            continue
        seen.add(relative)
        if not source_dir.is_dir():
            errors.append(f"missing source directory: {item.get('source_dir')}")
            continue
        if any(".git" in path.relative_to(source_dir).parts for path in source_dir.rglob(".git")):
            errors.append(f"Git administrative data was copied into {item['source_dir']}")
        actual_hash, actual_count = hash_tree(source_dir)
        if actual_hash != item.get("source_tree_sha256"):
            errors.append(f"content hash mismatch: {item.get('name')}")
        if actual_count != item.get("file_count"):
            errors.append(f"file count mismatch: {item.get('name')}")
        if not item.get("license_files"):
            review_count += 1
            if item.get("license_status") != "review-required-no-license-file":
                errors.append(f"missing license must be marked for review: {item.get('name')}")
        for nested in item.get("nested_gitlinks", []):
            nested_path = source_dir / nested["path"]
            if not nested_path.exists():
                errors.append(f"missing nested submodule: {item.get('name')}/{nested['path']}")

    if args.xenia_root:
        xenia_root = args.xenia_root.expanduser().resolve()
        recorded_commit = lock.get("repository", {}).get("commit")
        actual_commit = run_git(xenia_root, "rev-parse", "HEAD")
        if actual_commit != recorded_commit:
            errors.append(f"Xenia HEAD mismatch: lock={recorded_commit}, checkout={actual_commit}")
        actual = upstream_dependencies(xenia_root, actual_commit)
        expected: dict[str, tuple[str, str]] = {}
        for item in deps:
            mode = "160000" if item.get("commit_kind") == "submodule-gitlink" else "040000"
            expected[item["name"]] = (mode, item["commit"])
        if actual != expected:
            errors.append("Xenia third_party directory/gitlink inventory differs from the lock")

    print(f"Xenia vendored source: {len(deps)} dependency trees, {review_count} license-file reviews")
    print(f"Pinned Xenia commit: {lock.get('repository', {}).get('commit', '<missing>')}")
    print(f"Package source root: {lock.get('source_root')}")
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    print("xenia-vendor-source-audit: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"xenia-vendor-source-audit: {error}", file=sys.stderr)
        raise SystemExit(1)
