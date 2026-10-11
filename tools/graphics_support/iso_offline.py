"""Extract retail Halo 3 shader microcode and run CPU-only compiler checks.

Halo layout facts: XboxChaos/Assembly fd14ef3c and TagTool ce2dc6ac;
see README for pinned primary sources. Payload offsets are checked against the
owning map, not merely the ISO. Never launch Xenia or submit GPU commands.
"""
from __future__ import annotations

from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import math
import shlex
import struct

from .checks import execute, executable
from .iso import InventoryError, hash_file, inventory, read_at

STAGES = ("translation", "rewrite", "spirv_validation", "msl_conversion", "air_compilation")
POLICY = "halo3-retail-xbox-microcode-fsi-default-v1"
PROFILE = {"name": "FSI default vertex/pixel, 1x resolution, 256 dynamic registers",
           "vertex_interpolators": "all guest-written outputs", "pixel_interpolators": "all 16 inputs",
           "spirv": "1.5", "max_storage_buffer_range": 134217728,
           "full_draw_index_uint32": True, "vertex_pipeline_stores_and_atomics": True,
           "fragment_stores_and_atomics": True, "fragment_shader_sample_interlock": True,
           "clip_distance": False, "cull_distance": False, "image_view_format_swizzle": False,
           "signed_zero_inf_nan_preserve_float32": False, "denorm_flush_to_zero_float32": False,
           "rounding_mode_rte_float32": False, "demote_to_helper_invocation": False,
           "native_2x_msaa": False,
           "limits": "Declared compile profile; runtime pipeline state, tessellation, clip planes, resource values and visual fidelity remain untested."}


def u32(data, offset=0):
    return struct.unpack_from(">I", data, offset)[0]


def inspect_vertex_fetches(code):
    """Independent metadata audit of EXEC/fetch fields documented by ucode.h.

    Full fetch stride is word 2 bits 0..7; mini fetch (word 1 bit 30)
    inherits its full fetch's stride. This never supplies a guessed layout.
    """
    if len(code) < 12 or len(code) % 12:
        raise InventoryError("Invalid vertex microcode extent")
    words = struct.unpack(f">{len(code)//4}I",code)
    bound, i, clauses = len(words)//3, 0, []
    while i < bound:
        a,b,c = words[i*3:i*3+3]
        for low,high in ((a,b&0xffff),((b>>16)|((c&0xffff)<<16),c>>16)):
            if (high>>12)&15 in (1,2,3,4,5,6,13,14):
                address,count,sequence = low&0xfff,(low>>12)&7,(low>>16)&0xfff
                if address+count > len(words)//3:
                    raise InventoryError("Vertex EXEC outside microcode extent")
                bound=min(bound,address)
                clauses.append((address,count,sequence))
        i+=1
    full,mini,zero = set(),set(),set()
    for address,count,sequence in clauses:
        for n in range(count):
            index=address+n
            if (sequence>>(n*2))&1:
                op,flags,stride=words[index*3:index*3+3]
                if op&31 == 0:
                    if flags&(1<<30):mini.add(index)
                    else:
                        full.add(index)
                        if not stride&255:zero.add(index)
    return {"full_fetches":len(full),"mini_fetches":len(mini),"zero_stride_full_fetches":sorted(zero),
            "runtime_layout_unresolved":bool(zero)}


class CacheReader:
    def __init__(self, stream, entry, iso_size):
        self.stream, self.entry, self.iso_size = stream, entry, iso_size
        h = self.read(0, 12288)
        if h[:4] != b"head" or u32(h, 4) != 11 or h[284:316].split(b"\0")[0] != b"11855.07.08.20.2317.halo3_ship":
            raise InventoryError("Unsupported Halo cache layout")
        adjust = struct.unpack_from(">i", h, 1140)[0]
        self.magic = u32(h, 744) - ((u32(h, 1164) + adjust) & 0xffffffff)

    def read(self, offset, size):
        if offset < 0 or offset + size > self.entry["size"]:
            raise InventoryError("Shader pointer outside owning map")
        return read_at(self.stream, self.entry["offset"] + offset, size, self.iso_size)

    def pointer(self, pointer, size):
        if pointer == 0:
            raise InventoryError("Null shader data pointer")
        return self.read(pointer - self.magic, size)


