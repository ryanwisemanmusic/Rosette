#!/usr/bin/env python3
"""Look inside one captured frame of the Vulkan stream Rosette hands MoltenVK.

Rosette's brightness ladder reads three images after a frame has finished.
When the first of them (the swap texture) is already wrong - Halo 3's campaign
picture was red and blown out on 2026-10-04 - the fault is in one of the
dozens of render passes before it, and only a pass-by-pass view can name it.

Run Xenia under Rosette with ROSETTE_VULKAN_GFXR=1 and press F10 in game:
the GFXReconstruct layer writes `rosette-vulkan*.gfxr` beside the run log
(lib/gpu/vulkan/capture_plan.zig). `plan` converts the capture to JSONL and
builds a static API-call plan; it does not run captured shaders. `dump` invokes
`gfxrecon-replay` and executes the captured Vulkan work, including captured
shaders, on the selected GPU. Do not use `dump` unless GPU replay is intended:

    plan CAPTURE.gfxr --out DIR [--granularity pass|draw] [--dispatch]
        Convert the capture (gfxrecon-convert, cached in DIR) and write the
        --dump-resources configuration: every submitted command buffer, every
        render pass in it, and its last draw (`pass`) or every draw (`draw`).

    dump CAPTURE.gfxr --out DIR [--icd ICD.json|system|sdk-2024]
                      [--granularity pass|draw] [--dispatch] [--descriptors]
                      [--validate]
        Execute the captured Vulkan work with the dump configuration. Images are dumped raw (true
        values, float16 HDR included); `index` turns them into previews.
        --icd picks the driver: `system` is /usr/local's MoltenVK (1.4.x),
        `sdk-2024` the January 2024 SDK's MoltenVK 1.2.7 that runs Xenia
        today. --validate adds the Khronos validation layer to the replay.

    index DIR
        Decode every raw dump GFXReconstruct wrote (formats from its
        *_dr.json), write DIR/previews/*.png (HDR auto-exposed, the scale is
        in the index) and DIR/index.md: per image the submit, pass, draw,
        format, size, per-channel mean/max, NaN/Inf counts and preview.

    diff DIR_A DIR_B
        Compare two dumps of the same capture (two drivers) image by image
        and name the first pass whose output differs.

    self-test
        Checks the pure parts (the planner, the format decoders, the PNG
        writer) on synthetic data. No GPU, SDK or capture needed.

Requires Python 3 with numpy, and the Vulkan SDK (newest ~/VulkanSDK/<version>
is used; GFXReconstruct 1.0.5 or later for --dump-resources).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

try:
    import numpy as np
except ImportError:  # pragma: no cover - reported by main()
    np = None


# ---------------------------------------------------------------------------
# SDK and driver discovery
# ---------------------------------------------------------------------------

def _version_key(name: str):
    parts = name.split(".")
    if len(parts) < 2 or not all(p.isdigit() for p in parts):
        return None
    return tuple(int(p) for p in parts)


def find_sdk() -> Path:
    """The newest ~/VulkanSDK/<version>/macOS that has gfxrecon-replay."""
    override = os.environ.get("ROSETTE_VULKAN_SDK")
    if override:
        return Path(override)
    root = Path.home() / "VulkanSDK"
    best = None
    for entry in root.iterdir() if root.is_dir() else []:
        key = _version_key(entry.name)
        if key is None:
            continue
        macos = entry / "macOS"
        if (macos / "bin" / "gfxrecon-replay").exists() and (best is None or key > best[0]):
            best = (key, macos)
    if best is None:
        raise SystemExit("no ~/VulkanSDK/<version>/macOS with gfxrecon-replay; set ROSETTE_VULKAN_SDK")
    return best[1]


def driver_environment(sdk: Path, icd: str | None) -> dict:
    env = dict(os.environ)
    env["DYLD_LIBRARY_PATH"] = str(sdk / "lib")
    if icd in (None, "", "system"):
        path = Path("/usr/local/share/vulkan/icd.d/MoltenVK_icd.json")
    elif icd == "sdk-2024":
        path = Path.home() / "VulkanSDK/vulkan/macOS/share/vulkan/icd.d/MoltenVK_icd.json"
    else:
        path = Path(icd)
    if not path.exists():
        raise SystemExit(f"ICD manifest not found: {path}")
    env["VK_ICD_FILENAMES"] = str(path)
    env["VK_DRIVER_FILES"] = str(path)
    return env


# ---------------------------------------------------------------------------
# The dump plan
# ---------------------------------------------------------------------------

BEGIN_PASS = {
    "vkCmdBeginRenderPass", "vkCmdBeginRenderPass2", "vkCmdBeginRenderPass2KHR",
    "vkCmdBeginRendering", "vkCmdBeginRenderingKHR",
}
END_PASS = {
    "vkCmdEndRenderPass", "vkCmdEndRenderPass2", "vkCmdEndRenderPass2KHR",
    "vkCmdEndRendering", "vkCmdEndRenderingKHR",
}
DISPATCH = {"vkCmdDispatch", "vkCmdDispatchIndirect", "vkCmdDispatchBase", "vkCmdDispatchBaseKHR"}


def _function(record: dict):
    return record.get("function") or record.get("vkFunc")


def _submitted_buffers(name: str, args: dict) -> list:
    handles = []
    submits = args.get("pSubmits") or []
    # gfxrecon's JSONL writer emits a lone struct as an object for submitCount
    # == 1, but as an array for larger submissions. Accept both encodings.
    if isinstance(submits, dict):
        submits = [submits]
    if not isinstance(submits, list):
        return handles
    for submit in submits:
        if not isinstance(submit, dict):
            continue
        if name == "vkQueueSubmit":
            command_buffers = submit.get("pCommandBuffers") or []
            if isinstance(command_buffers, list):
                handles.extend(command_buffers)
        else:  # vkQueueSubmit2 / KHR
            infos = submit.get("pCommandBufferInfos") or []
            if isinstance(infos, dict):
                infos = [infos]
            if isinstance(infos, list):
                for info in infos:
                    if isinstance(info, dict):
                        handles.append(info.get("commandBuffer"))
    return [h for h in handles if h]


def build_plan(records, granularity: str = "pass", dispatch: bool = False) -> dict:
    """GFXReconstruct --dump-resources configuration for every submitted
    command buffer: its render passes and their last (or every) draw."""
    recording = {}   # command buffer handle -> recording in progress
    finished = {}    # command buffer handle -> last completed recording
    plan = {"BeginCommandBuffer": [], "Draw": [], "RenderPass": [], "Dispatch": [],
            "TraceRays": [], "QueueSubmit": []}
    summary = []
    seen_begins = set()
    for record in records:
        fn = _function(record)
        if not fn:
            continue
        name = fn.get("name", "")
        args = fn.get("args") or {}
        index = record.get("index")
        cb = args.get("commandBuffer")
        if name == "vkBeginCommandBuffer":
            recording[cb] = {"begin": index, "passes": [], "open": None, "dispatches": []}
        elif name == "vkEndCommandBuffer" and cb in recording:
            finished[cb] = recording.pop(cb)
        elif cb in recording:
            current = recording[cb]
            if name in BEGIN_PASS:
                current["open"] = {"begin": index, "end": None, "draws": []}
            elif name in END_PASS and current["open"] is not None:
                current["open"]["end"] = index
                current["passes"].append(current["open"])
                current["open"] = None
            elif name.startswith("vkCmdDraw") and current["open"] is not None:
                current["open"]["draws"].append(index)
            elif name in DISPATCH and current["open"] is None:
                current["dispatches"].append(index)
        elif name in ("vkQueueSubmit", "vkQueueSubmit2", "vkQueueSubmit2KHR"):
            for handle in _submitted_buffers(name, args):
                done = finished.get(handle)
                if done is None or done["begin"] in seen_begins:
                    continue
                passes = [p for p in done["passes"] if p["draws"]]
                dispatches = done["dispatches"] if dispatch else []
                if not passes and not dispatches:
                    continue
                seen_begins.add(done["begin"])
                plan["BeginCommandBuffer"].append(done["begin"])
                plan["QueueSubmit"].append(index)
                plan["RenderPass"].append([[p["begin"], p["end"]] for p in passes])
                draws = []
                for p in passes:
                    draws.extend(p["draws"] if granularity == "draw" else p["draws"][-1:])
                plan["Draw"].append(draws)
                plan["Dispatch"].append(dispatches)
                plan["TraceRays"].append([])
                summary.append({"submit": index, "begin": done["begin"], "passes": len(passes),
                                "draws": sum(len(p["draws"]) for p in passes), "dumped": len(draws)})
    return {"config": plan, "summary": summary}


def convert(capture: Path, sdk: Path, output_dir: Path) -> Path:
    jsonl = output_dir / (capture.stem + ".jsonl")
    if not jsonl.exists() or jsonl.stat().st_mtime < capture.stat().st_mtime:
        subprocess.run([str(sdk / "bin" / "gfxrecon-convert"), "--format", "jsonl",
                        "--output", str(jsonl), str(capture)], check=True)
    return jsonl


def read_records(jsonl: Path):
    with open(jsonl) as handle:
        for line in handle:
            line = line.strip()
            if line:
                yield json.loads(line)


# ---------------------------------------------------------------------------
# Raw image decoding
# ---------------------------------------------------------------------------

def _f11(bits):
    exponent = (bits >> 6) & 0x1F
    mantissa = (bits & 0x3F).astype(np.float64)
    return _small_float(exponent, mantissa, 64.0)


def _f10(bits):
    exponent = (bits >> 5) & 0x1F
    mantissa = (bits & 0x1F).astype(np.float64)
    return _small_float(exponent, mantissa, 32.0)


def _small_float(exponent, mantissa, scale):
    exponent = exponent.astype(np.int64)
    normal = np.ldexp(1.0 + mantissa / scale, exponent - 15)
    denormal = np.ldexp(mantissa / scale, -14)
    value = np.where(exponent == 0, denormal, normal)
    return np.where(exponent == 31, np.where(mantissa == 0, np.inf, np.nan), value)


def decode(raw: bytes, width: int, height: int, fmt: str):
    """Return an (H, W, 4) float64 array of channel values, or None when the
    format is not one this tool knows. UNORM/SNORM are normalised, floats are
    their true values (HDR intact), integers are their integer values."""
    fmt = fmt.replace("VK_FORMAT_", "")
    count = width * height
    buf = np.frombuffer(raw, dtype=np.uint8)

    def channels(array, order):
        out = np.zeros((count, 4), dtype=np.float64)
        out[:, 3] = 1.0
        for dest, src in enumerate(order):
            if src is not None:
                out[:, dest] = array[:, src]
        return out.reshape(height, width, 4)

    def norm(bits, signed):
        if signed:
            return np.maximum(bits / float((1 << (bits.dtype.itemsize * 8 - 1)) - 1), -1.0)
        return bits / float((1 << (bits.dtype.itemsize * 8)) - 1)

    table = {
        "R8G8B8A8_UNORM": (np.uint8, 4, (0, 1, 2, 3), False),
        "R8G8B8A8_SRGB": (np.uint8, 4, (0, 1, 2, 3), False),
        "R8G8B8A8_SNORM": (np.int8, 4, (0, 1, 2, 3), True),
        "B8G8R8A8_UNORM": (np.uint8, 4, (2, 1, 0, 3), False),
        "B8G8R8A8_SRGB": (np.uint8, 4, (2, 1, 0, 3), False),
        "R8_UNORM": (np.uint8, 1, (0, 0, 0, None), False),
        "R8G8_UNORM": (np.uint8, 2, (0, 1, None, None), False),
        "R16_UNORM": (np.uint16, 1, (0, 0, 0, None), False),
        "R16G16_UNORM": (np.uint16, 2, (0, 1, None, None), False),
        "R16G16_SNORM": (np.int16, 2, (0, 1, None, None), True),
        "R16G16B16A16_UNORM": (np.uint16, 4, (0, 1, 2, 3), False),
        "R16G16B16A16_SNORM": (np.int16, 4, (0, 1, 2, 3), True),
    }
    if fmt in table:
        dtype, n, order, signed = table[fmt]
        size = np.dtype(dtype).itemsize * n * count
        if len(raw) < size:
            return None
        values = np.frombuffer(raw[:size], dtype=dtype).reshape(count, n)
        return channels(norm(values, signed), order)
    float_table = {
        "R16_SFLOAT": (np.float16, 1, (0, 0, 0, None)),
        "R16G16_SFLOAT": (np.float16, 2, (0, 1, None, None)),
        "R16G16B16A16_SFLOAT": (np.float16, 4, (0, 1, 2, 3)),
        "R32_SFLOAT": (np.float32, 1, (0, 0, 0, None)),
        "R32G32_SFLOAT": (np.float32, 2, (0, 1, None, None)),
        "R32G32B32A32_SFLOAT": (np.float32, 4, (0, 1, 2, 3)),
        "D32_SFLOAT": (np.float32, 1, (0, 0, 0, None)),
        "R32_UINT": (np.uint32, 1, (0, 0, 0, None)),
        "R16G16_UINT": (np.uint16, 2, (0, 1, None, None)),
        "R16G16B16A16_UINT": (np.uint16, 4, (0, 1, 2, 3)),
        "R32G32_UINT": (np.uint32, 2, (0, 1, None, None)),
    }
    if fmt in float_table:
        dtype, n, order = float_table[fmt]
        size = np.dtype(dtype).itemsize * n * count
        if len(raw) < size:
            return None
        values = np.frombuffer(raw[:size], dtype=dtype).reshape(count, n).astype(np.float64)
        return channels(values, order)
    if fmt in ("A2B10G10R10_UNORM_PACK32", "A2R10G10B10_UNORM_PACK32"):
        if len(raw) < 4 * count:
            return None
        words = np.frombuffer(raw[: 4 * count], dtype=np.uint32).astype(np.int64)
        low, mid, high = words & 0x3FF, (words >> 10) & 0x3FF, (words >> 20) & 0x3FF
        alpha = (words >> 30) & 0x3
        r, b = (low, high) if fmt.startswith("A2B10") else (high, low)
        out = np.stack([r / 1023.0, mid / 1023.0, b / 1023.0, alpha / 3.0], axis=1)
        return out.reshape(height, width, 4)
    if fmt == "B10G11R11_UFLOAT_PACK32":
        if len(raw) < 4 * count:
            return None
        words = np.frombuffer(raw[: 4 * count], dtype=np.uint32).astype(np.int64)
        out = np.stack([_f11(words & 0x7FF), _f11((words >> 11) & 0x7FF),
                        _f10((words >> 22) & 0x3FF), np.ones(count)], axis=1)
        return out.reshape(height, width, 4)
    del buf
    return None


def stats(image) -> dict:
    flat = image.reshape(-1, 4)
    finite = np.isfinite(flat)
    result = {"nan": int(np.isnan(flat[:, :3]).sum()), "inf": int(np.isinf(flat[:, :3]).sum())}
    clean = np.where(finite, flat, 0.0)
    result["mean"] = [float(v) for v in clean[:, :3].mean(axis=0)]
    result["max"] = [float(v) for v in clean[:, :3].max(axis=0)]
    result["min"] = [float(v) for v in clean[:, :3].min(axis=0)]
    return result


def preview_rgb8(image):
    """8-bit RGB for viewing. Values in [0, 1] are shown as they are; an HDR
    image is scaled so its 99.5th-percentile channel value maps to 1. Returns
    (pixels, scale)."""
    rgb = np.nan_to_num(image[:, :, :3], nan=0.0, posinf=0.0, neginf=0.0)
    scale = 1.0
    peak = float(np.percentile(rgb, 99.5)) if rgb.size else 0.0
    if peak > 1.0:
        scale = 1.0 / peak
    shown = np.clip(rgb * scale, 0.0, 1.0)
    return (shown * 255.0 + 0.5).astype(np.uint8), scale


def write_png(path: Path, pixels) -> None:
    """Write an (H, W, 3) uint8 array as a PNG (filter 0, zlib level 6)."""
    height, width, _ = pixels.shape
    rows = np.concatenate([np.zeros((height, 1), dtype=np.uint8),
                           pixels.reshape(height, width * 3)], axis=1)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
                     chunk(b"IDAT", zlib.compress(rows.tobytes(), 6)) + chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Index and diff
# ---------------------------------------------------------------------------

def dumped_images(directory: Path):
    """Every image GFXReconstruct dumped, in command order, from its *_dr.json."""
    entries = []
    for meta in sorted(directory.glob("*_dr.json")):
        data = json.loads(meta.read_text())
        for block in data:
            for kind in ("drawCallCommands", "dispatchCommands"):
                for command in block.get(kind, []) or []:
                    order = command.get("drawIndex", command.get("dispatchIndex", 0))
                    for attachment in command.get("colorAttachments", []) or []:
                        for sub in attachment.get("subresources", []):
                            entries.append({
                                "order": order, "kind": kind, "submit": command.get("queueSubmitIndex"),
                                "begin": command.get("beginCommandBufferIndex"),
                                "role": f"att{attachment.get('location', 0)}",
                                "image": attachment.get("imageId"), "format": attachment.get("format", "?"),
                                "width": sub["dimensions"][0], "height": sub["dimensions"][1],
                                "file": sub.get("file", ""),
                            })
    entries.sort(key=lambda e: (e["order"], e["role"]))
    return entries


def index(directory: Path) -> list:
    previews = directory / "previews"
    previews.mkdir(exist_ok=True)
    rows = []
    for entry in dumped_images(directory):
        path = Path(entry["file"])
        if not path.is_absolute():
            path = directory / path.name
        if not path.exists():
            continue
        row = dict(entry)
        if path.suffix == ".bin":
            image = decode(path.read_bytes(), entry["width"], entry["height"], entry["format"])
            if image is not None:
                row.update(stats(image))
                pixels, scale = preview_rgb8(image)
                preview = previews / (path.stem + ".png")
                write_png(preview, pixels)
                row["preview"] = str(preview.relative_to(directory))
                row["scale"] = scale
        else:
            row["preview"] = path.name
        rows.append(row)
    lines = ["| draw | submit | att | image | format | size | mean RGB | max RGB | NaN/Inf | preview (scale) |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for row in rows:
        mean = "/".join(f"{v:.3f}" for v in row.get("mean", [])) or "-"
        peak = "/".join(f"{v:.3f}" for v in row.get("max", [])) or "-"
        lines.append(f"| {row['order']} | {row['submit']} | {row['role']} | {row['image']} | {row['format'].replace('VK_FORMAT_', '')} "
                     f"| {row['width']}x{row['height']} | {mean} | {peak} | {row.get('nan', '-')}/{row.get('inf', '-')} "
                     f"| {row.get('preview', '-')} ({row.get('scale', 1.0):.3g}) |")
    (directory / "index.md").write_text("\n".join(lines) + "\n")
    (directory / "index.json").write_text(json.dumps(rows, indent=1))
    return rows


def diff(first: Path, second: Path) -> list:
    a = {Path(e["file"]).name: e for e in dumped_images(first)}
    b = {Path(e["file"]).name: e for e in dumped_images(second)}
    report = []
    for name, entry in sorted(a.items(), key=lambda item: item[1]["order"]):
        other = b.get(name)
        if other is None:
            continue
        left, right = first / name, second / name
        if not left.exists() or not right.exists():
            continue
        x = decode(left.read_bytes(), entry["width"], entry["height"], entry["format"])
        y = decode(right.read_bytes(), other["width"], other["height"], other["format"])
        if x is None or y is None or x.shape != y.shape:
            continue
        delta = np.abs(np.nan_to_num(x) - np.nan_to_num(y))[:, :, :3]
        report.append({"order": entry["order"], "file": name, "max_delta": float(delta.max()),
                       "differing_pixels": int((delta.max(axis=2) > 1e-3).sum())})
    return report


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def command_plan(args) -> Path:
    sdk = find_sdk()
    capture = Path(args.capture).resolve()
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    plan = build_plan(read_records(convert(capture, sdk, out_dir)), args.granularity, args.dispatch)
    config = plan["config"]
    config["DumpResourcesOptions"] = {"ImageFormat": "png", "DumpRawImages": True, "DumpDepth": False,
                                      "DumpAllDescriptors": bool(getattr(args, "descriptors", False))}
    out = out_dir / (capture.stem + "_dump.json")
    out.write_text(json.dumps(config, indent=1))
    passes = sum(item["passes"] for item in plan["summary"])
    dumped = sum(item["dumped"] for item in plan["summary"])
    print(f"{len(plan['summary'])} submitted command buffers, {passes} render passes with draws, "
          f"{dumped} dump points -> {out}")
    return out


def command_dump(args) -> None:
    sdk = find_sdk()
    config = command_plan(args)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    command = [str(sdk / "bin" / "gfxrecon-replay"), "--dump-resources", str(config),
               "--dump-resources-dir", str(out)]
    if args.validate:
        command.append("--validate")
    command.append(str(Path(args.capture).resolve()))
    env = driver_environment(sdk, args.icd)
    log = out / "replay.log"
    with open(log, "w") as handle:
        result = subprocess.run(command, env=env, stdout=handle, stderr=subprocess.STDOUT)
    print(f"replay exit {result.returncode} (driver {env['VK_ICD_FILENAMES']}); log {log}")
    rows = index(out)
    print(f"{len(rows)} images indexed -> {out / 'index.md'}")


def command_index(args) -> None:
    rows = index(Path(args.directory))
    print(f"{len(rows)} images indexed -> {Path(args.directory) / 'index.md'}")


def command_diff(args) -> None:
    report = diff(Path(args.first), Path(args.second))
    first = next((r for r in report if r["differing_pixels"]), None)
    for row in report:
        print(f"draw {row['order']:>8}  max_delta {row['max_delta']:.4f}  differing_pixels {row['differing_pixels']:>8}  {row['file']}")
    print("first differing dump:", first["file"] if first else "none")


def self_test() -> None:
    # GFXReconstruct serializes one-submit `pSubmits` as an object, while
    # multi-submit arrays are lists. Both forms must retain every command
    # buffer selected for an offline replay plan.
    assert _submitted_buffers("vkQueueSubmit", {"pSubmits": {"pCommandBuffers": [1]}}) == [1]
    assert _submitted_buffers("vkQueueSubmit", {"pSubmits": [{"pCommandBuffers": [1, 2]}]}) == [1, 2]
    assert _submitted_buffers("vkQueueSubmit2", {"pSubmits": {
        "pCommandBufferInfos": {"commandBuffer": 3},
    }}) == [3]
    assert _submitted_buffers("vkQueueSubmit", {"pSubmits": "unexpected"}) == []

    records = [
        {"index": 1, "function": {"name": "vkBeginCommandBuffer", "args": {"commandBuffer": 7}}},
        {"index": 2, "function": {"name": "vkCmdBeginRenderPass", "args": {"commandBuffer": 7}}},
        {"index": 3, "function": {"name": "vkCmdDraw", "args": {"commandBuffer": 7}}},
        {"index": 4, "function": {"name": "vkCmdDrawIndexed", "args": {"commandBuffer": 7}}},
        {"index": 5, "function": {"name": "vkCmdEndRenderPass", "args": {"commandBuffer": 7}}},
        {"index": 6, "function": {"name": "vkCmdBeginRenderPass", "args": {"commandBuffer": 7}}},
        {"index": 7, "function": {"name": "vkCmdEndRenderPass", "args": {"commandBuffer": 7}}},
        {"index": 8, "function": {"name": "vkCmdDispatch", "args": {"commandBuffer": 7}}},
        {"index": 9, "function": {"name": "vkEndCommandBuffer", "args": {"commandBuffer": 7}}},
        {"index": 10, "function": {"name": "vkQueueSubmit", "args": {"pSubmits": {"pCommandBuffers": [7]}}}},
        {"index": 11, "function": {"name": "vkQueueSubmit", "args": {"pSubmits": [{"pCommandBuffers": [7]}]}}},
    ]
    plan = build_plan(records)["config"]
    assert plan["BeginCommandBuffer"] == [1], plan
    assert plan["QueueSubmit"] == [10], plan              # one dump per recording
    assert plan["RenderPass"] == [[[2, 5]]], plan          # the clear-only pass has no draw to dump
    assert plan["Draw"] == [[4]], plan                     # pass granularity: the last draw
    assert build_plan(records, "draw")["config"]["Draw"] == [[3, 4]]
    assert build_plan(records, dispatch=True)["config"]["Dispatch"] == [[8]]

    pixels = bytes([10, 20, 30, 255]) * 4
    image = decode(pixels, 2, 2, "VK_FORMAT_B8G8R8A8_UNORM")
    assert abs(image[0, 0, 0] - 30 / 255) < 1e-9 and abs(image[0, 0, 2] - 10 / 255) < 1e-9
    word = (1023 << 20) | (512 << 10) | 0
    image = decode(struct.pack("<I", word), 1, 1, "A2B10G10R10_UNORM_PACK32")
    assert image[0, 0, 0] == 0.0 and abs(image[0, 0, 2] - 1.0) < 1e-9
    half = np.array([2.5, -1.0, np.inf, np.nan], dtype=np.float16).tobytes()
    image = decode(half, 1, 1, "R16G16B16A16_SFLOAT")
    summary = stats(image)
    assert summary["max"][0] == 2.5 and summary["inf"] == 1 and summary["nan"] == 0
    rgb, scale = preview_rgb8(np.full((2, 2, 4), 4.0))
    assert scale == 0.25 and int(rgb[0, 0, 0]) == 255
    # B10G11R11: 1.0 is exponent 15, mantissa 0 in every channel.
    one = (15 << 6) | ((15 << 6) << 11) | ((15 << 5) << 22)
    image = decode(struct.pack("<I", one), 1, 1, "B10G11R11_UFLOAT_PACK32")
    assert np.allclose(image[0, 0, :3], 1.0), image
    path = Path(os.environ.get("TMPDIR", "/tmp")) / "capture_replay_selftest.png"
    write_png(path, np.zeros((3, 2, 3), dtype=np.uint8))
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", data[16:24]) == (2, 3)
    raw = zlib.decompress(data[data.index(b"IDAT") + 4: data.index(b"IEND") - 8])
    assert len(raw) == 3 * (1 + 2 * 3)
    path.unlink()
    print("capture_replay self-test: OK")


def main(argv=None) -> int:
    if np is None:
        print("capture_replay.py needs numpy (python3 -m pip install numpy)", file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    plan = sub.add_parser("plan")
    plan.add_argument("capture")
    plan.add_argument("--out", required=True, help="Rosette-owned output directory; capture files remain read-only")
    plan.add_argument("--granularity", choices=("pass", "draw"), default="pass")
    plan.add_argument("--dispatch", action="store_true")
    plan.add_argument("--descriptors", action="store_true")
    plan.set_defaults(handler=command_plan)
    dump = sub.add_parser("dump")
    dump.add_argument("capture")
    dump.add_argument("--out", required=True)
    dump.add_argument("--icd", default="system")
    dump.add_argument("--granularity", choices=("pass", "draw"), default="pass")
    dump.add_argument("--dispatch", action="store_true")
    dump.add_argument("--descriptors", action="store_true")
    dump.add_argument("--validate", action="store_true")
    dump.set_defaults(handler=command_dump)
    idx = sub.add_parser("index")
    idx.add_argument("directory")
    idx.set_defaults(handler=command_index)
    dif = sub.add_parser("diff")
    dif.add_argument("first")
    dif.add_argument("second")
    dif.set_defaults(handler=command_diff)
    test = sub.add_parser("self-test")
    test.set_defaults(handler=lambda _args: self_test())
    args = parser.parse_args(argv)
    args.handler(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
