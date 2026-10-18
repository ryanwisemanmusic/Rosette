#!/usr/bin/env python3
"""Rosetta-owned Xenia run identity, health, comparison, and promotion tools.

This module only reads Xenia source and run logs. `prepare` creates Rosetta run
records; `finalize` parses Rosetta/Xenia output after the PE runner has exited.
It never launches Xenia or changes Xenia source files. When requested, run
records may be stored under Xenia's `.rosette` data directory.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from typing import Any

_SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))
import fetch_constant_diagnostics

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        tomllib = None


SCHEMA_VERSION = 1
ZERO_SHA256 = "0" * 64
BUILD_IDENTITY_SKIP_DIRS = {".git", ".zig-cache", "zig-cache", "__pycache__", "build", "out", "obj"}
PERFORMANCE_ENV = (
    "ROSETTE_XENIA_APU",
    "ROSETTE_PE64_SDL_AUDIO_DRIVER",
    "ROSETTE_PE64_NATIVE_PTHREAD_COND",
    "ROSETTE_PE64_GUEST_WAIT_COMPAT",
    "ROSETTE_PE64_GUEST_SCHEDULER",
    "ROSETTE_PE64_GUEST_SCHEDULER_QUANTUM",
    "ROSETTE_PE64_GUEST_SCHEDULER_SLICE",
    "ROSETTE_PE64_GUEST_SCHEDULER_EXPLICIT_STRIDE",
    "ROSETTE_PE64_XENIA_RIJNDAEL_ACCELERATOR",
    "ROSETTE_PE64_XENIA_SHA1_ACCELERATOR",
    "ROSETTE_PE64_XENIA_TABULATE_ACCELERATOR",
    "ROSETTE_PE64_SDL_AUDIO_DRIVER",
    "ROSETTE_PE64_MAX_STEPS",
    "ROSETTE_XENIA_LOG_LEVEL",
    "ROSETTE_XENIA_MEDIA_SHA256",
    "ROSETTE_XENIA_FATAL_POINT_TERMINATE",
    "ROSETTE_ASYNC_LOG",
    "ROSETTE_INPUT_HASH_STALL_SECONDS",
    "ROSETTE_ELF_GRAPHICS_PROGRESS_TRACE",
    "ROSETTE_ELF_GRAPHICS_BOUNDARY_TRACE",
    "ROSETTE_ELF_GRAPHICS_STATE_DUMP",
    "ROSETTE_VULKAN_REPORT_VERBOSE",
    "ROSETTE_VULKAN_REPORT_INTERVAL_MS",
    "ROSETTE_VULKAN_CAPTURE",
    "ROSETTE_VULKAN_GFXR",
    "ROSETTE_FSI_EVIDENCE",
    "ROSETTE_HOST_PROFILE",
    "MTL_SHADER_VALIDATION",
    "MTL_SHADER_VALIDATION_REPORT_TO_STDERR",
    "MTL_SHADER_VALIDATION_FAIL_MODE",
    "MTL_SHADER_VALIDATION_ABORT_ON_FAULT",
    "MTL_SHADER_VALIDATION_DUMP_PIPELINES",
    "ROSETTE_VULKAN_COCOA_PREVIEW",
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def gfxr_artifacts(run_dir: pathlib.Path) -> list[dict[str, Any]]:
    """List completed GFXReconstruct files, including F10 trimmed captures.

    The capture layer writes the configured canonical path only while recording;
    trigger captures are sibling `*_trim_trigger_*.gfxr` files. Empty files are
    retained as diagnostics but do not count as usable capture artifacts.
    """
    artifacts: list[dict[str, Any]] = []
    for path in sorted(run_dir.glob("rosette-vulkan*.gfxr")):
        try:
            size = path.stat().st_size
        except OSError:
            continue
        artifacts.append({
            "path": str(path),
            "name": path.name,
            "kind": "trimmed" if "_trim_trigger_" in path.name else "canonical",
            "bytes": size,
            "usable": size > 0,
        })
    return artifacts


def sha256_file(path: pathlib.Path) -> str | None:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError:
        return None


def atomic_write_bytes(path: pathlib.Path, content: bytes, mode: int) -> None:
    """Replace one file atomically without exposing a partial TOML write."""
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.rosette-tmp-", dir=path.parent)
    temporary = pathlib.Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        try:
            directory_fd = os.open(path.parent, os.O_RDONLY)
        except OSError:
            return
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            temporary.unlink()
        except OSError:
            pass
        raise


def toml_validation_error(content: bytes) -> str | None:
    if b"\0" in content:
        return "contains embedded NUL bytes"
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        return f"is not UTF-8 at byte {error.start}"
    if tomllib is None:
        raise ValueError("cannot safely validate Xenia config: Python tomllib/tomli is unavailable")
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        return f"is invalid TOML: {error}"
    return None


def preflight_xenia_config(bundle_value: str | pathlib.Path) -> dict[str, Any]:
    """Validate the generated bundle config and repair invalid TOML Rosetta-side.

    The source checkout is never consulted or written. A single sibling file
    keeps the most recent malformed bytes for diagnosis, so repeated launches
    do not grow the Xenia run directory or an archive tree.
    """
    bundle = pathlib.Path(bundle_value).expanduser()
    if not bundle.is_dir():
        raise ValueError(f"Xenia config bundle is not a directory: {bundle}")
    config = bundle / "xenia-canary.config.toml"
    backup = bundle / "xenia-canary.config.toml.rosette-invalid"
    if config.is_symlink():
        raise ValueError(f"Xenia config must be a regular non-symlink file: {config}")
    if not config.exists():
        return {"action": "missing", "sha256": None, "bytes": 0, "backup_sha256": None}
    metadata = config.stat()
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"Xenia config must be a regular file: {config}")
    original = config.read_bytes()
    invalid_reason = toml_validation_error(original)
    original_sha256 = hashlib.sha256(original).hexdigest()
    if invalid_reason is None:
        return {"action": "valid", "sha256": original_sha256, "bytes": len(original), "backup_sha256": None}

    if backup.is_symlink() or (backup.exists() and not backup.is_file()):
        raise ValueError(f"Xenia config evidence path is not a regular file: {backup}")
    # Avoid replacing a file that Xenia or another process changed after the
    # validation snapshot. We have not launched the guest yet, so a mismatch
    # indicates an external writer and should be diagnosed, not overwritten.
    if config.read_bytes() != original:
        raise ValueError(f"Xenia config changed during preflight; refusing to replace it: {config}")

    mode = stat.S_IMODE(metadata.st_mode)
    atomic_write_bytes(backup, original, mode)
    clean_defaults = b"# Invalid TOML preserved in xenia-canary.config.toml.rosette-invalid; Xenia may regenerate defaults.\n"
    atomic_write_bytes(config, clean_defaults, mode)
    if toml_validation_error(config.read_bytes()) is not None:
        raise ValueError(f"Rosetta config repair did not produce valid TOML: {config}")
    return {
        "action": "repaired",
        "sha256": original_sha256,
        "bytes": len(original),
        "backup_sha256": hashlib.sha256(original).hexdigest(),
        "reason": invalid_reason,
    }


GPU_RENDER_SETTING_KEYS = ("render_target_path_vulkan", "readback_resolve", "occlusion_query")


def bundle_gpu_render_settings(bundle_value: str | pathlib.Path) -> dict[str, str | None]:
    """Record the render path, readback mode and occlusion-query mode Xenia will actually load.

    A key absent from the config is None: Xenia then uses its own default
    (occlusion_query defaults to "fast"), and the log says so instead of guessing.
    """
    if tomllib is None:
        raise ValueError("cannot record Xenia GPU settings: Python tomllib/tomli is unavailable")
    config_path = pathlib.Path(bundle_value).expanduser() / "xenia-canary.config.toml"
    if not config_path.is_file():
        return {key: None for key in GPU_RENDER_SETTING_KEYS}
    try:
        config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"cannot record Xenia GPU settings from {config_path}: {error}") from error
    gpu = config.get("GPU", {})
    if not isinstance(gpu, dict):
        raise ValueError(f"Xenia GPU table is not a TOML table in {config_path}")
    settings: dict[str, str | None] = {}
    for key in GPU_RENDER_SETTING_KEYS:
        value = gpu.get(key)
        if value is not None and not isinstance(value, str):
            raise ValueError(f"Xenia GPU setting GPU.{key} must be a string in {config_path}")
        settings[key] = value
    return settings


def file_fingerprint(value: str | None, *, hash_file: bool = False) -> dict[str, Any] | None:
    if not value or value == "<none>":
        return None
    path = pathlib.Path(value).expanduser()
    try:
        stat = path.stat()
    except OSError:
        return {"path": str(path), "available": False}
    return {
        "path": str(path.resolve()),
        "available": path.is_file(),
        "size_bytes": stat.st_size if path.is_file() else None,
        "mtime_ns": stat.st_mtime_ns,
        "sha256": sha256_file(path) if hash_file and path.is_file() else None,
    }


def process_start_identity(pid: int) -> str | None:
    """Return the OS start token so PID reuse cannot masquerade as liveness."""
    try:
        result = subprocess.run(
            ["ps", "-p", str(pid), "-o", "lstart="],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def manifest_supervisor_is_live(path: pathlib.Path) -> bool:
    """Return true only when a running manifest still names the same process."""
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
        if manifest.get("status") != "running":
            return False
        pid = int(manifest.get("supervisor_pid", 0))
        expected = manifest.get("supervisor_start_identity")
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return False
    if pid <= 0 or not expected:
        return False
    return process_start_identity(pid) == expected


def prepare_run_slot(run_root: pathlib.Path, slot_name: str) -> pathlib.Path:
    """Reuse one named run directory and prune prior generated run folders."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", slot_name) or slot_name in {".", ".."}:
        raise ValueError(f"invalid run slot name: {slot_name!r}")
    run_dir = run_root / slot_name
    if run_dir.is_symlink():
        raise ValueError(f"run slot must not be a symlink: {run_dir}")
    if run_dir.exists() and not run_dir.is_dir():
        raise ValueError(f"run slot must be a directory: {run_dir}")

    # The stable slot is latest-only. Remove only the manager's own timestamped
    # run directories (identified by their manifest and generated run-ID name);
    # unrelated files such as .DS_Store and unknown directories are untouched.
    run_id_pattern = re.compile(r"\d{8}T\d{6}Z-[0-9a-f]{12}")
    for previous in run_root.iterdir():
        if previous == run_dir or not previous.is_dir() or previous.is_symlink():
            continue
        if not run_id_pattern.fullmatch(previous.name) or not (previous / "manifest.json").is_file():
            continue
        manifest_path = previous / "manifest.json"
        if manifest_supervisor_is_live(manifest_path):
            raise ValueError(f"cannot reuse one run slot while a prior Xenia run is active: {previous}")
        shutil.rmtree(previous)

    run_dir.mkdir(exist_ok=True)
    if run_dir.exists():
        manifest_path = run_dir / "manifest.json"
        if manifest_path.is_file() and manifest_supervisor_is_live(manifest_path):
            raise ValueError(f"cannot overwrite the active Rosetta run slot: {run_dir}")
        # These are the fixed names owned by the run manager. Caller-selected
        # paths retain the normal collision check below and are never removed.
        for name in ("manifest.json", "evidence.json", "summary.md", "rosette-xenia.log", "rosette-xenia.trace.log"):
            artifact = run_dir / name
            if artifact.is_symlink() or artifact.is_file():
                artifact.unlink()
            elif artifact.exists():
                raise ValueError(f"managed run output is not a regular file: {artifact}")
    return run_dir


