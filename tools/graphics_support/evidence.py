"""Observed run facts and content-addressed shader evidence, never GPU execution."""
from __future__ import annotations

from collections import Counter
import hashlib
import math
from pathlib import Path
import re
import struct

from .iso import InventoryError, hash_file

PAIR = re.compile(r"([\w/()]+)=([^\s;]+)")
ARCHIVE_NAME = re.compile(r"module-([0-9a-f]+)-([0-9a-f]+)\.(guest|native)\.spv$")


def fields(line):
    result = {}
    for key, value in PAIR.findall(line.split(";", 1)[0]):
        if value in ("true", "false"):
            value = value == "true"
        else:
            try:
                value = int(value, 16 if value.startswith("0x") else 10)
            except ValueError:
                pass
        result[key] = value
    return result


def parse_log(path: Path) -> dict:
    path = path.resolve(strict=True)
    text = path.read_text(errors="replace")
    ids = set(re.findall(r"(?:run_id\s*=\s*)([\w-]+)", text))
    if len(ids) != 1:
        raise InventoryError("A log must identify exactly one run; do not concatenate runs")
    builds = set(re.findall(r"build_identity_sha256\s*=\s*([0-9a-f]{64})", text))
    if len(builds) != 1:
        raise InventoryError("A log must identify exactly one runner build")
    shaders, pipelines, cadence, warnings, events, snapshots, host = [], [], [], [], [], {}, {}
    seen_shaders, seen_pipelines, seen_cadence = set(), set(), set()
    driver = None
    fetch_kinds, fetch_constants, brightness, isolation, exit_info = Counter(), set(), [], [], {}
    sampled_rgb, sample_views, gamma_contracts, render_settings = [], [], [], {}
    media = re.search(r"^media = (.+)$", text, re.M)
    markers = {"VULKAN FSI GUARD:": "guard", "METAL COMMAND BUFFER POLICY:": "policy",
               "VULKAN FSI CPU ROUTE:": "cpu_route", "VULKAN ROBUST ACCESS:": "robust",
               "VULKAN FSI PIXEL FREQUENCY: enabled=": "fsi_pixel_frequency",
               "VULKAN HDR RESOLVE: enabled=": "hdr_resolve",
               "VULKAN FSI RASTER": "raster", "VULKAN FSI GUARD SAFETY:": "safety",
               "NATIVE METAL TEXTURES: pipelines=": "native_textures",
               "NATIVE METAL TEXTURES: enabled=": "native_texture_profile",
               "RECT EXPAND: enabled=": "rect_expand", "BRIGHTNESS LADDER SUMMARY:": "brightness_summary",
               "FRAME GENERATION RATE:": "frame_rate", "PRESENT CEILING:": "present_ceiling",
               "  tessellation_pipeline:": "tessellation_pipeline", "  tessellation_shader_modules:": "tessellation_modules",
               "  fsi_shader_modules:": "fsi_shader_modules",
               "FRAME CAPTURE SUMMARY:": "frame_capture",
               "VULKAN CAPTURE STATUS:": "render_pass_capture"}
    for number, line in enumerate(text.splitlines(), 1):
        data = fields(line)
        if line.startswith('xenia_gpu_render_settings = '):
            render_settings = fields(line.split(' = ', 1)[1])
        if 'BRIGHTNESS SAMPLED RGB:' in line and len(sampled_rgb) < 400:
            sampled_rgb.append(dict(data, line=number))
        if 'BRIGHTNESS SAMPLE VIEW:' in line and len(sample_views) < 400:
            sample_views.append(dict(data, line=number))
        if 'GAMMA CHANNEL CONTRACT:' in line and len(gamma_contracts) < 200:
            gamma_contracts.append(dict(data, line=number))
        if "VULKAN DRIVER:" in line:
            driver = {k: data[k] for k in ("name", "info", "api", "id") if k in data}
        if "Vulkan FSI SHADER:" in line:
            key = tuple(data.get(k) for k in ("module_id", "guest", "spirv_hash"))
            if key not in seen_shaders:
                shaders.append(dict(data, line=number))
                seen_shaders.add(key)
        if "Vulkan FSI PIPELINE:" in line:
            # Include handles: identical fingerprints can be distinct creations.
            # Repeated summary records are not new attempts.
            key = tuple(sorted(data.items()))
            if key not in seen_pipelines:
                pipelines.append(dict(data, line=number))
                seen_pipelines.add(key)
        if "FRAME HUD RATE:" in line and isinstance(data.get("presented_fps"), str):
            try:
                rate = float(data["presented_fps"])
            except ValueError:
                rate = None
            key = (data.get("accepted_presents"), rate)
            if rate is not None and math.isfinite(rate) and rate >= 0 and key not in seen_cadence:
                cadence.append({"present": key[0], "fps": rate, "line": number})
                seen_cadence.add(key)
        # Xenia's own warning: the title bound something other than a texture
        # to a texture fetch slot. The type is in the low two bits of dword 0.
        fetch = re.match(r"w> [0-9A-F]{8} Texture fetch constant \(([0-9A-F]{8}) .*\) is completely invalid!", line)
        if fetch:
            fetch_kinds[("invalid_texture", "invalid_vertex", "texture", "vertex")[int(fetch[1], 16) & 3]] += 1
            fetch_constants.add(line[line.index("(") + 1:line.index(")")])
        sample = re.search(r"BRIGHTNESS LADDER:\s+stage=(\w+) .*mean_rgb=(\d+)/(\d+)/(\d+) max_rgb=(\d+)/(\d+)/(\d+) .*white_rgb_ge240=(\d+)/(\d+).* frame=(\d+)", line)
        if sample and len(brightness) < 400:
            brightness.append({"frame": int(sample[10]), "stage": sample[1], "mean_rgb": [int(sample[i]) for i in (2, 3, 4)],
                               "max_rgb": [int(sample[i]) for i in (5, 6, 7)], "white": int(sample[8]), "pixels": int(sample[9]), "line": number})
        if "VULKAN FSI ISOLATION:" in line and len(isolation) < 64:
            isolation.append(dict(data, line=number))
        exit_match = re.match(r"(?:# )?(runner_exit_status|started_utc|finished_utc) = (\S+)", line)
        if exit_match:
            exit_info[exit_match[1]] = exit_match[2]
        for marker, name in markers.items():
            if marker in line:
                # Snapshots are cumulative; last snapshot wins, never sum them.
                suffix = "_submission" if "expanded_submits" in data else ""
                snapshots[name + suffix] = dict(data, line=number)
        if "FRAME HOST COST:" in line:
            if "stage" in data:
                host[data["stage"]] = dict(data, line=number)
            elif "present_intervals" in data:
                snapshots["present_intervals"] = dict(data, line=number)
        if "VULKAN FSI WATCHDOG " in line and re.search(r"WATCHDOG (risk|severe|failed|recovered):", line):
            events.append({"kind": re.search(r"WATCHDOG (\w+):", line)[1], "line": number, "fields": data})
        if re.search(r"Caused GPU Address Fault|Caused GPU Hang|SubmissionsIgnored|Graphics device lost|software_guard_device_loss=true", line, re.I):
            warnings.append({"kind": "gpu_failure", "line": number, "text": line[:1600]})
        elif re.search(r"Failed to create one or more tessellation shaders|vulkan-tessellation-unavailable", line):
            warnings.append({"kind": "capability_warning", "line": number, "text": line[:1600]})
        elif re.search(r"REFUSED|refusal=|Couldn't extract memexport|DESCRIPTOR UPDATE REFUSED", line):
            # Advisory observations are not asset failures.
            warnings.append({"kind": "advisory_or_refusal", "line": number, "text": line[:1600]})
    attempts = len(pipelines)
    success = sum(p.get("result") == 0 and p.get("real", 0) != 0 for p in pipelines)
    candidates = []
    for event in events:
        if event['kind'] != 'failed': continue
        hashes = event['fields'].get('pipelines(first/last)', '')
        for label, value in zip(('first', 'last'), str(hashes).split('/')):
            try: fingerprint = int(value, 16)
            except ValueError: continue
            matches = [p for p in pipelines if p.get('pipeline_hash') == fingerprint and p.get('line', 0) < event['line'] and p.get('result') == 0]
            if matches:
                candidates.append({'position': label, 'event_line': event['line'], 'pipeline': matches[-1],
                                   'scope': 'Boundary draw in failed timing group; not proof that this shader caused the asynchronous GPU hang'})
    return {"path": str(path), "sha256": hash_file(path), "run_id": ids.pop(), "build": builds.pop(),
            "driver": driver, "shaders": shaders, "pipelines": pipelines, "snapshots": snapshots,
            "media_path": media[1].strip() if media else None,
            "media_identity_scope": "Log names a path, not a historical ISO checksum; matching paths do not prove unchanged contents",
            "host_cost": host, "cadence": cadence, "events": events, "warnings": warnings,
            "failure_candidates": candidates,
            "exit": exit_info, "isolation_events": isolation,
            "texture_fetch_warnings": {"warnings": sum(fetch_kinds.values()), "distinct_constants": len(fetch_constants),
                                       "types": dict(fetch_kinds),
                                       "scope": "Xenia warns, then binds its null texture (cleared to zero) for these slots; the log does not say which shader asked or why the title left a vertex fetch constant there."},
            "brightness_samples": brightness,
            "sampled_rgb": sampled_rgb, "sample_views": sample_views,
            "gamma_contracts": gamma_contracts, "render_settings": render_settings,
            "pipeline_creation": {"observed_attempts": attempts, "accepted": success,
                                  "acceptance_percent": 100 * success / attempts if attempts else None,
                                  "scope": "Logged creations only; includes unidentified/non-FSI pipelines. Creation is not correct rendering."},
            "cadence_scope": "Windowed accepted native presents, not Xbox simulation FPS or scene-matched gameplay FPS",
            "shader_to_iso_asset_mapping": "unknown: guest GPU microcode identities are not retail pixl/vtsh tag identities"}


