"""Layout-neutral compiler checks for vertex programs whose fetches are patched at runtime.

The ISO stores every vertex fetch as a template: data format, stride and offset are
all zero because Direct3D patches them when a vertex declaration is bound. Xenia's
translator takes those values from the instruction, so the stored microcode cannot
be translated as it is. This module patches a *declared* layout into a copy of the
microcode and sends it through the unchanged translation → rewrite → validation →
MSL → AIR chain.

What a pass means: the shader, with that declared layout, converts through the
installed compilers. It is not evidence for any layout a real vertex declaration
uses, so these results are reported separately and never raise the main compiler
percentage. What a failure would mean: a conversion defect that is independent of
the stride or offset constants, which is exactly what is worth finding offline.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import html
import json
from pathlib import Path
import struct

from .iso import InventoryError, hash_file
from .iso_offline import STAGES, check_module, query_saved_profile, unknown_reason, verified_baseline

# xenos::VertexFormat values (xenos.h). Only formats with four components are
# patched into arbitrary programs: a fetch whose destination uses components
# that the declared format does not carry is a pairing no real declaration makes.
FORMATS = {"k_8_8_8_8": 6, "k_2_10_10_10": 7, "k_16_16_16_16": 26, "k_16_16_16_16_FLOAT": 32,
           "k_32_32_32_32": 35, "k_32_32_32_32_FLOAT": 38}
PACKED = {"k_8_8_8_8", "k_2_10_10_10", "k_16_16_16_16", "k_32_32_32_32"}
# (label, signed, integer, signed repeating fraction mode bit)
FLAG_VARIANTS = (("unsigned normalized", 0, 0, 0), ("signed normalized", 1, 0, 0),
                 ("signed normalized, alternate repeating fraction", 1, 0, 1),
                 ("unsigned integer", 0, 1, 0), ("signed integer", 1, 1, 0))
FETCH_OPCODES = (1, 2, 3, 4, 5, 6, 13, 14)
NEUTRAL = {"name": "interleaved float4", "format": "k_32_32_32_32_FLOAT", "signed": 0, "integer": 0,
           "rf_mode": 0, "stride_dwords_per_attribute": 4,
           "declaration": "Every vertex attribute is one float4 element (four 32-bit floats). Attributes that share a "
                          "fetch constant are interleaved in program order, so the stride is four dwords times the "
                          "number of attributes in the group and each following attribute's offset is four dwords "
                          "further on."}


def fetch_indices(words):
    """Vertex-fetch instruction indices reachable from EXEC clauses, in program order."""
    bound, i, clauses = len(words) // 3, 0, []
    while i < bound:
        a, b, c = words[i*3:i*3+3]
        for low, high in ((a, b & 0xffff), ((b >> 16) | ((c & 0xffff) << 16), c >> 16)):
            if (high >> 12) & 15 in FETCH_OPCODES:
                address, count, sequence = low & 0xfff, (low >> 12) & 7, (low >> 16) & 0xfff
                if address + count > len(words) // 3:
                    raise InventoryError("Vertex EXEC outside microcode extent")
                bound = min(bound, address)
                clauses.append((address, count, sequence))
        i += 1
    found = set()
    for address, count, sequence in clauses:
        for n in range(count):
            index = address + n
            if (sequence >> (n*2)) & 1 and words[index*3] & 31 == 0:
                found.add(index)
    return sorted(found)


def patch_vertex_microcode(code, format_name=None, signed=None, integer=None, rf_mode=None):
    """Return a copy of big-endian vertex microcode with a declared layout, plus a report.

    Full fetches begin an attribute group; the mini fetches that follow share its
    stride. Nothing but format, signedness/normalization flags, stride and offset
    changes.
    """
    spec = dict(NEUTRAL)
    if format_name is not None:
        spec.update(format=format_name, signed=signed, integer=integer, rf_mode=rf_mode,
                    name=f"{format_name} {'signed' if signed else 'unsigned'} {'integer' if integer else 'normalized'}")
    if spec["format"] not in FORMATS:
        raise InventoryError(f"Unsupported declared vertex format {spec['format']}")
    if len(code) < 12 or len(code) % 12:
        raise InventoryError("Invalid vertex microcode extent")
    words = list(struct.unpack(f">{len(code)//4}I", code))
    indices = fetch_indices(words)
    groups, current = [], None
    for index in indices:
        if (words[index*3+1] >> 30) & 1:
            if current is None:
                raise InventoryError("Mini vertex fetch has no preceding full fetch to declare a stride")
            current.append(index)
        else:
            current = [index]
            groups.append(current)
    if not groups:
        raise InventoryError("Program has no vertex fetch to declare")
    per_attribute = spec["stride_dwords_per_attribute"]
    for group in groups:
        stride = per_attribute * len(group)
        if stride > 255:
            raise InventoryError("Declared stride exceeds the instruction's 8-bit dword field")
        for position, index in enumerate(group):
            w1, w2 = words[index*3+1], words[index*3+2]
            w1 = (w1 & ~((63 << 16) | (1 << 12) | (1 << 13) | (1 << 14))) | (FORMATS[spec["format"]] << 16) \
                | (spec["signed"] << 12) | (spec["integer"] << 13) | (spec["rf_mode"] << 14)
            w2 = (w2 & ~0x7fffffff)                       # stride and offset only; predicate bit survives
            w2 |= (stride if position == 0 else 0) | ((position * per_attribute) << 8)
            words[index*3+1], words[index*3+2] = w1, w2
    patched = struct.pack(f">{len(words)}I", *words)
    return patched, {"layout": spec["name"], "format": spec["format"], "attributes": len(indices),
                     "attribute_groups": len(groups), "strides_dwords": [per_attribute*len(g) for g in groups]}


def _record(base, patched_path, patched_sha, report):
    return {"id": "vs:" + patched_sha, "stage": "vs", "sha256": patched_sha, "path": str(patched_path),
            "base_id": base["id"], "base_sha256": base["sha256"], "layout_report": report,
            "checks": {s: {"status": "unknown"} for s in STAGES}}


def _run(snapshot, output, jobs, workers):
    result, original, translator, helper, output = verified_baseline(snapshot, output)
    output.mkdir(parents=True)
    query, profile = query_saved_profile(result, original, output)
    tools = {k: v["path"] if v else None for k, v in result["tools"].items()}
    microcode, checks = output / "microcode", output / "checks"
    microcode.mkdir(); checks.mkdir()
    records = []
    for base, kwargs in jobs:
        patched, report = patch_vertex_microcode(Path(base["path"]).read_bytes(), **kwargs)
        sha = hashlib.sha256(patched).hexdigest()
        target = microcode / f"{sha}.vs"
        if not target.exists():
            target.write_bytes(patched)
        records.append(_record(base, target, sha, report))
    unique = {r["sha256"]: r for r in records}
    records = list(unique.values())
    done = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for _ in pool.map(lambda r: check_module(r, translator, helper, checks, tools, profile), records):
            done += 1
            if done % 25 == 0 or done == len(records):
                print(f"Layout-neutral vertex compiler checks {done}/{len(records)}", flush=True)
    return result, records, query


def _summary(records):
    passed = [r for r in records if all(r["checks"][s]["status"] == "pass" for s in STAGES)]
    failed = [r for r in records if any(r["checks"][s]["status"] == "fail" for s in STAGES)]
    return {"programs": len({r["base_id"] for r in records}), "variants": len(records),
            "ready": len(passed), "failed": len(failed), "unknown": len(records) - len(passed) - len(failed),
            "stages": {s: {k: sum(r["checks"][s]["status"] == k for r in records) for k in ("pass", "fail", "unknown")}
                       for s in STAGES}}


def neutral_vertex_checks(snapshot, output, workers=4, limit=None):
    """Run every runtime-layout vertex program under the declared float4 layout."""
    if not 1 <= workers <= 8 or limit is not None and limit < 1:
        raise InventoryError("Workers must be 1..8 and limit positive")
    base_result = snapshot.get("iso_offline") or {}
    if base_result.get("neutral_vertex_layout"):
        raise InventoryError("This baseline already has layout-neutral vertex evidence; continue from a new report")
    pending = [m for m in base_result.get("modules", []) if unknown_reason(m) == "runtime vertex layout"]
    pending = pending[:limit] if limit else pending
    result, records, query = _run(snapshot, output, [(m, {}) for m in pending], workers)
    result["neutral_vertex_layout"] = {
        "scope": "Compiler conversion of ISO vertex programs after patching ONE declared layout. A real Direct3D vertex "
                 "declaration can use any of Xenia's vertex formats, strides and offsets, so this is not runtime layout "
                 "evidence and is excluded from the main compiler-ready percentage.",
        "layout": NEUTRAL, "profile_query": query, "modules": records, "summary": _summary(records),
        "output": str(output.resolve())}
    return result["neutral_vertex_layout"]


def format_matrix_checks(snapshot, output, workers=4, programs=8):
    """Exercise Xenia's vertex unpack code for four-component formats and flag variants.

    Smallest programs that fetch at least once, spread over distinct fetch
    counts, keep the matrix bounded; the unpack code is shared by every shader.
    """
    base_result = snapshot.get("iso_offline") or {}
    if base_result.get("vertex_format_matrix"):
        raise InventoryError("This baseline already has vertex format-matrix evidence")
    candidates = []
    for m in base_result.get("modules", []):
        if m["stage"] != "vs" or unknown_reason(m) != "runtime vertex layout":
            continue
        try:
            attributes = len(fetch_indices(list(struct.unpack(f">{Path(m['path']).stat().st_size//4}I", Path(m["path"]).read_bytes()))))
        except (InventoryError, OSError, struct.error):
            continue
        if attributes:
            candidates.append((attributes, m["bytes"], m["sha256"], m))
    candidates.sort(key=lambda c: c[:3])
    chosen, seen = [], set()
    for attributes, _, _, module in candidates:
        if attributes not in seen or len(candidates) <= programs:
            chosen.append(module)
            seen.add(attributes)
        if len(chosen) == programs:
            break
    jobs = []
    for module in chosen:
        for name in FORMATS:
            variants = FLAG_VARIANTS if name in PACKED else FLAG_VARIANTS[:1]
            for _, signed, integer, rf in variants:
                jobs.append((module, dict(format_name=name, signed=signed, integer=integer, rf_mode=rf)))
    result, records, query = _run(snapshot, output, jobs, workers)
    by_format = {}
    for r in records:
        by_format.setdefault(r["layout_report"]["format"], []).append(r)
    result["vertex_format_matrix"] = {
        "scope": "Representative real vertex programs recompiled under each four-component vertex format and flag "
                 "variant. This checks Xenia's unpack translation and the downstream conversion; it does not select, "
                 "predict or verify any layout Halo 3 binds at runtime.",
        "programs": [m["id"] for m in chosen], "profile_query": query, "modules": records,
        "summary": _summary(records),
        "formats": {f: _summary(rs) for f, rs in by_format.items()}, "output": str(output.resolve())}
    return result["vertex_format_matrix"]


def vertex_layout_view(result):
    """HTML for both vertex evidence blocks; empty when neither was run."""
    esc = lambda v: html.escape(str(v))
    neutral, matrix = result.get("neutral_vertex_layout"), result.get("vertex_format_matrix")
    if not neutral and not matrix:
        return ""
    parts = ["<h3>Vertex programs with runtime declarations</h3>"]
    if neutral:
        s = neutral["summary"]
        parts.append(f"""<div class="cards"><div class="card"><b>{s['ready']:,} / {s['variants']:,}</b>convert under the declared float4 layout</div><div class="card"><b>{s['failed']:,}</b>failed checks</div><div class="card"><b>{s['unknown']:,}</b>unknown</div></div>