def canonical_hash(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def current_source_tree_hash(root: pathlib.Path) -> str | None:
    """Recompute the source digest used by build_identity_manifest.py."""
    return current_tree_hash(root, ("ISA", "lib", "src", "pkg", "include"), "rosette-source")


def current_tree_hash(root: pathlib.Path, directories: tuple[str, ...], label: str) -> str | None:
    entries: list[tuple[str, pathlib.Path]] = []
    missing_root = False
    for directory in directories:
        base = root / directory
        if not base.exists():
            missing_root = True
            continue
        for current, dirnames, filenames in os.walk(base):
            current_path = pathlib.Path(current)
            dirnames[:] = sorted(
                name
                for name in dirnames
                if name not in BUILD_IDENTITY_SKIP_DIRS and not (current_path / name).is_symlink()
            )
            for filename in sorted(filenames):
                path = current_path / filename
                if path.is_symlink():
                    continue
                relative = path.relative_to(base).as_posix()
                entries.append((f"{label}/{base.name}/{relative}", path))
    if not entries:
        if label == "rosette-generated" and missing_root:
            return hashlib.sha256(b"rosette-generated-tree\0empty").hexdigest()
        return ZERO_SHA256
    digest = hashlib.sha256()
    for relative, path in sorted(entries, key=lambda entry: entry[0]):
        content_hash = sha256_file(path)
        if content_hash is None:
            return None
        digest.update(relative.encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(content_hash))
        digest.update(b"\0")
    return digest.hexdigest()


def current_build_graph_hash(root: pathlib.Path) -> str | None:
    paths = (pathlib.Path("build.zig"), pathlib.Path("build/Makefile"))
    existing = [path for path in paths if (root / path).is_file()]
    if not existing:
        return ZERO_SHA256
    digest = hashlib.sha256()
    for relative in sorted(existing, key=lambda path: str(root / path)):
        content_hash = sha256_file(root / relative)
        if content_hash is None:
            return None
        digest.update(relative.as_posix().encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(content_hash))
        digest.update(b"\0")
    return digest.hexdigest()


def current_run_systems_hash(root: pathlib.Path) -> str | None:
    paths = (
        pathlib.Path("tools/guest_runtime/scripts/rosette_guest_systems.py"),
        pathlib.Path("tools/guest_runtime/scripts/rosette-guest-run.sh"),
        pathlib.Path("tools/test_guest_run_systems.py"),
    )
    digest = hashlib.sha256()
    for relative in sorted(paths, key=lambda path: path.as_posix()):
        path = root / relative
        content_hash = sha256_file(path)
        if content_hash is None:
            return None
        digest.update(relative.as_posix().encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(content_hash))
        digest.update(b"\0")
    return digest.hexdigest()


def atomic_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex[:8])
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def is_within(path: pathlib.Path, parent: pathlib.Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except (OSError, ValueError):
        return False


def is_read_only_xenia_source_path(path: pathlib.Path, source_root: pathlib.Path) -> bool:
    """Whether path is inside Xenia source and outside Rosetta's data directory."""
    return is_within(path, source_root) and not is_within(path, source_root / ".rosette")


def prepare(args: argparse.Namespace) -> int:
    run_root = pathlib.Path(args.run_root).expanduser()
    source_root = pathlib.Path(args.source_root).expanduser()
    rosette_data_root = source_root / ".rosette"
    if rosette_data_root.is_symlink():
        raise ValueError(f"Rosetta data directory inside Xenia must not be a symlink: {rosette_data_root}")
    if is_read_only_xenia_source_path(run_root, source_root):
        raise ValueError(
            "Rosetta run root must be outside the Xenia checkout or under its .rosette data directory: "
            f"{run_root}"
        )
    if run_root.is_symlink():
        raise ValueError(f"run root must not be a symlink: {run_root}")
    run_root.mkdir(parents=True, exist_ok=True)
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:12]
    run_slot = getattr(args, "run_slot", "")
    run_dir = prepare_run_slot(run_root, run_slot) if run_slot else run_root / run_id

    repo_root = pathlib.Path(args.repo_root).expanduser()
    if args.run_log:
        log_path = pathlib.Path(args.run_log).expanduser()
    else:
        log_path = run_dir / "rosette-xenia.log"
    if args.trace_log:
        trace_path = pathlib.Path(args.trace_log).expanduser()
    else:
        trace_path = run_dir / "rosette-xenia.trace.log"

    for artifact_path in (log_path, trace_path):
        if is_read_only_xenia_source_path(artifact_path, source_root):
            raise ValueError(
                "Rosetta run output must be outside the Xenia checkout or under its .rosette data directory: "
                f"{artifact_path}"
            )
        if artifact_path.exists():
            raise ValueError(f"run output already exists; choose a fresh path to preserve prior evidence: {artifact_path}")
    if log_path.resolve() == trace_path.resolve():
        raise ValueError("detailed log and internal trace must use separate paths")

    if not run_slot:
        run_dir.mkdir()
    for artifact_path in (log_path, trace_path):
        artifact_path.parent.mkdir(parents=True, exist_ok=True)

    build_manifest = repo_root / ".rosette" / "build-identity.json"
    build_manifest_hash = sha256_file(build_manifest)
    profile = {name: os.environ.get(name) for name in PERFORMANCE_ENV if name in os.environ}
    # A title XISO can be several gigabytes. Hashing it on the launch path
    # would delay the very run this record is intended to measure. Exact
    # media hashes may be supplied through ROSETTE_MEDIA_HASH; otherwise path,
    # size and mtime are retained as a lower-cost comparison identity.
    media = file_fingerprint(args.media)
    declared_media_hash = os.environ.get("ROSETTE_XENIA_MEDIA_SHA256", "").strip().lower()
    if declared_media_hash:
        if not re.fullmatch(r"[0-9a-f]{64}", declared_media_hash):
            raise ValueError("ROSETTE_XENIA_MEDIA_SHA256 must be exactly 64 hexadecimal characters")
        if media is None:
            raise ValueError("ROSETTE_XENIA_MEDIA_SHA256 was supplied but no media image is selected")
        media["sha256"] = declared_media_hash
    bundle_path = pathlib.Path(args.bundle).expanduser()
    bundle_config = file_fingerprint(str(bundle_path / "xenia-canary.config.toml"), hash_file=True)
    gpu_render_settings = bundle_gpu_render_settings(bundle_path)
    bundle_settings = file_fingerprint(str(bundle_path / "xconfig.settings"), hash_file=True)
    recent_config = file_fingerprint(str(bundle_path / "recent.toml"), hash_file=True)
    bundle_manifest = file_fingerprint(str(bundle_path / "rosette-xenia-windows.json"), hash_file=True)
    controller_db = file_fingerprint(str(bundle_path / "gamecontrollerdb.txt"), hash_file=True)
    supervisor_start = process_start_identity(args.supervisor_pid)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "status": "running",
        "started_utc": utc_now(),
        "finished_utc": None,
        "supervisor_pid": args.supervisor_pid,
        "supervisor_parent_pid": os.getppid(),
        "supervisor_start_identity": supervisor_start,
        "scenario": args.scenario.strip() or None,
        "host": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "processor": platform.processor() or None,
        },
        "paths": {
            "repo_root": str(repo_root.resolve()),
            "source_root": str(source_root.resolve()),
            "run_dir": str(run_dir.resolve()),
            "run_log": str(log_path.resolve()),
            "trace_log": str(trace_path.resolve()),
            "build_identity": str(build_manifest.resolve()),
            "launcher": str(pathlib.Path(__file__).resolve()),
        },
        "inputs": {
            "bundle": {
                "path": str(bundle_path.resolve()),
                "config": bundle_config,
                "gpu_render_settings": gpu_render_settings,
                "settings": bundle_settings,
                "recent": recent_config,
                "manifest": bundle_manifest,
                "controller_database": controller_db,
            },
            "executable": file_fingerprint(args.executable, hash_file=True),
            "runner": file_fingerprint(args.runner, hash_file=True),
            "media": media,
            "launch_arguments": list(args.launch_arg),
            "xenia_source_root": str(source_root.resolve()),
            "build_identity_sha256": build_manifest_hash,
            "profile": profile,
            "profile_sha256": canonical_hash(profile),
        },
        "evidence": None,
        "runner_exit_status": None,
    }
    manifest_path = run_dir / "manifest.json"
    atomic_json(manifest_path, manifest)
    shell_values = {
        "run_id": run_id,
        "run_dir": str(run_dir),
        "run_log": str(log_path),
        "trace_log": str(trace_path),
        "run_manifest": str(manifest_path),
        "build_identity_sha256": build_manifest_hash or "unavailable",
        "xenia_render_target_path_vulkan": gpu_render_settings["render_target_path_vulkan"] or "<unset>",
        "xenia_readback_resolve": gpu_render_settings["readback_resolve"] or "<unset>",
        "xenia_occlusion_query": gpu_render_settings["occlusion_query"] or "<unset>",
    }
    for name, value in shell_values.items():
        print(f"{name}={shlex.quote(value)}")
    return 0