def spirv_info(data: bytes) -> dict:
    if len(data) < 20 or len(data) % 4 or len(data) > 32 << 20:
        raise InventoryError("Invalid SPIR-V byte size")
    words = struct.unpack(f"<{len(data) // 4}I", data)
    if words[0] != 0x07230203 or words[4] != 0 or not 0 < words[3] < 0x400000:
        raise InventoryError("Invalid SPIR-V header")
    models, caps, opcodes = set(), set(), Counter()
    glsl_sets, half_ops = set(), Counter()
    at = 5
    while at < len(words):
        length, op = words[at] >> 16, words[at] & 0xffff
        if length == 0 or at + length > len(words):
            raise InventoryError("Malformed SPIR-V instruction stream")
        if op == 15 and length >= 4:
            models.add(words[at + 1])
        if op == 17 and length == 2:
            caps.add(words[at + 1])
        if op == 11 and length >= 3:
            name = struct.pack(f'<{length-2}I', *words[at+2:at+length]).split(b'\0', 1)[0]
            if name == b'GLSL.std.450':
                glsl_sets.add(words[at+1])
        if op == 12 and length >= 6 and words[at+3] in glsl_sets and words[at+4] in (58, 62):
            half_ops[words[at+4]] += 1
        opcodes[op] += 1
        at += length
    # Rosette hashes each 32-bit word as an eight-byte little-endian value.
    fingerprint = 14695981039346656037
    for word in words:
        for byte in struct.pack("<Q", word):
            fingerprint = ((fingerprint ^ byte) * 1099511628211) & 0xffffffffffffffff
    return {"fingerprint": fingerprint, "bytes": len(data), "version": words[1],
            "execution_models": sorted(models), "capabilities": sorted(caps),
            "begin_interlock_ops": opcodes[5364], "end_interlock_ops": opcodes[5365],
            "half_conversion_ops": {"pack_half2x16": half_ops[58], "unpack_half2x16": half_ops[62]},
            "structural_readability": "pass", "checks": {}}


