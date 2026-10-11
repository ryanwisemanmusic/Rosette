#!/usr/bin/env python3
"""Create a read-only inventory of GFXReconstruct capture containers.

This calls only `gfxrecon-info`: it reads capture metadata and does not replay
the Vulkan stream or execute captured shaders. Hashes and reports are written
only below the explicit Rosette-owned `--out` directory.

    python3 tools/vulkan/gfxr_inventory.py CAPTURE.gfxr [...] \\
        --info-tool "$VULKAN_SDK/bin/gfxrecon-info" --out DIR \\
        [--capture-log gfxrecon.log]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
from typing import Any


def _first(pattern: str, text: str) -> str | None:
    match = re.search(pattern, text, re.MULTILINE)
    return match.group(1).strip() if match else None


def _first_int(pattern: str, text: str) -> int | None:
    match = re.search(pattern, text)
    return int(match.group(1)) if match else None


def parse_info(text: str) -> dict[str, Any]:
    frame = re.search(r"Total frames:\s*(\d+)(?:\s*\(trimmed frame range\s*(\d+)-(\d+)\))?", text)
    return {
        "total_frames": int(frame.group(1)) if frame else None,
        "frame_start": int(frame.group(2)) if frame and frame.group(2) else None,
        "frame_end": int(frame.group(3)) if frame and frame.group(3) else None,
        "resolution": _first(r"Used resolutions:\s*([^\n]+)", text),
        "device_name": _first(r"^\s*Device name:\s*([^\n]+)", text),
        "api_version": _first(r"^\s*API version:\s*\d+\s*\(([^)]+)\)", text),
        "target_api_version": _first(r"^\s*Target API version:\s*\d+\s*\(([^)]+)\)", text),
        "graphics_pipelines": _first_int(r"Total graphics pipelines:\s*(\d+)", text),
        "compute_pipelines": _first_int(r"Total compute pipelines:\s*(\d+)", text),
        "memory_allocations": _first_int(r"Total allocations:\s*(\d+)", text),
        "gfxrecon_version": _first(r"GFXR version:\s*([^\n]+)", text),
        "capture_timestamp": _first(r"Capture timestamp:\s*([^\n]+)", text),
        "compression": _first(r"Compression format:\s*([^\n]+)", text),
    }


def parse_capture_log(text: str) -> dict[str, dict[str, Any]]:
    """Associate sequential GFXReconstruct save/finish messages by filename."""
    rows: dict[str, dict[str, Any]] = {}
    active: str | None = None
    for line in text.splitlines():
        recording = re.search(r"Recording graphics API capture to\s+(.+?\.gfxr)\s*$", line)
        if recording:
            active = pathlib.Path(recording.group(1)).name
            rows.setdefault(active, {"recorded": True, "finished": False})
        if active is None:
            continue
        memory = re.search(r"WriteResourceMemoryState\(\).*saved in\s+(\d+)\s+ms", line)
        if memory:
            rows[active]["resource_memory_state_ms"] = int(memory.group(1))
        state = re.search(r"WriteState\(\).*saved in\s+(\d+)\s+ms", line)
        if state:
            rows[active]["state_ms"] = int(state.group(1))
        if "Finished recording graphics API capture" in line:
            rows[active]["finished"] = True
            active = None
    return rows


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory_capture(path: pathlib.Path, info_tool: pathlib.Path, log_rows: dict[str, dict[str, Any]]) -> dict[str, Any]:
    resolved = path.resolve()
    result = subprocess.run([str(info_tool), str(resolved)], check=False, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"gfxrecon-info failed for {resolved}: {result.stderr[-2000:]}")
    return {
        "name": resolved.name,
        "path": str(resolved),
        "bytes": resolved.stat().st_size,
        "sha256": sha256_file(resolved),
        "container": parse_info(result.stdout + "\n" + result.stderr),
        "capture_log": log_rows.get(resolved.name, {"recorded": None, "finished": None}),
    }


def render_markdown(manifest: dict[str, Any]) -> str:
    lines = [
        "# GFXReconstruct capture inventory",
        "",
        manifest["scope"],
        "",
        f"- Captures: {len(manifest['captures'])}",
        f"- Total bytes: {manifest['total_bytes']}",
        f"- Completed in GFXReconstruct log: {manifest['completed_count']}",
        "",
        "| Frame | Size | Graphics pipelines | Compute pipelines | Timestamp | File |",
        "| ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for row in manifest["captures"]:
        container = row["container"]
        frame = container["frame_start"]
        lines.append(
            f"| {frame if frame is not None else 'unknown'} | {row['bytes']} "
            f"| {container['graphics_pipelines'] if container['graphics_pipelines'] is not None else 'unknown'} "
            f"| {container['compute_pipelines'] if container['compute_pipelines'] is not None else 'unknown'} "
            f"| {container['capture_timestamp'] or 'unknown'} | `{row['name']}` |"
        )
    lines += [
        "",
        "## Limits",
        "",
        "The inventory proves the listed GFXR files are readable capture containers and records their metadata. It does not identify rendered pixel values, associate a Xenos fetch warning with a Vulkan descriptor slot, or prove Metal texture/pipeline correctness. No captured Vulkan work was replayed.",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures", nargs="+", type=pathlib.Path)
    parser.add_argument("--info-tool", required=True, type=pathlib.Path)
    parser.add_argument("--capture-log", type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    log_rows = parse_capture_log(args.capture_log.read_text(encoding="utf-8", errors="replace")) if args.capture_log else {}
    captures = [inventory_capture(path, args.info_tool.resolve(), log_rows) for path in args.captures]
    captures.sort(key=lambda row: (row["container"]["frame_start"] is None, row["container"]["frame_start"] or 0, row["name"]))
    manifest = {
        "schema": "rosette-gfxr-inventory-v1",
        "scope": "Static GFXReconstruct container inspection via gfxrecon-info; no replay or captured-shader execution.",
        "info_tool": str(args.info_tool.resolve()),
        "capture_log": str(args.capture_log.resolve()) if args.capture_log else None,
        "captures": captures,
        "total_bytes": sum(row["bytes"] for row in captures),
        "completed_count": sum(row["capture_log"].get("finished") is True for row in captures),
    }
    (out / "inventory.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (out / "inventory.md").write_text(render_markdown(manifest), encoding="utf-8")
    print(f"Inventoried {len(captures)} capture(s), {manifest['total_bytes']} bytes -> {out / 'inventory.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