def find_last(pattern: str, text: str, flags: int = re.MULTILINE | re.IGNORECASE) -> re.Match[str] | None:
    matches = list(re.finditer(pattern, text, flags))
    return matches[-1] if matches else None


def parse_key_values(fragment: str) -> dict[str, int]:
    return {name: int(value) for name, value in re.findall(r"([A-Za-z][A-Za-z0-9_]*)=(\d+)", fragment)}


def parse_log(log_path: pathlib.Path, manifest: dict[str, Any] | None = None) -> dict[str, Any]:
    text = log_path.read_text(encoding="utf-8", errors="replace")
    run_ids = re.findall(r"PE64 RUN CONTEXT: run_id=([A-Za-z0-9_-]+)", text)
    manifest_run_id = manifest.get("run_id") if manifest else None
    run_context_match = bool(manifest_run_id and manifest_run_id in run_ids)

    texture_descriptors = [" ".join(raw.split()).upper() for raw in re.findall(
        r"^\s*(?:w>|warn(?:ing)?\b).*?Texture fetch constant\s*\(([^)]*)\)\s*is completely invalid",
        text,
        re.IGNORECASE | re.MULTILINE,
    )]
    unique_texture_descriptors = sorted(set(texture_descriptors))
    fetch_diagnostics = fetch_constant_diagnostics.summarize_descriptors(texture_descriptors)
    vertex_fetch_examples = fetch_constant_diagnostics.vertex_descriptor_examples(fetch_diagnostics)
    fetch_diagnosis = fetch_constant_diagnostics.diagnosis_text(fetch_diagnostics)

    frame_line = find_last(r"FRAME GENERATION RATE:([^\n]+)", text)
    frame_values: dict[str, Any] = {}
    if frame_line:
        fields = frame_line.group(1)
        def optional_number(pattern: str, cast: Any) -> Any:
            match = re.search(pattern, fields)
            return cast(match.group(1)) if match else None

        frame_values = {
            "picture_frame": optional_number(r"\bpicture_frame=(\d+)", int),
            "picture_fps": optional_number(r"\bpicture_fps=([0-9]+(?:\.[0-9]+)?)", float),
            "first_observed_picture_raw_present": optional_number(r"\bfirst_observed_picture_raw_present=(\d+)", int),
            "initial_to_picture_ms": optional_number(r"\binitial_to_picture_ms=(\d+)", int),
        }
    else:
        frame_values = {"picture_frame": None, "picture_fps": None}

    fps_values = [float(v) for v in re.findall(r"(?<![A-Za-z0-9_])fps=([0-9]+(?:\.[0-9]+)?)", text, re.IGNORECASE)]
    game_loop_fps = fps_values[-1] if fps_values else None

    budget_line = find_last(r"PE64 STEP BUDGET:([^\n]+)", text)
    budget: dict[str, Any] = {}
    if budget_line:
        body = budget_line.group(1)
        m = re.search(r"interpreted=(\d+).*?elapsed=(\d+)s.*?rate\(window/run\)=(\d+)/(\d+) instructions/s", body)
        if m:
            budget = {
                "interpreted_instructions": int(m.group(1)),
                "elapsed_seconds": int(m.group(2)),
                "window_instructions_per_second": int(m.group(3)),
                "run_instructions_per_second": int(m.group(4)),
            }
    frame_cost_line = find_last(r"PE64 FRAME COST:([^\n]+)", text)
    frame_cost: dict[str, Any] = {}
    if frame_cost_line:
        body = frame_cost_line.group(1)
        m = re.search(r"swaps=(\d+).*?instructions_per_swap\(mean_last_32/min/max/lifetime_mean\)=(\d+)/(\d+)/(\d+)/(\d+).*?interpreter_rate=(\d+) instructions/s -> ([0-9.]+) swaps/s possible; 30 swaps/s needs (\d+) instructions/s \(([0-9.]+)x this run\)", body)
        if m:
            frame_cost = {
                "swaps": int(m.group(1)),
                "instructions_per_swap_mean_last_32": int(m.group(2)),
                "instructions_per_swap_min": int(m.group(3)),
                "instructions_per_swap_max": int(m.group(4)),
                "instructions_per_swap_lifetime_mean": int(m.group(5)),
                "interpreter_instructions_per_second": int(m.group(6)),
                "possible_swaps_per_second": float(m.group(7)),
                "instructions_per_second_for_30_fps": int(m.group(8)),
                "required_speedup_for_30_fps": float(m.group(9)),
            }

    fallback_line = find_last(r"PE64 BLOCK JIT FALLBACK OPS:([^\n]+)", text)
    fallback_ops: dict[str, dict[str, int]] = {}
    if fallback_line:
        for name, count, percent, details in re.findall(
            r"\b([A-Za-z][A-Za-z0-9_]*)=(\d+)\((\d+)%([^)]*)\)", fallback_line.group(1)
        ):
            values = parse_key_values(details)
            fallback_ops[name] = {"calls": int(count), "share_percent": int(percent), **values}

    lane_line = find_last(r"PE64 BLOCK JIT LANE:([^\n]+)", text)
    fallback_calls = None
    invalidations = None
    if lane_line:
        match = re.search(r"\bfallback_calls=(\d+)", lane_line.group(1))
        if match:
            fallback_calls = int(match.group(1))
        match = re.search(r"\btlb\(considers/fills/refused/invalidations/flushes\)=([0-9/]+)", lane_line.group(1))
        if match:
            fields = [int(value) for value in match.group(1).split("/")]
            if len(fields) == 5:
                invalidations = fields[3]

    ledger_line = find_last(r"PE64 BLOCK JIT FALLBACK LEDGER:([^\n]+)", text)
    fallback_ledger: dict[str, int] = {}
    if ledger_line:
        fallback_ledger = parse_key_values(ledger_line.group(1))
        reason_match = re.search(r"reasons\(([^)]+)\)=([0-9/]+)", ledger_line.group(1))
        if reason_match:
            reason_names = reason_match.group(1).split("/")
            reason_counts = reason_match.group(2).split("/")
            if len(reason_names) == len(reason_counts):
                fallback_ledger.update({name: int(count) for name, count in zip(reason_names, reason_counts)})

    # In a parallel run the title's threads are workers: their translator's
    # fallbacks, whether their memory accesses take the direct TLB route,
    # and where each one's wall time went are the frame-rate evidence.
    worker_ledger_line = find_last(r"PE64 BLOCK JIT WORKER FALLBACK LEDGER:([^\n]+)", text)
    worker_fallback_ledger: dict[str, int] = {}
    if worker_ledger_line:
        worker_fallback_ledger = parse_key_values(worker_ledger_line.group(1))
        reason_match = re.search(r"reasons\(([^)]+)\)=([0-9/]+)", worker_ledger_line.group(1))
        if reason_match:
            reason_names = reason_match.group(1).split("/")
            reason_counts = reason_match.group(2).split("/")
            if len(reason_names) == len(reason_counts):
                worker_fallback_ledger.update({name: int(count) for name, count in zip(reason_names, reason_counts)})

    worker_tlb_line = find_last(r"PE64 BLOCK JIT WORKER TLB:([^\n]+)", text)
    worker_tlb: dict[str, Any] = {}
    if worker_tlb_line:
        body = worker_tlb_line.group(1)
        route = re.search(r"\bdirect_route=(true|false)", body)
        if route:
            worker_tlb["direct_route"] = route.group(1) == "true"
        for key in ("fills", "refused", "cross_thread_invalidations", "raced_fills_retired"):
            m = re.search(rf"\b{key}=(\d+)", body)
            if m:
                worker_tlb[key] = int(m.group(1))

    # Two FAST IMPORTS lines exist: the precise-time query and, at exit, the
    # C runtime's memcpy/memmove/memset lane. Match each by its own field.
    fast_import_line = find_last(r"PE64 WINDOWS FAST IMPORTS: GetSystemTimePreciseAsFileTime calls=(\d+)", text)
    fast_time_imports = int(fast_import_line.group(1)) if fast_import_line else None
    counter_line = find_last(
        r"PE64 WINDOWS FAST IMPORTS: GetSystemTimePreciseAsFileTime calls=\d+ QueryPerformanceCounter=(\d+) QueryPerformanceFrequency=(\d+)",
        text,
    )
    fast_counter_imports = (
        {"QueryPerformanceCounter": int(counter_line.group(1)), "QueryPerformanceFrequency": int(counter_line.group(2))}
        if counter_line
        else None
    )
    crt_line = find_last(r"PE64 WINDOWS FAST IMPORTS: crt memcpy=(\d+) memmove=(\d+) memset=(\d+)", text)
    fast_crt_imports = (
        {"memcpy": int(crt_line.group(1)), "memmove": int(crt_line.group(2)), "memset": int(crt_line.group(3))}
        if crt_line
        else None
    )

    # Each busy worker's own translator: how far its table grew and why its
    # interpreted steps were interpreted. The last report per slot wins.
    worker_translators: dict[int, dict[str, Any]] = {}
    for m in re.finditer(
        r"PE64 BLOCK JIT WORKER THREAD: slot=(\d+) name='([^'\n]*)' table=(\d+) growths=(\d+) live=(\d+) compiled=(\d+) "
        r"evictions=(\d+) hotness_replacements=(\d+) resets=(\d+) code_mib\(used/reserved\)=(\d+)/(\d+) executions=(\d+) "
        r"retired=(\d+) interpreted\(cold/refused/reset_pending\)=(\d+)/(\d+)/(\d+)",
        text,
    ):
        slot = int(m.group(1))
        worker_translators[slot] = {
            "slot": slot,
            "name": m.group(2),
            "table": int(m.group(3)),
            "growths": int(m.group(4)),
            "live": int(m.group(5)),
            "compiled": int(m.group(6)),
            "evictions": int(m.group(7)),
            "hotness_replacements": int(m.group(8)),
            "resets": int(m.group(9)),
            "code_mib_used": int(m.group(10)),
            "code_mib_reserved": int(m.group(11)),
            "executions": int(m.group(12)),
            "retired": int(m.group(13)),
            "interpreted_cold": int(m.group(14)),
            "interpreted_refused": int(m.group(15)),
            "interpreted_reset_pending": int(m.group(16)),
        }
        line_end = text.find("\n", m.end())
        rest = text[m.end() : line_end if line_end != -1 else len(text)]
        dispatch = re.search(r"dispatch\(entries/relinks/native_hops\)=(\d+)/(\d+)/(\d+) retired_per_dispatch=(\d+)", rest)
        if dispatch:
            worker_translators[slot].update(
                {
                    "dispatch_entries": int(dispatch.group(1)),
                    "dispatch_relinks": int(dispatch.group(2)),
                    "native_hops": int(dispatch.group(3)),
                    "retired_per_dispatch": int(dispatch.group(4)),
                }
            )
        exits = re.search(r"chain_exits\(budget/break/miss\)=(\d+)/(\d+)/(\d+) tlb_fills=(\d+)", rest)
        if exits:
            worker_translators[slot].update(
                {
                    "chain_exits_budget": int(exits.group(1)),
                    "chain_exits_break": int(exits.group(2)),
                    "chain_exits_miss": int(exits.group(3)),
                    "tlb_fills": int(exits.group(4)),
                }
            )

    worker_profiles: list[dict[str, Any]] = []
    for m in re.finditer(r"PE64 HOST PROFILE THREAD slot=(\d+) '([^'\n]*)': samples=(\d+)[^\n]*?wall time: ([^;\n]+)", text):
        shares = {key: float(value) for key, value in re.findall(r"(\w+)=([0-9.]+)%", m.group(4))}
        worker_profiles.append({"slot": int(m.group(1)), "name": m.group(2), "samples": int(m.group(3)), **shares})

    rect_line = find_last(r"RECT EXPAND:([^\n]+)", text)
    rect: dict[str, Any] = {}
    if rect_line:
        body = rect_line.group(1)
        for key in ("rewritten", "transform_refused", "non_vertex_skipped", "already_expanded_skipped", "draws_tagged", "declined_foreign_index", "driver_rejections"):
            m = re.search(rf"\b{key}=(\d+)", body)
            if m:
                rect[key] = int(m.group(1))
        overflow = re.search(r"overflow\(modules/pipelines\)=(\d+)/(\d+)", body)
        if overflow:
            rect["module_overflow"] = int(overflow.group(1))
            rect["pipeline_overflow"] = int(overflow.group(2))

    graphics_route_line = find_last(r"GRAPHICS ROUTE:([^\n]+)", text)
    graphics_route: dict[str, int] = {}
    if graphics_route_line:
        bind = re.search(r"descriptors\(updates/native_writes/binds_forwarded/binds_rejected\)=([0-9/]+)", graphics_route_line.group(1))
        presents = re.search(r"presented_sources\(sampled/transfer/upload/unresolved\)=([0-9/]+)", graphics_route_line.group(1))
        if bind:
            graphics_route.update(zip(("descriptor_updates", "native_descriptor_writes", "binds_forwarded", "binds_rejected"), map(int, bind.group(1).split("/"))))
        if presents:
            graphics_route.update(zip(("sampled_presents", "transfer_presents", "upload_presents", "unresolved_presents"), map(int, presents.group(1).split("/"))))

    # Every Metal-backed driver reports the GPU as its adapter name, so the
    # VULKAN DRIVER line is the only record of which driver rendered.
    # Mesa's driver info has spaces ("Mesa 24.0.0 (LLVM 17.0.6)"), so the
    # fields are delimited by the next key, not by whitespace.
    driver_line = find_last(r"VULKAN DRIVER: name=(.*?) info=(.*?) id=\d+\((\w+)\) api=([0-9.]+)", text)
    vulkan_driver: dict[str, str] = {}
    if driver_line:
        vulkan_driver = {"name": driver_line.group(1), "info": driver_line.group(2), "id": driver_line.group(3), "api": driver_line.group(4)}

    clock_line = find_last(r"PE64 XENIA TIME PLANE:([^\n]+)", text)
    time_plane: dict[str, Any] = {}
    if clock_line:
        body = clock_line.group(1)
        status = re.search(r"\bstatus=([A-Za-z_-]+)", body)
        speed = re.search(r"\bxbox_speed=([0-9]+(?:\.[0-9]+)?)", body)
        window = re.search(r"\bwindow\(host_ms/xbox_ms\)=(\d+)/(\d+)", body)
        time_plane = {
            "status": status.group(1) if status else "unknown",
            "xbox_speed": float(speed.group(1)) if speed else None,
            "host_window_ms": int(window.group(1)) if window else None,
            "xbox_window_ms": int(window.group(2)) if window else None,
        }

    readiness_chains: dict[str, dict[str, Any]] = {}
    for chain_name in ("FIRST FRAME CHAIN", "GUEST OUTPUT CHAIN"):
        chain_lines = text.splitlines()
        header = [
            index
            for index, line in enumerate(chain_lines)
            if chain_name in line and re.search(r"\d+/\d+ observable", line)
        ]
        lines: list[str] = []
        summary_line = chain_lines[header[-1]] if header else ""
        if header:
            for line in chain_lines[header[-1] + 1 :]:
                if chain_name not in line:
                    break
                if "owner=" in line and re.search(r"\b(met|unmet|unobservable)\s*\(", line):
                    lines.append(line)
        stages: dict[str, Any] = {"met": 0, "unmet": 0, "unobservable": 0, "first_unmet": None}
        summary = re.search(
            r"(\d+)/(\d+) observable (?:preconditions|stages) met \((\d+) (?:unobservable|not observable)",
            summary_line,
        )
        if summary:
            stages["met"] = int(summary.group(1))
            stages["unmet"] = max(0, int(summary.group(2)) - int(summary.group(1)))
            stages["unobservable"] = int(summary.group(3))
        for line in lines:
            stage = re.search(r"\b([A-Za-z0-9_]+)\s+owner=([^\s]+)\s+(met|unmet|unobservable)\s*\(", line)
            if stage and stage.group(3) == "unmet" and stages["first_unmet"] is None:
                stages["first_unmet"] = {"stage": stage.group(1), "owner": stage.group(2)}
        if not summary:
            for line in lines:
                stage = re.search(r"\b(met|unmet|unobservable)\s*\(", line)
                if stage:
                    stages[stage.group(1)] += 1
        if lines or summary:
            readiness_chains[chain_name.lower().replace(" ", "_")] = stages

    stage_state = {
        "guest_execution": "observed" if budget else "unobserved",
        "guest_clock": time_plane.get("status", "unobserved"),
        "graphics_initialization": "observed" if graphics_route else "unobserved",
        "content_present": "observed" if (frame_values.get("picture_frame") or 0) > 0 else "unobserved",
        "runtime_run_id": "matched" if run_context_match else ("missing" if manifest_run_id else "no-manifest"),
    }
    if stage_state["guest_clock"] == "stalled":
        stage_state["guest_execution"] = "stalled"

    findings: list[str] = []
    unknowns: list[str] = []
    if len(texture_descriptors):
        findings.append(f"{len(texture_descriptors)} invalid texture fetch warning(s), {len(unique_texture_descriptors)} distinct descriptors")
    if fetch_diagnosis:
        findings.append(fetch_diagnosis)
    if fetch_diagnostics["warning_type_counts"].get("vertex"):
        unknowns.append("the log does not identify why a texture binding requested a vertex-typed fetch slot")
    if invalidations is not None and invalidations:
        findings.append(f"{invalidations} block-JIT TLB invalidation(s)")
    if rect.get("transform_refused", 0):
        findings.append(f"{rect['transform_refused']} rectangle shader transform refusal(s)")
    if rect.get("declined_foreign_index", 0):
        findings.append(f"{rect['declined_foreign_index']} rectangle-shaped draws declined because of foreign indices")
    if rect.get("driver_rejections", 0):
        findings.append(f"{rect['driver_rejections']} driver draw rejection(s)")
    if fallback_ledger.get("missing_native_template", 0):
        findings.append(f"{fallback_ledger['missing_native_template']} native-template fallback(s)")
    elif fallback_calls and "missing_native_template" not in fallback_ledger:
        unknowns.append("fallback causes and sampled costs are not present in this log")
    if invalidations is None:
        unknowns.append("block-JIT invalidation count is not present in this log")
    for translator in worker_translators.values():
        interpreted = translator["interpreted_cold"] + translator["interpreted_refused"] + translator["interpreted_reset_pending"]
        total = interpreted + translator["retired"]
        # An interpreted step costs about a hundred translated ones, so one
        # percent interpreted is already most of a thread's time.
        if total and interpreted * 100 >= total:
            findings.append(
                f"worker '{translator['name']}' interpreted {interpreted * 100 / total:.1f}% of its instructions "
                f"(cold {translator['interpreted_cold']}, refused {translator['interpreted_refused']}) with a {translator['table']}-slot table "
                f"after {translator['growths']} growth(s)"
            )
    if worker_tlb.get("direct_route") is False:
        findings.append("the parallel direct TLB route is off: every translated worker access took the coordinated helper")
    elif worker_tlb.get("direct_route") and not worker_tlb.get("fills"):
        findings.append("the parallel direct TLB route is on but no worker page was admitted")
    if not budget:
        unknowns.append("guest instruction throughput is not present in this log")
    if frame_values.get("picture_frame") is None:
        unknowns.append("completed picture-frame evidence is not present in this log")
    if not graphics_route:
        unknowns.append("graphics route evidence is not present in this log")
    for chain_name, stage_counts in readiness_chains.items():
        if stage_counts.get("first_unmet"):
            first = stage_counts["first_unmet"]
            findings.append(f"earliest unmet stage in {chain_name}: {first['stage']} (owner {first['owner']})")
        if stage_counts.get("unobservable", 0):
            unknowns.append(f"{stage_counts['unobservable']} unobservable stage(s) in {chain_name}")

    return {
        "schema_version": SCHEMA_VERSION,
        "log": {"path": str(log_path.resolve()), "sha256": sha256_file(log_path), "bytes": log_path.stat().st_size},
        "run_id": manifest_run_id,
        "runtime_run_id_matches": run_context_match,
        "runtime_run_ids": sorted(set(run_ids)),
        "metrics": {
            "frame": frame_values,
            "game_loop_fps": game_loop_fps,
            "step_budget": budget,
            "frame_cost": frame_cost,
            "fallback_calls": fallback_calls,
            "fallback_ops": fallback_ops,
            "fallback_ledger": fallback_ledger,
            "worker_fallback_ledger": worker_fallback_ledger,
            "worker_tlb": worker_tlb,
            "fast_time_imports": fast_time_imports,
            "fast_crt_imports": fast_crt_imports,
            "fast_counter_imports": fast_counter_imports,
            "worker_translators": sorted(worker_translators.values(), key=lambda row: row["slot"]),
            "worker_profiles": worker_profiles,
            "block_jit_tlb_invalidations": invalidations,
            "invalid_texture_warning_lines": len(texture_descriptors),
            "invalid_texture_distinct_descriptors": len(unique_texture_descriptors),
            "invalid_texture_descriptors": unique_texture_descriptors,
            "invalid_texture_descriptor_type_counts": fetch_diagnostics["warning_type_counts"],
            "invalid_texture_distinct_descriptor_type_counts": fetch_diagnostics["distinct_type_counts"],
            "invalid_texture_unparsed_warning_lines": fetch_diagnostics["unparsed_warning_lines"],
            "invalid_texture_descriptor_diagnostics": fetch_diagnostics["descriptors"],
            "vertex_fetch_descriptor_examples": vertex_fetch_examples,
            "rectangle_expansion": rect,
            "vulkan_driver": vulkan_driver,
            "graphics_route": graphics_route,
            "time_plane": time_plane,
            "readiness_chains": readiness_chains,
        },
        "readiness": stage_state,
        "liveness": {
            "status": "advancing" if budget.get("run_instructions_per_second", 0) > 0 else "unknown",
            "stalled_markers": len(re.findall(r"PE64 STALL: no observable progress", text)),
            "time_plane": time_plane.get("status", "unknown"),
        },
        "findings": findings,
        "unknowns": unknowns,
        "promotion": {
            "status": "blocked" if findings or unknowns else "eligible_pending_artifact_checks",
            "findings": findings,
            "unknowns": unknowns,
        },
    }


