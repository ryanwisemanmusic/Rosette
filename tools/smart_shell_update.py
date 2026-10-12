#!/usr/bin/env python3
"""Change-aware shell refresh with a conservative full-update fallback.

The fast path is deliberately small: it recognizes only processor source
subtrees with a matching focused regression suite. Any unknown input, missing
state, toolchain/configuration change, Xenia source change, or missing shipped
artifact delegates to the full sanity path. It never launches Xenia.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 3
TIMINGS: list[dict[str, Any]] = []
STATE_RELATIVE = Path(".rosette/shell-update-state.json")
SNAPSHOT_SKIP_DIRS = {
    ".git",
    ".rosette",
    ".zig-cache",
    "zig-cache",
    "__pycache__",
    "node_modules",
}
EXCLUDED_STATUS_ROOTS = {".rosette", "zig-out"}
SCOPE_TESTS = {
    "elf-processor-process-impl": ("elf-check",),
    "elf-processor-windows-runtime": ("elf-check",),
    "elf-processor-block-jit": ("block-jit-check",),
    "elf-processor": ("elf-check",),
    "macho-processor": ("macho-processor-check",),
    "dyld-forwarder": ("dyld-check",),
}
SCOPE_PATHS = {
    "elf-processor-process-impl": ("lib/processor/ELF_processor/process/impl/",),
    "elf-processor-windows-runtime": (
        "src/x64-ASM/windows_runtime.zig",
        "src/x64-ASM/windows_runtime/",
    ),
    "elf-processor-block-jit": (
        "lib/processor/ELF_processor/block_jit.zig",
        "lib/processor/ELF_processor/block_jit/",
    ),
    "elf-processor": ("lib/processor/ELF_processor/",),
    "macho-processor": ("lib/Mach-O/",),
    "dyld-forwarder": ("lib/linker/dyld/",),
}
SOURCE_ARTIFACTS = (
    "zig-out/bin/rosette-shell",
    "zig-out/bin/elf_processor",
    "zig-out/bin/macho_processor",
    "zig-out/bin/rosette-router",
    "zig-out/bin/rosette_assembler_runner",
    "zig-out/bin/rosette_exe_runner",
    "zig-out/lib/rosette-exec.dylib",
    "zig-out/lib/avx-shim.dylib",
)
FULL_PREREQUISITES = (
    "shell-helper-build",
    "test-census",
    "xenia-run-systems-check",
    "shell-update-system-check",
    "source-budget-check",
    "audit-phase-coverage",
    "xenia-fork-manifest",
    "replay-evidence",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def command_text(command: list[str], cwd: Path) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if completed.returncode:
        raise RuntimeError(f"command failed ({completed.returncode}): {' '.join(command)}\n{completed.stdout}")
    return completed.stdout.rstrip("\n")


def decode_git_path(value: str) -> str:
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        try:
            decoded = ast.literal_eval(value)
            if isinstance(decoded, str):
                return decoded
        except (SyntaxError, ValueError):
            pass
    return value


def parse_status_paths(status_text: str) -> list[str]:
    paths: set[str] = set()
    for line in status_text.splitlines():
        if not line:
            continue
        path_text = line[3:] if len(line) > 3 else ""
        if " -> " in path_text:
            path_text = path_text.split(" -> ", 1)[1]
        path_text = decode_git_path(path_text).replace("\\", "/").rstrip("/")
        if path_text and not any(
            path_text == root or path_text.startswith(root + "/")
            for root in EXCLUDED_STATUS_ROOTS
        ):
            paths.add(path_text)
    return sorted(paths)


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hash_path(path: Path) -> str:
    """Hash the current bytes of a Git status path, including untracked dirs."""
    if not path.exists() and not path.is_symlink():
        return "deleted"
    if path.is_symlink():
        return sha256_bytes(b"symlink\0" + os.readlink(path).encode("utf-8", errors="surrogateescape"))
    if path.is_file():
        return hash_file(path)
    if not path.is_dir():
        return "unreadable"

    digest = hashlib.sha256()
    try:
        for directory, dirnames, filenames in os.walk(path):
            current = Path(directory)
            dirnames[:] = sorted(
                name
                for name in dirnames
                if name not in SNAPSHOT_SKIP_DIRS and not (current / name).is_symlink()
            )
            for name in sorted(filenames):
                child = current / name
                if child.is_symlink():
                    content_hash = sha256_bytes(
                        b"symlink\0" + os.readlink(child).encode("utf-8", errors="surrogateescape")
                    )
                else:
                    content_hash = hash_file(child)
                digest.update(child.relative_to(path).as_posix().encode())
                digest.update(b"\0")
                digest.update(bytes.fromhex(content_hash))
                digest.update(b"\0")
    except OSError as error:
        raise RuntimeError(f"cannot fingerprint {path}: {error}") from error
    return digest.hexdigest()


def current_source_snapshot(root: Path) -> dict[str, Any]:
    """Canonical content identities, stable across commits and staging.

    Clean tracked files use Git's blob identities; modified/untracked files
    get the exact same blob digest over their current bytes. Git HEAD alone
    cannot distinguish a code change from committing already tested bytes.
    """
    head = command_text(["git", "rev-parse", "HEAD"], root)
    algorithm = command_text(["git", "rev-parse", "--show-object-format"], root)
    if algorithm not in ("sha1", "sha256"):
        raise RuntimeError("unsupported Git object format: " + algorithm)
    entries = command_text(["git", "ls-files", "--stage", "-z"], root)
    status = command_text(["git", "status", "--porcelain=v1", "--untracked-files=all"], root)
    dirty = set(parse_status_paths(status))
    flags = command_text(["git", "ls-files", "-v", "-z"], root)
    # Honor changes hidden from status by assume-unchanged or skip-worktree.
    dirty.update(item[2:] for item in flags.split("\0") if item and (item[0].islower() or item[0] == "S"))
    files: dict[str, str] = {}
    for entry in entries.split("\0"):
        if not entry:
            continue
        metadata, relative = entry.split("\t", 1)
        mode, blob, stage = metadata.split()
        if stage != "0":
            raise RuntimeError("unresolved index entry: " + relative)
        if excluded_snapshot_path(relative):
            continue
        files[relative] = mode + ":" + blob
    for relative in dirty:
        if excluded_snapshot_path(relative):
            continue
        path = root / relative
        if path.is_symlink():
            data, mode = os.readlink(path).encode("utf-8", errors="surrogateescape"), "120000"
        elif path.is_file():
            data = path.read_bytes()
            mode = "100755" if path.stat().st_mode & 0o111 else "100644"
        elif not path.exists():
            files.pop(relative, None)
            continue
        else:
            raise RuntimeError("source status did not enumerate individual files: " + relative)
        digest = hashlib.new(algorithm)
        digest.update(b"blob " + str(len(data)).encode() + b"\0" + data)
        files[relative] = mode + ":" + digest.hexdigest()
    encoded = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"head": head, "files": files, "sha256": sha256_bytes(encoded),
            "identity": "git-blob-content-and-mode-v1"}


def excluded_snapshot_path(relative: str) -> bool:
    first = relative.split("/", 1)[0]
    if first in EXCLUDED_STATUS_ROOTS:
        return True
    # Session notes are documentation, not executable inputs. Source fixtures,
    # scripts, build definitions and configuration remain in the snapshot.
    return relative == "AGENTS.md" or (
        relative.endswith(".md") and first in {"docs", "Rosette_Brain"}
    )


def external_fingerprint(root: Path, xenia_root: Path) -> dict[str, str]:
    tools_dir = root / "tools"
    sys.path.insert(0, str(tools_dir))
    import build_identity_manifest as identity

    manifest_path = root / ".rosette" / "xenia-fork-manifest.json"
    xenia_script = tools_dir / "build_xenia_fork_manifest.py"
    run_checked(
        [sys.executable, str(xenia_script), "--root", str(xenia_root), "--output", str(manifest_path)],
        root,
    )
    try:
        xenia_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read Xenia source manifest: {error}") from error
    return {
        "toolchain": identity.toolchain_identity()["hash"],
        "configuration": identity.configuration_identity()["hash"],
        "xenia_root": str(xenia_root.resolve()),
        "xenia_identity": str(xenia_manifest.get("identity_hash", "unavailable")),
        "runtime_optimize": "ReleaseFast",
    }


def run_checked(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> None:
    print("+ " + " ".join(command), flush=True)
    start = time.monotonic()
    result = subprocess.run(command, cwd=cwd, env=env, check=False)
    elapsed = time.monotonic() - start
    TIMINGS.append({"command": command, "elapsed_seconds": elapsed, "exit_code": result.returncode})
    print(f"shell-update timing: {elapsed:.3f}s exit={result.returncode} {Path(command[0]).name}", flush=True)
    result.check_returncode()


def make_command(root: Path, xenia_root: Path, targets: list[str]) -> list[str]:
    # GNUmakefile already selects build/Makefile from the repository root.
    # Configuration travels in the environment; Make invocations stay bare.
    return [shutil.which("make") or "make", *targets]


def make_env(xenia_root: Path | None = None) -> dict[str, str]:
    env = os.environ.copy()
    for name in ("MAKEFLAGS", "MFLAGS", "MAKELEVEL"):
        env.pop(name, None)
    env["ROSETTE_RUNTIME_OPTIMIZE"] = "ReleaseFast"
    if xenia_root is not None:
        env["XENIA_ROOT"] = str(xenia_root)
    return env


def record_update(
    root: Path,
    xenia_root: Path,
    mode: str,
    scope: str,
    checks: tuple[str, ...] = (),
) -> None:
    script = root / "tools" / "record_shell_update.py"
    command = [
        sys.executable,
        str(script),
        "--root",
        str(root),
        "--helper",
        str(root / "zig-out/bin/rosette-shell"),
        "--source",
        str(root / "src/shell/global_config/rosette_shell.zig"),
        "--census",
        str(root / ".rosette/test-census.json"),
        "--output",
        str(root / ".rosette/shell-update.json"),
        "--verification-mode",
        mode,
        "--verification-scope",
        scope,
    ]
    for check in checks:
        command.extend(("--verification-check", check))
    run_checked(command, root)


def refresh_identity(root: Path, xenia_root: Path) -> None:
    run_checked(
        [
            sys.executable,
            str(root / "tools/build_identity_manifest.py"),
            "--root",
            str(root),
            "--xenia-root",
            str(xenia_root),
            "--helper",
            str(root / "zig-out/bin/rosette-shell"),
            "--census",
            str(root / ".rosette/test-census.json"),
            "--shell-update",
            str(root / ".rosette/shell-update.json"),
            "--fork-manifest",
            str(root / ".rosette/xenia-fork-manifest.json"),
            "--phase-coverage",
            str(root / ".rosette/audit-phase-coverage.json"),
            "--evidence-replay",
            str(root / ".rosette/evidence-replay.json"),
            "--output",
            str(root / ".rosette/build-identity.json"),
        ],
        root,
    )


def install_shell(root: Path) -> None:
    helper = root / "zig-out/bin/rosette-shell"
    if not helper.is_file():
        raise RuntimeError(f"built shell helper is missing: {helper}")
    run_checked([str(helper), "update", str(root)], root)


def full_update(root: Path, xenia_root: Path) -> None:
    print(
        "WARNING: shell-update-all is the full sanity check. It runs the complete Zig census and all shell build audits; allow about 20 minutes or longer.",
        flush=True,
    )
    run_checked(make_command(root, xenia_root, list(FULL_PREREQUISITES)), root, make_env(xenia_root))
    install_shell(root)
    record_update(root, xenia_root, "full", "all", ("zig-build-check=0",))
    refresh_identity(root, xenia_root)
    prime_state(root, xenia_root)


def target_scope_for_paths(paths: list[str]) -> str | None:
    if not paths:
        return None
    if all(any(path.startswith(prefix) for prefix in SCOPE_PATHS["elf-processor-process-impl"]) for path in paths):
        return "elf-processor-process-impl"
    if all(any(path.startswith(prefix) for prefix in SCOPE_PATHS["elf-processor-windows-runtime"]) for path in paths):
        return "elf-processor-windows-runtime"
    if all(any(path.startswith(prefix) for prefix in SCOPE_PATHS["elf-processor-block-jit"]) for path in paths):
        return "elf-processor-block-jit"
    if all(any(path.startswith(prefix) for prefix in SCOPE_PATHS["elf-processor"]) for path in paths):
        return "elf-processor"
    if all(any(path.startswith(prefix) for prefix in SCOPE_PATHS["macho-processor"]) for path in paths):
        return "macho-processor"
    if all(any(path.startswith(prefix) for prefix in SCOPE_PATHS["dyld-forwarder"]) for path in paths):
        return "dyld-forwarder"
    return None


def load_state(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return result if result.get("schema_version") == SCHEMA_VERSION else None


def write_state(root: Path, xenia_root: Path) -> None:
    snapshot = current_source_snapshot(root)
    state_path = root / STATE_RELATIVE
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state = {
        "schema_version": SCHEMA_VERSION,
        "updated_at_utc": datetime.now(timezone.utc).isoformat(),
        "snapshot": snapshot,
        "external": external_fingerprint(root, xenia_root),
        "artifacts": artifact_hashes(root),
        "policy": {
            "fast_scopes": sorted(SCOPE_TESTS),
            "unknown_changes": "full-sanity-update",
            "generated_roots_excluded": sorted(EXCLUDED_STATUS_ROOTS),
        },
    }
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"shell-update-state: primed {state_path} ({len(snapshot['files'])} changed paths)")


def prime_state(root: Path, xenia_root: Path) -> None:
    write_state(root, xenia_root)


def artifact_hashes(root: Path) -> dict[str, str | None]:
    """Record the exact installed inputs a relink would reuse."""
    return {
        relative: hash_file(root / relative) if (root / relative).is_file() else None
        for relative in SOURCE_ARTIFACTS
    }


def artifact_issues(root: Path, expected: dict[str, str | None] | None) -> list[str]:
    current = artifact_hashes(root)
    missing = [path for path, digest in current.items() if digest is None]
    issues = [f"missing artifact {path}" for path in missing]
    if expected is None or set(expected) != set(SOURCE_ARTIFACTS):
        issues.append("missing or incomplete artifact identity baseline")
    else:
        issues.extend(
            f"artifact differs from last successful update: {path}"
            for path, digest in current.items()
            if digest is not None and digest != expected.get(path)
        )
    return issues


def focused_update(root: Path, xenia_root: Path, scope: str) -> None:
    tests = SCOPE_TESTS[scope]
    zig_command = [
        shutil.which("zig") or "zig",
        "build",
        "--build-file",
        "build/build.zig",
        "--prefix",
        "zig-out",
        "-Doptimize=ReleaseFast",
        *tests,
    ]
    cache = root / "build/.zig-cache"
    env = os.environ.copy()
    env["ZIG_LOCAL_CACHE_DIR"] = str(cache)
    env["ZIG_GLOBAL_CACHE_DIR"] = str(cache / "global")
    run_checked(zig_command, root, env)
    if scope.startswith("elf-"):
        targets = ["elf-processor-build", "elf-processor-dylib", "exe-runner-build"]
        if scope == "elf-processor-windows-runtime":
            targets.append("macho-processor-build")
    elif scope == "macho-processor":
        targets = ["macho-processor-build", "exe-runner-build"]
    else:
        targets = ["dyld-processor-build", "elf-processor-dylib", "exe-runner-build"]
    run_checked(make_command(root, xenia_root, targets), root, make_env(xenia_root))
    install_shell(root)
    record_update(root, xenia_root, "incremental", scope, tuple(f"{name}=0" for name in tests))
    refresh_identity(root, xenia_root)
    write_state(root, xenia_root)


def relink_update(root: Path, xenia_root: Path) -> None:
    install_shell(root)
    record_update(root, xenia_root, "relink", "unchanged-source-relink")
    refresh_identity(root, xenia_root)
    write_state(root, xenia_root)


def run(root: Path, xenia_root: Path, requested_scope: str) -> int:
    root = root.resolve()
    xenia_root = xenia_root.expanduser().resolve()
    state_path = root / STATE_RELATIVE
    previous = load_state(state_path)

    if requested_scope == "all":
        full_update(root, xenia_root)
        return 0
    if previous is None:
        print("shell-update: no trusted incremental state; using the full sanity path", flush=True)
        full_update(root, xenia_root)
        return 0

    snapshot = current_source_snapshot(root)
    paths = sorted(
        path
        for path in set(snapshot["files"]) | set(previous["snapshot"].get("files", {}))
        if snapshot["files"].get(path) != previous["snapshot"].get("files", {}).get(path)
    )
    reasons: list[str] = []
    try:
        external = external_fingerprint(root, xenia_root)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"shell-update: cannot verify external build inputs ({error}); using full sanity path", flush=True)
        full_update(root, xenia_root)
        return 0
    if external != previous.get("external"):
        reasons.append("toolchain, configuration, or Xenia source identity changed")

    detected_scope = target_scope_for_paths(paths)
    if paths and detected_scope is None:
        reasons.append("changed paths include an unclassified build or test input")
    if requested_scope in SCOPE_TESTS and paths:
        requested_prefixes = SCOPE_PATHS[requested_scope]
        if not all(any(path.startswith(prefix) for prefix in requested_prefixes) for path in paths):
            reasons.append(f"pending changes extend outside requested scope {requested_scope}")
    if requested_scope in ("elf-processor-process-impl", "elf-processor-windows-runtime") and detected_scope == "elf-processor":
        reasons.append(f"pending ELF changes extend outside {requested_scope.removeprefix('elf-processor-')}")
    stale_artifacts = artifact_issues(root, previous.get("artifacts"))
    if stale_artifacts:
        reasons.extend(stale_artifacts)

    if reasons:
        print("shell-update: " + "; ".join(reasons) + "; using full sanity path", flush=True)
        full_update(root, xenia_root)
        return 0

    if paths:
        scope = requested_scope if requested_scope in SCOPE_TESTS else detected_scope
        if scope is None:
            print("shell-update: no scoped change remains; relinking current artifacts", flush=True)
            relink_update(root, xenia_root)
        else:
            print(f"shell-update: changes={len(paths)} scope={scope}", flush=True)
            focused_update(root, xenia_root, scope)
        return 0

    if requested_scope in SCOPE_TESTS:
        print(f"shell-update: forcing focused verification scope={requested_scope}", flush=True)
        focused_update(root, xenia_root, requested_scope)
    else:
        print("shell-update: source and external inputs match the installed snapshot; refreshing shell integration", flush=True)
        relink_update(root, xenia_root)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--xenia-root", type=Path, required=True)
    parser.add_argument(
        "--scope",
        choices=("auto", "all", "relink", *sorted(SCOPE_TESTS)),
        default="auto",
    )
    parser.add_argument("--prime-state", action="store_true")
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    xenia_root = args.xenia_root.expanduser().resolve()
    if args.prime_state:
        prime_state(root, xenia_root)
        return 0
    requested_scope = "auto" if args.scope in ("auto", "relink") else args.scope
    if args.scope == "relink":
        requested_scope = "relink"
    started = time.monotonic()
    result = 1
    try:
        result = run(root, xenia_root, requested_scope)
        return result
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"shell-update: ERROR: {error}", file=sys.stderr, flush=True)
        return 1
    finally:
        report = {"schema_version": 1, "elapsed_seconds": time.monotonic() - started,
                  "exit_code": result, "requested_scope": requested_scope, "stages": TIMINGS}
        (root / ".rosette").mkdir(exist_ok=True)
        (root / ".rosette/shell-update-timings.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
