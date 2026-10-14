#!/usr/bin/env python3
"""Build a content-addressed Rosette/Xenia admission manifest.

The manifest is intentionally produced outside the emulator.  It binds the
source trees, fork base, generated inputs, toolchain, shell helper, tests,
backend policy, and semantic configuration before a guest run starts.  Paths
are metadata only; no identity digest is derived from a path string.

Missing optional Xenia or host data is recorded as ``unavailable`` and leaves
the corresponding identity value empty.  This keeps ``make shell-update``
useful on another machine while ensuring an authentic runtime cannot mistake a
missing input for a matching one.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import platform
import re
import sys
import subprocess
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = 2
HEX_ZERO = "0" * 64
SKIP_DIRS = {
    ".git",
    ".zig-cache",
    "zig-cache",
    "__pycache__",
    "build",
    "out",
    "obj",
    # Xenia's top-level .rosette directory contains runtime logs, captures,
    # caches, and per-run evidence. It is not part of the source tree. Xenia's
    # .gitignore does not consistently hide it, so an untracked directory can
    # otherwise make every shell update hash tens of thousands of run files.
    ".rosette",
}
RUNTIME_INPUT_SUFFIXES = {".iso", ".xiso", ".xex"}
XENIA_GENERATED_ROOTS = {".rosette"}


def is_xenia_generated_path(path: str) -> bool:
    normalized = path.replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    normalized = normalized.rstrip("/")
    return any(
        normalized == generated or normalized.startswith(generated + "/")
        for generated in XENIA_GENERATED_ROOTS
    )


def filter_xenia_status(status: str) -> str:
    """Drop runtime-owned Xenia output roots from source status identity."""
    kept: list[str] = []
    for line in status.splitlines():
        path_text = line[3:] if len(line) > 3 else ""
        path_text = path_text.strip()
        if len(path_text) >= 2 and path_text[0] == '"' and path_text[-1] == '"':
            try:
                path_text = ast.literal_eval(path_text)
            except (SyntaxError, ValueError):
                pass
        if is_xenia_generated_path(path_text):
            continue
        kept.append(line)
    return "\n".join(kept)


def filter_xenia_paths(paths: str) -> str:
    """Drop generated roots from a newline-delimited Git path list."""
    return "\n".join(
        line for line in paths.splitlines() if not is_xenia_generated_path(line)
    )


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hash_stream(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iter_files(root: Path) -> Iterable[tuple[str, Path]]:
    if not root.exists():
        return
    if root.is_file():
        yield root.name, root
        return
    # Prune generated/build trees while walking. ``rglob`` visits every entry
    # before the caller can discard it, which is needlessly expensive for the
    # Xenia checkout's object/cache directories.
    for directory, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(
            name for name in dirnames
            if name not in SKIP_DIRS and not (Path(directory) / name).is_symlink()
        )
        for name in sorted(filenames):
            path = Path(directory) / name
            if path.is_symlink():
                continue
            relative = path.relative_to(root)
            yield relative.as_posix(), path


def hash_tree(roots: Iterable[Path], label: str) -> tuple[str, int, list[str]]:
    """Hash relative names and bytes, never an absolute filesystem path."""
    entries: list[tuple[str, Path]] = []
    missing: list[str] = []
    for root in roots:
        if not root.exists():
            missing.append(str(root))
            continue
        for relative, path in iter_files(root):
            entries.append((f"{label}/{root.name}/{relative}", path))
    entries.sort(key=lambda item: item[0])
    digest = hashlib.sha256()
    for relative, path in entries:
        digest.update(relative.encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(hash_stream(path)))
        digest.update(b"\0")
    if not entries:
        return HEX_ZERO, 0, missing
    return digest.hexdigest(), len(entries), missing


def hash_nested_repository(root: Path, label: str) -> tuple[str, int, list[str]]:
    """Hash a nested checkout without rescanning its entire clean history.

    Xenia keeps many dependencies as Git submodules. Their commit IDs already
    identify every clean tracked byte; only the dirty/untracked delta needs
    file-content hashing. This also avoids walking generated dependency trees
    and makes an unreadable runtime media file irrelevant to source identity.
    """
    head, head_error = command_text(["git", "-C", str(root), "rev-parse", "HEAD"])
    if head is None:
        return HEX_ZERO, 0, [str(root), head_error or "nested repository has no HEAD"]

    changed, changed_error = command_text(
        ["git", "-C", str(root), "diff", "--name-only", "HEAD"]
    )
    untracked, untracked_error = command_text(
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard"]
    )
    submodules, submodules_error = command_text(
        ["git", "-C", str(root), "submodule", "status", "--recursive"]
    )
    deleted, deleted_error = command_text(
        ["git", "-C", str(root), "ls-files", "--deleted"]
    )
    if changed is None or untracked is None or submodules is None or deleted is None:
        return HEX_ZERO, 0, [
            str(root),
            changed_error
            or untracked_error
            or submodules_error
            or deleted_error
            or "nested git query failed",
        ]

    changed_paths = {
        Path(item.strip())
        for item in (changed + "\n" + untracked).splitlines()
        if item.strip()
    }
    digest = hashlib.sha256()
    digest.update(b"git-head\0" + head.encode() + b"\0")
    digest.update(b"git-diff\0" + changed.encode() + b"\0")
    digest.update(b"git-untracked\0" + untracked.encode() + b"\0")
    digest.update(b"git-submodules\0" + submodules.encode() + b"\0")
    digest.update(b"git-deleted\0" + deleted.encode() + b"\0")
    missing: list[str] = []
    count = 1  # The commit marker is an identity-bearing entry by itself.
    deleted_paths = {
        Path(item.strip()).as_posix()
        for item in deleted.splitlines()
        if item.strip()
    }

    for relative in sorted(changed_paths, key=lambda item: item.as_posix()):
        relative_text = relative.as_posix().rstrip("/")
        if not relative_text or Path(relative_text).suffix.lower() in RUNTIME_INPUT_SUFFIXES:
            continue
        path = root / relative
        if not path.exists() and relative_text in deleted_paths:
            # A deliberate deletion is part of the worktree identity through
            # the diff/status material above; it is not an unavailable input.
            continue
        if path.is_symlink():
            try:
                content_hash = sha256_bytes(
                    b"symlink\0" + os.readlink(path).encode("utf-8", errors="surrogateescape")
                )
            except OSError as error:
                missing.append(f"{relative_text}: {error}")
                continue
        elif path.is_file():
            try:
                content_hash = hash_stream(path)
            except OSError as error:
                missing.append(f"{relative_text}: {error}")
                continue
        elif path.is_dir() and (path / ".git").exists():
            content_hash, nested_count, nested_missing = hash_nested_repository(
                path, f"{label}/{relative_text}"
            )
            if content_hash == HEX_ZERO or nested_missing:
                missing.extend(
                    f"{relative_text}/{item}" if item else relative_text
                    for item in (nested_missing or [""])
                )
                continue
            count += nested_count
        else:
            missing.append(relative_text)
            continue
        digest.update(f"{label}/{relative_text}".encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(content_hash))
        digest.update(b"\0")
        count += 1

    if missing:
        return HEX_ZERO, 0, missing
    return digest.hexdigest(), count, []


def gitlink_paths(root: Path) -> set[str]:
    """Return submodule paths from the parent index without walking them.

    A Gitlink's object ID is the complete identity of the clean nested
    checkout.  The parent checkout's status/diff material, which
    ``hash_git_tree`` already folds into its digest, records whether the
    worktree differs from that Gitlink.  Looking up the nested checkout's
    ``HEAD`` is therefore sufficient here and avoids recursively asking Git
    to inspect a potentially very large nested object database just to prove
    that an unchanged submodule is unchanged.
    """
    listing, _ = command_text(["git", "-C", str(root), "ls-files", "--stage"])
    if listing is None:
        return set()
    paths: set[str] = set()
    for line in listing.splitlines():
        fields = line.split(None, 3)
        if len(fields) != 4 or fields[0] != "160000":
            continue
        paths.add(Path(fields[3]).as_posix())
    return paths


def gitlink_status(root: Path) -> str:
    """Return parent-index Gitlink records as the submodule identity."""
    listing, _ = command_text(["git", "-C", str(root), "ls-files", "--stage"])
    if listing is None:
        return ""
    records: list[str] = []
    for line in listing.splitlines():
        fields = line.split(None, 3)
        if len(fields) == 4 and fields[0] == "160000":
            records.append(f"{fields[0]} {fields[1]}\t{fields[3]}")
    return "\n".join(records)


def hash_gitlink_checkout(root: Path, label: str) -> tuple[str, int, list[str]]:
    """Hash a nested checkout through its commit identity only.

    The parent Git worktree status is included by ``hash_git_tree``.  Combining
    that status with the nested HEAD gives a stable identity for both clean
    submodules and modified submodules without scanning their packfiles.
    """
    head, error = command_text(["git", "-C", str(root), "rev-parse", "HEAD"])
    if head is None:
        return HEX_ZERO, 0, [str(root), error or "nested checkout has no HEAD"]
    digest = sha256_bytes(
        f"{label}/git-head\0{head}".encode()
    )
    return digest, 1, []


def hash_git_tree(root: Path, label: str) -> tuple[str, int, list[str]]:
    """Hash a Git commit plus the readable worktree delta.

    A commit ID already content-addresses every clean tracked byte. Walking
    every tracked file is both redundant and unsafe for Xenia's removable
    checkout, which contains large dependency packfiles. The status record
    identifies the small set of local edits; only those files/directories are
    read, while parent-index Gitlinks identify clean submodules.
    """
    head, head_error = command_text(["git", "-C", str(root), "rev-parse", "HEAD"])
    if head is None:
        return HEX_ZERO, 0, [head_error or str(root)]
    status, status_error = command_text(
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
    deleted, deleted_error = command_text(
        ["git", "-C", str(root), "ls-files", "--deleted"]
    )
    submodules = gitlink_status(root)
    if status is None or deleted is None:
        return HEX_ZERO, 0, [
            status_error or deleted_error or "git identity query failed"
        ]
    if not head:
        return HEX_ZERO, 0, ["git identity query returned an empty HEAD"]

    # `.rosette` is a Rosette runtime-data directory in the adjacent Xenia
    # checkout, not Xenia source. Filter it consistently from the status
    # witness and content delta so logs/captures cannot dominate shell-update.
    status = filter_xenia_status(status)
    deleted = filter_xenia_paths(deleted)

    digest = hashlib.sha256()
    digest.update(b"git-head\0" + head.encode() + b"\0")
    digest.update(b"git-status\0" + status.encode() + b"\0")
    digest.update(b"git-deleted\0" + deleted.encode() + b"\0")
    if submodules:
        digest.update(b"gitlinks\0" + submodules.encode() + b"\0")

    count = 1  # The commit marker is an identity-bearing entry by itself.
    missing: list[str] = []
    read_error = False
    deleted_paths = {
        Path(item.strip()).as_posix()
        for item in deleted.splitlines()
        if item.strip()
    }
    delta_paths: dict[str, str] = {}
    for line in status.splitlines():
        if not line:
            continue
        status_code = line[:2].strip() or "??"
        path_text = line[3:] if len(line) > 3 else ""
        if " -> " in path_text:
            path_text = path_text.split(" -> ", 1)[1]
        relative_text = path_text.strip().strip('"').replace("\\", "/")
        if relative_text and not is_xenia_generated_path(relative_text):
            delta_paths[relative_text] = status_code

    for relative_text, status_code in sorted(delta_paths.items()):
        relative = Path(relative_text)
        path = root / relative
        # Title media is an input identity of its own, not part of the Xenia
        # source tree. Keeping it out here means an unreadable ISO cannot
        # collapse the source identity to all-zero; the media identity still
        # has to be supplied separately before an authentic run.
        if relative.suffix.lower() in RUNTIME_INPUT_SUFFIXES:
            continue
        if not path.exists() and (relative_text in deleted_paths or "D" in status_code):
            # Deletions are represented by the Git status/diff identity above,
            # and do not make an otherwise readable source checkout incomplete.
            continue

        if path.is_symlink():
            try:
                content_hash = sha256_bytes(
                    b"symlink\0" + os.readlink(path).encode("utf-8", errors="surrogateescape")
                )
            except OSError as error:
                read_error = True
                missing.append(f"{relative_text}: {error}")
                continue
            entry_count = 1
        elif path.is_file():
            try:
                content_hash = hash_stream(path)
            except OSError as error:
                read_error = True
                missing.append(f"{relative_text}: {error}")
                continue
            entry_count = 1
        elif path.is_dir():
            nested_hash, nested_count, nested_missing = hash_tree(
                [path], f"{label}/{relative_text}"
            )
            if nested_hash == HEX_ZERO or not nested_count:
                read_error = True
                missing.extend(
                    f"{relative_text}/{item}" if item else relative_text
                    for item in (nested_missing or [""])
                )
                continue
            if nested_missing:
                read_error = True
                missing.extend(
                    f"{relative_text}/{item}" if item else relative_text
                    for item in nested_missing
                )
                continue
            content_hash = nested_hash
            entry_count = nested_count
        else:
            read_error = True
            missing.append(relative_text)
            continue

        digest.update(f"{label}/{relative_text}".encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(content_hash))
        digest.update(b"\0")
        count += entry_count
    if not count or read_error:
        return HEX_ZERO, 0, missing
    return digest.hexdigest(), count, missing


def hash_paths(paths: Iterable[Path], root: Path) -> tuple[str, int, list[str]]:
    existing = [path for path in paths if path.exists()]
    missing = [str(path.relative_to(root) if path.is_relative_to(root) else path) for path in paths if not path.exists()]
    digest = hashlib.sha256()
    count = 0
    for path in sorted(existing, key=lambda item: str(item)):
        relative = path.relative_to(root).as_posix() if path.is_relative_to(root) else path.name
        if path.is_file():
            digest.update(relative.encode())
            digest.update(b"\0")
            digest.update(bytes.fromhex(hash_stream(path)))
            digest.update(b"\0")
            count += 1
        elif path.is_dir():
            tree_hash, tree_count, _ = hash_tree([path], relative)
            digest.update(relative.encode())
            digest.update(b"\0")
            digest.update(bytes.fromhex(tree_hash))
            digest.update(b"\0")
            count += tree_count
    return (digest.hexdigest() if count else HEX_ZERO), count, missing


def command_text(command: list[str]) -> tuple[str | None, str | None]:
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    except OSError as error:
        return None, str(error)
    # Preserve leading spaces: Git porcelain uses the first two columns for
    # the index/worktree status, and stripping them corrupts a first-line
    # path such as `.gitignore` into `gitignore`.
    value = completed.stdout.rstrip()
    if completed.returncode != 0:
        return None, value or f"exit {completed.returncode}"
    return value, None


def value_hash(label: str, value: str) -> str:
    return sha256_bytes(label.encode() + b"\0" + value.encode())


def identity_input(label: str, raw: str | None) -> dict:
    if raw is None or not raw.strip():
        return {"hash": HEX_ZERO, "kind": "missing", "available": False}
    value = raw.strip()
    candidate = Path(value).expanduser()
    path_like = "/" in value or "\\" in value or value.startswith((".", "~"))
    if candidate.exists():
        if candidate.is_file():
            digest = hash_stream(candidate)
            return {"hash": digest, "kind": "content", "available": True}
        if candidate.is_dir():
            digest, count, missing = hash_tree([candidate], label)
            return {
                "hash": digest,
                "kind": "content-tree",
                "available": count > 0 and not missing,
                "file_count": count,
                "missing": missing,
            }
    if path_like:
        # A path-shaped value that cannot be read is explicitly unavailable,
        # never a hash of the path text.
        return {"hash": HEX_ZERO, "kind": "unavailable-path", "available": False}
    return {"hash": value_hash(label, value), "kind": "declared-value", "available": True}


def declared_digest_input(label: str, raw: str | None) -> dict:
    """Read a caller-supplied digest without turning a path into identity.

    The title/media variables are conventionally named ``*_HASH``.  A real
    digest is already content identity and must not be hashed a second time;
    a path-shaped value still goes through ``identity_input`` so a path cannot
    accidentally become an admission token.
    """
    if raw is not None and re.fullmatch(r"[0-9a-fA-F]{64}", raw.strip()):
        return {"hash": raw.strip().lower(), "kind": "declared-digest", "available": True}
    return identity_input(label, raw)


def git_info(root: Path | None) -> dict:
    if root is None or not root.exists():
        return {"status": "unavailable", "root_present": False}
    # Git searches parent directories when a source archive has no .git
    # marker.  That would bind an extracted Windows Xenia tree to an
    # unrelated parent repository, so only query Git when metadata belongs to
    # this exact root.
    if not (root / ".git").exists():
        return {
            "status": "unavailable",
            "root_present": True,
            "error": "not a git checkout; using filesystem-tree identity",
        }
    top, top_error = command_text(["git", "-C", str(root), "rev-parse", "--show-toplevel"])
    head, head_error = command_text(["git", "-C", str(root), "rev-parse", "HEAD"])
    branch, branch_error = command_text(["git", "-C", str(root), "branch", "--show-current"])
    if top is None or head is None:
        return {
            "status": "unavailable",
            "root_present": True,
            "error": top_error or head_error or "not a git tree",
        }
    base = None
    base_source = None
    for candidate in ("origin/master", "origin/main", "upstream/master", "upstream/main"):
        found, _ = command_text(["git", "-C", str(root), "merge-base", "HEAD", candidate])
        if found:
            base = found
            base_source = candidate
            break
    if base is None:
        base, _ = command_text(["git", "-C", str(root), "rev-parse", "HEAD^"])
        base_source = "parent" if base else None
    status_text, _ = command_text(
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
    status_lines = [line for line in (status_text or "").splitlines() if line]
    paths: list[dict] = []
    for line in status_lines:
        status = line[:2].strip() or "??"
        path_text = line[3:] if len(line) >= 4 else ""
        if " -> " in path_text:
            path_text = path_text.split(" -> ", 1)[1]
        relative = Path(path_text).as_posix()
        paths.append(
            {
                "path": relative,
                "status": status,
                "classification": classify_fork_path(relative),
            }
        )
    paths.sort(key=lambda item: item["path"])
    diff_hash = sha256_bytes(
        b"worktree-status-v1\0"
        + (base or "HEAD").encode()
        + b"\0"
        + (status_text or "").encode()
    )
    return {
        "status": "available",
        "root_present": True,
        "branch": branch or "",
        "head": head,
        "base": base or "",
        "base_source": base_source or "",
        "status_path_count": len(paths),
        "status_paths": paths,
        "diff_name_status_sha256": diff_hash,
    }


def classify_fork_path(path: str) -> str:
    lower = path.lower()
    if any(token in lower for token in ("third_party/", "vendor/", "generated/", ".inc")):
        return "generated-or-vendor-content"
    if any(token in lower for token in ("test", "tests/", "testing/")):
        return "test-only-change"
    if any(token in lower for token in ("cmakelists", "cmake/", "scripts/", ".cmake")):
        return "platform-build-work"
    if "/gpu/" in lower or "/kernel/" in lower or "/cpu/" in lower or "/ui/" in lower:
        return "required-rosette-integration"
    return "intentional-platform-work"


def tree_identity(root: Path) -> dict:
    source_roots = [root / name for name in ("ISA", "lib", "src", "pkg", "include")]
    source_hash, source_count, source_missing = hash_tree(source_roots, "rosette-source")
    generated_roots = [
        root / "include" / "generated",
        root / "pkg" / "generated",
        root / "src" / "generated",
        root / "build" / "generated",
        root / "zig-out" / "generated",
    ]
    generated_hash, generated_count, generated_missing = hash_tree(generated_roots, "rosette-generated")
    # The generated roots are an optional set.  When none exists, that is a
    # verified empty generated tree, not an unavailable tree: zero is reserved
    # for an input that could not be inspected.  Keeping a non-zero digest for
    # the empty set lets the runtime distinguish "there are no generated
    # assets" from "the deployment identity was never produced".
    if generated_count == 0 and generated_missing:
        generated_hash = value_hash("rosette-generated-tree", "empty")
        generated_missing = []
    graph_hash, graph_count, graph_missing = hash_paths(
        [root / "build" / "build.zig", root / "build" / "Makefile"], root
    )
    vendor_hash, vendor_count, vendor_missing = hash_tree([root / "third_party"], "rosette-vendor")
    return {
        "source_tree": {"hash": source_hash, "file_count": source_count, "missing": source_missing},
        "generated_tree": {"hash": generated_hash, "file_count": generated_count, "missing": generated_missing},
        "build_graph": {"hash": graph_hash, "file_count": graph_count, "missing": graph_missing},
        "vendor_libraries": {"hash": vendor_hash, "file_count": vendor_count, "missing": vendor_missing},
    }


def toolchain_identity() -> dict:
    commands = {
        "zig": ["zig", "version"],
        "clang": ["clang", "--version"],
        "cmake": ["cmake", "--version"],
    }
    outputs: dict[str, str] = {}
    unavailable: list[str] = []
    for name, command in commands.items():
        output, error = command_text(command)
        if output is None:
            unavailable.append(f"{name}: {error or 'unavailable'}")
        else:
            outputs[name] = output
    outputs["host"] = "\n".join((platform.platform(), platform.machine(), platform.processor()))
    canonical = json.dumps(outputs, sort_keys=True, separators=(",", ":"))
    return {
        "hash": sha256_bytes(canonical.encode()) if not unavailable else HEX_ZERO,
        "outputs": outputs,
        "unavailable": unavailable,
    }


def configuration_identity() -> dict:
    names = (
        "ROSETTE_EXECUTION_PROFILE",
        "ROSETTE_BACKEND",
        "ROSETTE_DEVICE",
        "ROSETTE_DRIVER",
        "ROSETTE_MOLTENVK",
        "ROSETTE_METAL_CAPABILITIES",
        "ROSETTE_CVAR_HASH",
        "XENIA_CVAR_HASH",
        "ROSETTE_TIME_CONFIG",
        "ROSETTE_SCHEDULER_CONFIG",
        "ROSETTE_OBSERVER_CONFIG",
        "ROSETTE_ADMISSION_CONFIG",
        "ROSETTE_BUDGET_CONFIG",
        "ROSETTE_FRONTIER_CONFIG",
        "ROSETTE_OPTIONAL_RHI",
        "ROSETTE_TRACE_ROOT",
    )
    values = {name: identity_input(name, os.environ.get(name)) for name in names}
    canonical = json.dumps(values, sort_keys=True, separators=(",", ":"))
    return {"hash": sha256_bytes(canonical.encode()), "values": values}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--xenia-root", type=Path)
    parser.add_argument(
        "--allow-unavailable-xenia",
        action="store_true",
        help=(
            "write an explicitly incomplete identity only when the Xenia root "
            "is absent; intended for refreshing the Rosette shell without the source drive"
        ),
    )
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--census", type=Path)
    parser.add_argument("--shell-update", type=Path)
    parser.add_argument("--fork-manifest", type=Path)
    parser.add_argument("--phase-coverage", type=Path)
    parser.add_argument("--evidence-replay", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    xenia = args.xenia_root
    if xenia is None:
        env_xenia = os.environ.get("XENIA_ROOT")
        xenia = Path(env_xenia).expanduser() if env_xenia else None
    if xenia is None:
        conventional = Path("/Volumes/2023 Drive/xenia/xenia")
        xenia = conventional if conventional.exists() else None
    if xenia is not None:
        xenia = xenia.resolve()

    trees = tree_identity(root)
    rosette_git = git_info(root)
    xenia_git = git_info(xenia)
    xenia_hash, xenia_count, xenia_missing = (
        hash_git_tree(xenia, "xenia-source")
        if xenia and (xenia / ".git").exists()
        else hash_tree([xenia], "xenia-source")
        if xenia
        else (HEX_ZERO, 0, ["xenia-root"])
    )
    toolchain = toolchain_identity()
    config = configuration_identity()
    helper = args.helper.resolve() if args.helper else None
    census = args.census.resolve() if args.census else None
    shell_update = args.shell_update.resolve() if args.shell_update else None
    fork_manifest = args.fork_manifest.resolve() if args.fork_manifest else None
    phase_coverage = args.phase_coverage.resolve() if args.phase_coverage else None
    evidence_replay = args.evidence_replay.resolve() if args.evidence_replay else None
    run_system_paths = [
        root / "tools" / "xenia" / "scripts" / "rosette_xenia_systems.py",
        root / "tools" / "xenia" / "scripts" / "rosette-xenia-run.sh",
        root / "tools" / "test_xenia_run_systems.py",
    ]
    run_system_hash, run_system_count, run_system_missing = hash_paths(run_system_paths, root)

    artifacts = {
        "shell_helper": {"hash": hash_stream(helper) if helper and helper.is_file() else HEX_ZERO, "available": bool(helper and helper.is_file())},
        "test_manifest": {"hash": hash_stream(census) if census and census.is_file() else HEX_ZERO, "available": bool(census and census.is_file())},
        "shell_update": {"hash": hash_stream(shell_update) if shell_update and shell_update.is_file() else HEX_ZERO, "available": bool(shell_update and shell_update.is_file())},
        "xenia_fork_manifest": {"hash": hash_stream(fork_manifest) if fork_manifest and fork_manifest.is_file() else HEX_ZERO, "available": bool(fork_manifest and fork_manifest.is_file())},
        "phase_coverage": {"hash": hash_stream(phase_coverage) if phase_coverage and phase_coverage.is_file() else HEX_ZERO, "available": bool(phase_coverage and phase_coverage.is_file())},
        "evidence_replay": {"hash": hash_stream(evidence_replay) if evidence_replay and evidence_replay.is_file() else HEX_ZERO, "available": bool(evidence_replay and evidence_replay.is_file())},
        "xenia_run_systems": {
            "hash": run_system_hash,
            "file_count": run_system_count,
            "missing": run_system_missing,
            "available": run_system_count == len(run_system_paths) and not run_system_missing,
        },
    }

    identity = {
        "rosette_source_revision": value_hash("rosette-head", rosette_git.get("head", "")) if rosette_git.get("head") else HEX_ZERO,
        "rosette_source_tree": trees["source_tree"]["hash"],
        "rosette_generated_tree": trees["generated_tree"]["hash"],
        "xenia_source_revision": value_hash("xenia-head", xenia_git.get("head", "")) if xenia_git.get("head") else HEX_ZERO,
        "xenia_source_tree": xenia_hash,
        "xenia_fork_tree": xenia_hash,
        "xenia_base_commit": value_hash("xenia-base", xenia_git.get("base", "")) if xenia_git.get("base") else HEX_ZERO,
        "title_xex": declared_digest_input("title-xex", os.environ.get("ROSETTE_TITLE_XEX_HASH"))["hash"],
        "title_xiso": declared_digest_input("title-xiso", os.environ.get("ROSETTE_MEDIA_HASH"))["hash"],
        "media": declared_digest_input("media", os.environ.get("ROSETTE_MEDIA_HASH"))["hash"],
        "compiler": toolchain["hash"],
        "linker": identity_input("linker", os.environ.get("LD", "clang"))["hash"],
        "translator": trees["source_tree"]["hash"],
        "generator": trees["generated_tree"]["hash"],
        "shell_helper": artifacts["shell_helper"]["hash"],
        "build_graph": trees["build_graph"]["hash"],
        "toolchain": toolchain["hash"],
        "host": toolchain["hash"],
        "backend": config["values"]["ROSETTE_BACKEND"]["hash"],
        "device": config["values"]["ROSETTE_DEVICE"]["hash"],
        "driver": config["values"]["ROSETTE_DRIVER"]["hash"],
        "moltenvk": config["values"]["ROSETTE_MOLTENVK"]["hash"],
        "metal": config["values"]["ROSETTE_METAL_CAPABILITIES"]["hash"],
        "semantic_config": config["hash"],
        "cvar": config["values"]["ROSETTE_CVAR_HASH"]["hash"] or config["values"]["XENIA_CVAR_HASH"]["hash"],
        "time_config": config["values"]["ROSETTE_TIME_CONFIG"]["hash"],
        "scheduler_config": config["values"]["ROSETTE_SCHEDULER_CONFIG"]["hash"],
        "observer_config": config["values"]["ROSETTE_OBSERVER_CONFIG"]["hash"],
        "admission_config": config["values"]["ROSETTE_ADMISSION_CONFIG"]["hash"],
        "budget_config": config["values"]["ROSETTE_BUDGET_CONFIG"]["hash"],
        "frontier_config": config["values"]["ROSETTE_FRONTIER_CONFIG"]["hash"],
        "shader_assets": trees["generated_tree"]["hash"],
        "vendor_libraries": trees["vendor_libraries"]["hash"],
        "schema": value_hash("schema", f"rosette-xenia-v{SCHEMA_VERSION}"),
        "test_manifest": artifacts["test_manifest"]["hash"],
        "shell_update": artifacts["shell_update"]["hash"],
        "xenia_fork_manifest": artifacts["xenia_fork_manifest"]["hash"],
        "phase_coverage": artifacts["phase_coverage"]["hash"],
        "evidence_replay": artifacts["evidence_replay"]["hash"],
        "xenia_run_systems": artifacts["xenia_run_systems"]["hash"],
    }
    identity_canonical = json.dumps(identity, sort_keys=True, separators=(",", ":"))
    identity_hash = sha256_bytes(identity_canonical.encode())
    report = {
        "schema_version": SCHEMA_VERSION,
        "identity_hash": identity_hash,
        "identity_hash_u64": identity_hash[:16],
        "identity": identity,
        "rosette": trees,
        "rosette_git": rosette_git,
        "xenia": {
            "root_present": bool(xenia and xenia.exists()),
            "tree_hash": xenia_hash,
            "file_count": xenia_count,
            "missing": xenia_missing,
            "content_scope": "git-commit-plus-nonignored-worktree-deltas" if xenia and (xenia / ".git").exists() else "filesystem-tree",
            "git": xenia_git,
        },
        "toolchain": toolchain,
        "configuration": config,
        "artifacts": artifacts,
        "admission": {
            "complete": all(value != HEX_ZERO for value in identity.values()),
            "path_values_are_content_hashed": True,
            "authentic_requires_runtime_cross_check": True,
            "fork_manifest_is_source_only": True,
        },
    }
    # A manifest whose Xenia revision is unknown can never seal.
    #
    # `xenia_source_revision` and `xenia_base_commit` come only from Git; the
    # runtime fills the host, device and media fields but has no way to invent
    # these. Writing zeros for them produces a file that loads cleanly, reports
    # no conflict, and then leaves the manifest unsealable — which surfaces as
    # "RUN ADMISSION: refusing authentic guest start ... failure=seal-missing"
    # with nothing pointing back here.
    #
    # The usual cause is XENIA_ROOT pointing somewhere other than the tree that
    # was actually built, so the message names the path it used.
    unsealable = [
        name
        for name in ("xenia_source_revision", "xenia_base_commit")
        if set(identity.get(name, "")) == {"0"}
    ]
    missing_xenia_is_explicitly_allowed = (
        args.allow_unavailable_xenia and (xenia is None or not xenia.exists())
    )
    if unsealable and not missing_xenia_is_explicitly_allowed:
        print(
            "build-identity: REFUSING to write an unsealable manifest; "
            "{} could not be determined from xenia-root={} (git status={}). "
            "Every authentic run would be refused with failure=seal-missing. "
            "Point --xenia-root (or XENIA_ROOT) at the Xenia checkout that was "
            "built; it must be a Git checkout with its own .git.".format(
                ", ".join(unsealable),
                xenia if xenia is not None else "<unset>",
                xenia_git.get("status", "unknown"),
            ),
            file=sys.stderr,
        )
        return 1
    if unsealable:
        print(
            "build-identity: writing explicitly incomplete identity because "
            "the Xenia source root is absent; authentic run admission remains unavailable",
            file=sys.stderr,
        )

    output = args.output if args.output.is_absolute() else root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "build-identity: hash={} complete={} rosette_files={} xenia_files={} output={}".format(
            report["identity_hash_u64"],
            report["admission"]["complete"],
            trees["source_tree"]["file_count"],
            xenia_count,
            output,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
