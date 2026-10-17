#!/usr/bin/env python3
"""Audit Xenos fetch-constant warnings from Rosette logs, without running Xenia.

The output preserves every warning occurrence, exact six-dword descriptor,
descriptor kind, and any adjacent matching Rosette fatal-point context. A
vertex-typed descriptor is reported as a resource-kind mismatch; it is not
misclassified as an unsupported Metal texture format.

    python3 tools/guest_runtime/scripts/audit_fetch_descriptors.py LOG [LOG ...] --out DIR
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

_SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))
import fetch_constant_diagnostics


def _file_stem(audit: dict) -> str:
    run_id = audit["source"].get("run_id")
    if run_id:
        return run_id
    source = pathlib.Path(audit["source"]["name"]).stem
    return source or "fetch-warning-audit"


def _descriptor_bounds(audit: dict) -> tuple[int | None, int | None]:
    addresses = [
        row["decode"]["vertex_fetch"]["address_bytes"]
        for row in audit["descriptors"]
        if row["decode"].get("vertex_fetch") is not None
    ]
    return (min(addresses), max(addresses)) if addresses else (None, None)


def render_summary(audits: list[dict]) -> str:
    lines = [
        "# Xenos fetch warning audit",
        "",
        "This report decodes logged six-dword descriptors. It does not infer texture payload contents or claim that a GPU path is correct.",
        "",
        "| Run | Warning lines | Unique descriptors | Type counts | Matching fatal context | Unparsed | Texture support result |",
        "| --- | ---: | ---: | --- | ---: | ---: | --- |",
    ]
    for audit in audits:
        counts = audit["counts"]
        lines.append(
            f"| `{audit['source'].get('run_id') or pathlib.Path(audit['source']['name']).name}` "
            f"| {counts['warning_occurrences']} | {counts['unique_descriptors']} "
            f"| `{json.dumps(counts['warning_type_counts'], sort_keys=True)}` "
            f"| {counts['matching_fatal_point_contexts']} "
            f"| {counts['unparsed_occurrences']} "
            f"| `{audit['interpretation']['texture_support_status']}` |"
        )
    for audit in audits:
        counts = audit["counts"]
        low, high = _descriptor_bounds(audit)
        lines += [
            "",
            f"## {audit['source'].get('run_id') or pathlib.Path(audit['source']['name']).name}",
            "",
            f"- Source SHA-256: `{audit['source'].get('sha256') or 'unavailable'}`",
            f"- Type counts by unique descriptor: `{json.dumps(counts['unique_type_counts'], sort_keys=True)}`",
            f"- Texture-typed unique descriptors: {counts['texture_typed_unique_descriptors']}",
            f"- Vertex-typed unique descriptors: {counts['vertex_typed_unique_descriptors']}",
            f"- Decoded vertex address range: `{f'0x{low:08X}–0x{high:08X}' if low is not None else 'none'}`",
            f"- Matching fatal-point contexts: {counts['matching_fatal_point_contexts']} warning occurrence(s) across {counts['descriptors_with_fatal_point_context']} descriptor(s)",
            f"- Vertex descriptor shapes: `{json.dumps(counts['vertex_descriptor_shapes'], sort_keys=True)}`",
            f"- Interpretation: {audit['interpretation']['vertex_descriptor_status']}",
            f"- Metal: {audit['interpretation']['native_metal_claim']}",
            f"- Detail JSON: `{_file_stem(audit)}.json`",
        ]
    lines += ["", "Every occurrence and descriptor is in the adjacent JSON files. A decoded vertex range does not prove that its backing guest memory or draw binding is valid.", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path, help="Rosette-owned output directory")
    args = parser.parse_args(argv)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    audits = []
    for log in args.logs:
        audit = fetch_constant_diagnostics.audit_log(log)
        output = out / (_file_stem(audit) + ".json")
        output.write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
        audits.append(audit)
    summary = out / "summary.md"
    summary.write_text(render_summary(audits), encoding="utf-8")
    print(f"Audited {len(audits)} log(s) -> {summary}")
    for audit in audits:
        counts = audit["counts"]
        print(f"{audit['source'].get('run_id') or audit['source']['name']}: "
              f"{counts['warning_occurrences']} warnings, {counts['unique_descriptors']} unique, "
              f"types={counts['warning_type_counts']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
