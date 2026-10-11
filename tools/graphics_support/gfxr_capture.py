"""CPU-only audit of GFXReconstruct JSON exports; never replays a capture.

The audit correlates recorded Vulkan commands with the FSI framebuffer,
graphics pipelines, shader module identities and descriptor image metadata.
It does not inspect rendered pixels or certify ISO assets.
"""
from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

from .iso import InventoryError, hash_file

SCHEMA = 1
FSI_WIDTH_MIN = 8192
IMAGE_DESCRIPTOR_TYPES = {
    "VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE", "VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER",
    "VK_DESCRIPTOR_TYPE_STORAGE_IMAGE", "VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT",
}


def _records(path: Path):
    decoder = json.JSONDecoder()
    with path.open(errors="replace") as stream:
        for line_number, line in enumerate(stream, 1):
            start = line.find("{")
            if start < 0:
                continue
            try:
                value, _ = decoder.raw_decode(line[start:])
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                yield line_number, value


def _image_descriptor_record(kind, info):
    return {"descriptor_type": kind, "image_view": info.get("imageView"),
            "image_layout": info.get("imageLayout")}


def audit_jsonl(jsonl: Path, capture: Path, converter: Path,
                binary_dir: Path | None = None, shader_archive: Path | None = None) -> dict:
    """Summarize API records and identify FSI draws by the recorded 8192² framebuffer."""
    jsonl = jsonl.resolve(strict=True)
    capture = capture.resolve(strict=True)
    converter = converter.resolve(strict=True)
    render_passes, framebuffers, images, views, pipelines, modules = {}, {}, {}, {}, {}, {}
    descriptor_sets = defaultdict(dict)
    descriptor_generation = Counter()
    command_buffers = defaultdict(lambda: {"framebuffer": None, "pipelines": {}, "sets": defaultdict(dict)})
    calls, frame_numbers = Counter(), set()
    descriptor_updates = Counter()
    copy_calls = Counter()
    fsi_draws = []
    fsi_unknown_secondary = 0
    record_count = 0

    for _, record in _records(jsonl):
        record_count += 1
        state = record.get("state")
        if isinstance(state, dict) and state.get("marker_type") == "BeginMarker":
            if isinstance(state.get("frame_number"), int):
                frame_numbers.add(state["frame_number"])
        function = record.get("function")
        if not isinstance(function, dict):
            continue
        name = function.get("name")
        if not isinstance(name, str):
            continue
        calls[name] += 1
        args = function.get("args") or {}

        if name == "vkCreateRenderPass":
            handle = args.get("pRenderPass")
            info = args.get("pCreateInfo") or {}
            if handle is not None:
                render_passes[handle] = {"attachments": info.get("attachmentCount"),
                                         "subpasses": info.get("subpassCount")}
        elif name == "vkCreateFramebuffer":
            handle = args.get("pFramebuffer")
            info = args.get("pCreateInfo") or {}
            if handle is not None:
                framebuffers[handle] = {"render_pass": info.get("renderPass"),
                                        "attachment_count": info.get("attachmentCount"),
                                        "width": info.get("width"), "height": info.get("height"),
                                        "layers": info.get("layers")}
        elif name == "vkCreateImage":
            handle = args.get("pImage")
            info = args.get("pCreateInfo") or {}
            if handle is not None:
                images[handle] = {"format": info.get("format"), "extent": info.get("extent"),
                                  "mips": info.get("mipLevels"), "layers": info.get("arrayLayers"),
                                  "type": info.get("imageType")}
        elif name == "vkCreateImageView":
            handle = args.get("pView")
            info = args.get("pCreateInfo") or {}
            if handle is not None:
                views[handle] = {"image": info.get("image"), "format": info.get("format"),
                                 "view_type": info.get("viewType"), "components": info.get("components"),
                                 "subresource": info.get("subresourceRange")}
        elif name in ("vkCreateGraphicsPipelines", "vkCreateComputePipelines"):
            handles = args.get("pPipelines") or []
            infos = args.get("pCreateInfos") or []
            for handle, info in zip(handles, infos):
                stages = info.get("stageCount", 0)
                stage_records = info.get("pStages") or []
                pipelines[handle] = {"kind": "graphics" if name == "vkCreateGraphicsPipelines" else "compute",
                                     "stages": [{"stage": s.get("stage"), "module": s.get("module")}
                                                for s in stage_records],
                                     "render_pass": info.get("renderPass"),
                                     "layout": info.get("layout"),
                                     "topology": (info.get("pInputAssemblyState") or {}).get("topology"),
                                     "stage_count": stages}
        elif name == "vkCreateShaderModule":
            handle = args.get("pShaderModule")
            info = args.get("pCreateInfo") or {}
            if handle is not None:
                modules[handle] = {"code_bytes": info.get("codeSize"), "binary_reference": info.get("pCode")}
        elif name == "vkUpdateDescriptorSets":
            for write in args.get("pDescriptorWrites") or []:
                set_handle, kind = write.get("dstSet"), write.get("descriptorType")
                if set_handle is None or not isinstance(kind, str):
                    continue
                binding, first = write.get("dstBinding", 0), write.get("dstArrayElement", 0)
                image_infos = write.get("pImageInfo") or []
                buffer_infos = write.get("pBufferInfo") or []
                texel_views = write.get("pTexelBufferView") or []
                for index, value in enumerate(image_infos):
                    descriptor_sets[set_handle][(binding, first + index)] = _image_descriptor_record(kind, value)
                    descriptor_generation[set_handle] += 1
                    descriptor_updates[kind] += 1
                for index, value in enumerate(buffer_infos):
                    descriptor_sets[set_handle][(binding, first + index)] = {"descriptor_type": kind,
                                                                             "buffer": value.get("buffer"),
                                                                             "offset": value.get("offset"),
                                                                             "range": value.get("range")}
                    descriptor_generation[set_handle] += 1
                    descriptor_updates[kind] += 1
                for index, value in enumerate(texel_views):
                    descriptor_sets[set_handle][(binding, first + index)] = {"descriptor_type": kind,
                                                                             "texel_buffer_view": value}
                    descriptor_generation[set_handle] += 1
                    descriptor_updates[kind] += 1
        elif name == "vkCmdBeginRenderPass":
            info = args.get("pRenderPassBegin") or {}
            command_buffers[args.get("commandBuffer")]["framebuffer"] = info.get("framebuffer")
        elif name in ("vkCmdEndRenderPass", "vkCmdEndRendering"):
            command_buffers[args.get("commandBuffer")]["framebuffer"] = None
        elif name == "vkCmdBindPipeline":
            bind_point = args.get("pipelineBindPoint", "VK_PIPELINE_BIND_POINT_GRAPHICS")
            command_buffers[args.get("commandBuffer")]["pipelines"][bind_point] = args.get("pipeline")
        elif name == "vkCmdBindDescriptorSets":
            state = command_buffers[args.get("commandBuffer")]
            bind_point = args.get("pipelineBindPoint", "VK_PIPELINE_BIND_POINT_GRAPHICS")
            for index, handle in enumerate(args.get("pDescriptorSets") or []):
                state["sets"][bind_point][args.get("firstSet", 0) + index] = handle
        elif name == "vkCmdExecuteCommands":
            command_buffer = args.get("commandBuffer")
            framebuffer = framebuffers.get(command_buffers[command_buffer]["framebuffer"], {})
            if framebuffer.get("width", 0) >= FSI_WIDTH_MIN:
                fsi_unknown_secondary += len(args.get("pCommandBuffers") or [])
        elif name.startswith("vkCmdCopy") or name.startswith("vkCmdResolve"):
            copy_calls[name] += 1
        elif name in ("vkCmdDraw", "vkCmdDrawIndexed", "vkCmdDrawIndirect", "vkCmdDrawIndexedIndirect",
                      "vkCmdDrawIndirectCount", "vkCmdDrawIndexedIndirectCount"):
            command_buffer = args.get("commandBuffer")
            state = command_buffers[command_buffer]
            framebuffer = framebuffers.get(state["framebuffer"], {})
            render_pass = render_passes.get(framebuffer.get("render_pass"), {})
            if (framebuffer.get("attachment_count") == 0 and render_pass.get("attachments") == 0 and
                    framebuffer.get("width", 0) >= FSI_WIDTH_MIN and framebuffer.get("height", 0) >= FSI_WIDTH_MIN):
                graphics_sets = state["sets"].get("VK_PIPELINE_BIND_POINT_GRAPHICS", {})
                fsi_draws.append({"command": name, "command_buffer": command_buffer,
                                  "pipeline": state["pipelines"].get("VK_PIPELINE_BIND_POINT_GRAPHICS"),
                                  "sets": dict(graphics_sets),
                                  "set_generations": {handle: descriptor_generation[handle]
                                                      for handle in graphics_sets.values()},
                                  "descriptors": {handle: dict(descriptor_sets.get(handle, {}))
                                                  for handle in graphics_sets.values()},
                                  "framebuffer": state["framebuffer"]})

    if not record_count:
        raise InventoryError("No JSON records found in GFXReconstruct conversion")

    module_archive = {}
    if binary_dir:
        module_archive = _match_shader_modules(modules, binary_dir.resolve(strict=True), shader_archive)
    else:
        for module in modules.values():
            module["archive_match"] = "not_requested"

    pipeline_draws = Counter(draw["pipeline"] for draw in fsi_draws)
    shader_uses = Counter()
    pipeline_rows = []
    image_references = Counter()
    image_views_used, images_used = set(), set()
    formats = Counter()
    image_descriptor_slots = 0
    unresolved_image_views = 0
    descriptor_sets_rewritten_after_draw = 0
    for draw in fsi_draws:
        pipeline = pipelines.get(draw["pipeline"], {})
        for stage in pipeline.get("stages", []):
            module = stage.get("module")
            if module is not None:
                shader_uses[module] += 1
        for set_handle in draw["sets"].values():
            if descriptor_generation[set_handle] > draw["set_generations"].get(set_handle, 0):
                descriptor_sets_rewritten_after_draw += 1
            for descriptor in draw["descriptors"].get(set_handle, {}).values():
                kind = descriptor.get("descriptor_type")
                if kind not in IMAGE_DESCRIPTOR_TYPES:
                    continue
                image_descriptor_slots += 1
                view_handle = descriptor.get("image_view")
                view = views.get(view_handle)
                if view is None:
                    unresolved_image_views += 1
                    continue
                image_views_used.add(view_handle)
                image_handle = view.get("image")
                if image_handle is not None:
                    images_used.add(image_handle)
                image = images.get(image_handle, {})
                extent = image.get("extent") or {}
                mapping = json.dumps(view.get("components"), sort_keys=True, separators=(",", ":"))
                formats[(kind, view.get("format"), view.get("view_type"),
                         extent.get("width"), extent.get("height"), extent.get("depth"), mapping)] += 1
                image_references[image_handle] += 1
    for handle, count in pipeline_draws.most_common(32):
        pipeline = pipelines.get(handle, {})
        stages = []
        for stage in pipeline.get("stages", []):
            module_id = stage.get("module")
            module = modules.get(module_id, {})
            stages.append({"stage": stage.get("stage"), "module": module_id,
                           "code_bytes": module.get("code_bytes"),
                           "archive_match": module.get("archive_match", "unavailable")})
        pipeline_rows.append({"pipeline": handle, "draws": count, "topology": pipeline.get("topology"),
                             "creation_record": "present" if pipeline else "not_in_capture",
                             "stages": stages})

    fsi_framebuffers = []
    for handle, framebuffer in framebuffers.items():
        render_pass = render_passes.get(framebuffer.get("render_pass"), {})
        if (framebuffer.get("attachment_count") == 0 and render_pass.get("attachments") == 0 and
                framebuffer.get("width", 0) >= FSI_WIDTH_MIN and framebuffer.get("height", 0) >= FSI_WIDTH_MIN):
            fsi_framebuffers.append({"handle": handle, **framebuffer})

    archive_matches = Counter()
    for module_id in shader_uses:
        module = modules.get(module_id, {})
        role = next((entry["role"] for entry in module.get("archive_files", [])), None)
        state = module.get("archive_match", "unavailable")
        archive_matches[f"{role}_exact_byte_match" if role and state == "exact_byte_match" else state] += 1
    return {
        "schema": SCHEMA,
        "capture": {"path": str(capture), "sha256": hash_file(capture), "bytes": capture.stat().st_size,
                    "frames": sorted(frame_numbers)},
        "converter": {"path": str(converter), "sha256": hash_file(converter)},
        "analysis": {"mode": "offline_json_api_audit", "gpu_replay": False,
                     "game_shader_dispatch": False, "rendered_pixel_data": False,
                     "scope": "Recorded Vulkan calls/state only; no pixel readback or visual correctness assertion."},
        "record_count": record_count,
        "api_call_counts": {name: calls[name] for name in (
            "vkCreateShaderModule", "vkCreateGraphicsPipelines", "vkCreateComputePipelines",
            "vkCreateImage", "vkCreateImageView", "vkCreateFramebuffer", "vkCmdBeginRenderPass",
            "vkCmdEndRenderPass", "vkCmdBindPipeline", "vkCmdBindDescriptorSets", "vkCmdDraw",
            "vkCmdDrawIndexed", "vkCmdDispatch", "vkCmdCopyImageToBuffer", "vkCmdCopyBufferToImage") if calls[name]},
        "descriptor_update_types": dict(sorted(descriptor_updates.items())),
        "resource_copy_calls": dict(sorted(copy_calls.items())),
        "fsi": {"identification": "attachment-less render pass + framebuffer at least 8192x8192",
                "framebuffers": sorted(fsi_framebuffers, key=lambda row: row["handle"]),
                "draw_calls": len(fsi_draws), "draw_command_types": dict(sorted(Counter(d["command"] for d in fsi_draws).items())),
                "command_buffers": len({d["command_buffer"] for d in fsi_draws}),
                "unique_pipelines": len(pipeline_draws), "unique_shader_modules": len(shader_uses),
                "draws_without_pipeline_creation_record": sum(count for handle, count in pipeline_draws.items()
                                                              if handle not in pipelines),
                "pipeline_handles_without_creation_record": sorted(handle for handle in pipeline_draws
                                                                     if handle not in pipelines),
                "shader_module_uses": dict(sorted(shader_uses.items())),
                "shader_archive_module_counts": dict(sorted(archive_matches.items())),
                "top_pipelines": pipeline_rows,
                "bound_image_descriptor_slots": image_descriptor_slots,
                "unresolved_image_view_slots": unresolved_image_views,
                "bound_sets_rewritten_later_in_api_order": descriptor_sets_rewritten_after_draw,
                "descriptor_mapping_scope": "Descriptor contents sampled at the recorded API call position. Later descriptor writes are counted; Vulkan execution-time state is not inferred where update-after-bind or later reuse changes semantics.",
                "unique_image_views": len(image_views_used), "unique_images": len(images_used),
                "image_descriptors_by_format": [
                    {"descriptor_type": key[0], "format": key[1], "view_type": key[2],
                     "width": key[3], "height": key[4], "depth": key[5],
                     "component_mapping": json.loads(key[6]), "draw_bind_occurrences": count}
                    for key, count in formats.most_common(40)],
                "secondary_command_buffers_not_expanded": fsi_unknown_secondary},
        "object_counts": {"render_passes": len(render_passes), "framebuffers": len(framebuffers),
                          "images": len(images), "image_views": len(views),
                          "graphics_pipelines": sum(p["kind"] == "graphics" for p in pipelines.values()),
                          "compute_pipelines": sum(p["kind"] == "compute" for p in pipelines.values()),
                          "shader_modules": len(modules)},
        "shader_modules": {str(k): v for k, v in sorted(modules.items())},
    }


