"""White-orb evidence: semantic contracts and sampled inputs, never asset certification."""
import html
import json
import math
from pathlib import Path

from .iso import InventoryError, hash_file

GROUPS = {'all_65536_encodings': 65536,
          'all_32767_positive_and_negative_midpoint_ties': 32767,
          'midpoint_float32_neighbors': 3084,
          'nonfinite_signed_zero_and_saturation': 196}
BAD = ('bad_decode_x', 'bad_decode_y', 'bad_pack', 'bad_roundtrip')


def attach_video(snapshot, manifest):
    path = manifest.resolve(strict=True)
    result = json.loads(path.read_text())
    frames = result.get('frames', [])
    duration = result.get('duration')
    if result.get('schema') != 'rosette-white-orb-video-v1' or not 1 <= len(frames) <= 8 or not isinstance(duration, (int, float)) or not math.isfinite(duration):
        raise InventoryError('Invalid reviewed video manifest')
    if any(type(f.get('seconds')) not in (int, float) or not 0 <= f['seconds'] < duration or not isinstance(f.get('note'), str) for f in frames):
        raise InventoryError('Invalid video timestamp or note')
    if len(result.get('commands', [])) != len(frames) or any(c['returncode'] for c in result['commands']):
        raise InventoryError('Incomplete video extraction')
    if any(not result.get(k) for k in ('source_hashes', 'tool_hashes', 'video', 'video_sha256')):
        raise InventoryError('Video extraction provenance missing')
    snapshot['white_orb_video'] = {'manifest': str(path), 'manifest_sha256': hash_file(path), 'result': result}
    return verify_video(snapshot)


def verify_video(snapshot):
    record = snapshot.get('white_orb_video')
    if not record:
        return None
    result, stale = record['result'], []
    refs = {record['manifest']: record['manifest_sha256'], result['video']: result['video_sha256']}
    for group in ('source_hashes', 'tool_hashes'):
        refs.update(result.get(group, {}))
    refs.update({f['path']: f['sha256'] for f in result['frames']})
    refs.update({c['log']: c['sha256'] for c in result['commands']})
    for path, sha in refs.items():
        try:
            valid = hash_file(Path(path)) == sha
        except OSError:
            valid = False
        if not valid:
            stale.append(path)
    try:
        if json.loads(Path(record['manifest']).read_text()) != result:
            stale.append('Snapshot differs from video manifest')
    except (OSError, ValueError):
        pass
    record['verification'] = {'status': 'unknown' if stale else 'verified_extraction', 'stale': sorted(set(stale))}
    return record['verification']


def attach_hdr(snapshot, manifest):
    path = manifest.resolve(strict=True)
    result = json.loads(path.read_text())
    if result.get('schema') != 'rosette-hdr-float16-v1' or result.get('status') not in ('pass', 'fail'):
        raise InventoryError('Not an HDR float16 contract manifest')
    checks = result.get('checks', [])
    if checks:
        expected = {(v, p, g) for v in ('original', 'rewritten') for p in ('vulkan', 'metal') for g in GROUPS}
        keys = {(c['variant'], c['path'], c['group']) for c in checks}
        if len(checks) != 16 or keys != expected or result.get('rows') != sum(GROUPS.values()):
            raise InventoryError('Missing HDR conversion cases')
        for c in checks:
            if c['rows'] != GROUPS[c['group']] or any(type(c.get(k)) is not int or not 0 <= c[k] <= c['rows'] for k in BAD):
                raise InventoryError('Invalid HDR row/mismatch counts')
            if c.get('status') != ('fail' if any(c[k] for k in BAD) else 'pass'):
                raise InventoryError('HDR status conflicts with mismatch counts')
    if result['status'] == 'pass':
        if result.get('ordinary_ieee_half_decode_mismatches') != 2048:
            raise InventoryError('HDR oracle negative control missing')
        if len(checks) != 16 or any(c['status'] != 'pass' for c in checks):
            raise InventoryError('Incomplete passing HDR contract')
        if any(not result.get(k) for k in ('source_hashes', 'tool_hashes', 'artifact_hashes', 'commands', 'device_logs')):
            raise InventoryError('HDR contract requires complete provenance')
        if any(c['returncode'] for c in result['commands']):
            raise InventoryError('HDR build or execution failed')
        logs = result['device_logs']
        if set(logs) != {'original', 'rewritten'} or any('VULKAN guards=intact input=unchanged' not in s or 'METAL device=' not in s or 'guards=intact input=unchanged rows=101583' not in s for s in logs.values()):
            raise InventoryError('HDR guard/device evidence missing')
    snapshot['hdr_semantics'] = {'manifest': str(path), 'manifest_sha256': hash_file(path), 'result': result}
    return verify_hdr(snapshot)