def extract_program(reader, block, stage):
    """Return code/constants with explicit source extents; null slots are absent."""
    runtime = u32(block, 76)
    if runtime == 0:
        return {"status": "absent", "reason": "Null compiled Xbox shader slot"}, None, None
    header_size = 0x28 if stage == "ps" else 0x368
    header = reader.pointer(runtime, header_size + 28)
    data_pointer = u32(header, 16)
    magic, debug_size, total, _, _, _, code_header = struct.unpack_from(">7I", header, header_size)
    if magic >> 16 != 0x102a or not 28 <= debug_size <= (1 << 20):
        raise InventoryError("Invalid Xbox shader debug header")
    reader.pointer(runtime + header_size, debug_size)
    if total > (1 << 20):
        raise InventoryError("Shader data exceeds bounded extraction limit")
    constants, code = 0, total
    if code_header:
        if code_header < 28 or code_header + 8 > debug_size:
            raise InventoryError("Shader code-size header outside debug structure")
        constants, code = struct.unpack(">II", reader.pointer(runtime + header_size + code_header, 8))
    if code < 12 or code % 12 or constants + code > total:
        raise InventoryError("Invalid shader code/constant sizes")
    payload = reader.pointer(data_pointer, total)
    const_data, microcode = payload[:constants], payload[constants:constants + code]
    source = {"status": "extracted", "stage": stage,
              "runtime_header_offset": runtime - reader.magic,
              "code_offset": data_pointer - reader.magic + constants,
              "code_bytes": code, "constant_bytes": constants,
              "constants_sha256": hashlib.sha256(const_data).hexdigest(),
              "debug_header_sha256": hashlib.sha256(header).hexdigest()}
    return source, microcode, const_data


def extract_shaders(snapshot, output):
    # Fresh inventory supplies both hash verification and independently reread
    # table identities; never trust a saved snapshot's offsets without checking.
    print("Verifying ISO hash and rereading shader tag tables (read only)...", flush=True)
    fresh = inventory(Path(snapshot["iso"]["path"]))
    if fresh["sha256"] != snapshot["iso"]["sha256"] or fresh["policy"] != snapshot["iso"]["policy"]:
        raise InventoryError("ISO or inventory policy changed; scan a new baseline")
    if fresh["files"] != snapshot["iso"]["files"]:
        raise InventoryError("Saved ISO filesystem inventory differs")
    expected = {a["id"]: a["metadata_offset"] for a in snapshot["iso"]["assets"]}
    if expected != {a["id"]: a["metadata_offset"] for a in fresh["assets"]}:
        raise InventoryError("Saved tag inventory differs from the ISO")
    iso = Path(fresh["path"])
    before = iso.stat()
    files = {e["path"]: e for e in fresh["files"]}
    modules, tags, references = {}, [], []
    code_dir, constant_dir = output / "microcode", output / "constants"
    code_dir.mkdir(); constant_dir.mkdir()
    with iso.open("rb") as stream:
        readers = {}
        for a in fresh["assets"]:
            if a["class"] not in ("pixl", "vtsh", "glps", "glvs"):
                continue
            tag = {"asset_id": a["id"], "map": a["map"], "name": a["name"], "class": a["class"], "status": "unknown"}
            tags.append(tag)
            try:
                if a["map"] not in readers:
                    readers[a["map"]] = CacheReader(stream, files[a["map"]], fresh["size"])
                reader = readers[a["map"]]
                offset = 20 if a["class"] in ("pixl", "vtsh") else 16
                count, ptr = struct.unpack(">II", reader.read(a["metadata_offset"] + offset, 8))
                if count > 8192:
                    raise InventoryError("Compiled shader table exceeds extraction limit")
                tag.update(status="enumerated", slots=count)
                blocks = reader.pointer(ptr, count * 80) if count else b""
                stage = "ps" if a["class"] in ("pixl", "glps") else "vs"
                for n in range(count):
                    reference = {"asset_id": a["id"], "slot": n}
                    references.append(reference)
                    try:
                        source, code, const = extract_program(reader, blocks[n*80:(n+1)*80], stage)
                        reference.update(source)
                        if code is None:
                            continue
                        sha = hashlib.sha256(code).hexdigest()
                        key = stage + ":" + sha
                        reference["module_id"] = key
                        if key not in modules:
                            path = code_dir / (sha + "." + stage)
                            path.write_bytes(code)
                            modules[key] = {"id": key, "stage": stage, "sha256": sha,
                                            "bytes": len(code), "path": str(path),
                                            "checks": {s: {"status": "unknown"} for s in STAGES}}
                        const_path = constant_dir / (source["constants_sha256"] + ".bin")
                        if not const_path.exists():
                            const_path.write_bytes(const)
                    except InventoryError as error:
                        reference.update(status="unknown", reason=str(error))
            except InventoryError as error:
                tag.update(status="unknown", reason=str(error))
    after = iso.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise InventoryError("ISO changed during extraction")
    result = {"policy": POLICY, "iso_sha256": fresh["sha256"], "profile": PROFILE,
              "tags": tags, "references": references, "modules": sorted(modules.values(), key=lambda m: m["id"]),
              "texture_check": {"scope": "Bitmap metadata only; resource page extraction/untile/decode not implemented. No supported-texture percentage asserted.",
                                "subimages": sum(len(a.get("subimages", [])) for a in fresh["assets"]),
                                "payload_pass": 0, "payload_fail": 0,
                                "formats": dict(Counter(str(i["format"]) for a in fresh["assets"] for i in a.get("subimages", [])))},
              "scope": "ISO-resident compiled shader slots, deduplicated by stage + SHA-256. CPU translation and compiler acceptance only; no GPU dispatch or rendering proof.",
              "output": str(output)}
    print(f"Extracted {len(modules):,} unique programs from {len(references):,} slots in {len(tags):,} shader tags", flush=True)
    return result