def _spirv_fingerprint(data: bytes):
    if len(data) < 20 or len(data) % 4 or data[:4] != b"\x03\x02#\x07":
        return None
    words = struct.unpack(f"<{len(data) // 4}I", data)
    value = 14695981039346656037
    for word in words:
        for byte in struct.pack("<Q", word):
            value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return value


def _match_shader_modules(modules, binary_dir: Path, shader_archive: Path | None):
    archive = {}
    if shader_archive:
        for path in shader_archive.resolve(strict=True).glob("*.spv"):
            match = re.fullmatch(r"module-[0-9a-f]+-([0-9a-f]+)\.(guest|native)\.spv", path.name)
            if match:
                archive.setdefault(int(match.group(1), 16), []).append((path.stat().st_size, match.group(2), path))
    for module_id, module in modules.items():
        reference = module.get("binary_reference")
        if not isinstance(reference, str) or reference == "[Binary data]":
            module["archive_match"] = "binary_unavailable"
            continue
        # gfxrecon-convert writes a path prefixed by the sidecar directory
        # itself (for example "capture/<index>_shader_module_...bin").
        candidate = (binary_dir / Path(reference).name).resolve()
        if binary_dir not in candidate.parents or not candidate.is_file():
            module["archive_match"] = "binary_missing"
            continue
        data = candidate.read_bytes()
        module["captured_sha256"] = hashlib.sha256(data).hexdigest()
        module["captured_spirv_fingerprint"] = _spirv_fingerprint(data)
        module["archive_match"] = "not_found"
        module["archive_files"] = []
        fingerprint = module["captured_spirv_fingerprint"]
        if fingerprint is None:
            continue
        for size, role, path in archive.get(fingerprint, []):
            if size == len(data) and path.read_bytes() == data:
                module["archive_match"] = "exact_byte_match"
                module["archive_files"].append({"name": path.name, "role": role, "path": str(path),
                                                "sha256": hash_file(path)})
                break
    return modules