def finalize(args: argparse.Namespace) -> int:
    manifest_path = pathlib.Path(args.manifest).expanduser()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    log_path = pathlib.Path(args.log).expanduser()
    evidence = parse_log(log_path, manifest)
    capture_request = (manifest.get("inputs", {}).get("profile", {}).get("ROSETTE_VULKAN_GFXR") or "off").strip()
    run_dir = pathlib.Path(manifest["paths"]["run_dir"])
    gfxr_path = run_dir / "rosette-vulkan.gfxr"
    gfxr_log_path = run_dir / "gfxrecon.log"
    try:
        gfxr_bytes = gfxr_path.stat().st_size
    except OSError:
        gfxr_bytes = 0
    try:
        gfxr_log_bytes = gfxr_log_path.stat().st_size
    except OSError:
        gfxr_log_bytes = 0
    capture_artifacts = gfxr_artifacts(run_dir)
    usable_captures = [item for item in capture_artifacts if item["usable"]]
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    layer_active = "enabled on the real instance" in log_text or "VULKAN CAPTURE: active mode=" in log_text
    if usable_captures:
        capture_status = "artifact_present"
    elif capture_request.lower() in ("", "0", "off"):
        capture_status = "not_requested"
    elif not layer_active:
        capture_status = "requested_but_layer_not_active"
    else:
        capture_status = "layer_active_but_no_artifact"
    capture = {
        "request": capture_request,
        "status": capture_status,
        "layer_active": layer_active,
        "capture_path": str(gfxr_path),
        "capture_bytes": gfxr_bytes,
        "artifacts": capture_artifacts,
        "usable_artifact_count": len(usable_captures),
        "trimmed_artifact_count": sum(item["kind"] == "trimmed" for item in usable_captures),
        "usable_artifact_bytes": sum(item["bytes"] for item in usable_captures),
        "capture_log_path": str(gfxr_log_path),
        "capture_log_bytes": gfxr_log_bytes,
        "swapchain_png_probe_is_gfxr": False,
    }
    evidence["vulkan_capture"] = capture
    if capture_status != "artifact_present":
        evidence.setdefault("unknowns", []).append(
            "GFXReconstruct capture "
            f"status={capture_status} request={capture_request or 'off'}; the swapchain PNG/readback probe cannot identify which render pass causes fog or exposure errors."
        )
    manifest["status"] = "complete" if args.exit_status == 0 else "failed"
    manifest["finished_utc"] = utc_now()
    manifest["runner_exit_status"] = args.exit_status
    manifest["evidence"] = evidence
    atomic_json(manifest_path, manifest)
    run_dir = pathlib.Path(manifest["paths"]["run_dir"])
    atomic_json(run_dir / "evidence.json", evidence)
    (run_dir / "summary.md").write_text(render_summary(manifest, evidence), encoding="utf-8")
    print(f"Rosette Xenia run evidence: run_id={manifest['run_id']} promotion={evidence['promotion']['status']} log={log_path}")
    return 0


