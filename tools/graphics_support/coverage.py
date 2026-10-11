"""Fixed-denominator progress and explicit, build-scoped asset attestations."""
from __future__ import annotations

from collections import Counter, defaultdict
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path

from . import SCHEMA, POLICY
from .iso import InventoryError, denominator_hash, hash_file

STAGES = ("payload_decode", "shader_translation", "correct_render")


def validate(snapshot):
    if snapshot.get("schema") != SCHEMA or snapshot["iso"].get("policy") != POLICY:
        raise InventoryError("Unknown snapshot schema or inventory policy")
    iso = snapshot["iso"]
    if denominator_hash(iso["assets"]) != iso["denominator_sha256"]:
        raise InventoryError("Inventory denominator changed or snapshot is damaged")
    if any(not a["id"].startswith(iso["sha256"] + ":") for a in iso["assets"]):
        raise InventoryError("Asset does not belong to this ISO")
    return snapshot


def new_snapshot(iso, run=None, archive=None, scenario="unspecified"):
    return {"schema": SCHEMA, "created_utc": datetime.now(timezone.utc).isoformat(),
            "iso": iso, "run": run, "shader_archive": archive, "ledger": [], "revocations": [],
            "context": {"build": (run or {}).get("build"), "driver": (run or {}).get("driver"),
                        "scenario": scenario}}


def scope_key(context):
    return json.dumps(context, sort_keys=True, ensure_ascii=True, separators=(",", ":"))


def attest(snapshot, request, request_dir: Path):
    validate(snapshot)
    if not snapshot["context"]["build"] or not snapshot["context"]["driver"] or snapshot["context"]["scenario"] == "unspecified":
        raise InventoryError("Attestations require a known build, driver and named scenario")
    ids = request.get("asset_ids")
    if not isinstance(ids, list) or not ids or len(ids) != len(set(ids)):
        raise InventoryError("Specify a nonempty list of unique asset_ids")
    known = {a["id"] for a in snapshot["iso"]["assets"]}
    if not set(ids) <= known:
        raise InventoryError("Attestation contains an unknown ISO asset identity")
    stage, outcome = request.get("stage"), request.get("outcome")
    if stage not in STAGES or outcome not in ("pass", "fail"):
        raise InventoryError("Invalid evidence stage or outcome")
    if not isinstance(request.get("note"), str) or not request["note"].strip():
        raise InventoryError("Evidence needs a description of the check and its asset mapping")
    proof = (request_dir / request["proof_path"]).resolve(strict=True)
    if not proof.is_file():
        raise InventoryError("Proof must be a saved evidence file")
    record = {"asset_ids": sorted(ids), "stage": stage, "outcome": outcome,
              "proof_path": str(proof), "proof_sha256": hash_file(proof), "note": request["note"],
              "context": copy.deepcopy(snapshot["context"]), "iso_sha256": snapshot["iso"]["sha256"]}
    record["id"] = hashlib.sha256(json.dumps(record, sort_keys=True, ensure_ascii=True).encode()).hexdigest()
    if record["id"] not in {r["id"] for r in snapshot["ledger"]}:
        snapshot["ledger"].append(record)
    return record["id"]


def revoke(snapshot, record_id, reason):
    if record_id not in {r["id"] for r in snapshot["ledger"]} or not reason.strip():
        raise InventoryError("Revocation requires an existing proof id and a reason")
    if record_id in {r["id"] for r in snapshot["revocations"]}:
        raise InventoryError("Proof already revoked")
    snapshot["revocations"].append({"id": record_id, "reason": reason,
                                     "utc": datetime.now(timezone.utc).isoformat()})


def states(snapshot, verify_proofs=True):
    validate(snapshot)
    known = {a["id"] for a in snapshot["iso"]["assets"]}
    context, outcomes, seen = scope_key(snapshot["context"]), defaultdict(set), set()
    revoked = {r["id"] for r in snapshot["revocations"]}
    hashes = {}
    for record in snapshot["ledger"]:
        if record["id"] in seen:
            raise InventoryError("Duplicate proof record")
        seen.add(record["id"])
        payload = {k: v for k, v in record.items() if k != "id"}
        if hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=True).encode()).hexdigest() != record["id"]:
            raise InventoryError("Proof record has been altered")
        if record["iso_sha256"] != snapshot["iso"]["sha256"] or not set(record["asset_ids"]) <= known:
            raise InventoryError("Proof does not belong to this inventory")
        if record["stage"] not in STAGES or record["outcome"] not in ("pass", "fail"):
            raise InventoryError("Invalid proof record")
        if record["id"] in revoked or scope_key(record["context"]) != context:
            continue
        if verify_proofs:
            path = record["proof_path"]
            if path not in hashes:
                try:
                    hashes[path] = hash_file(Path(path))
                except OSError as error:
                    raise InventoryError(f"Proof is no longer readable: {path}") from error
            if hashes[path] != record["proof_sha256"]:
                raise InventoryError(f"Proof content changed: {path}")
        for asset in record["asset_ids"]:
            outcomes[asset, record["stage"]].add(record["outcome"])
    return {asset: {stage: ("unknown" if not outcomes[asset, stage] else
                           "conflict" if len(outcomes[asset, stage]) > 1 else
                           "confirmed" if "pass" in outcomes[asset, stage] else "known_failure")
                    for stage in STAGES} for asset in known}


