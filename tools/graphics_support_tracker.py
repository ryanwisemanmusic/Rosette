#!/usr/bin/env python3
"""Read-only ISO graphics inventory, observed shader checks and evidence progress.

Run --help. This standalone tool does not launch Xenia or require shell-update.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from graphics_support.checks import compile_shaders
from graphics_support.coverage import attest, compare, new_snapshot, revoke, summarize, validate
from graphics_support.evidence import parse_log, shader_archive
from graphics_support.iso import InventoryError, inventory
from graphics_support.iso_offline import iso_check, recover_iso_checks, resume_iso_checks
from graphics_support.texture_checks import texture_check
from graphics_support.report import write_snapshot
from graphics_support.native_metal import attach_native
from graphics_support.live_metal import attach_live
from graphics_support.progress import attach_progress
from graphics_support.tag_checks import check_tags
from graphics_support.vertex_layout import format_matrix_checks, neutral_vertex_checks
from graphics_support.fsi_sampling import attach_sampling
from graphics_support.white_orbs import attach_hdr, attach_video
from graphics_support.offline_checks import record_checks
from graphics_support.hdr_chain import record_chain
from graphics_support.hdr_resolve import attach_resolve, attach_regions
from graphics_support.gfxr_capture import attach_capture

ROOT = Path(__file__).resolve().parents[1]


def load(path):
    return validate(json.loads(Path(path).read_text()))


def parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    scan = sub.add_parser("scan", help="Hash/read ISO metadata and optionally associate a log/archive")
    scan.add_argument("iso", type=Path)
    refresh = sub.add_parser("refresh", help="Reuse the fixed inventory and ledger with a new run; no ISO reread")
    refresh.add_argument("snapshot", type=Path)
    for command in (scan, refresh):
        command.add_argument("--log", type=Path)
        command.add_argument("--shader-dir", type=Path)
        command.add_argument("--failure-shaders-only", action="store_true", help="Index only failed timing-group boundary guest shader candidates; requires log and archive")
        command.add_argument("--scenario", default="unspecified", help="Explicit scenario name; required for attestations")
        command.add_argument("--out", required=True, type=Path)
    check = sub.add_parser("compile", help="Production rewrite + validation/MSL/AIR; never GPU dispatch")
    check.add_argument("snapshot", type=Path)
    check.add_argument("--evidence-dir", required=True, type=Path)
    check.add_argument("--out", required=True, type=Path)
    check.add_argument("--limit", type=int, help="Optional bounded subset; untested modules stay unknown")
    check.add_argument("--zig", default="zig")
    check.add_argument("--validator", default="spirv-val")
    check.add_argument("--converter", default="MoltenVKShaderConverter")
    iso_test = sub.add_parser("iso-check", help="Extract ISO Xbox shaders, translate with read-only Xenia source, compile to Metal AIR; no game launch")
    iso_test.add_argument("snapshot", type=Path)
    iso_test.add_argument("--xenia-source", required=True, type=Path)
    iso_test.add_argument("--evidence-dir", required=True, type=Path)
    iso_test.add_argument("--out", required=True, type=Path)
    iso_test.add_argument("--workers", type=int, default=4)
    iso_test.add_argument("--limit", type=int, help="Optional subset; untested unique programs remain unknown")
    iso_test.add_argument("--zig", default="zig")
    iso_test.add_argument("--validator", default="spirv-val")
    iso_test.add_argument("--converter", default="MoltenVKShaderConverter")
    iso_test.add_argument("--reuse-extraction", action="store_true", help="Recompile hash-verified extracted programs from this snapshot; preserve ISO extraction evidence")
    iso_test.add_argument("--driver", type=Path, help="MoltenVK dylib queried read only (default: SDK alongside converter)")
    recover = sub.add_parser("recover-iso", help="Recover durable outcomes from an interrupted ISO compiler sweep; no compilation")
    recover.add_argument("snapshot", type=Path)
    recover.add_argument("--evidence-dir", required=True, type=Path)
    recover.add_argument("--out", required=True, type=Path)
    resume = sub.add_parser("resume-iso", help="Continue unknown compiler checks with identical verified sources/tools/device; keep completed outcomes")
    resume.add_argument("snapshot", type=Path)
    resume.add_argument("--evidence-dir",required=True,type=Path)
    resume.add_argument("--out",required=True,type=Path)
    resume.add_argument("--workers",type=int,default=4)
    resume.add_argument("--limit",type=int)
    progress = sub.add_parser("progress", help="Record exact compiler/native/live/run progress against an earlier saved snapshot; no rendering claim")
    progress.add_argument("snapshot", type=Path)
    progress.add_argument("previous", type=Path)
    progress.add_argument("--out", required=True, type=Path)
    vertex = sub.add_parser("vertex-layout", help="Compile runtime-layout vertex programs under a declared neutral layout plus a format matrix; separate from the main compiler count")
    vertex.add_argument("snapshot", type=Path)
    vertex.add_argument("--evidence-dir", required=True, type=Path)
    vertex.add_argument("--out", required=True, type=Path)
    vertex.add_argument("--workers", type=int, default=4)
    vertex.add_argument("--limit", type=int, help="Optional bounded subset of runtime-layout vertex programs")
    vertex.add_argument("--matrix-programs", type=int, default=8, help="Representative programs for the format matrix; 0 skips it")
    tags = sub.add_parser("tag-check", help="Check selected retail effect/light/model references and numeric metadata; no rendering attestation")
    tags.add_argument("snapshot", type=Path)
    tags.add_argument("--schemas", required=True, type=Path)
    tags.add_argument("--evidence-dir", required=True, type=Path)
    tags.add_argument("--per-class", default=100, type=int)
    tags.add_argument("--out", required=True, type=Path)
    textures = sub.add_parser("texture-check", help="Compile read-only Xenia texture-loader sources, with ISO format metadata; payload fidelity stays unknown")
    textures.add_argument("snapshot", type=Path)
    textures.add_argument("--xenia-source", required=True, type=Path)
    textures.add_argument("--evidence-dir", required=True, type=Path)
    textures.add_argument("--out", required=True, type=Path)
    textures.add_argument("--workers", type=int, default=2)
    textures.add_argument("--zig", default="zig")
    textures.add_argument("--validator", default="spirv-val")
    textures.add_argument("--converter", default="MoltenVKShaderConverter")
    evidence = sub.add_parser("attest", help="Record explicit asset proof; compilation never auto-certifies tags")
    evidence.add_argument("snapshot", type=Path)
    evidence.add_argument("manifest", type=Path, help="JSON: asset_ids, stage, outcome, proof_path, note")
    evidence.add_argument("--out", required=True, type=Path)
    remove = sub.add_parser("revoke", help="Retract an attestation with a saved audit reason")
    remove.add_argument("snapshot", type=Path)
    remove.add_argument("proof_id")
    remove.add_argument("--reason", required=True)
    remove.add_argument("--out", required=True, type=Path)
    diff = sub.add_parser("compare", help="Same ISO/policy/scenario progress, with exact gained/lost IDs")
    diff.add_argument("before", type=Path)
    diff.add_argument("after", type=Path)
    diff.add_argument("--target", type=float)
    diff.add_argument("--compiler-target", type=float, help="Separate target for identical ISO program/profile/driver compiler evidence")
    diff.add_argument("--out", required=True, type=Path, help="New JSON comparison file")
    report = sub.add_parser("report", help="Regenerate a report, rechecking saved asset proof hashes")
    report.add_argument("snapshot", type=Path)
    report.add_argument("--out", required=True, type=Path)
    native = sub.add_parser("metal-evidence", help="Attach hash-verified native Metal contract checks; no ISO correctness promotion")
    native.add_argument("snapshot",type=Path)
    native.add_argument("manifest",type=Path)
    native.add_argument("--out",required=True,type=Path)
    live = sub.add_parser("metal-live-evidence", help="Attach live texture contract evidence; runtime gameplay remains unverified")
    live.add_argument("snapshot",type=Path)
    live.add_argument("manifest",type=Path)
    live.add_argument("--out",required=True,type=Path)
    sampling = sub.add_parser("fsi-sampling-evidence", help="Attach bounded FSI semantic contracts; no Halo correctness claim")
    sampling.add_argument("snapshot", type=Path)
    sampling.add_argument("manifest", type=Path)
    sampling.add_argument("--out", required=True, type=Path)
    hdr = sub.add_parser("hdr-evidence", help="Attach bounded HDR semantics; no Halo rendering certification")
    hdr.add_argument("snapshot", type=Path)
    hdr.add_argument("manifest", type=Path)
    hdr.add_argument("--out", required=True, type=Path)
    checks = sub.add_parser("offline-checks", help="Attach native-GPU counter and CPU-decoder oracle results; no Halo rendering claim")
    checks.add_argument("snapshot", type=Path)
    for name in ('hdr-resolve-evidence', 'orb-region-evidence'):
        evidence = sub.add_parser(name, help="Attach bounded resolve semantics or supplied screenshot regions; no asset certification")
        evidence.add_argument('snapshot', type=Path)
        evidence.add_argument('manifest', type=Path)
        evidence.add_argument('--out', required=True, type=Path)
    checks.add_argument("--zpd-log", required=True, type=Path)
    checks.add_argument("--oracle-log", required=True, type=Path)
    checks.add_argument("--source", action="append", default=[], type=Path, help="source or tool file the results depend on (hashed)")
    checks.add_argument("--notes", default="", help="what was run and on which driver")
    checks.add_argument("--out", required=True, type=Path)
    chain = sub.add_parser("hdr-chain-evidence", help="Attach Halo's decoded HDR chain, native fast-math probe and format-aware sampled frame data; no Halo rendering claim")
    chain.add_argument("snapshot", type=Path)
    chain.add_argument("--fast-math-log", action="append", required=True, type=Path, help="probe_fast_math output, once per mode")
    chain.add_argument("--disasm-dir", required=True, type=Path)
    chain.add_argument("--run-log", required=True, type=Path)
    chain.add_argument("--source", action="append", default=[], type=Path, help="source or tool file the results depend on (hashed)")
    chain.add_argument("--notes", default="")
    chain.add_argument("--out", required=True, type=Path)
    video = sub.add_parser("orb-video-evidence", help="Attach extracted recording frames; human notes stay observations")
    video.add_argument("snapshot", type=Path)
    video.add_argument("manifest", type=Path)
    video.add_argument("--out", required=True, type=Path)
    capture = sub.add_parser("capture-evidence", help="Attach a CPU-only GFXReconstruct API audit; no replay or visual correctness claim")
    capture.add_argument("snapshot", type=Path)
    capture.add_argument("manifest", type=Path)
    capture.add_argument("--out", required=True, type=Path)
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        # Preserve evidence/baselines rather than silently overwriting them.
        if args.out.exists():
            raise InventoryError("Output exists; choose a new file/directory")
        if args.command in ("scan", "refresh"):
            run = parse_log(args.log) if args.log else None
            if args.command == "scan":
                print("Hashing ISO and reading bounded metadata (read only)...", flush=True)
                snapshot = new_snapshot(inventory(args.iso), scenario=args.scenario)
            else:
                snapshot = load(args.snapshot)
            if run and run.get("media_path") and Path(run["media_path"]).resolve() != Path(snapshot["iso"]["path"]).resolve():
                raise InventoryError("Log media path differs from the ISO inventory; scan the correct image")
            snapshot["run"] = run
            snapshot["context"] = {"build": (run or {}).get("build"), "driver": (run or {}).get("driver"), "scenario": args.scenario}
            if args.shader_dir:
                print("Indexing shader evidence (no GPU work)...", flush=True)
                fingerprints = None
                if args.failure_shaders_only:
                    fingerprints = {c['pipeline']['shader_hash'] for c in (run or {}).get('failure_candidates',[]) if c['pipeline'].get('shader_hash')}
                    if not fingerprints: raise InventoryError('No failed timing-group shader candidates in supplied log')
                snapshot["shader_archive"] = shader_archive(args.shader_dir, run, fingerprints)
            elif args.command == "refresh":
                snapshot["shader_archive"] = None
        elif args.command == "compare":
            result = compare(load(args.before), load(args.after), args.target, args.compiler_target)
            args.out.parent.mkdir(parents=True, exist_ok=True)
            with args.out.open("x") as stream:
                json.dump(result, stream, indent=2)
            print(f"Confirmed {result['confirmed_before']}/{result['denominator']} -> {result['confirmed_after']}/{result['denominator']}; change {result['percentage_point_change']} percentage points")
            if "additional_confirmed_instances_needed" in result:
                print(f"Target {args.target}% needs {result['additional_confirmed_instances_needed']} additional confirmed instances")
            return 0
        else:
            snapshot = load(args.snapshot)
            if args.command == "metal-evidence":
                print(json.dumps(attach_native(snapshot,args.manifest),indent=2))
            elif args.command == "fsi-sampling-evidence":
                print(json.dumps(attach_sampling(snapshot, args.manifest), indent=2))
            elif args.command == "hdr-evidence":
                print(json.dumps(attach_hdr(snapshot, args.manifest), indent=2))
            elif args.command == 'hdr-resolve-evidence':
                print(json.dumps(attach_resolve(snapshot, args.manifest), indent=2))
            elif args.command == 'orb-region-evidence':
                print(json.dumps(attach_regions(snapshot, args.manifest), indent=2))
            elif args.command == "offline-checks":
                print(json.dumps(record_checks(snapshot, args.zpd_log, args.oracle_log, args.source, args.notes), indent=2))
            elif args.command == "hdr-chain-evidence":
                print(json.dumps(record_chain(snapshot, args.fast_math_log, args.disasm_dir, args.run_log, args.source, args.notes), indent=2))
            elif args.command == "orb-video-evidence":
                print(json.dumps(attach_video(snapshot, args.manifest), indent=2))
            elif args.command == "capture-evidence":
                print(json.dumps(attach_capture(snapshot, args.manifest), indent=2))
            elif args.command == "metal-live-evidence":
                print(json.dumps(attach_live(snapshot,args.manifest),indent=2))
            elif args.command == "tag-check":
                print(json.dumps(check_tags(snapshot, args.schemas, args.evidence_dir, args.per_class), indent=2))
            elif args.command == "attest":
                proof = attest(snapshot, json.loads(args.manifest.read_text()), args.manifest.resolve().parent)
                print(f"Saved attestation {proof}")
            elif args.command == "revoke":
                revoke(snapshot, args.proof_id, args.reason)
            elif args.command == "compile":
                compile_shaders(snapshot, args.evidence_dir, ROOT, args.zig, args.validator, args.converter, args.limit)
            elif args.command == "iso-check":
                result = iso_check(snapshot, args.evidence_dir, ROOT, args.xenia_source, args.zig,
                                   args.validator, args.converter, args.workers, args.limit, not args.reuse_extraction, args.driver)
                print(json.dumps(result["summary"], indent=2), flush=True)
            elif args.command == "texture-check":
                texture_check(snapshot,args.evidence_dir,ROOT,args.xenia_source,args.zig,args.validator,args.converter,args.workers)
            elif args.command == "recover-iso":
                recover_iso_checks(snapshot,args.evidence_dir)
            elif args.command == "progress":
                print(json.dumps(attach_progress(snapshot, args.previous), indent=2), flush=True)
            elif args.command == "vertex-layout":
                if args.evidence_dir.exists():
                    raise InventoryError("Use a new vertex layout evidence directory")
                args.evidence_dir.mkdir(parents=True)
                neutral = neutral_vertex_checks(snapshot, args.evidence_dir / "neutral", args.workers, args.limit)
                print(json.dumps(neutral["summary"], indent=2), flush=True)
                if args.matrix_programs:
                    matrix = format_matrix_checks(snapshot, args.evidence_dir / "matrix", args.workers, args.matrix_programs)
                    print(json.dumps(matrix["summary"], indent=2), flush=True)
            elif args.command == "resume-iso":
                result=resume_iso_checks(snapshot,args.evidence_dir,args.workers,args.limit)
                print(json.dumps(result["summary"],indent=2),flush=True)
        write_snapshot(snapshot, args.out)
        counts = summarize(snapshot)["coverage"].get("all", {})
        print(f"Graphics tag instances: {counts.get('total', 0):,}; confirmed: {counts.get('confirmed', 0):,}; unknown: {counts.get('unknown', 0):,}")
        print(f"Report: {args.out.resolve() / 'report.html'}")
        return 0
    except (InventoryError, ValueError, KeyError, TypeError, OSError) as error:
        print(f"Tracker error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