def check_module(module, translator, helper, output, tools, profile):
    """Persist each completed outcome, including failures and unknown inputs."""
    try:
        _check_module(module, translator, helper, output, tools, profile)
    finally:
        folder = output / (module["stage"] + "-" + module["sha256"])
        if folder.is_dir():
            checkpoint = folder / "result.json.tmp"
            checkpoint.write_text(json.dumps(module, indent=2))
            checkpoint.replace(folder / "result.json")


def _check_module(module, translator, helper, output, tools, profile):
    sha, stage = module["sha256"], module["stage"]
    folder = output / (stage + "-" + sha)
    folder.mkdir()
    original, rewritten = folder / "original", folder / "rewritten"
    original.mkdir(); rewritten.mkdir()
    spv = original / (sha + ".spv")
    checks = module["checks"]
    code = Path(module["path"])
    if hash_file(code) != sha:
        raise InventoryError("Extracted shader hash changed")
    if stage == "vs":
        module["vertex_fetch_audit"] = inspect_vertex_fetches(code.read_bytes())
    checks["translation"] = execute([str(translator), stage, str(code), str(spv), str(profile["feature_mask"]),
                                     str(profile["max_storage_buffer_range"]), str(profile["spirv_version"])], folder / "translate.log")
    if checks["translation"].get("returncode") == 6:
        checks["translation"].update(status="unknown", reason="Runtime vertex declaration required; ISO fetch template has zero stride")
    if checks["translation"]["status"] != "pass":
        return
    if not spv.is_file() or spv.stat().st_size < 20:
        checks["translation"].update(status="fail", reason="No SPIR-V produced")
        return
    checks["translation"].update(output=str(spv), output_sha256=hash_file(spv))
    checks["rewrite"] = execute([str(helper), str(original), str(rewritten)], folder / "rewrite.log")
    spv = rewritten / (sha + ".spv")
    if checks["rewrite"]["status"] != "pass":
        return
    if not spv.is_file():
        checks["rewrite"].update(status="fail", reason="No hardened SPIR-V produced")
        return
    checks["rewrite"].update(output=str(spv), output_sha256=hash_file(spv))
    if not tools["validator"]:
        return
    checks["spirv_validation"] = execute([tools["validator"], "--target-env", "vulkan1.2", str(spv)], folder / "validate.log")
    if checks["spirv_validation"]["status"] == "pass":
        # Validation produces no new file; retain the identity of the artifact
        # that passed, as well as the command, exit code and diagnostic log.
        checks["spirv_validation"].update(output=str(spv), output_sha256=hash_file(spv))
    if checks["spirv_validation"]["status"] != "pass" or not tools["converter"]:
        return
    metal, air = folder / "shader.metal", folder / "shader.air"
    checks["msl_conversion"] = execute([tools["converter"], "-si", str(spv), "-mo", str(metal), "-mv", "2.3", "-mp", "macos", "-q"], folder / "convert.log")
    if checks["msl_conversion"]["status"] != "pass":
        return
    if not metal.is_file() or not metal.stat().st_size:
        checks["msl_conversion"].update(status="fail", reason="No MSL produced")
        return
    checks["msl_conversion"].update(output=str(metal), output_sha256=hash_file(metal))
    if tools["xcrun"]:
        checks["air_compilation"] = execute([tools["xcrun"], "-sdk", "macosx", "metal", "-std=macos-metal2.3", "-c", str(metal), "-o", str(air)], folder / "metal.log")
        if checks["air_compilation"]["status"] == "pass":
            if not air.is_file() or not air.stat().st_size:
                checks["air_compilation"].update(status="fail", reason="No AIR produced")
            else:
                checks["air_compilation"].update(output=str(air), output_sha256=hash_file(air))


