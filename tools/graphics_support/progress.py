"""Exact progress against an earlier saved report; never a rendering claim."""
import html
import json
from pathlib import Path

from .iso import InventoryError, hash_file
from .iso_offline import compare_compilers
from .run_view import native_dispatch_total
from .white_orbs import verify_hdr


def _native_checks(snapshot):
    return len(((snapshot.get("native_metal") or {}).get("result") or {}).get("checks", []))


def _live_checks(snapshot):
    return len(((snapshot.get("live_metal") or {}).get("result") or {}).get("checks", []))


def _hdr_checks(snapshot):
    verified = verify_hdr(snapshot)
    return sum(verified['passes_by_path'].values()) if verified else 0


def _observed(snapshot):
    """(ready, matched) guest modules from the supplied run that passed every archived check."""
    modules = [m for m in (snapshot.get("shader_archive") or {}).get("modules", [])
               if m.get("role") == "guest" and m.get("current_run_guest_match")]
    stages = ("rewrite", "spirv_validation", "msl_conversion", "air_compilation")
    ready = sum(all(m.get("checks", {}).get(s, {}).get("status") == "pass" for s in stages) for m in modules)
    return ready, len(modules)


def attach_progress(snapshot, previous_path):
    path = Path(previous_path).resolve(strict=True)
    previous = json.loads(path.read_text())
    if previous.get("iso", {}).get("sha256") != snapshot["iso"]["sha256"]:
        raise InventoryError("Progress needs a previous report for the same ISO")
    before, after = previous.get("iso_offline"), snapshot.get("iso_offline")
    if not before or not after:
        raise InventoryError("Both reports need ISO compiler results")
    comparison = compare_compilers(before, after)
    neutral = (after.get("neutral_vertex_layout") or {}).get("summary") or {}
    matrix = (after.get("vertex_format_matrix") or {}).get("summary") or {}
    snapshot["progress"] = {
        "previous_report": str(path), "previous_sha256": hash_file(path),
        "previous_run": (previous.get("run") or {}).get("run_id"), "current_run": (snapshot.get("run") or {}).get("run_id"),
        "compiler": {"denominator": comparison["denominator"], "ready_before": comparison["ready_before"],
                     "ready_after": comparison["ready_after"], "gained": len(comparison["gained"]), "lost": len(comparison["lost"]),
                     "percentage_point_change": comparison["percentage_point_change"]},
        "references": {"before": before["summary"]["compiler_ready_references"], "after": after["summary"]["compiler_ready_references"],
                       "extracted": after["summary"]["extracted_references"]},
        "failed": {"before": before["summary"]["compiler_fail"], "after": after["summary"]["compiler_fail"]},
        "neutral_vertex": {"ready": neutral.get("ready", 0), "variants": neutral.get("variants", 0)},
        "format_matrix": {"ready": matrix.get("ready", 0), "variants": matrix.get("variants", 0)},
        "neutral_vertex_before": (before.get("neutral_vertex_layout") or {}).get("summary") or {},
        "format_matrix_before": (before.get("vertex_format_matrix") or {}).get("summary") or {},
        "native_checks": {"before": _native_checks(previous), "after": _native_checks(snapshot)},
        "live_checks": {"before": _live_checks(previous), "after": _live_checks(snapshot)},
        "hdr_checks": {"before": _hdr_checks(previous), "after": _hdr_checks(snapshot)},
        "observed_scope": ("Earlier archive selected failed-group boundary candidates only." if (previous.get('shader_archive') or {}).get('selection_fingerprints') is not None else
                           "Each count covers exact modules in its own supplied run; scene coverage can change the count."),
        "observed_modules": {"before": _observed(previous), "after": _observed(snapshot)},
        "native_dispatches": {"before": native_dispatch_total(previous.get("run")), "after": native_dispatch_total(snapshot.get("run"))},
        "scope": "Counts of saved checks and logged counters. Compiler gains are additional testing of unchanged programs under the unchanged profile, not shader fixes, and no rendering coverage changes.",
    }
    return snapshot["progress"]


def progress_view(snapshot):
    p = snapshot.get("progress")
    if not p:
        return ""
    esc = lambda v: html.escape(str(v))
    c = p["compiler"]
    current_hdr = _hdr_checks(snapshot)
    earlier_layout = lambda key: (f"{p[key].get('ready', 0):,} of {p[key].get('variants', 0):,}" if p.get(key) else "not recorded")
    rows = [
        ("Unique ISO programs compiler-ready", f"{c['ready_before']:,}", f"{c['ready_after']:,} of {c['denominator']:,}",
         f"+{c['ready_after'] - c['ready_before']:,} ({c['gained']:,} gained, {c['lost']:,} lost, {c['percentage_point_change']:+.3f} points)"),
        ("Extracted shader references compiler-ready", f"{p['references']['before']:,}", f"{p['references']['after']:,} of {p['references']['extracted']:,}",
         f"{p['references']['after'] - p['references']['before']:+,}"),
        ("Failed compiler checks", f"{p['failed']['before']:,}", f"{p['failed']['after']:,}", ""),
        ("Vertex programs under a declared float4 layout (separate)", earlier_layout('neutral_vertex_before'), f"{p['neutral_vertex']['ready']:,} of {p['neutral_vertex']['variants']:,}", "does not change the main count"),
        ("Vertex format-matrix variants (separate)", earlier_layout('format_matrix_before'), f"{p['format_matrix']['ready']:,} of {p['format_matrix']['variants']:,}", ""),
        ("Native Metal component contract checks", f"{p['native_checks']['before']:,}", f"{p['native_checks']['after']:,}", f"{p['native_checks']['after'] - p['native_checks']['before']:+,}"),
        ("Live texture route contract groups", f"{p['live_checks']['before']:,}", f"{p['live_checks']['after']:,}", ""),
        ("HDR extended float16 semantic groups (hash-verified)", f"{p.get('hdr_checks', {}).get('before', 0):,}",
         f"{current_hdr:,}", "isolated conversion contract; current proof hashes rechecked; no ISO rendering promotion"),
        ("Logged-run FSI guest modules through rewrite → AIR", f"{p['observed_modules']['before'][0]:,} of {p['observed_modules']['before'][1]:,}",
         f"{p['observed_modules']['after'][0]:,} of {p['observed_modules']['after'][1]:,}", p.get('observed_scope', 'Earlier archive selection scope not recorded.')),
        ("Native texture dispatches in the supplied log", f"{p['native_dispatches']['before']:,}", f"{p['native_dispatches']['after']:,}",
         "supplied logs are different runs and builds"),
    ]
    body = "".join(f"<tr><td>{esc(a)}</td><td>{esc(b)}</td><td>{esc(c_)}</td><td>{esc(d)}</td></tr>" for a, b, c_, d in rows)
    return f"""<section id="progress"><h2>Progress since the previous report</h2>
<p>Compared with <code>{esc(p['previous_report'])}</code> (previous run {esc(p['previous_run'] or 'none')}; this report's run {esc(p['current_run'] or 'none')}). {esc(p['scope'])}</p>
<div class="scroll"><table><thead><tr><th>Measure</th><th>Before</th><th>Now</th><th>Change</th></tr></thead><tbody>{body}</tbody></table></div></section>"""