def shader_archive(path: Path, run: dict | None = None, fingerprints: set[int] | None = None) -> dict:
    path = path.resolve(strict=True)
    if not path.is_dir():
        raise InventoryError("Shader archive must be a directory")
    records, failures, count = {}, [], 0
    logged = {(s.get("guest"), s.get("spirv_hash")) for s in (run or {}).get("shaders", [])}
    for file in sorted(path.glob("*.spv")):
        match = ARCHIVE_NAME.fullmatch(file.name)
        if fingerprints is not None and (not match or match[3] != 'guest' or int(match[2],16) not in fingerprints):
            continue
        count += 1
        try:
            if file.stat().st_size > 32 << 20:
                raise InventoryError("Shader exceeds evidence module limit")
            data = file.read_bytes()
            sha = hashlib.sha256(data).hexdigest()
            role = match[3] if match else "unclassified"
            info = records.get((sha, role))
            if info is None:
                info = dict(spirv_info(data), sha256=sha, role=role, paths=[], current_run_guest_match=False)
                records[sha, role] = info
            if match and info["fingerprint"] != int(match[2], 16):
                raise InventoryError("Archive filename fingerprint does not match content")
            info["paths"].append(str(file))
            if match and role == "guest" and (int(match[1], 16), int(match[2], 16)) in logged:
                info["current_run_guest_match"] = True
        except (InventoryError, OSError) as error:
            failures.append({"path": str(file), "error": str(error)})
    items = sorted((r for r in records.values() if r["paths"]), key=lambda r: (r["role"], r["sha256"]))
    matched = {r["fingerprint"] for r in items if r["current_run_guest_match"]}
    return {"path": str(path), "files_seen": count, "modules": items, "unreadable": failures,
            "logged_fsi_guest_hashes": len({h for _, h in logged}), "matched_fsi_guest_hashes": len(matched),
            "selection_fingerprints": sorted(fingerprints) if fingerprints is not None else None,
            "scope": ("Selected failed-group boundary guest shader candidates only; not the complete run archive. " if fingerprints is not None else "Accumulated archive. ") + "Deduplicated by SHA-256 and role; exact guest handle+fingerprint matching only. Native modules cannot be paired to a run from reused handles."}