def unknown_reason(module):
    checks = module["checks"]
    if any(c["status"] == "fail" for c in checks.values()) or all(c["status"] == "pass" for c in checks.values()):
        return ""
    if any("missing or changed" in c.get("reason", "") for c in checks.values()):
        return "stale evidence"
    if checks["translation"].get("returncode") == 6:
        return "runtime vertex layout"
    if not checks["translation"].get("command"):
        return "untested"
    return "incomplete check"


def shader_tag_matrix(result):
    """Map compiler evidence back to every extracted ISO shader-family tag.

    This is a slot-level compiler view. Null slots are reported separately and
    never counted as failed shaders; it cannot establish pipeline pairing or
    correct rendering.
    """
    modules = {m["id"]: m for m in result.get("modules", [])}
    references = {}
    for ref in result.get("references", []):
        references.setdefault(ref.get("asset_id"), []).append(ref)
    rows = []
    tag_states = Counter()
    slot_counts = Counter()
    for tag in result.get("tags", []):
        slots = references.get(tag.get("asset_id"), [])
        counts = Counter()
        for ref in slots:
            state = ref.get("status", "unknown")
            if state == "absent":
                counts["absent"] += 1
                continue
            if state != "extracted":
                counts["extraction_unknown"] += 1
                continue
            counts["extracted"] += 1
            module = modules.get(ref.get("module_id"))
            if module is None:
                counts["compiler_unknown"] += 1
            elif any(module.get("checks", {}).get(stage, {}).get("status") == "fail" for stage in STAGES):
                counts["compiler_fail"] += 1
            elif all(module.get("checks", {}).get(stage, {}).get("status") == "pass" for stage in STAGES):
                counts["compiler_ready"] += 1
            else:
                counts["compiler_unknown"] += 1
        if tag.get("status") != "enumerated":
            state = "tag_parse_unknown"
        elif not slots or counts["absent"] == len(slots):
            state = "no_compiled_program"
        elif counts["compiler_fail"]:
            state = "compiler_failed"
        elif counts["extraction_unknown"] or counts["compiler_unknown"]:
            state = "compiler_unknown"
        else:
            state = "compiler_ready"
        tag_states[state] += 1
        slot_counts.update(counts)
        rows.append([tag.get("asset_id", ""), tag.get("name", ""), tag.get("map", ""),
                     tag.get("class", ""), state, len(slots), counts["absent"], counts["extracted"],
                     counts["compiler_ready"], counts["compiler_fail"],
                     counts["extraction_unknown"] + counts["compiler_unknown"]])
    summary = {"tags": len(rows), "tag_states": dict(sorted(tag_states.items())),
               "slots": sum(slot_counts.values()), "absent_slots": slot_counts["absent"],
               "extracted_slots": slot_counts["extracted"],
               "compiler_ready_slots": slot_counts["compiler_ready"],
               "compiler_failed_slots": slot_counts["compiler_fail"],
               "unknown_slots": slot_counts["extraction_unknown"] + slot_counts["compiler_unknown"],
               "scope": "ISO shader-tag slots mapped to compiler outcomes; null slots are separate, and pipeline pairing/rendering remain unverified."}
    return summary, rows


