#!/usr/bin/env python3
"""Convert and audit GFXReconstruct captures without replaying them."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import tempfile

from .gfxr_capture import SCHEMA, run_audit
from .iso import InventoryError


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures", nargs="+", type=Path)
    parser.add_argument("--converter", default="gfxrecon-convert")
    parser.add_argument("--shader-archive", type=Path,
                        help="Optional Vulkan shader archive for exact binary matching")
    parser.add_argument("--match-capture", type=Path,
                        help="One capture to export shader binaries for exact archive matching")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        output = args.out.resolve()
        if output.exists():
            raise InventoryError("Output exists; preserve prior capture evidence and choose a new path")
        captures = [path.resolve(strict=True) for path in args.captures]
        if len(captures) != len(set(captures)):
            raise InventoryError("Duplicate capture path")
        match_capture = args.match_capture.resolve(strict=True) if args.match_capture else None
        if match_capture and match_capture not in captures:
            raise InventoryError("--match-capture must name one of the supplied captures")
        if match_capture and not args.shader_archive:
            raise InventoryError("--match-capture requires --shader-archive")
        records = []
        with tempfile.TemporaryDirectory(prefix="rosette-gfxr-reports-") as directory:
            temporary = Path(directory)
            for index, capture in enumerate(captures):
                result = run_audit(capture, temporary / f"audit-{index}.json", args.converter,
                                   args.shader_archive,
                                   include_binaries=capture == match_capture)
                records.append(result)
                fsi = result.get("fsi", {})
                print(f"{capture.name}: frame={result['capture']['frames']} FSI_draws={fsi.get('draw_calls', 0)} "
                      f"pipelines={fsi.get('unique_pipelines', 0)} shader_modules={fsi.get('unique_shader_modules', 0)}",
                      flush=True)
        manifest = {"schema": SCHEMA, "captures": records,
                    "analysis_scope": "CPU-only Vulkan API trace audit; no replay, GPU work or correctness promotion"}
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"Saved capture audit: {output}")
        return 0
    except (InventoryError, OSError, ValueError) as error:
        parser.exit(1, f"GFXReconstruct audit error: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
