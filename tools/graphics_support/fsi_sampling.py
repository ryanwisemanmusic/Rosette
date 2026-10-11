"""Hash-verified FSI semantic evidence, separate from compiler and asset coverage."""
import html
import json
from pathlib import Path

from .iso import InventoryError, hash_file

SCHEMA = 'rosette-fsi-pixel-frequency-v1'


def attach_sampling(snapshot, manifest):
    path = manifest.resolve(strict=True)
    result = json.loads(path.read_text())
    if result.get('schema') != SCHEMA or result.get('status') not in ('pass', 'fail'):
        raise InventoryError('Not an FSI pixel-frequency contract manifest')
    if result['status'] == 'pass':
        if any(not result.get(k) for k in ('commands', 'source_hashes', 'tool_hashes', 'artifact_hashes', 'device_profile')):
            raise InventoryError('Frequency evidence needs complete provenance')
        cases = result.get('cases', [])
        keys = {(c['normalized'], c['order'], c['samples'], c['mask'], c['draws']) for c in cases}
        expected = {(v, o, s, m, d) for v in (0, 1) for o in (0, 1) for s in (1, 2, 4) for m in (5, 15) for d in (1, 7)}
        if keys != expected or len(cases) != 48 or any(c['returncode'] for c in result['commands']):
            raise InventoryError('Missing native frequency cases or failed command')
        if any(c['z_bad'] or c.get('z_parity_bad') != 0 or c['count_bad'] or c['invocation_bad'] or c['guards'] != 'intact' or (c['normalized'] and c['xy_bad']) for c in cases):
            raise InventoryError('Frequency contract is not a passing result')
        if sum(not c['normalized'] and c['xy_bad'] > 0 for c in cases) != 16:
            raise InventoryError('Expected MSAA negative controls are missing')
    snapshot['fsi_sampling'] = {'manifest': str(path), 'manifest_sha256': hash_file(path), 'result': result}
    return verify_sampling(snapshot)


def verify_sampling(snapshot):
    record = snapshot.get('fsi_sampling')
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
            stale.append('Snapshot differs from frequency manifest')
    except (OSError, ValueError):
        pass
    for group in ('source_hashes', 'tool_hashes', 'artifact_hashes'):
        for path, sha in result.get(group, {}).items():
            check(path, sha)
    for command in result.get('commands', []):
        check(command['log'], command['sha256'])
    status = 'unknown' if stale else result['status']
    record['verification'] = {'status': status, 'stale': sorted(set(stale))}
    return {'status': status, 'pass': 24 if status == 'pass' else 0, 'stale': sorted(set(stale))}


def sampling_view(snapshot):
    summary = verify_sampling(snapshot)
    if summary is None:
        return ''
    result = snapshot['fsi_sampling']['result']
    esc = lambda x: html.escape(str(x))
    stale = f"<p class='note'>Claims withdrawn: {esc('; '.join(summary['stale']))}</p>" if summary['stale'] else ''
    runtime = ((snapshot.get('run') or {}).get('snapshots') or {}).get('fsi_pixel_frequency') or {}
    corrected = runtime.get('normalized', 0)
    runtime_note = (f"{corrected:,} corrected modules logged in this run" if isinstance(corrected, int) and corrected > 0
                    else 'no corrected modules reported in supplied run')
    rows = ''.join(f"<tr><td>{c['samples']}× / {c['mask']}</td><td>{c['order']} / {c['draws']}</td><td>{c['xy_bad']}</td><td>{c['z_bad']} / {esc(c.get('z_parity_bad', 'unknown'))}</td><td>{c['count_bad']} / {c['invocation_bad']}</td><td>{esc(c['guards'])}</td></tr>" for c in result.get('cases', []) if c['normalized'])
    return f'''<section id="fsi-frequency"><h2>FSI pixel-center correction · live shader path</h2>{stale}
<div class="cards"><div class="card"><b>{summary['pass']} / 24</b>native semantic contract checks passed</div><div class="card"><b>{'16' if summary['status']=='pass' else 'Unverified'} negative controls</b>old MSAA coordinates differ from pixel centers</div><div class="card"><b>Halo image unverified</b>{runtime_note}</div></div>
<p>The tested MoltenVK path inferred sample frequency from an unused SampleRateShading capability, added sample_id and shifted fragment X/Y. Rosette now centers the X/Y loads only in eligible FSI modules while preserving Z/W, per-sample execution, coverage, atomics and interlock ordering. Explicit SampleId, SamplePosition, Sample interpolation and complex decorations preserve the original module. Robust access remains active.</p>
<p class="note">An earlier capability-removal candidate compiled successfully but failed atomic sample-write parity on the native driver. It was rejected before installation. Compiler acceptance alone would have missed that regression.</p>
<p>{esc(result.get('device_profile', 'Device unknown'))}</p>
<p>{esc(result.get('depth_finding', 'Depth unverified'))} {esc(result.get('invocation_finding', 'Invocation counts unverified'))}</p>
<p class="note">This reproduces and corrects a conversion defect. It does not prove the cause of Halo's white orbs, certify ISO rendering, or predict FPS. No bloom/gamma multiplier was applied. The main ISO compiler percentage still describes its saved profile; this additional semantic test does not change that denominator.</p>
<details><summary>Pixel-center, coverage and ordered-write cases</summary><table><thead><tr><th>Samples / mask</th><th>Creation order / draws</th><th>X/Y mismatch</th><th>Depth plane / bit mismatch</th><th>Sample / invocation mismatch</th><th>Guards</th></tr></thead><tbody>{rows}</tbody></table></details>
<p>Runtime log: <code>VULKAN FSI PIXEL FREQUENCY</code>. Comparison switch: <code>ROSETTE_FSI_PIXEL_FREQUENCY=0</code>. Future runtime counters show whether the correction executed; a matched scene or first-bad-pass capture is needed to assess the picture.</p>
<details><summary>Contract manifest</summary><pre>{esc(json.dumps({k:v for k,v in result.items() if k != 'cases'}, indent=2))}</pre></details></section>'''