<p>{esc(neutral['scope'])}</p><p><strong>Declared layout.</strong> {esc(neutral['layout']['declaration'])}</p>
<div class="scroll"><table><thead><tr><th>Offline check</th><th>Pass</th><th>Fail</th><th>Unknown</th></tr></thead><tbody>{''.join(f"<tr><td>{esc(stage)}</td><td>{c['pass']:,}</td><td>{c['fail']:,}</td><td>{c['unknown']:,}</td></tr>" for stage, c in s['stages'].items())}</tbody></table></div>""")
    if matrix:
        s = matrix["summary"]
        rows = "".join(f"<tr><td>{esc(f)}</td><td>{v['variants']:,}</td><td>{v['ready']:,}</td><td>{v['failed']:,}</td><td>{v['unknown']:,}</td></tr>" for f, v in sorted(matrix["formats"].items()))
        parts.append(f"""<p><strong>Vertex format matrix.</strong> {s['ready']:,} / {s['variants']:,} variants of {len(matrix['programs'])} representative programs convert through every stage. {esc(matrix['scope'])}</p>
<div class="scroll"><table><thead><tr><th>Declared format</th><th>Variants</th><th>Ready</th><th>Failed</th><th>Unknown</th></tr></thead><tbody>{rows}</tbody></table></div>""")
    parts.append("<p class=\"note\">Layout-neutral results show that the conversion chain accepts these shapes. They do not show that any ISO vertex shader draws correctly with Halo 3's real declarations, and they never change the main compiler-ready count above.</p>")
    return "".join(parts)
