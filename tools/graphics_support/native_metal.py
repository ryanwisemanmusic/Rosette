"""Native component evidence, kept separate from ISO rendering attestations."""
from collections import Counter
import html
import json
from pathlib import Path

from .iso import InventoryError, hash_file

SCHEMA = "rosette-native-metal-contracts-v1"
# (row label, native check-name prefix, Halo cache format ID, decoded output).
# A Halo cache ID is only an inventory candidate for the hardware block format;
# DXN mono+alpha shares the DXN block decode, and its channel meaning is a
# sampling contract this table does not test. IDs 36/37 (DXT3a variants whose
# hardware mapping is not established here) are deliberately left unmapped.
TEXTURE_CONTRACTS = (("DXT1", "DXT1", 14, "RGBA8Unorm"), ("DXT3", "DXT3", 15, "RGBA8Unorm"),
                     ("DXT5", "DXT5", 16, "RGBA8Unorm"), ("CTX1", "CTX1", 34, "RG8Unorm"),
                     ("DXN", "DXN", 33, "RG8Unorm"), ("DXN mono+alpha", "DXN", 39, "RG8Unorm"),
                     ("DXT5A", "DXT5A", 38, "R8Unorm"), ("DXT3A", "DXT3A", 35, "R8Unorm"))


def attach_native(snapshot, manifest):
    manifest = manifest.resolve(strict=True)
    result = json.loads(manifest.read_text())
    if result.get("schema") != SCHEMA or result.get("status") not in ("pass", "fail"):
        raise InventoryError("Not a saved native Metal component test manifest")
    if result.get("status") == "pass" and (not result.get("checks") or any(c.get("status") != "pass" for c in result["checks"])):
        raise InventoryError("Native Metal success must include passing contract checks")
    if result.get("status") == "pass" and (any(not result.get(g) for g in ("source_hashes","tools","artifact_hashes","oracle_script","build")) or any(b.get("returncode") != 0 for b in result["build"])):
        raise InventoryError("Native Metal success needs source/tool/artifact/oracle/build provenance")
    snapshot["native_metal"] = {"manifest": str(manifest), "manifest_sha256": hash_file(manifest), "result": result}
    return verify_native(snapshot)


def verify_native(snapshot):
    record = snapshot.get("native_metal")
    if not record: return None
    result, stale = record["result"], []
    def check(path, sha):
        try: matches = hash_file(Path(path)) == sha
        except OSError: matches = False
        if not matches: stale.append(path)
    check(record["manifest"], record["manifest_sha256"])
    try:
        if json.loads(Path(record["manifest"]).read_text()) != result:
            stale.append("Snapshot differs from saved native manifest")
    except (OSError, ValueError): pass
    for group in ("source_hashes", "tools", "artifact_hashes"):
        for path,sha in result.get(group, {}).items(): check(path,sha)
    oracle = result.get("oracle_script", {})
    if oracle: check(oracle["path"],oracle["sha256"])
    for build in result.get("build", []): check(build["log"],build["log_sha256"])
    record["verification"] = {"status": "unknown" if stale else result["status"], "stale": sorted(set(stale))}
    return native_summary(snapshot)


def native_summary(snapshot):
    record = snapshot.get("native_metal")
    if not record: return None
    result = record["result"]
    verification = record.get("verification", {"status":"unknown", "stale":["Evidence not verified"]})
    counts = Counter("unknown" if verification["status"] == "unknown" else c["status"] for c in result.get("checks", []))
    return {"status":verification["status"],"checks":len(result.get("checks",[])),
            "pass":counts["pass"],"fail":counts["fail"],"unknown":counts["unknown"],
            "device":result.get("device"),"scope":result["scope"],"stale":verification["stale"],
            "texture_contracts": texture_contract_summary(snapshot)}