def verify_hdr(snapshot):
    record = snapshot.get('hdr_semantics')
    if not record:
        return None
    result, stale = record['result'], []
    def check(path, sha):
        try:
            matches = hash_file(Path(path)) == sha
        except OSError:
            matches = False
        if not matches:
            stale.append(str(path))
    check(record['manifest'], record['manifest_sha256'])
    try:
        if json.loads(Path(record['manifest']).read_text()) != result:
            stale.append('Snapshot differs from HDR manifest')
    except (OSError, ValueError):
        pass
    for group in ('source_hashes', 'tool_hashes', 'artifact_hashes'):
        for path, sha in result.get(group, {}).items():
            check(path, sha)
    for c in result.get('commands', []):
        check(c['log'], c['sha256'])
    status = 'unknown' if stale else result['status']
    counts = {p: sum(c['status'] == 'pass' for c in result.get('checks', []) if c['path'] == p) if not stale else 0 for p in ('vulkan', 'metal')}
    record['verification'] = {'status': status, 'stale': sorted(set(stale)), 'passes_by_path': counts}
    return record['verification']


def white_orb_view(snapshot):
    run = snapshot.get('run') or {}
    if not run and not snapshot.get('hdr_semantics'):
        return ''
    esc = lambda x: html.escape(str(x))
    video = verify_video(snapshot)
    footage = ''
    if video:
        if video['stale']:
            footage = f"<p class='note'>Video extraction attribution withdrawn: {esc('; '.join(video['stale']))}</p>"
        else:
            frames = snapshot['white_orb_video']['result']['frames']
            pictures = ''.join(f"<figure style='margin:12px 0'><img src='assets/white-orb-{i}.png' alt='{esc(f['note'])}' style='max-width:100%;height:auto'><figcaption>{f['seconds']:g} s · {esc(f['note'])}</figcaption></figure>" for i,f in enumerate(frames))
            footage = f"<details><summary>Reviewed recording frames ({len(frames)})</summary><p>Extracted with CPU video decoding. Notes are visual observations; recording timestamps and the HUD are not a matched FPS benchmark.</p>{pictures}</details>"
    snaps = run.get('snapshots') or {}
    frequency = snaps.get('fsi_pixel_frequency') or {}
    capture = snaps.get('render_pass_capture') or {}
    frame_capture = snaps.get('frame_capture') or {}
    gamma = run.get('gamma_contracts') or []
    different = [g for g in gamma if isinstance(g.get('full_table_channel_pairs_differ'), int) and g['full_table_channel_pairs_differ'] > 0]
    equal = sum(g.get('full_table_channel_pairs_differ') == 0 for g in gamma)
    settings = run.get('render_settings') or {}
    rows = [
        ('Coordinate correction', f"{esc(frequency.get('normalized', 'unknown'))} corrected modules; {esc(frequency.get('driver_rejections', 'unknown'))} driver rejections. Runtime use is not visual proof."),
        ('Gamma channel contract', f"{equal} equal-channel ramps, {len(different)} unequal-channel ramps among {len(gamma)} observations. This checks full observed tables, but does not identify the exact shader binding or prove the ramp is appropriate for the scene."),
        ('Frame capture', f"Render-pass capture state {esc(capture.get('state', 'unknown'))}, file {esc(capture.get('capture_file', 'unknown'))}; {esc(frame_capture.get('saved', 'unknown'))} swap-image captures saved. A screenshot cannot expose the producing pass's resources, constants and blend state."),
        ('Resolve / occlusion settings', f"readback_resolve={esc(settings.get('readback_resolve', 'unknown'))}, occlusion_query={esc(settings.get('occlusion_query', 'unknown'))}. An absent setting remains unknown; no configuration experiment was run."),
    ]
    selected = [m for m in (snapshot.get('shader_archive') or {}).get('modules', []) if m.get('current_run_guest_match')]
    census = [m['half_conversion_ops'] for m in selected if 'half_conversion_ops' in m]
    pack = sum(c['pack_half2x16'] > 0 for c in census)
    unpack = sum(c['unpack_half2x16'] > 0 for c in census)
    rows.append(('Observed HDR conversion census', f"{pack}/{len(selected)} exact matched guest modules contain PackHalf2x16; {unpack}/{len(selected)} contain UnpackHalf2x16 ({len(census)} parsed). Opcode presence does not establish runtime format, executed branch or the cause of a white region."))
    table = ''.join(f'<tr><td>{esc(k)}</td><td>{v}</td></tr>' for k,v in rows)
    samples = {}
    views = {(v.get('frame'), v.get('stage')): v for v in run.get('sample_views', [])}
    for sample in run.get('sampled_rgb', []):
        samples.setdefault(sample.get('frame'), {})[sample.get('stage')] = sample
    brightness = ''
    if samples:
        b = []
        for frame, stages in sorted(samples.items()):
            a, o = stages.get('swap_texture', {}), stages.get('guest_output', {})
            view = views.get((frame, 'swap_texture'), {})
            b.append(f"<tr><td>{esc(frame)}</td><td>{esc(a.get('mean_rgb', 'unread'))}</td><td>{esc(o.get('mean_rgb', 'unread'))}</td><td>{esc(view.get('components', 'unknown'))}</td></tr>")
        brightness = f"""<details><summary>Submitted-view RGB samples ({len(samples)} frames)</summary><p>These values apply the logged view's RGB permutation to the raw transfer. That descriptor is a candidate source, not proof of the binding fetched by the shader. Different frames or runs are not matched scenes. Loading frames may be white.</p><table><thead><tr><th>Frame</th><th>Candidate pre-gamma RGB</th><th>Gamma output RGB</th><th>View components</th></tr></thead><tbody>{''.join(b)}</tbody></table></details>"""
    summary = verify_hdr(snapshot)
    hdr = '<p>Extended float16 semantic probe: not supplied.</p>'
    if summary:
        result = snapshot['hdr_semantics']['result']
        counts = summary['passes_by_path']
        stale = f"<p class='note'>HDR claims withdrawn: {esc('; '.join(summary['stale']))}</p>" if summary['stale'] else ''
        cases = ''.join(f"<tr><td>{esc(c['variant'])} / {esc(c['path'])}</td><td>{esc(c['group'])}</td><td>{c['rows']:,}</td><td>{'/'.join(str(c[k]) for k in BAD)}</td><td>{esc('unknown' if summary['stale'] else c['status'])}</td></tr>" for c in result.get('checks', []))
        hdr = f"""<h3>HDR extended float16 · semantic checks on this GPU</h3>{stale}
<p>Evidence status: {esc(summary['status'])}. {esc(result.get('error', ''))}</p>
<div class='cards'><div class='card'><b>{counts['vulkan']} / 8</b>exact Xenia pack/unpack through MoltenVK</div><div class='card'><b>{counts['metal']} / 8</b>independent native Metal conversion</div><div class='card'><b>{result.get('rows', 0):,}</b>bounded rows per dispatch</div></div>
<p>All 65,536 encodings, all positive/negative midpoint ties, subnormal neighbors, overflow, NaNs and signed zero are compared with an independent numeric CPU oracle. Original and production-rewritten synthetic shaders are tested. Xbox extended float16's largest exponent is finite; it cannot be decoded as an ordinary IEEE half without correction.</p>
<p>CPU negative control: ordinary IEEE half differs for {esc(result.get('ordinary_ieee_half_decode_mismatches', 'unknown'))} encodings. No faulty shader was dispatched for this control.</p>
<p class='note'>This tests the exact conversion primitives in isolation. It does not test Halo's blend equations, texture resources, resolve exponent bias, lighting constants or occlusion queries. The native .metallib is a standalone foundation and is not connected to live FSI. Passing checks do not promote any ISO tag or predict visual changes or FPS.</p>
<details><summary>HDR contract outcomes and mismatches</summary><table><thead><tr><th>Variant / route</th><th>Group</th><th>Rows</th><th>Decode X/Y / pack / roundtrip mismatches</th><th>Status</th></tr></thead><tbody>{cases}</tbody></table><pre>{esc(json.dumps(result.get('device_logs', {}), indent=2))}</pre></details>"""
    return f"""<section id='white-orbs'><h2>White-orb investigation · tested behavior and missing scene evidence</h2>
<p>Compiler readiness answers whether code can compile. It cannot rule out wrong shader behavior or bad inputs. This investigation targets bright character-shaped regions and excessive glare; the first pass producing them remains unidentified.</p>{footage}
<table><thead><tr><th>Evidence</th><th>Finding and limits</th></tr></thead><tbody>{table}</tbody></table>{brightness}{hdr}
<h3>Remaining tests that can explain the glare</h3><table><thead><tr><th>Unknown</th><th>Evidence needed</th></tr></thead><tbody>
<tr><td>HDR blend / resolve / exponent bias</td><td>Capture the first damaged pass, its EDRAM input/output, format and resolve constants; compare bounded data with a numeric oracle.</td></tr>
<tr><td>Lighting, bloom and exposure inputs</td><td>Actual constants, sampled textures and pass bindings. The shader/tag inventory cannot reconstruct those runtime values.</td></tr>
<tr><td>Occlusion / lens-flare response</td><td>Query results and a matched configuration experiment. No measured query evidence in this report.</td></tr>
<tr><td>Texture payload, tiling and mip interpretation</td><td>Extracted resource pixels and verified decoding, beyond metadata and standalone decoder contracts.</td></tr></tbody></table>
<p>Existing capture helper: <code>tools/vulkan/capture_halo3_fsi.sh --frame 3072</code> (one diagnostic frame; F10 alternative). No game was launched or capture requested during this pass.</p></section>"""