def offline_summary(result):
    modules = result.get("modules", [])
    total = len(modules)
    stages = {s: dict(Counter(m["checks"][s]["status"] for m in modules)) for s in STAGES}
    passed = sum(all(m["checks"][s]["status"] == "pass" for s in STAGES) for m in modules)
    failed = sum(any(m["checks"][s]["status"] == "fail" for s in STAGES) for m in modules)
    by_id = {m["id"]: m for m in modules}
    extracted = [r for r in result["references"] if r["status"] == "extracted"]
    ready_refs = sum(all(by_id[r["module_id"]]["checks"][s]["status"] == "pass" for s in STAGES) for r in extracted)
    tag_mapping, _ = shader_tag_matrix(result)
    return {"unique_programs": total, "compiler_ready": passed, "compiler_fail": failed,
            "compiler_unknown": total - passed - failed,
            "unknown_reasons": dict(Counter(unknown_reason(m) for m in modules if unknown_reason(m))),
            "compiler_ready_percent": round(100*passed/total, 3) if total else None,
            "shader_tags": len(result["tags"]), "tag_parse_unknown": sum(t["status"] == "unknown" for t in result["tags"]),
            "empty_tags": sum(t.get("slots") == 0 and t["status"] == "enumerated" for t in result["tags"]),
            "enumerated_slots": len(result["references"]), "extracted_references": len(extracted),
            "compiler_ready_references": ready_refs,
            "reference_ready_percent": round(100*ready_refs/len(extracted), 3) if extracted else None,
            "absent_slots": sum(r["status"] == "absent" for r in result["references"]),
            "extraction_unknown_slots": sum(r["status"] == "unknown" for r in result["references"]),
            "stages": stages, "tag_mapping": tag_mapping}


def compare_compilers(before, after, target=None):
    if before["policy"] != after["policy"] or before["iso_sha256"] != after["iso_sha256"]:
        raise InventoryError("Cannot compare compiler results across different ISO/layout policies")
    left = {m["id"]: m for m in before["modules"]}
    right = {m["id"]: m for m in after["modules"]}
    if set(left) != set(right):
        raise InventoryError("Compiler denominator changed; extraction baseline must match")
    keys = ("name", "vertex_interpolators", "pixel_interpolators", "feature_mask", "spirv_version",
            "max_storage_buffer_range", "native_2x_msaa", "driver_sha256")
    if any(before["profile"].get(k) != after["profile"].get(k) for k in keys):
        raise InventoryError("Compiler profile/driver changed; compare the same test conditions")
    ready = lambda m: all(m["checks"][s]["status"] == "pass" for s in STAGES)
    gained = sorted(i for i in left if not ready(left[i]) and ready(right[i]))
    lost = sorted(i for i in left if ready(left[i]) and not ready(right[i]))
    old, new = sum(map(ready,left.values())),sum(map(ready,right.values()))
    result = {"denominator":len(left),"ready_before":old,"ready_after":new,"gained":gained,"lost":lost,
              "percentage_point_change":100*(new-old)/len(left) if left else None,
              "scope":"Compiler readiness only; identical extracted programs/profile/driver. Rendering and FPS are separate."}
    if target is not None:
        if not math.isfinite(target) or not 0 <= target <= 100:
            raise InventoryError("Compiler target must be a finite percentage from 0 to 100")
        result.update(target_percent=target, additional_ready_programs_needed=max(0,math.ceil(target*len(left)/100)-new))
    return result