def render_summary(manifest: dict[str, Any], evidence: dict[str, Any]) -> str:
    metrics = evidence["metrics"]
    graphics = metrics.get("graphics_route", {})
    rectangle = metrics.get("rectangle_expansion", {})
    fallback = metrics.get("fallback_ledger", {})
    worker_fallback = metrics.get("worker_fallback_ledger", {})
    worker_tlb = metrics.get("worker_tlb", {})
    vulkan_capture = evidence.get("vulkan_capture", {})

    def translated_share(profile: dict[str, Any]) -> float:
        return profile.get("translated_title", 0.0) + profile.get("translated_xenia", 0.0)

    busiest_workers = sorted(metrics.get("worker_profiles", []), key=translated_share, reverse=True)[:6]
    lines = [
        f"# Rosette Xenia run {manifest['run_id']}",
        "",
        f"- Status: {manifest['status']} (runner exit {manifest['runner_exit_status']})",
        f"- Started: {manifest['started_utc']}",
        f"- Finished: {manifest['finished_utc']}",
        f"- Scenario: {manifest.get('scenario') or 'unspecified'}",
        f"- Build identity SHA-256: {manifest['inputs'].get('build_identity_sha256') or 'unavailable'}",
        f"- Promotion: {evidence['promotion']['status']}",
        "",
        "## Readiness and performance",
        "",
        f"- Runtime run ID matched: {evidence['runtime_run_id_matches']}",
        f"- Readiness: {json.dumps(evidence['readiness'], sort_keys=True)}",
        f"- Frame generation: {metrics['frame'].get('picture_fps')} FPS at frame {metrics['frame'].get('picture_frame')}",
        f"- Run instruction rate: {metrics['step_budget'].get('run_instructions_per_second')} instructions/s",
        f"- Estimated 30 FPS requirement: {metrics['frame_cost'].get('required_speedup_for_30_fps')}x current rate",
        f"- Liveness / guest clock: {evidence['liveness'].get('status')} / {evidence['liveness'].get('time_plane')}",
        f"- Invalid textures: {metrics['invalid_texture_warning_lines']} warnings / {metrics['invalid_texture_distinct_descriptors']} descriptors",
        f"- Invalid texture fetch type counts (warning lines): {json.dumps(metrics['invalid_texture_descriptor_type_counts'], sort_keys=True)}",
        *[
            "- Vertex-fetch example from texture warning: "
            f"address=0x{example['vertex_fetch']['address_bytes']:08X} "
            f"size={example['vertex_fetch']['size_words']} words "
            f"endian-code={example['vertex_fetch']['endian_code']} "
            f"trailing-words-zero={example['trailing_words_zero']}"
            for example in metrics.get("vertex_fetch_descriptor_examples", [])[:1]
        ],
        f"- Block JIT fallbacks: {metrics['fallback_calls']}; TLB invalidations: {metrics['block_jit_tlb_invalidations']}",
        f"- Fallback reasons (missing template / hook observation / vector policy): {fallback.get('missing_native_template')} / {fallback.get('hook_observation')} / {fallback.get('vector_policy_disabled')}",
        f"- Worker translation: direct TLB route {worker_tlb.get('direct_route')}; fills {worker_tlb.get('fills')}; fallback reasons (missing template / hook observation / vector policy): {worker_fallback.get('missing_native_template')} / {worker_fallback.get('hook_observation')} / {worker_fallback.get('vector_policy_disabled')}",
        f"- Lock-free precise-time imports: {metrics.get('fast_time_imports')}",
        f"- Lock-free C runtime imports (memcpy/memmove/memset): {json.dumps(metrics.get('fast_crt_imports'), sort_keys=True)}",
        f"- Lock-free performance-counter imports: {json.dumps(metrics.get('fast_counter_imports'), sort_keys=True)}",
        *[
            f"- Worker translator: slot {row['slot']} '{row['name']}' table={row['table']} growths={row['growths']} "
            f"evictions={row['evictions']} hotness_replacements={row['hotness_replacements']} "
            f"interpreted(cold/refused/reset)={row['interpreted_cold']}/{row['interpreted_refused']}/{row['interpreted_reset_pending']} "
            f"retired={row['retired']}"
            + (
                f" dispatch(entries/relinks/native_hops)={row['dispatch_entries']}/{row['dispatch_relinks']}/{row['native_hops']} "
                f"retired_per_dispatch={row['retired_per_dispatch']}"
                if "dispatch_entries" in row
                else ""
            )
            + (
                f" chain_exits(budget/break/miss)={row['chain_exits_budget']}/{row['chain_exits_break']}/{row['chain_exits_miss']} "
                f"tlb_fills={row['tlb_fills']}"
                if "chain_exits_budget" in row
                else ""
            )
            for row in sorted(
                metrics.get("worker_translators", []),
                key=lambda row: row["interpreted_cold"] + row["interpreted_refused"] + row["interpreted_reset_pending"],
                reverse=True,
            )[:4]
        ],
        *[
            f"- Worker wall time: slot {profile['slot']} '{profile['name']}' translated={translated_share(profile):.1f}% "
            f"rosette={profile.get('rosette', 0.0):.1f}% waits={profile.get('system_and_waits', 0.0):.1f}% samples={profile['samples']}"
            for profile in busiest_workers
        ],
        f"- Vulkan driver: {metrics.get('vulkan_driver', {}).get('name', 'unrecorded')} {metrics.get('vulkan_driver', {}).get('info', '')} (Vulkan {metrics.get('vulkan_driver', {}).get('api', '?')})",
        f"- Graphics binds forwarded / rejected: {graphics.get('binds_forwarded')} / {graphics.get('binds_rejected')}; unresolved presents: {graphics.get('unresolved_presents')}",
        f"- Rectangle draws tagged / foreign-index declined / transform refused: {rectangle.get('draws_tagged')} / {rectangle.get('declined_foreign_index')} / {rectangle.get('transform_refused')}",
        "",
        "## Findings",
        "",
    ]
    if vulkan_capture:
        lines += [
            "",
            "## Vulkan render capture",
            "",
            f"- GFXReconstruct: {vulkan_capture.get('status')} (requested={vulkan_capture.get('request') or 'off'}, layer_active={vulkan_capture.get('layer_active')})",
            f"- Capture artifacts: {vulkan_capture.get('usable_artifact_count', 0)} usable, {vulkan_capture.get('trimmed_artifact_count', 0)} trimmed, {vulkan_capture.get('usable_artifact_bytes', 0)} bytes total",
            f"- Configured capture path: {vulkan_capture.get('capture_path')} ({vulkan_capture.get('capture_bytes')} bytes)",
            f"- Layer log: {vulkan_capture.get('capture_log_path')} ({vulkan_capture.get('capture_log_bytes')} bytes)",
            "- Fog/exposure pass attribution requires the `.gfxr` artifact; the swapchain probe is not a render-pass capture.",
        ]
    lines.extend(f"- {finding}" for finding in (evidence.get("findings") or ["No measured blockers in the available log."]))
    lines += ["", "## Unknown measurements", ""]
    lines.extend(f"- {item}" for item in (evidence.get("unknowns") or ["None in the available log."]))
    lines += ["", "Missing markers are left unknown; the log does not prove an unobserved stage failed.", ""]
    return "\n".join(lines)


