"""Decode Xenos fetch-constant warning records without changing guest state.

The texture and vertex descriptors occupy aliased views of the same Xenos
register aperture. A six-word warning therefore needs its two-bit type decoded
before its words are described as malformed texture data.
"""

from __future__ import annotations

from collections import Counter
import hashlib
import json
import pathlib
import re
from typing import Any, Iterable


FETCH_TYPE_NAMES = {
    0: "invalid_texture",
    1: "invalid_vertex",
    2: "texture",
    3: "vertex",
}
_WORD_RE = re.compile(r"^[0-9A-Fa-f]{8}$")
_WARNING_RE = re.compile(
    r"^\s*(?:w>|warn(?:ing)?\b).*?Texture fetch constant\s*\(([^)]*)\)\s*is completely invalid",
    re.IGNORECASE,
)
_RUN_ID_RE = re.compile(r"^#\s*run_id\s*=\s*([A-Za-z0-9_-]+)\s*$", re.MULTILINE)


def decode_descriptor(raw: str) -> dict[str, Any]:
    """Decode one normalized six-dword Xenos fetch snapshot."""
    normalized = " ".join(raw.split()).upper()
    tokens = normalized.split()
    if len(tokens) != 6 or not all(_WORD_RE.fullmatch(token) for token in tokens):
        return {
            "raw": normalized,
            "parse_status": "invalid_six_dword_record",
            "type_name": "unparsed",
            "type_code": None,
            "vertex_fetch": None,
            "trailing_words_zero": None,
        }

    words = [int(token, 16) for token in tokens]
    type_code = words[0] & 0x3
    type_name = FETCH_TYPE_NAMES[type_code]
    vertex_fetch = None
    if type_code in (1, 3):
        address_dwords = words[0] >> 2
        size_words = (words[1] >> 2) & 0x00FF_FFFF
        vertex_fetch = {
            "address_dwords": address_dwords,
            "address_bytes": address_dwords * 4,
            "endian_code": words[1] & 0x3,
            "size_words": size_words,
            "size_bytes": size_words * 4,
        }

    return {
        "raw": normalized,
        "parse_status": "ok",
        "type_name": type_name,
        "type_code": type_code,
        "vertex_fetch": vertex_fetch,
        "trailing_words_zero": all(word == 0 for word in words[2:]),
    }


def summarize_descriptors(raw_descriptors: Iterable[str]) -> dict[str, Any]:
    """Return occurrence and unique-value counts with exact descriptor decodes."""
    decoded_occurrences = [decode_descriptor(raw) for raw in raw_descriptors]
    unique = {item["raw"]: item for item in decoded_occurrences}
    warning_type_counts = Counter(item["type_name"] for item in decoded_occurrences)
    distinct_type_counts = Counter(item["type_name"] for item in unique.values())
    return {
        "warning_type_counts": dict(sorted(warning_type_counts.items())),
        "distinct_type_counts": dict(sorted(distinct_type_counts.items())),
        "unparsed_warning_lines": sum(item["parse_status"] != "ok" for item in decoded_occurrences),
        "descriptors": [unique[raw] for raw in sorted(unique)],
    }


def vertex_descriptor_examples(summary: dict[str, Any], limit: int = 3) -> list[dict[str, Any]]:
    """Return a few exact type=vertex examples, preserving their decoded ranges."""
    return [
        item
        for item in summary["descriptors"]
        if item["type_name"] == "vertex"
    ][:limit]


def diagnosis_text(summary: dict[str, Any]) -> str | None:
    """Describe only what the encoded words prove, leaving cause unresolved."""
    counts = summary["warning_type_counts"]
    vertex_lines = counts.get("vertex", 0)
    vertex_distinct = summary["distinct_type_counts"].get("vertex", 0)
    if vertex_lines:
        return (
            f"{vertex_lines} warning line(s) across {vertex_distinct} distinct descriptor(s) "
            "carry Xenos type=vertex in the texture-fetch warning path"
        )
    if not counts:
        return None
    return "invalid-texture warning descriptor types: " + ", ".join(
        f"{name}={count}" for name, count in sorted(counts.items())
    )