def run_audit(capture: Path, output: Path, converter: str = "gfxrecon-convert",
              shader_archive: Path | None = None, include_binaries: bool = False):
    capture, output = capture.resolve(strict=True), output.resolve()
    if output.exists():
        raise InventoryError("Output exists; preserve prior capture evidence and choose a new path")
    executable = shutil.which(converter)
    if not executable:
        raise InventoryError(f"Cannot find gfxrecon-convert: {converter}")
    converter_path = Path(executable).resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="rosette-gfxr-audit-") as temporary:
        temp = Path(temporary)
        converted = temp / "capture.jsonl"
        binary_dir = temp / converted.stem if include_binaries else None
        args = [str(converter_path), "--format", "jsonl", "--output", str(converted)]
        if include_binaries:
            args.append("--include-binaries")
        args.append(str(capture))
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if result.returncode:
            raise InventoryError("gfxrecon-convert failed: " + result.stderr[-2000:])
        data = audit_jsonl(converted, capture, converter_path, binary_dir, shader_archive)
        data["converter_output"] = {"stderr_tail": result.stderr[-1000:], "exit_code": result.returncode}
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(data, indent=2) + "\n")
    return data


def attach_capture(snapshot, manifest_path: Path):
    """Attach an audit manifest while keeping rendering-coverage states unchanged."""
    manifest_path = manifest_path.resolve(strict=True)
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("schema") != SCHEMA or not (
            isinstance(manifest.get("capture"), dict) or
            (isinstance(manifest.get("captures"), list) and manifest["captures"])):
        raise InventoryError("Unsupported GFXReconstruct audit manifest")
    verify_capture_record(manifest)
    snapshot["gfxr_capture_audit"] = manifest
    return manifest


