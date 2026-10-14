#!/usr/bin/env python3
"""Create a reviewable, content-addressed manifest of the Xenia fork.

The manifest is deliberately source-only.  It records the pinned base, the
current head, worktree status, and one classification for every path visible
to Git.  It does not build or launch Xenia.  Files that cannot be read are
retained as explicit unavailable entries and make the content identity
incomplete rather than silently hashing a path name.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import subprocess
from collections import Counter
from pathlib import Path


SCHEMA_VERSION = 2
ZERO_HASH = "0" * 64
# Xenia's adjacent `.rosette` tree is runtime output owned by Rosette. It can
# contain captures and per-run diagnostics, so neither Git-mode deltas nor an
# extracted filesystem tree may treat it as emulator source.
GENERATED_ROOTS = {".rosette"}
SKIP_DIRS = {".git", ".zig-cache", "zig-cache", "build", "out", "obj", *GENERATED_ROOTS}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def command_text(command: list[str]) -> tuple[str | None, str | None]:
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    except OSError as error:
        return None, str(error)
    # Preserve Git's two-column status prefix; stripping leading whitespace
    # would corrupt the first path in the manifest.
    output = result.stdout.rstrip()
    if result.returncode:
        return None, output or f"exit {result.returncode}"
    return output, None


def decode_git_path(value: str) -> str:
    """Decode Git's C-quoted porcelain path representation."""
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        try:
            decoded = ast.literal_eval(value)
            if isinstance(decoded, str):
                return decoded
        except (SyntaxError, ValueError):
            pass
    return value


def is_generated_runtime_path(value: str) -> bool:
    normalized = value.replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    normalized = normalized.rstrip("/")
    return any(
        normalized == generated or normalized.startswith(generated + "/")
        for generated in GENERATED_ROOTS
    )


def classify(path: str, content: bytes | None) -> tuple[str, str]:
    lower = path.lower()
    if (
        lower.startswith("third_party/")
        or "/third_party/" in lower
        or lower.startswith("vendor/")
        or "/generated/" in lower
        or lower.endswith(".spv")
        or "/shaders/bytecode/" in lower
    ):
        return "generated-or-vendor-content", "dependency or generated shader path"
    if (
        "test" in lower
        or lower.startswith("test/")
        or "/testing/" in lower
        or lower.endswith("_test.cc")
    ):
        return "test-only-change", "test or testing path"
    if (
        "cmake" in lower
        or lower.endswith(".cmake")
        or lower.endswith(".cmakelists")
        or lower.startswith("scripts/")
        or "/scripts/" in lower
        or lower.endswith(".sh")
    ):
        return "platform-build-work", "build or platform script"
    if (
        "rosette" in lower
        or "bridge" in lower
        or "mac" in lower
        or lower.startswith("src/xenia/gpu/")
        or lower.startswith("src/xenia/kernel/")
        or lower.startswith("src/xenia/cpu/")
    ):
        # A known stub is only assigned when the current file itself contains
        # an explicit stub marker.  This prevents a broad GPU/kernel path
        # heuristic from laundering an unreviewed fallback into support.
        if content is not None:
            text = content.decode("utf-8", errors="ignore").lower()
            if any(
                marker in text
                for marker in (
                    "todo(stub",
                    "not implemented",
                    "known stub",
                    "stub implementation",
                    "return false;  // stub",
                )
            ):
                return "known-stub", "explicit stub marker in file"
        return "required-rosette-integration", "load-bearing Xenia integration path"
    return "unreviewed-divergence", "outside the declared integration roots"


def parse_status(text: str) -> list[tuple[str, str]]:
    paths: list[tuple[str, str]] = []
    for line in text.splitlines():
        if not line:
            continue
        status = line[:2].strip() or "??"
        path_text = line[3:] if len(line) > 3 else ""
        if " -> " in path_text:
            path_text = path_text.split(" -> ", 1)[1]
        paths.append((decode_git_path(path_text), status))
    return sorted(paths, key=lambda item: item[0])


def parent_gitlink_status(root: Path) -> tuple[str | None, str | None]:
    """Return Gitlink records without opening nested submodule packfiles."""
    listing, error = command_text(["git", "-C", str(root), "ls-files", "--stage"])
    if listing is None:
        return None, error or "parent Gitlink index query failed"
    records: list[str] = []
    for line in listing.splitlines():
        fields = line.split(None, 3)
        if len(fields) != 4 or fields[0] != "160000":
            continue
        records.append(f"{fields[0]} {fields[1]}\t{fields[3]}")
    return "\n".join(records), None


