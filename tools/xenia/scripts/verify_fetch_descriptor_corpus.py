#!/usr/bin/env python3
"""Differentially verify logged fetch descriptors with Rosette's Zig decoder.

Consumes JSON produced by `audit_fetch_descriptors.py`, generates an evidence-
local Zig test, and runs the production `VertexFetch.decode` implementation on
every unique type=vertex descriptor. It does not touch Xenia, dispatch shaders,
or claim that the referenced guest memory is valid.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[3]
VERTEX_DECODER = ROOT / "lib/gpu/fetch_constants/vertex.zig"


def _zig_source(descriptors: list[dict[str, Any]]) -> str:
    records = []
    for descriptor in descriptors:
        decoded = descriptor["decode"]
        if decoded["parse_status"] != "ok" or decoded["type_name"] != "vertex":
            raise ValueError(f"descriptor is not a fully parsed type=vertex record: {descriptor['raw']}")
        words = [int(word, 16) for word in descriptor["raw"].split()]
        fetch = decoded["vertex_fetch"]
        records.append(
            ".{{ .raw = .{{ 0x{0:08x}, 0x{1:08x} }}, .address_bytes = {2}, .size_words = {3}, .endian_code = {4} }}".format(
                words[0], words[1], fetch["address_bytes"], fetch["size_words"], fetch["endian_code"]
            )
        )
    return (
        "const std = @import(\"std\");\n"
        "const vertex = @import(\"vertex\");\n"
        "const Case = struct { raw: [2]u32, address_bytes: u64, size_words: u32, endian_code: u2 };\n"
        f"const cases = [_]Case{{{', '.join(records)}}};\n"
        "test \"all logged vertex-kind fetch descriptors match the production Zig decoder\" {\n"
        "    for (cases) |case| {\n"
        "        const decoded = vertex.VertexFetch.decode(case.raw);\n"
        "        try std.testing.expectEqual(.vertex, decoded.type);\n"
        "        try std.testing.expectEqual(case.address_bytes, decoded.addressBytes());\n"
        "        try std.testing.expectEqual(case.size_words, decoded.size_words);\n"
        "        try std.testing.expectEqual(case.endian_code, @as(u2, @intCast(@intFromEnum(decoded.endian))));\n"
        "    }\n"
        "}\n"
    )


def run(audit_paths: list[pathlib.Path], out: pathlib.Path, zig: str = "zig") -> dict[str, Any]:
    descriptors: dict[str, dict[str, Any]] = {}
    audit_inputs = []
    for path in audit_paths:
        audit = json.loads(path.read_text(encoding="utf-8"))
        audit_inputs.append({"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "run_id": audit["source"].get("run_id")})
        for item in audit.get("descriptors", []):
            if item["decode"].get("type_name") != "vertex":
                raise ValueError(f"not all descriptors are vertex-typed: {item['raw']}")
            descriptors[item["raw"]] = item
    if not descriptors:
        raise ValueError("no vertex descriptors in audit inputs")

    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    zig_test = out / "vertex_fetch_descriptor_corpus.zig"
    zig_test.write_text(_zig_source(list(descriptors.values())), encoding="utf-8")
    zig_path = shutil.which(zig)
    if not zig_path:
        raise FileNotFoundError(f"Zig executable not found: {zig}")
    command = [zig_path, "test", "--dep", "vertex", f"-Mroot={zig_test}", f"-Mvertex={VERTEX_DECODER}"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    (out / "zig-test.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    manifest = {
        "schema": "rosette-vertex-fetch-corpus-check-v1",
        "scope": "All unique type=vertex descriptors in the supplied audits checked against lib/gpu/fetch_constants/vertex.zig; no backing-memory or GPU fetch claim.",
        "status": "pass" if result.returncode == 0 else "fail",
        "unique_descriptors": len(descriptors),
        "audit_inputs": audit_inputs,
        "decoder_source": str(VERTEX_DECODER),
        "zig": {"path": zig_path, "sha256": hashlib.sha256(pathlib.Path(zig_path).read_bytes()).hexdigest()},
        "test_source": str(zig_test),
        "test_source_sha256": hashlib.sha256(zig_test.read_bytes()).hexdigest(),
        "command": command,
        "returncode": result.returncode,
        "log": str(out / "zig-test.log"),
        "log_sha256": hashlib.sha256((out / "zig-test.log").read_bytes()).hexdigest(),
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    if result.stdout.strip():
        print(result.stdout.rstrip())
    if result.stderr.strip():
        print(result.stderr.rstrip(), file=sys.stderr)
    print(f"{manifest['status']}: production Zig decoder checked {len(descriptors)} unique descriptor(s)")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audits", nargs="+", type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--zig", default="zig")
    args = parser.parse_args(argv)
    try:
        return 0 if run(args.audits, args.out, args.zig)["status"] == "pass" else 1
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"fetch descriptor corpus check failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