def verify_offline_artifacts(result):
    """Withdraw stale compiler claims without changing the extracted denominator."""
    cache, gaps = {}, []

    def matches(path, sha):
        if not path or not sha:
            return False
        if path not in cache:
            try: cache[path] = hash_file(Path(path))
            except OSError: cache[path] = None
        return cache[path] == sha

    records = (result.get("modules", []) + result.get("texture_check", {}).get("loaders", []) +
               result.get("neutral_vertex_layout", {}).get("modules", []) +
               result.get("vertex_format_matrix", {}).get("modules", []))
    for record in records:
        original_ok = matches(record.get("path",record.get("source")),record["sha256"])
        for stage,check in record["checks"].items():
            if check["status"] not in ("pass","fail"):
                continue
            valid = original_ok and matches(check.get("log"),check.get("log_sha256"))
            if check["status"] == "pass":
                valid = valid and matches(check.get("output"),check.get("output_sha256"))
            if not valid:
                gaps.append({"id":record.get("id",record.get("name")),"stage":stage})
                check.update(status="unknown",reason="Saved compiler input/log/output missing or changed")
    result["artifact_verification"] = {"files_checked":len(cache),"withdrawn_stage_claims":gaps}
    result["summary"] = offline_summary(result)
    return result["artifact_verification"]


def compiled_dependency_hashes(build):
    """Hash actual compiler dependencies, including integration/system headers."""
    paths = set()
    for dependency in Path(build).rglob("*.o.d"):
        body = dependency.read_text().replace("\\\n", " ").partition(":")[2]
        paths.update(Path(p) for p in shlex.split(body) if Path(p).is_file())
    return {str(p): hash_file(p) for p in sorted(paths)}


def recover_iso_checks(snapshot, evidence):
    """Recover only durable outcomes; files without checkpoints remain unknown."""
    evidence = evidence.resolve()
    result = json.loads((evidence / "checkpoint-baseline.json").read_text())
    current = snapshot.get("iso_offline", {})
    if result["iso_sha256"] != snapshot["iso"]["sha256"] or result["policy"] != POLICY:
        raise InventoryError("Checkpoint ISO/policy differs from inventory")
    if {m["id"] for m in result["modules"]} != {m["id"] for m in current.get("modules", [])}:
        raise InventoryError("Checkpoint program denominator differs from extraction")
    for module in result["modules"]:
        p = evidence / "checks" / (module["stage"]+"-"+module["sha256"]) / "result.json"
        if not p.is_file():
            continue
        saved = json.loads(p.read_text())
        if any(saved.get(k) != module[k] for k in ("id","stage","sha256","path")):
            raise InventoryError("Checkpoint shader identity differs")
        if set(saved["checks"]) != set(STAGES) or any(c["status"] not in ("pass","fail","unknown") for c in saved["checks"].values()):
            raise InventoryError("Invalid checkpoint outcomes")
        module.update(saved)
    recovered = sum(bool(m["checks"]["translation"].get("command")) for m in result["modules"])
    result["sweep"] = {"complete": recovered == len(result["modules"]), "checkpointed_programs": recovered,
                       "uncheckpointed_programs": len(result["modules"])-recovered,
                       "note": "Recovered saved stage outcomes. Unfinished/uncheckpointed checks remain unknown."}
    snapshot["iso_offline"] = result
    verify_offline_artifacts(result)
    return result


def verified_baseline(snapshot, output):
    """Verify the saved translator, rewrite helper, sources, tools and driver.

    Shared by every continuation so a changed identity refuses the run instead
    of silently becoming a different test profile. Returns the compiler
    evidence record plus the verified executables.
    """
    result = snapshot.get("iso_offline")
    if not result or result["policy"] != POLICY or result["iso_sha256"] != snapshot["iso"]["sha256"]:
        raise InventoryError("No matching ISO compiler baseline")
    output, source = output.resolve(), Path(result["xenia_source"]).resolve()
    if output.exists() or output == source or source in output.parents:
        raise InventoryError("Use a new continuation evidence directory outside Xenia")
    # Validate the actual translator/helper and every recorded source/header.
    original = Path(result["compilation_output"])
    translator, helper = original / "native-build/iso_shader_translate", original / "prepare"
    identities = {str(translator):result["translator_sha256"], str(helper):result["rewrite_helper_sha256"],
                  result["profile"]["driver_path"]:result["profile"]["driver_sha256"]}
    for group in ("translation_source_hashes","harness_hashes","rewrite_sources","compiled_dependency_hashes"):
        identities.update(result.get(group,{}))
    identities.update({v["path"]:v["sha256"] for v in result["tools"].values() if v})
    for path,sha in identities.items():
        if hash_file(Path(path)) != sha:
            raise InventoryError(f"Compiler baseline changed: {path}; create a new test baseline")
    verify_offline_artifacts(result)
    return result, original, translator, helper, output