def hash_directory(path: Path) -> tuple[str, int | None]:
    """Hash a non-repository directory while skipping generated build data."""
    digest = hashlib.sha256()
    count = 0
    try:
        for directory, dirnames, filenames in os.walk(path):
            dirnames[:] = sorted(
                name
                for name in dirnames
                if name not in SKIP_DIRS
                and not (Path(directory) / name).is_symlink()
            )
            for name in sorted(filenames):
                child = Path(directory) / name
                relative = child.relative_to(path).as_posix()
                if child.is_symlink():
                    digest.update(
                        f"symlink/{relative}".encode()
                        + b"\0"
                        + os.readlink(child).encode("utf-8", errors="surrogateescape")
                        + b"\0"
                    )
                else:
                    digest.update(relative.encode())
                    digest.update(b"\0")
                    digest.update(child.read_bytes())
                    digest.update(b"\0")
                count += 1
    except OSError:
        return ZERO_HASH, None
    return (digest.hexdigest(), count) if count else (ZERO_HASH, None)


def hash_nested_repository(path: Path) -> tuple[str, int | None]:
    """Hash a nested checkout by commit plus its dirty/untracked delta."""
    head, _ = command_text(["git", "-C", str(path), "rev-parse", "HEAD"])
    if head is None:
        return ZERO_HASH, None
    changed, _ = command_text(["git", "-C", str(path), "diff", "--name-only", "HEAD"])
    untracked, _ = command_text(
        ["git", "-C", str(path), "ls-files", "--others", "--exclude-standard"]
    )
    status, _ = command_text(
        ["git", "-C", str(path), "status", "--porcelain=v1", "--untracked-files=all"]
    )
    submodules, _ = command_text(
        ["git", "-C", str(path), "submodule", "status", "--recursive"]
    )
    deleted, _ = command_text(["git", "-C", str(path), "ls-files", "--deleted"])
    if None in (changed, untracked, status, submodules, deleted):
        return ZERO_HASH, None

    digest = hashlib.sha256()
    for name, value in (
        ("head", head),
        ("changed", changed),
        ("untracked", untracked),
        ("status", status),
        ("submodules", submodules),
        ("deleted", deleted),
    ):
        digest.update(name.encode() + b"\0" + value.encode() + b"\0")
    deleted_paths = {
        Path(item.strip()).as_posix()
        for item in deleted.splitlines()
        if item.strip()
    }
    changed_paths = {
        Path(item.strip())
        for item in (changed + "\n" + untracked).splitlines()
        if item.strip()
    }
    count = 1  # The nested repository HEAD is an identity-bearing entry.
    for relative in sorted(changed_paths, key=lambda item: item.as_posix()):
        relative_text = relative.as_posix().rstrip("/")
        if not relative_text:
            continue
        child = path / relative
        if not child.exists() and relative_text in deleted_paths:
            continue
        if child.is_symlink():
            try:
                content_hash = sha256_bytes(
                    b"symlink\0" + os.readlink(child).encode("utf-8", errors="surrogateescape")
                )
            except OSError:
                return ZERO_HASH, None
            child_count = 1
        elif child.is_file():
            content_hash, size = file_hash(child)
            if content_hash == ZERO_HASH or size is None:
                return ZERO_HASH, None
            child_count = 1
        elif child.is_dir() and (child / ".git").exists():
            content_hash, nested_count = hash_nested_repository(child)
            if content_hash == ZERO_HASH or nested_count is None:
                return ZERO_HASH, None
            child_count = nested_count
        else:
            return ZERO_HASH, None
        digest.update(relative_text.encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(content_hash))
        digest.update(b"\0")
        count += child_count
    return digest.hexdigest(), count


def file_hash(path: Path) -> tuple[str, int | None]:
    try:
        if path.is_symlink():
            return (
                sha256_bytes(
                    b"symlink\0" + os.readlink(path).encode("utf-8", errors="surrogateescape")
                ),
                len(os.readlink(path)),
            )
        if path.is_dir():
            if (path / ".git").exists():
                return hash_nested_repository(path)
            return hash_directory(path)
        if not path.is_file():
            return ZERO_HASH, None
        digest = hashlib.sha256()
        size = 0
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
                size += len(chunk)
        return digest.hexdigest(), size
    except OSError:
        return ZERO_HASH, None