def compare_runs(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    mismatches: list[str] = []
    if not left.get("scenario") or left.get("scenario") == "unspecified":
        mismatches.append("left run has no explicit scenario label")
    if not right.get("scenario") or right.get("scenario") == "unspecified":
        mismatches.append("right run has no explicit scenario label")
    if left.get("scenario") != right.get("scenario"):
        mismatches.append("scenario labels differ")
    for field in ("system", "release", "machine"):
        if left.get("host", {}).get(field) != right.get("host", {}).get(field):
            mismatches.append(f"host {field} differs")
    for field in ("profile_sha256",):
        if left.get("inputs", {}).get(field) != right.get("inputs", {}).get(field):
            mismatches.append("runtime settings profile differs")
    left_inputs = left.get("inputs", {})
    right_inputs = right.get("inputs", {})
    executable_left = (left_inputs.get("executable") or {}).get("sha256")
    executable_right = (right_inputs.get("executable") or {}).get("sha256")
    if not executable_left or executable_left != executable_right:
        mismatches.append("Xenia executable identity differs or is unavailable")

    left_media = left_inputs.get("media")
    right_media = right_inputs.get("media")
    media_identity_basis = "none"
    if left_media is None or right_media is None:
        if left_media is not right_media:
            mismatches.append("media presence differs")
    else:
        left_media_hash = left_media.get("sha256")
        right_media_hash = right_media.get("sha256")
        if left_media_hash or right_media_hash:
            if not left_media_hash or left_media_hash != right_media_hash:
                mismatches.append("media content hash differs or is unavailable")
            else:
                media_identity_basis = "sha256"
        else:
            media_identity_basis = "canonical path, size and modification time"
            for field in ("path", "size_bytes", "mtime_ns"):
                if left_media.get(field) != right_media.get(field):
                    mismatches.append(f"media {field} differs or is unavailable")

    for field, label in (
        ("config", "bundle configuration"),
        ("settings", "Xenia settings file"),
        ("recent", "recent title configuration"),
        ("manifest", "bundle build manifest"),
        ("controller_database", "controller database"),
    ):
        lv = ((left_inputs.get("bundle") or {}).get(field) or {}).get("sha256")
        rv = ((right_inputs.get("bundle") or {}).get(field) or {}).get("sha256")
        if not lv or lv != rv:
            mismatches.append(f"{label} identity differs or is unavailable")
    if left_inputs.get("launch_arguments") != right_inputs.get("launch_arguments"):
        mismatches.append("guest launch arguments differ")

    left_metrics = (left.get("evidence") or {}).get("metrics", {})
    right_metrics = (right.get("evidence") or {}).get("metrics", {})
    metric_pairs = {
        "picture_fps": (left_metrics.get("frame", {}).get("picture_fps"), right_metrics.get("frame", {}).get("picture_fps")),
        "run_instructions_per_second": (left_metrics.get("step_budget", {}).get("run_instructions_per_second"), right_metrics.get("step_budget", {}).get("run_instructions_per_second")),
        "invalid_texture_distinct_descriptors": (left_metrics.get("invalid_texture_distinct_descriptors"), right_metrics.get("invalid_texture_distinct_descriptors")),
        "block_jit_tlb_invalidations": (left_metrics.get("block_jit_tlb_invalidations"), right_metrics.get("block_jit_tlb_invalidations")),
        "fallback_calls": (left_metrics.get("fallback_calls"), right_metrics.get("fallback_calls")),
        "declined_foreign_index": (left_metrics.get("rectangle_expansion", {}).get("declined_foreign_index"), right_metrics.get("rectangle_expansion", {}).get("declined_foreign_index")),
    }
    deltas = {}
    for name, (before, after) in metric_pairs.items():
        deltas[name] = {"before": before, "after": after, "delta": (after - before) if isinstance(before, (int, float)) and isinstance(after, (int, float)) else None}
    return {
        "comparable": not mismatches,
        "valid_for_performance_claim": not mismatches,
        "reasons_not_comparable": mismatches,
        "left_run_id": left.get("run_id"),
        "right_run_id": right.get("run_id"),
        "media_identity_basis": media_identity_basis,
        "software_versions": {
            "left_build_identity_sha256": left_inputs.get("build_identity_sha256"),
            "right_build_identity_sha256": right_inputs.get("build_identity_sha256"),
            "left_runner_sha256": (left_inputs.get("runner") or {}).get("sha256"),
            "right_runner_sha256": (right_inputs.get("runner") or {}).get("sha256"),
            "rosette_implementation_changed": (
                left_inputs.get("build_identity_sha256") != right_inputs.get("build_identity_sha256")
                or (left_inputs.get("runner") or {}).get("sha256") != (right_inputs.get("runner") or {}).get("sha256")
            ),
        },
        "deltas": deltas,
    }


def load_manifest(path: str) -> dict[str, Any]:
    return json.loads(pathlib.Path(path).expanduser().read_text(encoding="utf-8"))


def compare_command(args: argparse.Namespace) -> int:
    left = load_manifest(args.left)
    right = load_manifest(args.right)
    comparison = compare_runs(left, right)
    rendered = json.dumps(comparison, indent=2, sort_keys=True) + "\n"
    if args.output:
        pathlib.Path(args.output).expanduser().write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)
    return 0


