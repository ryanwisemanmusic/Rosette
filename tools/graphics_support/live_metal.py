"""Live route contract evidence; never promotes ISO or rendering coverage."""
import html
import json
from pathlib import Path
from .iso import InventoryError, hash_file
from .run_view import native_dispatch_total

SCHEMA='rosette-live-metal-texture-v1'

def attach_live(snapshot, manifest):
    path=manifest.resolve(strict=True);result=json.loads(path.read_text())
    if result.get('schema')!=SCHEMA or result.get('status') not in ('pass','fail'):
        raise InventoryError('Not a live Metal texture contract manifest')
    if result['status']=='pass' and (any(not result.get(k) for k in ('checks','commands','source_hashes','tools','artifact_hashes','loader_identities','xenia_pe')) or any(c.get('status')!='pass' for c in result['checks']) or any(c.get('returncode')!=0 for c in result['commands'])):
        raise InventoryError('Live route success needs passing checks and complete provenance')
    snapshot['live_metal']={'manifest':str(path),'manifest_sha256':hash_file(path),'result':result}
    return verify_live(snapshot)

def verify_live(snapshot):
    record=snapshot.get('live_metal')
    if not record:return None
    result=record['result'];stale=[]
    def check(path,sha):
        try:matches=hash_file(Path(path))==sha
        except OSError:matches=False
        if not matches:stale.append(str(path))
    check(record['manifest'],record['manifest_sha256'])
    try:
        if json.loads(Path(record['manifest']).read_text())!=result:stale.append('Snapshot differs from live manifest')
    except (OSError,ValueError):pass
    for group in ('source_hashes','tools','artifact_hashes'):
        for path,sha in result.get(group,{}).items():check(path,sha)
    pe=result.get('xenia_pe')
    if pe:check(pe['path'],pe['sha256'])
    for command in result.get('commands',[]):check(command['log'],command['sha256'])
    status='unknown' if stale else result['status'];checks=result.get('checks',[])
    record['verification']={'status':status,'stale':sorted(set(stale))}
    return {'status':status,'checks':len(checks),'pass':sum(c['status']=='pass' for c in checks) if status!='unknown' else 0,'runtime_status':'not_verified_after_rebuild','stale':sorted(set(stale))}

def live_view(snapshot):
    summary=verify_live(snapshot)
    if summary is None:return ''
    esc=lambda x:html.escape(str(x));result=snapshot['live_metal']['result']
    stale=f"<p class='note'>Claims withdrawn: {esc('; '.join(summary['stale']))}</p>" if summary['stale'] else ''
    checks=''.join(f"<li>{esc(c['name'])} · {esc(c['status'] if summary['status']!='unknown' else 'unknown')}</li>" for c in result.get('checks',[]))
    run=snapshot.get('run') or {}
    observed=run.get('snapshots',{}).get('native_textures')
    executed=native_dispatch_total(run)>0
    counts=[int(x) if x.isdigit() else 0 for x in str((observed or {}).get('dispatches(ctx1/dxt1/dxt3/dxt5)','')).split('/')]
    idle=' The DXT1/DXT3/DXT5 loaders did not dispatch in that log.' if len(counts)==4 and not any(counts[1:]) else ''
    runtime=''
    if observed and executed:
        runtime=f"<p class='note'>Supplied runtime log (run {esc(run.get('run_id','unknown'))}): dispatches CTX1/DXT1/DXT3/DXT5 = {esc(observed.get('dispatches(ctx1/dxt1/dxt3/dxt5)','unknown'))}; admission declines {esc(observed.get('declined','unknown'))}; pipeline failures {esc(observed.get('pipeline_failures','unknown'))}. This confirms the native CTX1 route executed in that build. It does not show that any picture improved.{idle}</p>"
    elif observed:
        runtime=f"<p class='note'>Supplied runtime log: dispatches CTX1/DXT1/DXT3/DXT5 = {esc(observed.get('dispatches(ctx1/dxt1/dxt3/dxt5)','unknown'))}; admission declines {esc(observed.get('declined','unknown'))}. Enabled pipelines without dispatched work do not establish native use. This run predates the current source changes.</p>"
    third="<div class=\"card\"><b>Executed in a supplied run</b>Halo rendering and FPS unverified</div>" if executed else "<div class=\"card\"><b>Rebuild needed</b>Halo rendering and FPS unverified</div>"
    return f'''<section id="live-metal"><h2>Native Metal texture route · source integration</h2>{stale}{runtime}
<div class="cards"><div class="card"><b>{summary['pass']} / {summary['checks']}</b>synthetic live contract groups passed</div><div class="card"><b>4 loaders</b>CTX1 / DXT1 / DXT3 / DXT5</div>{third}</div>
<p>Rosette-owned MSL compute pipelines now have a route through the existing Vulkan command stream. Activation requires the exact shipped loader, tested MoltenVK 1.2.7 discrete binding profile, compatible descriptors, complete constants and an unscaled 2D dispatch. Declined work retains the hardened original pipeline.</p>
<p>Tests compare bounded synthetic linear/tiled output against CPU expectations and production-hardened shipped loaders, including endian/alpha modes, cropped rows, guards, late descriptor updates, Vulkan copies and original pipeline restoration. No Xenia launch or game shader dispatch occurred.</p>
<p class="note">This is a narrow texture route, not a complete native FSI backend or a bloom/gamma fix. No ISO payload or rendering coverage is promoted. Full Zig gates and shell-update remain separate before verifying the current source in Halo. Opt out with <code>ROSETTE_NATIVE_METAL_TEXTURES=0</code>.</p>
<details><summary>Live route synthetic checks</summary><ul>{checks}</ul></details>
<details><summary>Source, driver and artifact provenance</summary><pre>{esc(json.dumps({k:v for k,v in result.items() if k!='checks'},indent=2))}</pre></details></section>'''