def read_content(path: Path) -> bytes | None:
    try:
        if not path.is_file() or path.is_symlink():
            return None
        return path.read_bytes()
    except OSError:
        return None


def choose_base(root: Path, requested: str | None) -> tuple[str, str]:
    if requested:
        resolved, error = command_text(["git", "-C", str(root), "rev-parse", requested])
        return (resolved or "", requested if resolved else error or "requested base unavailable")
    for candidate in ("origin/master", "origin/main", "upstream/master", "upstream/main"):
        base, _ = command_text(["git", "-C", str(root), "merge-base", "HEAD", candidate])
        if base:
            return base, candidate
    parent, _ = command_text(["git", "-C", str(root), "rev-parse", "HEAD^"])
    return parent or "", "parent" if parent else "unavailable"


def unavailable_report(root: Path, error: str) -> dict:
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "unavailable",
        "root_present": root.exists(),
        "root": str(root),
        "error": error,
        "identity_hash": ZERO_HASH,
        "admission": {"complete": False, "source_only": True},
        "entries": [],
        "declared_checks": [],
    }


def build_filesystem_manifest(root: Path) -> dict:
    """Describe an extracted Xenia source tree that has no Git metadata.

    A downloaded source archive is still a valid, reviewable input.  Do not
    let Git walk upward into an unrelated parent repository: the complete
    visible source tree is the identity in this mode, with generated/cache
    directories excluded by ``hash_directory``.
    """
    content_hash, file_count = hash_directory(root)
    if content_hash == ZERO_HASH or file_count is None:
        return unavailable_report(root, "Xenia source tree is empty or unreadable")
    identity_hash = sha256_bytes(
        b"xenia-filesystem\0"
        + content_hash.encode()
        + b"\0"
        + str(file_count).encode()
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "available",
        "repository_kind": "filesystem-tree",
        "root_present": True,
        "root": str(root),
        "identity_hash": identity_hash,
        "branch": "",
        "head": "",
        "base": "",
        "base_source": "filesystem-tree",
        "status_hash": sha256_bytes(b"filesystem-tree"),
        "diff_name_status_hash": sha256_bytes(b"filesystem-tree"),
        "status_path_count": file_count,
        "classification_counts": {"source-tree": file_count},
        "missing": [],
        "submodules": "",
        "entries": [],
        "source_tree": {"hash": content_hash, "file_count": file_count},
        "declared_checks": [
            {
                "name": "xenia-cmake-health",
                "kind": "compile-only",
                "command": "cmake --build build --config Debug --target xenia_canary -- -j2",
                "executed_by": "caller",
            },
            {
                "name": "xenia-authentic-run",
                "kind": "behavior",
                "command": "launch xenia with the sealed Rosetta manifest",
                "executed_by": "future-authentic-run",
                "required_for_admission": True,
            },
        ],
        "admission": {
            "complete": True,
            "source_only": True,
            "path_strings_are_metadata_only": True,
            "requires_behavior_validation": True,
            "content_scope": "filesystem-tree",
        },
    }