def query_saved_profile(result, original, output):
    """Re-query the physical device with the saved helper; refuse any drift."""
    query = execute([str(original/"native-build/iso_shader_profile"),result["profile"]["driver_path"]],output/"profile.log")
    if query["status"] != "pass":
        raise InventoryError("Saved physical-device profile query did not pass")
    profile = json.loads((output/"profile.log").read_text())
    if any(result["profile"].get(k) != v for k,v in profile.items()):
        raise InventoryError("Physical-device features changed; create a new compiler baseline")
    return query, profile


def resume_iso_checks(snapshot, output, workers=4, limit=None):
    """Continue untested/indeterminate programs using verified saved tools.

    Preserves completed passes and failures. No rebuilding or driver/source
    migration is silently treated as an equivalent test profile.
    """
    if not 1 <= workers <= 8 or limit is not None and limit < 1:
        raise InventoryError("Workers must be 1..8 and limit positive")
    result, original, translator, helper, output = verified_baseline(snapshot, output)
    selected = [m for m in result["modules"] if not any(c["status"]=="fail" for c in m["checks"].values())
                and not all(c["status"]=="pass" for c in m["checks"].values())
                and m["checks"]["translation"].get("returncode") != 6]
    selected = selected[:limit] if limit else selected
    output.mkdir(parents=True)
    query, profile = query_saved_profile(result, original, output)
    result.setdefault("continuations",[]).append({"output":str(output),"selected":len(selected),"profile_query":query,
                                                "scope":"Additional testing with unchanged sources/tools/profile; no runtime support fix inferred."})
    (output/"checkpoint-baseline.json").write_text(json.dumps(result,indent=2))
    tools = {k:v["path"] if v else None for k,v in result["tools"].items()}
    checks = output/"checks";checks.mkdir()
    def check(module):
        module["checks"] = {s:{"status":"unknown"} for s in STAGES}
        check_module(module,translator,helper,checks,tools,profile)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for n,_ in enumerate(pool.map(check,selected),1):
            if n%25==0 or n==len(selected):print(f"Additional ISO compiler checks {n}/{len(selected)}",flush=True)
    checked=sum(bool(m["checks"]["translation"].get("command")) for m in result["modules"])
    result["sweep"]={"complete":checked==len(result["modules"]),"checkpointed_programs":checked,
                     "uncheckpointed_programs":len(result["modules"])-checked,
                     "note":"Saved outcomes include earlier baseline and verified continuations. Untested programs remain unknown."}
    result["summary"]=offline_summary(result)
    (output/"manifest.json").write_text(json.dumps(result,indent=2))
    return result


