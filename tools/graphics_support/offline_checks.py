"""Offline contract checks that need no Halo data: bounded native-GPU and CPU-decoder results with
hash-verified provenance. A pass says a stage behaves as specified on tested inputs; it never says
Halo's picture is right, and a changed log or source withdraws the record."""
import html
import re
from pathlib import Path

from .iso import InventoryError, hash_file

SCHEMA = 'rosette-offline-checks-v1'
ZPD_LINE = re.compile(r'^ZPD (\S+) msaa=(\d)x depth=(\d) counter=(\d+) covered_samples=(\d+) ratio=([\d.]+)', re.M)
ORACLES = (('operand_roles', re.compile(r'operand roles: checked (\d+) three-register VEX forms, (\d+) differ')),
           ('memory_operands', re.compile(r'memory operands: checked (\d+) forms with a ModR/M memory operand, (\d+) differ')))


def parse_zpd(text):
    """Per MSAA setting: how many modules counted exactly the covered samples, none, or something else."""
    configs, modules = {}, set()
    for module, msaa, _depth, counter, covered, _ratio in ZPD_LINE.findall(text):
        modules.add(module)
        entry = configs.setdefault(f'{msaa}x', {'exact': 0, 'zero': 0, 'other': 0, 'over': 0})
        counter, covered = int(counter), int(covered)
        if counter == covered:
            entry['exact'] += 1
        elif counter == 0:
            entry['zero'] += 1
        else:
            entry['other'] += 1
            entry['over'] += counter > covered
    return {'modules': len(modules), 'configs': configs}


def parse_oracles(text):
    found = {}
    for name, pattern in ORACLES:
        match = pattern.search(text)
        if match:
            found[name] = {'checked': int(match[1]), 'differ': int(match[2])}
    return found


def record_checks(snapshot, zpd_log, oracle_log, sources, notes):
    """Parse the two logs, hash everything they depend on and attach the record."""
    zpd_text = Path(zpd_log).resolve(strict=True).read_text(errors='replace')
    oracle_text = Path(oracle_log).resolve(strict=True).read_text(errors='replace')
    zpd, oracles = parse_zpd(zpd_text), parse_oracles(oracle_text)
    if not zpd['modules'] or len(oracles) != len(ORACLES):
        raise InventoryError('Logs do not contain the ZPD counter lines and both CPU oracle summaries')
    refs = {str(Path(p).resolve(strict=True)): hash_file(Path(p).resolve(strict=True))
            for p in [zpd_log, oracle_log, *sources]}
    snapshot['offline_checks'] = {'schema': SCHEMA, 'zpd_counter': zpd, 'cpu_oracles': oracles,
                                  'notes': notes, 'hashes': refs}
    return verify_checks(snapshot)


def verify_checks(snapshot):
    record = snapshot.get('offline_checks')
    if not record:
        return None
    stale = []
    for path, sha in record['hashes'].items():
        try:
            valid = hash_file(Path(path)) == sha
        except OSError:
            valid = False
        if not valid:
            stale.append(path)
    record['verification'] = {'status': 'unknown' if stale else 'verified', 'stale': sorted(stale)}
    return record['verification']


def checks_view(snapshot):
    record = snapshot.get('offline_checks')
    if not record:
        return ''
    esc = lambda value: html.escape(str(value))
    status = verify_checks(snapshot)
    if status['stale']:
        return ("<section id='offline-checks'><h2>Offline contract checks</h2><p class='note'>Claims withdrawn: "
                f"{esc('; '.join(status['stale']))} changed after the checks ran.</p></section>")
    zpd, oracles = record['zpd_counter'], record['cpu_oracles']
    rows = ''.join(
        f"<tr><td>FSI occlusion counter, {esc(config)} MSAA</td><td>{c['exact']:,} of {zpd['modules']:,} production-rewritten Halo FSI shaders count exactly the covered samples; "
        f"{c['zero']:,} count nothing with the harness constants; {c['other']:,} count something else ({c['over']:,} too many)</td></tr>"
        for config, c in sorted(zpd['configs'].items()))
    rows += ''.join(
        f"<tr><td>Decoder {esc(name.replace('_', ' '))}</td><td>{o['checked']:,} instruction forms from Xenia's own JIT corpus decoded; {o['differ']:,} disagree with their disassembly text</td></tr>"
        for name, o in sorted(oracles.items()))
    return f"""<section id="offline-checks"><h2>Offline contract checks (no Halo data)</h2>
<p>{esc(record.get('notes', ''))}</p>
<div class="scroll"><table><thead><tr><th>Check</th><th>Result</th></tr></thead><tbody>{rows}</tbody></table></div>
<p class="note">The counter rows run each module on the real GPU through MoltenVK with Xenia's own clear-then-draw sequence and a full-screen draw. They test the shader's counting, not Halo's use of the result, the readback, or the flare math. A pass is not evidence the orbs are fixed or that they come from elsewhere.</p></section>"""