def build_manifest(root: Path, requested_base: str | None) -> dict:
    if not root.exists():
        return unavailable_report(root, "Xenia root does not exist")
    # An extracted source archive has no local .git metadata.  Require the
    # marker to live at this exact root before invoking Git; otherwise
    # `git -C` is allowed to discover an unrelated parent checkout.
    if not (root / ".git").exists():
        return build_filesystem_manifest(root)
    top, top_error = command_text(["git", "-C", str(root), "rev-parse", "--show-toplevel"])
    head, head_error = command_text(["git", "-C", str(root), "rev-parse", "HEAD"])
    if not top or not head:
        return unavailable_report(root, top_error or head_error or "not a git checkout")
    branch, _ = command_text(["git", "-C", str(root), "branch", "--show-current"])
    base, base_source = choose_base(root, requested_base)
    status_text, status_error = command_text(
        [
            "git",
            "-C",
            str(root),
            "status",
            "--porcelain=v1",
            "--untracked-files=normal",
            "--ignore-submodules=all",
            "--",
            ".",
            ":(exclude).rosette",
        ]
    )
    if status_text is None:
        return unavailable_report(root, status_error or "git status failed")

    parsed_status = parse_status(status_text)
    excluded_generated_roots = sorted(
        generated for generated in GENERATED_ROOTS if (root / generated).exists()
    )
    # Hash only source-bearing worktree entries. Runtime logs/captures can
    # change during a run and must not invalidate the source manifest.
    source_status = "\n".join(
        line
        for line in status_text.splitlines()
        if not is_generated_runtime_path(parse_status(line)[0][0])
    )

    entries: list[dict] = []
    missing: list[str] = []
    for path_text, status in parsed_status:
        if is_generated_runtime_path(path_text):
            continue
        relative = Path(path_text).as_posix()
        path = root / relative
        content = read_content(path)
        content_hash, size = file_hash(path)
        # A deleted tracked path is an intentional part of the fork diff, not
        # an unavailable input. Keep its zero content hash visible while
        # allowing the manifest to distinguish deletion from unreadability.
        if content_hash == ZERO_HASH and status != "D":
            missing.append(relative)
        classification, reason = classify(relative, content)
        entries.append(
            {
                "path": relative,
                "status": status,
                "classification": classification,
                "classification_reason": reason,
                "content_hash": content_hash,
                "size": size,
                "content_available": content_hash != ZERO_HASH,
            }
        )

    submodules, submodules_error = parent_gitlink_status(root)
    if submodules is None:
        return unavailable_report(root, submodules_error or "parent Gitlink query failed")
    # The base/head pair already identifies the complete committed range. The
    # expensive base-range diff is not needed for this source-only manifest;
    # hash the current worktree status as the local-delta witness instead.
    diff_hash = sha256_bytes(
        b"worktree-status-v2\0" + (base or "HEAD").encode() + b"\0" + source_status.encode()
    )
    status_hash = sha256_bytes(source_status.encode())
    canonical_entries = json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()
    identity_hash = sha256_bytes(
        b"xenia-fork\0"
        + head.encode()
        + b"\0"
        + base.encode()
        + b"\0"
        + status_hash.encode()
        + b"\0"
        + canonical_entries
        + b"\0"
        + (submodules or "").encode()
    )
    counts = Counter(entry["classification"] for entry in entries)
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "available",
        "root_present": True,
        "root": str(root),
        "identity_hash": identity_hash,
        "branch": branch or "",
        "head": head,
        "base": base,
        "base_source": base_source,
        "status_hash": status_hash,
        "diff_name_status_hash": diff_hash,
        "status_path_count": len(entries),
        "excluded_generated_roots": excluded_generated_roots,
        "classification_counts": dict(sorted(counts.items())),
        "missing": missing,
        "submodules": submodules or "",
        "entries": entries,
        "declared_checks": [
            {
                "name": "xenia-cmake-health",
                "kind": "compile-only",
                "command": "cmake --build build --config Debug --target xenia_canary -- -j2",
                "executed_by": "caller",
            },
            {
                "name": "xenia-authentic-run",
                "kind": "behavior",
                "command": "launch xenia with the sealed Rosette manifest",
                "executed_by": "future-authentic-run",
                "required_for_admission": True,
            },
        ],
        "admission": {
            "complete": bool(base and not missing),
            "source_only": True,
            "path_strings_are_metadata_only": True,
            "requires_behavior_validation": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--base")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--allow-missing-root",
        action="store_true",
        help=(
            "return success when the requested root is absent, while writing "
            "an explicit unavailable manifest; existing invalid roots still fail"
        ),
    )
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    report = build_manifest(root, args.base)
    output = args.output if args.output.is_absolute() else Path.cwd() / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "xenia-fork-manifest: status={} identity={} paths={} complete={} output={}".format(
            report["status"],
            report["identity_hash"][:16],
            report.get("status_path_count", 0),
            report["admission"]["complete"],
            output,
        )
    )
    if report["status"] == "available":
        return 0
    # Shell refresh does not build or launch Xenia.  It can proceed without a
    # removable source drive as long as the missing source stays explicit in
    # the manifest.  Do not extend this exception to an existing but unreadable
    # or malformed checkout, and keep all other callers strict by default.
    if args.allow_missing_root and not root.exists():
        print("xenia-fork-manifest: continuing with explicit unavailable source", flush=True)
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
