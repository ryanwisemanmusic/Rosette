"""The finite EDRAM/IEEE resolve mismatch, separate from actual Halo attribution."""
import html
import json
from pathlib import Path
from .iso import InventoryError, hash_file

GROUPS={'all_encodings':65536,'extended_negative_bias':65536,'extended_positive_bias':65536}

def attach_resolve(snapshot, manifest):
    path=manifest.resolve(strict=True);result=json.loads(path.read_text())
    if result.get('schema')!='rosette-hdr-resolve-v1' or result.get('status')!='pass':raise InventoryError('Passing HDR resolve manifest required')
    expected={(g,v,r) for g in GROUPS for v in ('original','corrected') for r in ('vulkan','metal')}
    checks=result.get('checks',[])
    if len(checks)!=12 or {(c['group'],c['variant'],c['route']) for c in checks}!=expected:raise InventoryError('HDR resolve cases incomplete')
    for c in checks:
        want=(2048 if c['group']=='all_encodings' else 65536) if c['variant']=='original' and c['route']=='vulkan' else 0
        if c.get('rows')!=GROUPS[c['group']] or c.get('mismatch_rows')!=want or c.get('expected_mismatch_rows')!=want or c.get('nonextended_mismatch_rows')!=0 or c.get('status')!='pass':raise InventoryError('HDR resolve mismatch contract invalid')
    kernels=result.get('kernels',[])
    if len(kernels)!=10 or len({k['name'] for k in kernels})!=10 or any(k.get('status')!='pass' or not 0<k.get('unpacks',0)<=96 or k.get('pe_offset',-1)<0 for k in kernels):raise InventoryError('Missing exact resolve compilation')
    if any(not result.get(k) for k in ('source_hashes','tool_hashes','artifact_hashes','commands')) or any(c['returncode'] for c in result['commands']):raise InventoryError('HDR resolve provenance incomplete')
    snapshot['hdr_resolve']={'manifest':str(path),'manifest_sha256':hash_file(path),'result':result}
    return verify_resolve(snapshot)

def verify_record(record):
    result=record['result'];refs={record['manifest']:record['manifest_sha256']};stale=[]
    for group in ('source_hashes','tool_hashes','artifact_hashes'):refs.update(result.get(group,{}))
    for image in result.get('images',[]):
        refs.update({image['path']:image['sha256'],image['raw']:image['raw_sha256'],image['log']:image['log_sha256']})
    for path,digest in refs.items():
        try:valid=hash_file(Path(path))==digest
        except OSError:valid=False
        if not valid:stale.append(path)
    try:
        if json.loads(Path(record['manifest']).read_text())!=result:stale.append('Snapshot differs from manifest')
    except (OSError,ValueError):pass
    record['verification']={'status':'unknown' if stale else 'verified','stale':sorted(set(stale))}
    return record['verification']

def verify_resolve(snapshot):
    return verify_record(snapshot['hdr_resolve']) if snapshot.get('hdr_resolve') else None

def attach_regions(snapshot, manifest):
    path=manifest.resolve(strict=True);result=json.loads(path.read_text());images=result.get('images',[])
    if result.get('schema')!='rosette-orb-regions-v1' or not 1<=len(images)<=4 or any(x['returncode'] for x in images):raise InventoryError('Invalid orb region map')
    if any(not result.get(k) for k in ('source_hashes','tool_hashes')):raise InventoryError('Missing region provenance')
    for image in images:
        a=image['analysis'];w,h=a['width'],a['height']
        if w!=320 or not 0<h<=640 or not 0<=a['white_samples']<=w*h or not 0<=a['red_samples']<=w*h:raise InventoryError('Invalid screenshot samples')
        for region in a['regions']:
            x,y,bw,bh=region['box']
            if not (0<=x<x+bw<=w and 0<=y<y+bh<=h):raise InventoryError('Invalid region bounds')
    snapshot['orb_regions']={'manifest':str(path),'manifest_sha256':hash_file(path),'result':result}
    return verify_record(snapshot['orb_regions'])