def manifest_artifact_gate(manifest: dict[str, Any], root: pathlib.Path) -> list[str]:
    findings: list[str] = []
    identity_path = root / ".rosette" / "build-identity.json"
    census_path = root / ".rosette" / "test-census.json"
    shell_update_path = root / ".rosette" / "shell-update.json"
    for path in (identity_path, census_path, shell_update_path):
        if not path.is_file():
            findings.append(f"missing verification artifact: {path.name}")
    if identity_path.is_file():
        identity_hash = sha256_file(identity_path)
        if identity_hash != manifest.get("inputs", {}).get("build_identity_sha256"):
            findings.append("build identity changed after the run; runtime evidence is stale for this build")
        identity = json.loads(identity_path.read_text(encoding="utf-8"))
        source_hash = identity.get("rosette", {}).get("source_tree", {}).get("hash")
        if not source_hash or current_source_tree_hash(root) != source_hash:
            findings.append("Rosetta source tree differs from or cannot be checked against the recorded build identity")
        generated_hash = identity.get("rosette", {}).get("generated_tree", {}).get("hash")
        if not generated_hash or current_tree_hash(
            root,
            ("include/generated", "pkg/generated", "src/generated", "build/generated", "zig-out/generated"),
            "rosette-generated",
        ) != generated_hash:
            findings.append("Rosetta generated inputs differ from or cannot be checked against the recorded build identity")
        build_graph_hash = identity.get("rosette", {}).get("build_graph", {}).get("hash")
        if not build_graph_hash or current_build_graph_hash(root) != build_graph_hash:
            findings.append("Rosetta build graph differs from or cannot be checked against the recorded build identity")
        vendor_hash = identity.get("rosette", {}).get("vendor_libraries", {}).get("hash")
        if not vendor_hash or current_tree_hash(root, ("third_party",), "rosette-vendor") != vendor_hash:
            findings.append("Rosetta vendor sources differ from or cannot be checked against the recorded build identity")
        run_system_artifact = identity.get("artifacts", {}).get("xenia_run_systems", {})
        if run_system_artifact:
            current_systems_hash = current_run_systems_hash(root)
            if not run_system_artifact.get("available") or current_systems_hash != run_system_artifact.get("hash"):
                findings.append("run supervisor/evidence tooling differs from the recorded build identity")
    if census_path.is_file():
        census = json.loads(census_path.read_text(encoding="utf-8"))
        execution = census.get("execution", {})
        test_hash = sha256_file(census_path)
        shell_update = json.loads(shell_update_path.read_text(encoding="utf-8")) if shell_update_path.is_file() else {}
        if execution.get("exit_code") != 0 or not execution.get("run_artifact_count_matches", False) or not census.get("contract", {}).get("authentic_ready", False):
            findings.append("Zig test census is not complete and passing")
        if shell_update.get("test_census_sha256") != test_hash:
            findings.append("global shell update does not record the current Zig test census")
        verification = shell_update.get("verification") or {}
        verification_mode = verification.get("mode")
        if verification_mode in ("incremental", "relink"):
            identity_source_hash = (
                identity_path.is_file()
                and json.loads(identity_path.read_text(encoding="utf-8"))
                .get("rosette", {})
                .get("source_tree", {})
                .get("hash")
            )
            if not verification.get("source_tree_complete") or verification.get("source_tree_sha256") != identity_source_hash:
                findings.append("shell update verification does not match the build identity's exact Rosetta source tree")
            checks = verification.get("checks") or []
            if any(item.get("exit_code") != 0 for item in checks if isinstance(item, dict)):
                findings.append("a focused shell update check did not pass")
            if verification_mode == "incremental":
                required_checks = {
                    "elf-processor-process-impl": {"elf-check"},
                    "elf-processor": {"elf-check"},
                    "macho-processor": {"macho-processor-check"},
                }.get(verification.get("scope"))
                passed_checks = {
                    item.get("name")
                    for item in checks
                    if isinstance(item, dict) and item.get("exit_code") == 0
                }
                if required_checks is None or not required_checks.issubset(passed_checks):
                    findings.append("focused shell update verification is missing its required processor regression suite")
            elif verification.get("scope") != "unchanged-source-relink":
                findings.append("relink verification does not prove that source inputs were unchanged")
    if shell_update_path.is_file():
        shell_update = json.loads(shell_update_path.read_text(encoding="utf-8"))
        if not shell_update.get("installed_matches_built", False):
            findings.append("installed global shell does not match the built shell helper")
    evidence = manifest.get("evidence") or {}
    if evidence.get("promotion", {}).get("status") != "eligible_pending_artifact_checks":
        findings.extend(evidence.get("promotion", {}).get("findings", []))
        findings.extend(evidence.get("promotion", {}).get("unknowns", []))
    if manifest.get("status") != "complete" or manifest.get("runner_exit_status") != 0:
        findings.append("runtime run did not complete successfully")
    if not evidence.get("runtime_run_id_matches", False):
        findings.append("runtime log does not carry the manifest run ID")
    return list(dict.fromkeys(findings))