def summarize(snapshot, verified=None):
    verified = states(snapshot) if verified is None else verified
    groups = defaultdict(Counter)
    formats, classes = Counter(), Counter()
    metadata = Counter()
    for asset in snapshot["iso"]["assets"]:
        status = verified[asset["id"]]["correct_render"]
        groups[asset["category"]][status] += 1
        groups["all"][status] += 1
        classes[asset["class"]] += 1
        metadata[asset["metadata_status"]] += 1
        for image in asset.get("subimages", []):
            formats[image["format"]] += 1
    result = {}
    for group, counts in sorted(groups.items()):
        total = sum(counts.values())
        confirmed = counts["confirmed"]
        evaluated = total - counts["unknown"]
        result[group] = {"total": total, **{s: counts[s] for s in ("confirmed", "known_failure", "conflict", "unknown")},
                         "confirmed_coverage_percent": 100 * confirmed / total if total else None,
                         "evaluated_percent": 100 * evaluated / total if total else None,
                         "pass_percent_of_evaluated": 100 * confirmed / evaluated if evaluated else None}
    stages = {stage: dict(Counter(v[stage] for v in verified.values())) for stage in STAGES}
    backlog = []
    for category in sorted(groups):
        if category == "all":
            continue
        items = [a for a in snapshot["iso"]["assets"] if a["category"] == category]
        partitions = Counter((a["class"], verified[a["id"]]["correct_render"]) for a in items)
        for (cls, state), n in partitions.most_common():
            if state != "confirmed":
                backlog.append({"category": category, "class": cls, "state": state, "instances": n})
    summary = {"coverage": result, "stages": stages, "metadata": dict(metadata),
            "bitmap_subimages_by_halo_format_id": dict(sorted(formats.items())),
            "classes": dict(classes), "backlog": backlog,
            "claim": "Confirmed coverage of enumerated graphics tag instances in this build/driver/scenario; unknown is not unsupported. Not an overall ISO compatibility percentage."}
    if snapshot.get("iso_offline"):
        from .iso_offline import offline_summary
        summary["iso_offline"] = offline_summary(snapshot["iso_offline"])
    if snapshot.get("native_metal"):
        from .native_metal import native_summary
        summary["native_metal"] = native_summary(snapshot)
    if snapshot.get("tag_checks"):
        from .tag_checks import tag_summary
        summary["tag_checks"] = tag_summary(snapshot)
    return summary


def compare(before, after, target=None, compiler_target=None):
    validate(before)
    validate(after)
    for key in ("sha256", "policy", "denominator_sha256"):
        if before["iso"][key] != after["iso"][key]:
            raise InventoryError(f"Cannot compare coverage: ISO {key} differs")
    if before["context"]["scenario"] != after["context"]["scenario"]:
        raise InventoryError("Cannot compare coverage across different scenarios")
    left, right = states(before), states(after)
    changes = {}
    for stage in STAGES:
        gained = sorted(i for i in left if left[i][stage] != "confirmed" and right[i][stage] == "confirmed")
        lost = sorted(i for i in left if left[i][stage] == "confirmed" and right[i][stage] != "confirmed")
        changes[stage] = {"gained": gained, "lost": lost}
    lsum, rsum = summarize(before, left), summarize(after, right)
    total = len(left)
    old = sum(v["correct_render"] == "confirmed" for v in left.values())
    new = sum(v["correct_render"] == "confirmed" for v in right.values())
    result = {"iso_sha256": after["iso"]["sha256"], "denominator": total,
              "before_context": before["context"], "after_context": after["context"],
              "context_changed": before["context"] != after["context"],
              "confirmed_before": old, "confirmed_after": new,
              "percentage_point_change": 100 * (new - old) / total if total else None,
              "changes": changes, "before": lsum["coverage"], "after": rsum["coverage"]}
    if target is not None:
        if not math.isfinite(target) or not 0 <= target <= 100:
            raise InventoryError("Target must be a finite percentage from 0 to 100")
        result["target_percent"] = target
        result["additional_confirmed_instances_needed"] = max(0, math.ceil(target * total / 100) - new)
    # Host timers overlap: compare raw counters without adding costs or promising saved FPS.
    result["timing"] = {"before": (before.get("run") or {}).get("snapshots"),
                        "after": (after.get("run") or {}).get("snapshots"),
                        "scope": "Different runs are not scene-matched benchmarks; fence observations include CPU/queue delay"}
    if before.get("iso_offline") and after.get("iso_offline"):
        from .iso_offline import compare_compilers
        result["iso_compiler"] = compare_compilers(before["iso_offline"],after["iso_offline"],compiler_target)
    elif compiler_target is not None:
        raise InventoryError("Compiler target requires direct ISO evidence in both snapshots")
    return result