def audit_log_text(text: str, source_name: str = "<memory>", source_sha256: str | None = None) -> dict[str, Any]:
    """Build a lossless occurrence-to-descriptor audit without GPU execution.

    In particular, this does not treat a descriptor that Xenia reports from a
    texture-fetch path as a texture. The Xenos type bits determine whether a
    native texture-format test is relevant at all.
    """
    lines = text.splitlines()
    run_id_match = _RUN_ID_RE.search(text)
    occurrences: list[dict[str, Any]] = []
    for line_index, line in enumerate(lines):
        warning = _WARNING_RE.search(line)
        if not warning:
            continue
        raw = " ".join(warning.group(1).split()).upper()
        decoded = decode_descriptor(raw)
        row: dict[str, Any] = {
            "line": line_index + 1,
            "raw": decoded["raw"],
            "decode": decoded,
        }
        thread = re.search(r"\b(?:w>|warn(?:ing)?\b)\s+([0-9A-Fa-f]{8})\b", line, re.IGNORECASE)
        if thread:
            row["emitter"] = thread.group(1).upper()

        # Preserve nearby Rosette shader/pipeline IDs as search context. These
        # messages are emitted asynchronously and do not prove which draw or
        # fetch slot used the descriptor.
        nearby = []
        for context_index in range(max(0, line_index - 3), min(len(lines), line_index + 7)):
            context = lines[context_index]
            shader = re.search(
                r"Vulkan FSI SHADER: module_id=(\d+) guest=(0x[0-9A-Fa-f]+).*?spirv_hash=(0x[0-9A-Fa-f]+) bytes=(\d+)",
                context,
            )
            pipeline = re.search(
                r"Vulkan FSI PIPELINE: ordinal=(\d+) result=(\d+).*?module_id=(\d+) shader_hash=(0x[0-9A-Fa-f]+) pipeline_hash=(0x[0-9A-Fa-f]+)",
                context,
            )
            if shader:
                nearby.append({
                    "line": context_index + 1,
                    "kind": "shader_module",
                    "module_id": int(shader.group(1)),
                    "guest": shader.group(2),
                    "spirv_hash": shader.group(3),
                    "bytes": int(shader.group(4)),
                })
            if pipeline:
                nearby.append({
                    "line": context_index + 1,
                    "kind": "pipeline",
                    "ordinal": int(pipeline.group(1)),
                    "result": int(pipeline.group(2)),
                    "module_id": int(pipeline.group(3)),
                    "shader_hash": pipeline.group(4),
                    "pipeline_hash": pipeline.group(5),
                })
        if nearby:
            row["nearby_vulkan_context"] = {
                "relationship": "adjacent_log_events_only; not a proven fetch-slot or draw association",
                "events": nearby,
            }

        # Rosette's enriched fatal-point line is adjacent to the warning and
        # carries an exact guest step/RIP. Keep the link only when the same
        # descriptor text is present; otherwise do not infer association.
        for context_index in range(line_index + 1, min(len(lines), line_index + 4)):
            context = lines[context_index]
            if "PE64 FATAL POINT:" not in context or decoded["raw"] not in context.upper():
                continue
            fatal: dict[str, Any] = {"line": context_index + 1}
            for field, pattern, cast in (
                ("label", r"\blabel=([^\s]+)", str),
                ("occurrence", r"\boccurrence=(\d+)", int),
                ("step", r"\bstep=(\d+)", int),
                ("rip", r"\brip=(0x[0-9A-Fa-f]+)", str),
                ("emitted_by", r"\bemitted_by='([^']*)'", str),
            ):
                found = re.search(pattern, context)
                if found:
                    fatal[field] = cast(found.group(1))
            classification = re.search(r"\bclassification=(.*?)\s+emitted_by=", context)
            if classification:
                fatal["classification"] = classification.group(1)
            row["fatal_point"] = fatal
            break
        occurrences.append(row)

    grouped: dict[str, dict[str, Any]] = {}
    for occurrence in occurrences:
        raw = occurrence["raw"]
        item = grouped.setdefault(raw, {
            "raw": raw,
            "decode": occurrence["decode"],
            "occurrences": [],
            "first_line": occurrence["line"],
            "last_line": occurrence["line"],
        })
        item["occurrences"].append(occurrence)
        item["last_line"] = occurrence["line"]

    descriptors = [grouped[key] for key in sorted(grouped)]
    type_counts = Counter(row["decode"]["type_name"] for row in occurrences)
    unique_type_counts = Counter(row["decode"]["type_name"] for row in descriptors)
    texture_candidates = [row for row in descriptors if row["decode"]["type_name"] == "texture"]
    vertex_descriptors = [row for row in descriptors if row["decode"]["type_name"] == "vertex"]
    vertex_shapes = Counter(
        (
            row["decode"]["vertex_fetch"]["size_words"],
            row["decode"]["vertex_fetch"]["endian_code"],
            row["decode"]["trailing_words_zero"],
        )
        for row in vertex_descriptors
    )
    vertex_addresses = [row["decode"]["vertex_fetch"]["address_bytes"] for row in vertex_descriptors]
    fatal_context_occurrences = [row for row in occurrences if row.get("fatal_point")]
    fatal_context_descriptors = {
        row["raw"]
        for row in descriptors
        if any(occurrence.get("fatal_point") for occurrence in row["occurrences"])
    }
    return {
        "schema": "rosette-xenos-fetch-warning-audit-v1",
        "source": {"name": source_name, "sha256": source_sha256, "run_id": run_id_match.group(1) if run_id_match else None},
        "scope": "log parsing and descriptor-bit decoding only; no Xenia launch, shader execution, or GPU dispatch",
        "counts": {
            "warning_occurrences": len(occurrences),
            "unique_descriptors": len(descriptors),
            "unparsed_occurrences": sum(row["decode"]["parse_status"] != "ok" for row in occurrences),
            "warning_type_counts": dict(sorted(type_counts.items())),
            "unique_type_counts": dict(sorted(unique_type_counts.items())),
            "texture_typed_unique_descriptors": len(texture_candidates),
            "vertex_typed_unique_descriptors": len(vertex_descriptors),
            "matching_fatal_point_contexts": len(fatal_context_occurrences),
            "descriptors_with_fatal_point_context": len(fatal_context_descriptors),
            "vertex_descriptor_shapes": [
                {"size_words": size, "endian_code": endian, "trailing_words_zero": trailing, "unique_count": count}
                for (size, endian, trailing), count in sorted(vertex_shapes.items())
            ],
            "vertex_address_range_bytes": [min(vertex_addresses), max(vertex_addresses)] if vertex_addresses else None,
        },
        "interpretation": {
            "texture_support_status": (
                "not_evaluated_no_texture_typed_warning_descriptors"
                if not texture_candidates else
                "requires_matching_texture_payload_format_and_native_case"
            ),
            "vertex_descriptor_status": (
                "wrong_resource_kind_for_texture_fetch; descriptor structure decoded, backing guest data not verified"
                if vertex_descriptors else "no_vertex_typed_warning_descriptors"
            ),
            "native_metal_claim": "No texture-decoder support is claimed for type=vertex records. Existing synthetic Metal texture tests do not prove these vertex ranges or this Xenia binding path.",
        },
        "descriptors": descriptors,
    }


def audit_log(path: pathlib.Path) -> dict[str, Any]:
    """Read and audit a log while recording its content hash."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        chunks = []
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
            chunks.append(chunk)
    text = b"".join(chunks).decode("utf-8", errors="replace")
    return audit_log_text(text, str(path.resolve()), digest.hexdigest())


def write_audit(path: pathlib.Path, output: pathlib.Path) -> dict[str, Any]:
    """Write an audit JSON file. Parent creation is confined to caller output."""
    result = audit_log(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result