def gate_command(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    findings = manifest_artifact_gate(manifest, pathlib.Path(args.root).expanduser())
    status = "blocked" if findings else "eligible"
    result = {"run_id": manifest.get("run_id"), "status": status, "findings": findings}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if findings else 0


def status_command(args: argparse.Namespace) -> int:
    run_root = pathlib.Path(args.run_root).expanduser()
    rows: list[dict[str, Any]] = []
    for path in sorted(run_root.glob("*/manifest.json")):
        try:
            manifest = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        state = manifest.get("status", "unknown")
        alive = False
        identity_verified: bool | None = None
        if state == "running":
            pid = manifest.get("supervisor_pid")
            if isinstance(pid, int) and pid > 1:
                try:
                    os.kill(pid, 0)
                    alive = True
                except ProcessLookupError:
                    alive = False
                except PermissionError:
                    alive = True
                expected_start = manifest.get("supervisor_start_identity")
                current_start = process_start_identity(pid) if alive else None
                if expected_start and current_start:
                    identity_verified = expected_start == current_start
                    if not identity_verified:
                        alive = False
                elif alive:
                    identity_verified = None
            state = ("running" if identity_verified is not False else "stale") if alive else "stale"
        rows.append({
            "run_id": manifest.get("run_id"),
            "state": state,
            "scenario": manifest.get("scenario"),
            "started_utc": manifest.get("started_utc"),
            "supervisor_pid": manifest.get("supervisor_pid"),
            "supervisor_parent_pid": manifest.get("supervisor_parent_pid"),
            "supervisor_identity_verified": identity_verified,
            "run_log": manifest.get("paths", {}).get("run_log"),
            "manifest": str(path),
        })
    print(json.dumps({"run_root": str(run_root.resolve()), "runs": rows}, indent=2, sort_keys=True))
    return 0


def preflight_config_command(args: argparse.Namespace) -> int:
    result = preflight_xenia_config(args.bundle)
    print("\t".join((
        str(result["action"]),
        str(result["sha256"] or "-"),
        str(result["bytes"]),
        str(result["backup_sha256"] or "-"),
        str(result.get("reason", "-")).replace("\t", " ").replace("\n", " "),
    )))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser("prepare", help="create a Rosetta-side run manifest")
    prepare_parser.add_argument("--run-root", required=True)
    prepare_parser.add_argument("--run-slot", default="", help="reuse this latest-only directory under the run root")
    prepare_parser.add_argument("--repo-root", required=True)
    prepare_parser.add_argument("--source-root", required=True)
    prepare_parser.add_argument("--bundle", required=True)
    prepare_parser.add_argument("--executable", required=True)
    prepare_parser.add_argument("--runner", required=True)
    prepare_parser.add_argument("--media", default="")
    prepare_parser.add_argument("--run-log", default="")
    prepare_parser.add_argument("--trace-log", default="")
    prepare_parser.add_argument("--scenario", default="unspecified")
    prepare_parser.add_argument("--supervisor-pid", type=int, required=True)
    prepare_parser.add_argument("--launch-arg", action="append", default=[])
    prepare_parser.set_defaults(handler=prepare)

    finalize_parser = subparsers.add_parser("finalize", help="parse a completed run and update its manifest")
    finalize_parser.add_argument("--manifest", required=True)
    finalize_parser.add_argument("--log", required=True)
    finalize_parser.add_argument("--exit-status", type=int, required=True)
    finalize_parser.set_defaults(handler=finalize)

    compare_parser = subparsers.add_parser("compare", help="compare two runs only when their capture profiles match")
    compare_parser.add_argument("--left", required=True)
    compare_parser.add_argument("--right", required=True)
    compare_parser.add_argument("--output", default="")
    compare_parser.set_defaults(handler=compare_command)

    gate_parser = subparsers.add_parser("gate", help="check runtime evidence and current build/test/shell artifacts")
    gate_parser.add_argument("--manifest", required=True)
    gate_parser.add_argument("--root", required=True)
    gate_parser.set_defaults(handler=gate_command)

    status_parser = subparsers.add_parser("status", help="read active and stale run supervisors without signalling them")
    status_parser.add_argument("--run-root", required=True)
    status_parser.set_defaults(handler=status_command)

    preflight_parser = subparsers.add_parser(
        "preflight-config",
        help="validate and Rosetta-side repair the generated Xenia bundle TOML before launch",
    )
    preflight_parser.add_argument("--bundle", required=True)
    preflight_parser.set_defaults(handler=preflight_config_command)

    args = parser.parse_args()
    try:
        return args.handler(args)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"rosette-xenia-systems: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