def texture_contract_summary(snapshot):
    """Component check counts and format census, never ISO payload certification."""
    record = snapshot.get("native_metal") or {}
    checks = record.get("result", {}).get("checks", [])
    verified = record.get("verification", {}).get("status") in ("pass", "fail")
    formats = Counter(i["format"] for a in snapshot["iso"]["assets"] for i in a.get("subimages", []))
    rows = []
    for name, prefix, format_id, output in TEXTURE_CONTRACTS:
        selected = [c for c in checks if c["name"].split(" ", 1)[0] == prefix]
        counts = Counter(c["status"] if verified else "unknown" for c in selected)
        rows.append({"name": name, "halo_format_id": format_id, "output": output,
                     "enumerated_subimages": formats[format_id], "checks": len(selected),
                     "pass": counts["pass"], "fail": counts["fail"], "unknown": counts["unknown"],
                     "iso_payload_status": "unknown"})
    return rows


def native_view(snapshot):
    summary = verify_native(snapshot)
    if summary is None: return ""
    result = snapshot["native_metal"]["result"]
    esc = lambda x: html.escape(str(x))
    rows = "".join(f"<tr><td>{esc(c['name'])}</td><td>{esc('unknown' if summary['status']=='unknown' else c['status'])}</td><td>{esc(c['oracle'])}</td><td>{c['seconds']*1000:.3f} ms</td></tr>" for c in result.get("checks", []))
    stale = f"<p class='note'>Claims withdrawn: {esc('; '.join(summary['stale']))}</p>" if summary["stale"] else ""
    textures = "".join(f"<tr><td>{c['name']} → {c['output']}</td><td>{c['halo_format_id']}</td><td>{c['enumerated_subimages']:,}</td><td>{c['pass']} / {c['checks']}</td><td>{c['fail']}</td><td>{c['unknown']}</td><td>Unknown · resources not decoded</td></tr>" for c in summary["texture_contracts"])
    return f"""<section id="native-metal"><h2>Rosette native Metal support foundation</h2>
<p>{esc(summary['scope'])}</p>{stale}
<div class="cards"><div class="card"><b>{summary['pass']} / {summary['checks']}</b>native component contract checks passed</div><div class="card"><b>{summary['fail']}</b>failed checks</div><div class="card"><b>{summary['unknown']}</b>stale or unverified checks</div></div>
<p>Device: {esc(summary['device'] or 'unavailable')} · Metal 2.3 · fast math disabled. Library source lives in <code>lib/metal/shaders</code> and <code>lib/metal/textures</code>; AIR and metallib artifacts are saved with this evidence.</p>
<h3>Native texture decoder contracts</h3><p>Halo format IDs identify the inventory candidates below. Passing check groups verify bounded synthetic linear-block conversions, not these ISO subimages.</p>
<div class="scroll"><table><thead><tr><th>Decoder / output</th><th>Halo format ID</th><th>Enumerated subimages</th><th>Passed / tested groups</th><th>Failed</th><th>Unverified</th><th>ISO pixel comparison</th></tr></thead><tbody>{textures}</tbody></table></div>
<p class="note">ISO resource pages, tiling, mips and sampling still need extraction and comparison. No ISO texture is marked supported by synthetic tests. These formats already have Xenia texture-loader paths; the native components are not evidence of missing MoltenVK support. The ordering primitive is not a complete Xbox EDRAM implementation. This section tests standalone components. Any separately attached live-route evidence describes runtime source integration; standalone checks alone do not imply a gameplay image or FPS change.</p>
<details><summary>Native checks and independent CPU oracles</summary><table><thead><tr><th>Check</th><th>Result</th><th>Oracle / scope</th><th>Host elapsed time</th></tr></thead><tbody>{rows}</tbody></table></details>
<p>Elapsed times include Python, encoding, completion observation and readback; they are not GPU timings or game benchmarks.</p>
<details><summary>Native build and artifact provenance</summary><pre>{esc(json.dumps({k:v for k,v in result.items() if k!='checks'},indent=2))}</pre></details></section>"""
