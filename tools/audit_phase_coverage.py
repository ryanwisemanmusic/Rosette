#!/usr/bin/env python3
"""Emit the no-Xenia implementation and release matrix for audit Phases 0-5.

This is intentionally a source/artifact check.  It never opens the Xenia
checkout and never launches an emulator.  The generated document is consumed
by build identity, so a binary cannot silently outlive the phase contract
that was tested beside it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


SCHEMA_VERSION = 1

PHASES = [
    {
        "id": 0,
        "name": "contract-evidence",
        "acceptance": "sealed identity, stable event authority, generation-aware IDs, and capability/refusal rows",
        "files": [
            "lib/diagnostics/audit_phase_contracts.zig",
            "lib/diagnostics/run_manifest.zig",
            "lib/diagnostics/event_identity.zig",
            "lib/diagnostics/run_journal.zig",
            "lib/diagnostics/durable_journal.zig",
        ],
    },
    {
        "id": 1,
        "name": "runtime-liveness",
        "acceptance": "causal object/wait/callback/module/ABI/memory evidence with visible bounded loss",
        "files": [
            "lib/diagnostics/audit_phase_contracts.zig",
            "lib/diagnostics/wait_graph.zig",
            "lib/diagnostics/sync_object_registry.zig",
            "lib/diagnostics/execution_provenance.zig",
            "lib/runtime/memory/root.zig",
            "lib/processor/ELF_processor/process.zig",
        ],
    },
    {
        "id": 2,
        "name": "graphics-semantics",
        "acceptance": "one frame token from guest swap through target, shader, descriptor, layout, resolve, readback, and paint",
        "files": [
            "lib/diagnostics/audit_phase_contracts.zig",
            "lib/gpu/xenos_frame_transaction.zig",
            "lib/gpu/present_chain.zig",
            "lib/gpu/screen_validity.zig",
            "lib/gpu/xenos_runtime.zig",
            "lib/gpu/shader_execution.zig",
            "lib/linker/dyld/dynamic_library_forwarder.zig",
        ],
    },
    {
        "id": 3,
        "name": "media-ui-services",
        "acceptance": "audio, input, assets, registry, COM, sockets, DLL, and window routes have explicit profile outcomes",
        "files": [
            "lib/diagnostics/audit_phase_contracts.zig",
            "lib/audio/audio_system.zig",
            "lib/audio/xma_decoder.zig",
            "lib/runtime/guest-abi/native_window_runtime.zig",
            "pkg/common/xenia/input-contract/src/root.zig",
            "pkg/dll/win32/ole32/src/root.zig",
            "pkg/dll/win32/wsock32/src/root.zig",
        ],
    },
    {
        "id": 4,
        "name": "performance-observer",
        "acceptance": "named phase budgets and observer overhead remain bounded and comparable",
        "files": [
            "lib/diagnostics/audit_phase_contracts.zig",
            "lib/diagnostics/run_budget.zig",
            "lib/diagnostics/execution_profile.zig",
            "lib/diagnostics/translation_economics.zig",
            "tools/test_census.py",
        ],
    },
    {
        "id": 5,
        "name": "release-profiles",
        "acceptance": "profile admission, fixture coverage, artifact hashes, and no-Xenia replay are explicit",
        "files": [
            "lib/diagnostics/audit_phase_contracts.zig",
            "tools/build_identity_manifest.py",
            "tools/replay_evidence.py",
            "tools/create_evidence_fixture.py",
            "tools/test_census.py",
            "app/bundling/build.zig",
        ],
    },
]

# The inventory is kept here as a release-facing index.  It is deliberately
# not inferred from the number of source files: an implemented function and a
# declared refusal are both meaningful only when the corresponding audit row
# has an owner and a profile.
ITEMS = [
    ("MS-01", 0, "immutable run identity", "contracted"),
    ("MS-02", 0, "relocatable bundle and dependency closure", "contracted"),
    ("MS-03", 0, "source/build/artifact consistency gate", "contracted"),
    ("MS-04", 1, "general PE module graph", "contracted"),
    ("MS-05", 1, "Windows loader search order and DLL identity", "contracted"),
    ("MS-06", 1, "complete Win64 calling and return ABI", "contracted"),
    ("MS-07", 1, "TLS, TEB/PEB, loader lock, and thread attach", "contracted"),
    ("MS-08", 1, "CRT and C++ runtime surface", "profiled"),
    ("MS-09", 1, "exception, unwind, and termination semantics", "profiled"),
    ("MS-10", 1, "kernel object and handle lifetime", "contracted"),
    ("MS-11", 1, "wait graph with producer and signal causality", "contracted"),
    ("MS-12", 1, "timed waits and timeout classification", "contracted"),
    ("MS-13", 1, "guest clock, timers, vblank, and time-plane ownership", "contracted"),
    ("MS-14", 1, "DPC/APC, interrupt callbacks, and re-entry", "contracted"),
    ("MS-15", 1, "IO completion, overlapped I/O, and asynchronous service threads", "profiled"),
    ("MS-16", 1, "native event-pump and host-thread ownership", "contracted"),
    ("MS-17", 1, "reservation/commit/section/view model", "contracted"),
    ("MS-18", 1, "relocation and fixed-address allocation capacity", "contracted"),
    ("MS-19", 1, "guest/host address provenance and pointer classification", "contracted"),
    ("MS-20", 1, "protection faults and exception routing", "contracted"),
    ("MS-21", 3, "guest filesystem and device namespace", "contracted"),
    ("MS-22", 3, "registry, profile, locale, and known-folder services", "profiled"),
    ("MS-23", 3, "file mapping, cache, and asset streaming", "profiled"),
    ("MS-24", 2, "host loader and Vulkan capability profile", "contracted"),
    ("MS-25", 2, "surface, CAMetalLayer, and drawable ownership", "contracted"),
    ("MS-26", 2, "swapchain image lifetime and acquire/present pairing", "contracted"),
    ("MS-27", 2, "Vulkan object identity, lifetime, and destruction", "contracted"),
    ("MS-28", 2, "descriptor set, view, sampler, and binding resolution", "contracted"),
    ("MS-29", 2, "resource layout, barriers, and visibility", "contracted"),
    ("MS-30", 2, "render pass, framebuffer, attachment, and store semantics", "contracted"),
    ("MS-31", 2, "shader translation and execution capability", "contracted"),
    ("MS-32", 2, "Xenos register state and PM4 semantic coverage", "contracted"),
    ("MS-33", 2, "Xbox 360 surface format, tiling, swizzle, and EDRAM/resolve", "profiled"),
    ("MS-34", 2, "transfer and upload provenance", "contracted"),
    ("MS-35", 2, "frame identity across guest, GPU, and UI", "contracted"),
    ("MS-36", 2, "content-aware pixel probe with source context", "contracted"),
    ("MS-37", 2, "screen-validity state machine and fail-closed policy", "contracted"),
    ("MS-38", 3, "window placement, resize, occlusion, and compositor authority", "contracted"),
    ("MS-39", 2, "present completion and compositor delivery proof", "contracted"),
    ("MS-40", 3, "audio signal, codec, and title-silence separation", "contracted"),
    ("MS-41", 3, "XMA and media pipeline", "profiled"),
    ("MS-42", 3, "input devices, focus, and HID/XInput policy", "profiled"),
    ("MS-43", 3, "font, text, and asset availability", "profiled"),
    ("MS-44", 3, "UI lifecycle and child-window/overlay behavior", "profiled"),
    ("MS-45", 3, "Windows API-set and kernel export closure", "contracted"),
    ("MS-46", 3, "import return-contract and error-code fidelity", "contracted"),
    ("MS-47", 3, "COM, GUID, apartment, and graphics factory services", "profiled"),
    ("MS-48", 5, "DirectX, DXGI, and native Windows graphics route", "profiled"),
    ("MS-49", 5, "Steam runtime, overlay, launcher, and child-process policy", "profiled"),
    ("MS-50", 3, "networking and service discovery", "profiled"),
    ("MS-51", 0, "single diagnostic authority and event taxonomy", "contracted"),
    ("MS-52", 0, "structured event journal and bounded-loss policy", "contracted"),
    ("MS-53", 0, "actionable capability and refusal matrix", "contracted"),
    ("MS-54", 4, "observer non-interference", "contracted"),
    ("MS-55", 4, "performance phase attribution and budgets", "contracted"),
    ("MS-56", 5, "verification and release artifact matrix", "contracted"),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_record(root: Path, relative: str) -> dict:
    path = root / relative
    if not path.is_file():
        return {"path": relative, "present": False, "sha256": ""}
    return {"path": relative, "present": True, "sha256": sha256(path)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output if args.output.is_absolute() else root / args.output

    phase_reports = []
    missing: list[str] = []
    all_sources: list[dict] = []
    for phase in PHASES:
        sources = [source_record(root, relative) for relative in phase["files"]]
        phase_missing = [entry["path"] for entry in sources if not entry["present"]]
        missing.extend(phase_missing)
        all_sources.extend(sources)
        phase_reports.append(
            {
                "id": phase["id"],
                "name": phase["name"],
                "status": "contracted" if not phase_missing else "blocked",
                "acceptance": phase["acceptance"],
                "source_files": sources,
                "xenia_execution": False,
            }
        )

    contract = root / "lib/diagnostics/audit_phase_contracts.zig"
    contract_text = contract.read_text(encoding="utf-8") if contract.is_file() else ""
    required_markers = (
        "pub const Phase = enum",
        "pub const Identity = struct",
        "pub const EventLedger = struct",
        "pub const FrameLedger = struct",
        "pub const ReleaseMatrix = struct",
    )
    missing_markers = [marker for marker in required_markers if marker not in contract_text]
    if missing_markers:
        missing.extend(f"audit_phase_contracts.zig:{marker}" for marker in missing_markers)

    # A source hash over the phase index makes the report itself reproducible
    # without hashing absolute paths or the external Xenia checkout.
    canonical_sources = json.dumps(
        sorted({entry["path"]: entry["sha256"] for entry in all_sources}.items()),
        separators=(",", ":"),
    ).encode()
    source_hash = hashlib.sha256(canonical_sources).hexdigest()

    report = {
        "schema_version": SCHEMA_VERSION,
        "contract_schema_version": 1,
        "source_hash": source_hash,
        "xenia_reference": {
            "read_only": True,
            "execution_performed": False,
            "files_read": 0,
            "files_written": 0,
        },
        "phases": phase_reports,
        "items": [
            {"id": item_id, "phase": phase, "name": name, "status": status}
            for item_id, phase, name, status in ITEMS
        ],
        "summary": {
            "phase_count": len(PHASES),
            "item_count": len(ITEMS),
            "contracted_items": sum(status == "contracted" for _, _, _, status in ITEMS),
            "profiled_items": sum(status == "profiled" for _, _, _, status in ITEMS),
            "blocked_sources": len(set(missing)),
            "fail_closed": True,
        },
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if missing:
        print("audit-phase-coverage: FAIL")
        for entry in sorted(set(missing)):
            print(f"  missing: {entry}")
        return 1
    print(
        "audit-phase-coverage: PASS "
        f"phases={len(PHASES)} items={len(ITEMS)} "
        f"contracted={report['summary']['contracted_items']} "
        f"profiled={report['summary']['profiled_items']} output={output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