def iso_check(snapshot, output, root, xenia_source, zig="zig", validator="spirv-val",
              converter="MoltenVKShaderConverter", workers=4, limit=None, extract=True, driver=None):
    source, output = xenia_source.resolve(strict=True), output.resolve()
    if source == output or source in output.parents or output.exists():
        raise InventoryError("Use a new evidence directory outside the read-only Xenia tree")
    if not 1 <= workers <= 8 or limit is not None and limit < 1:
        raise InventoryError("Workers must be 1..8 and limit positive")
    output.mkdir(parents=True)
    if extract:
        result = extract_shaders(snapshot, output)
    else:
        result = snapshot.get("iso_offline")
        if not result or result["policy"] != POLICY or result["iso_sha256"] != snapshot["iso"]["sha256"]:
            raise InventoryError("No matching extracted ISO evidence")
        for module in result["modules"]:
            if hash_file(Path(module["path"])) != module["sha256"]:
                raise InventoryError("Extracted microcode changed")
            module["checks"] = {s: {"status": "unknown"} for s in STAGES}
    result["compilation_output"] = str(output)
    snapshot["iso_offline"] = result
    tools = {k: executable(v) for k, v in {"cmake": "cmake", "clang": "clang++", "zig": zig,
                                          "validator": validator, "converter": converter, "xcrun": "xcrun"}.items()}
    result["tools"] = {k: {"path": v, "sha256": hash_file(Path(v))} if v else None for k, v in tools.items()}
    result["xenia_source"] = str(source)
    # Hash the exact selected translation source families and their headers.
    sources = sorted(set((source / "src/xenia/gpu").glob("*.h")) |
                     set((source / "src/xenia/base").glob("*.h")) |
                     set((source / "src/xenia/gpu").glob("*shader*.cc")) |
                     set((source / "third_party/glslang/SPIRV").glob("*.h")) |
                     set((source / "third_party/glslang/SPIRV").glob("*.cpp")) |
                     {source / "src/xenia/gpu/ucode.cc", source / "src/xenia/gpu/draw_util.cc",
                      source / "src/xenia/base/string_buffer.cc"})
    result["translation_source_hashes"] = {str(p): hash_file(p) for p in sources}
    result["harness_hashes"] = {str(p): hash_file(p) for p in sorted((root / "tools/graphics_support/native").rglob("*")) if p.is_file()}
    build, translator = output / "native-build", output / "native-build/iso_shader_translate"
    if not all(tools[k] for k in ("cmake", "clang", "zig")):
        result["build"] = {"status": "unknown", "reason": "Required native compiler/CMake/Zig unavailable"}
    else:
        result["configure"] = execute([tools["cmake"], "-S", str(root / "tools/graphics_support/native"), "-B", str(build),
                                        f"-DXENIA_SOURCE={source}", f"-DCMAKE_CXX_COMPILER={tools['clang']}",
                                        "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_BUILD_TYPE=Release"], output / "configure.log")
        if result["configure"]["status"] == "pass":
            result["build"] = execute([tools["cmake"], "--build", str(build), "-j", str(workers)], output / "build.log", timeout=600)
        else:
            result["build"] = {"status": "unknown", "reason": "Configuration did not pass"}
        helper = output / "prepare"
        paths = [root / "tools/vulkan/prepare_rect_shaders.zig", root / "lib/gpu/vulkan/rect_list_expand.zig", root / "lib/gpu/vulkan/robust_access.zig"]
        result["rewrite_sources"] = {str(p): hash_file(p) for p in paths}
        result["build_rewrite"] = execute([tools["zig"], "build-exe", "-O", "ReleaseFast", "-lc", "--dep", "rect", "--dep", "robust",
                                            f"-Mroot={paths[0]}", f"-Mrect={paths[1]}", f"-Mrobust={paths[2]}", f"-femit-bin={helper}"], output / "build-rewrite.log", timeout=120)
        if result["build"]["status"] == result["build_rewrite"]["status"] == "pass":
            result["translator_sha256"] = hash_file(translator)
            result["rewrite_helper_sha256"] = hash_file(helper)
            result["compiled_dependency_hashes"] = compiled_dependency_hashes(build)
            if driver is None:
                driver = Path(tools["converter"]).parent.parent / "lib/libMoltenVK.dylib" if tools["converter"] else None
            if driver is None or not driver.is_file():
                raise InventoryError("Pass --driver with the MoltenVK dylib for a read-only capability query")
            result["profile_query"] = execute([str(build / "iso_shader_profile"), str(driver.resolve())], output / "profile.log")
            if result["profile_query"]["status"] != "pass":
                raise InventoryError("FSI physical-device capability query did not pass")
            profile = json.loads((output / "profile.log").read_text())
            result["profile"] = {**PROFILE, **profile, "driver_path": str(driver.resolve()), "driver_sha256": hash_file(driver),
                                 "limits": "Queried device features; one FSI vertex/pixel interface per shader. Runtime vertex declarations and other pipeline variants remain unknown."}
            # Preserve the complete extraction/profile/build baseline before
            # long checks; per-module result.json files survive interruptions.
            (output / "checkpoint-baseline.json").write_text(json.dumps(result, indent=2))
            selected = result["modules"][:limit] if limit else result["modules"]
            checks_dir = output / "checks"
            checks_dir.mkdir()
            with ThreadPoolExecutor(max_workers=workers) as pool:
                jobs = [pool.submit(check_module, m, translator, helper, checks_dir, tools, profile) for m in selected]
                for n, job in enumerate(jobs, 1):
                    job.result()
                    if n % 25 == 0 or n == len(jobs):
                        print(f"ISO shader compiler checks {n}/{len(jobs)}", flush=True)
    result["summary"] = offline_summary(result)
    (output / "manifest.json").write_text(json.dumps(result, indent=2))
    return result