def resolve_view(snapshot):
    esc=lambda x:html.escape(str(x));record=snapshot.get('hdr_resolve');content=''
    if record:
        v=verify_record(record)
        if v['stale']:content=f"<p class='note'>Resolve claims withdrawn: {esc('; '.join(v['stale']))}</p>"
        else:
            kernels=record['result']['kernels']
            rows=''.join(f"<tr><td>{esc(k['name'])}</td><td>{k['unpacks']}</td><td>{'seen in supplied archive' if k['observed'] else 'not seen'}</td><td>rewrite / validation / MSL / AIR pass</td></tr>" for k in kernels)
            content=f"""<div class='cards'><div class='card'><b>2,048</b>finite encodings misread by the original decoder</div><div class='card'><b>196,608</b>corrected synthetic rows match the numeric oracle</div><div class='card'><b>10 / 10</b>exact shipped resolve variants compile</div></div>
<p>The FSI writer encodes exponent 31 as finite, up to ±131008. The shipped full-resolve kernels decode it as IEEE half, producing Infinity or NaN. Rosette now corrects source decoding before exponent bias for ten exact SHA-256 identities, then applies existing buffer protection. Destination packing, ordinary texture loads and guest shader code retain their original behavior.</p>
<p>All 65,536 encodings and all 64 signed resolve biases for exponent-31 values were checked through MoltenVK and independent native Metal. The original failure is reproduced; nonextended encodings and signed zero are preserved. Five corrected kernel identities were present in the supplied run. Compiler acceptance of a kernel does not prove that it ran with float16 EDRAM.</p>
<details><summary>Exact kernel scope</summary><table><thead><tr><th>Kernel</th><th>Source half decodes corrected</th><th>Archive evidence</th><th>Offline chain</th></tr></thead><tbody>{rows}</tbody></table></details>
<p class='note'>Live correction: <code>ROSETTE_HDR_RESOLVE=0</code> opts out; the normal launcher needs no special arguments. Look for <code>VULKAN HDR RESOLVE</code> in the next log. The offline probe verifies the decoding primitive, not a full Halo frame. The run has no captured EDRAM values, so this defect is not yet proven to cause its white orbs. The native .metallib is a standalone oracle; the live implementation rewrites SPIR-V in Rosette.</p>"""
            runtime=(snapshot.get('run') or {}).get('snapshots',{}).get('hdr_resolve')
            if runtime:
                content+=f"<p>Supplied run: corrected modules {esc(runtime.get('corrected_modules','unknown'))}, corrected source unpacks {esc(runtime.get('corrected_unpacks','unknown'))}, driver rejections {esc(runtime.get('driver_rejections','unknown'))}; shader creation alone does not establish executed formats or visual improvement.</p>"
            else:
                content+="<p>Supplied run predates this correction: no live HDR resolve counter is available yet.</p>"
    images='';regions=snapshot.get('orb_regions')
    if regions and verify_record(regions)['status']=='verified':
        for i,image in enumerate(regions['result']['images']):
            a=image['analysis'];boxes=''.join(f"<rect x='{b['box'][0]}' y='{b['box'][1]}' width='{b['box'][2]}' height='{b['box'][3]}' fill='none' stroke='#7dd6c5' stroke-width='1'/><text x='{b['box'][0]+2}' y='{b['box'][1]+8}' fill='#10151d' font-size='7'>G{j+1}</text>" for j,b in enumerate(a['regions']))
            images+=f"<figure><div style='position:relative'><img src='assets/orb-region-{i}.png' style='width:100%;display:block' alt='Supplied campaign screenshot with coarse bright-region boxes'><svg viewBox='0 0 {a['width']} {a['height']}' style='position:absolute;inset:0;width:100%;height:100%'>{boxes}</svg></div><figcaption>{esc(Path(image['path']).name)} · white samples {a['white_percent']:.2f}% · red-dominant samples {a['red_percent']:.2f}%</figcaption></figure>"
        images=f"<details open><summary>Mapped white regions and red scene samples</summary><p>{esc(regions['result']['scope'])} HUD, UI and loading images can also meet these thresholds. These are measurements of the supplied screenshots, not predicted post-fix results.</p>{images}</details>"
    red="""<h3 id='red-scene'>Red scene saturation · a separate unresolved output</h3><p>The supplied screenshots show broad red scene saturation in addition to localized white glare. Full observed gamma tables have equal channels, and earlier candidate pre-gamma samples are already red or white. This narrows the investigation upstream but does not certify the gamma ramp or identify the producing draw.</p><p>The resolve correction only changes exponent-31 source values. It cannot guarantee normal colors when the source format is 7e3, the source value is in ordinary float16 range, or lighting/texture inputs are already wrong. No color filter is applied: clipped image data cannot be recovered by post-processing. Actual pass inputs, resolve format/bias and lighting constants remain the next attribution evidence.</p>"""
    return f"<section id='hdr-resolve'><h2>Live HDR resolve correction · reproduced finite-value mismatch</h2>{content}{images}{red}</section>" if record or regions else ''