def verify_capture_record(manifest):
    records = manifest.get("captures", [manifest])
    if not records:
        raise InventoryError("GFXReconstruct audit has no captures")
    for record in records:
        capture = record["capture"]
        if hash_file(Path(capture["path"])) != capture["sha256"]:
            raise InventoryError("GFXReconstruct capture changed after audit")
        converter = record["converter"]
        if hash_file(Path(converter["path"])) != converter["sha256"]:
            raise InventoryError("GFXReconstruct converter changed after audit")
        for module in record.get("shader_modules", {}).values():
            for item in module.get("archive_files", []):
                if hash_file(Path(item["path"])) != item["sha256"]:
                    raise InventoryError("Matched shader archive module changed after capture audit")
    return True


def capture_view(snapshot):
    audit = snapshot.get("gfxr_capture_audit")
    if not audit:
        return ""
    records = audit.get("captures", [audit])
    esc = lambda value: html.escape(str(value))
    draw_total = sum(r.get("fsi", {}).get("draw_calls", 0) for r in records)
    pipeline_total = sum(r.get("fsi", {}).get("unique_pipelines", 0) for r in records)
    unique_modules = {m for r in records for m in r.get("fsi", {}).get("shader_module_uses", {})}
    rows = []
    details = []
    for index, record in enumerate(records, 1):
        fsi = record.get("fsi", {})
        capture = record.get("capture", {})
        rows.append(f"<tr><td>{index}</td><td>{esc(capture.get('path'))}</td><td>{esc(capture.get('frames'))}</td>"
                    f"<td>{fsi.get('draw_calls',0):,}</td><td>{fsi.get('command_buffers',0):,}</td>"
                    f"<td>{fsi.get('unique_pipelines',0):,}</td><td>{fsi.get('unique_shader_modules',0):,}</td>"
                    f"<td>{esc(json.dumps(fsi.get('shader_archive_module_counts', {}), sort_keys=True))}</td></tr>")
        top = "".join(
            "<tr><td>" + esc(p["pipeline"]) + "</td><td>" + esc(p["draws"]) + "</td><td>" +
            esc(p.get("topology")) + "</td><td>" + esc(p.get("creation_record")) + "</td><td>" + esc(" · ".join(
                f"{s.get('stage')} module {s.get('module')} ({s.get('archive_match')})" for s in p.get("stages", [])) or
                "Pipeline shader creation record not present in this capture") + "</td></tr>"
            for p in fsi.get("top_pipelines", [])[:12])
        formats = "".join("<tr><td>" + esc(r.get("descriptor_type")) + "</td><td>" + esc(r.get("format")) +
                          "</td><td>" + esc(r.get("view_type")) + "</td><td>" + esc(f"{r.get('width')}×{r.get('height')}×{r.get('depth')}") +
                          "</td><td>" + esc(json.dumps(r.get("component_mapping"), sort_keys=True)) +
                          "</td><td>" + esc(r.get("draw_bind_occurrences")) + "</td></tr>"
                          for r in fsi.get("image_descriptors_by_format", []))
        details.append(f"<details><summary>Capture {index}: frame(s) {esc(capture.get('frames'))} · {fsi.get('draw_calls',0):,} FSI draws</summary>"
                       f"<p>Source SHA-256 <code>{esc(capture.get('sha256'))}</code>. {esc(record.get('analysis', {}).get('scope'))}</p>"
                       f"<h3>Highest-use FSI pipelines</h3><div class=\"scroll\"><table><thead><tr><th>Pipeline</th><th>Draws</th><th>Topology</th><th>Creation record</th><th>Shader modules</th></tr></thead><tbody>{top}</tbody></table></div>"
                       f"<h3>Bound image descriptor declarations</h3><div class=\"scroll\"><table><thead><tr><th>Descriptor</th><th>Format</th><th>View</th><th>Extent</th><th>Component mapping</th><th>Bind occurrences</th></tr></thead><tbody>{formats}</tbody></table></div>"
                       f"<p>{fsi.get('bound_image_descriptor_slots',0):,} initialized image-descriptor bindings; {fsi.get('unresolved_image_view_slots',0):,} references without captured image-view metadata; {fsi.get('bound_sets_rewritten_later_in_api_order',0):,} draw-to-set bindings whose descriptor set was written again later in the API trace. Descriptor values are sampled at the recorded draw's API position, not asserted as execution-time state.</p></details>")
    module_roles = Counter()
    for record in records:
        for role, count in record.get("fsi", {}).get("shader_archive_module_counts", {}).items():
            module_roles[role] += count
    return f"""<section id="gfxr-capture"><h2>Offline GFXReconstruct capture audit</h2>
<p>{len(records)} supplied capture(s) · one-frame Vulkan API traces parsed on CPU. Capture hashes are checked while rendering this report.</p>
<p>Recorded commands/state only. Captures were not replayed; no game shaders were dispatched. Resource declarations do not contain sampled pixel values or prove which draw caused the image defect.</p>
<div class="cards"><div class="card"><b>{draw_total:,}</b>draw calls in identified FSI pass(es)</div>
<div class="card"><b>{pipeline_total:,}</b>per-capture FSI pipeline observations</div>
<div class="card"><b>{len(unique_modules):,}</b>distinct captured shader module handles across traces</div>
<div class="card"><b>{esc(json.dumps(dict(module_roles), sort_keys=True))}</b>exact archive matches by role (module-use observations)</div></div>
<p>FSI passes were identified by attachment-less render passes with an 8192×8192-or-larger framebuffer. Descriptor-to-ISO-tag identity, actual pixel content and visual correctness remain unverified.</p>
<div class="scroll"><table><thead><tr><th>#</th><th>Capture</th><th>Frame(s)</th><th>FSI draws</th><th>Command buffers</th><th>Pipelines</th><th>Shader modules</th><th>Exact archive matches by role</th></tr></thead><tbody>{''.join(rows)}</tbody></table></div>
{''.join(details)}
</section>"""
