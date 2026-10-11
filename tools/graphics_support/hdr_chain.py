"""Halo 3's HDR chain, native special-value semantics, and format-aware run measurements.

Hash-verified like other evidence records. Sampled RGB bytes are not packed bit patterns: their
interpretation depends on the observed front-buffer encoding. In particular, format 54 is
10:10:10:2 UNORM, not Xenos 7e3. Nothing here certifies a Halo picture or attributes a bad pixel
to a shader; the report separates measured pre/post-gamma evidence from unmeasured inputs."""
import html
import re
from pathlib import Path

from .iso import InventoryError, hash_file

SCHEMA = 'rosette-hdr-chain-v2'
MODE = re.compile(r'^mode=MVK_CONFIG_FAST_MATH_ENABLED=(\d)$', re.M)
RESULT = re.compile(r'^(\S+)\s+(\S+)\s+bits=0x([0-9a-f]{8})$', re.M)
SAMPLED = re.compile(r'BRIGHTNESS SAMPLED RGB: frame=(\d+) stage=(\S+) mean_rgb=(\d+)/(\d+)/(\d+) max_rgb=(\d+)/(\d+)/(\d+)')
FRONT_BUFFER = re.compile(r'PE64 FRONT BUFFER: swaps_described=(\d+) format=([^\r\n(]+) \(raw (\d+)\)')
SOURCE_ENCODING = re.compile(r'FSI WHITE SOURCE ENCODING: frame=(\d+) stage=\S+ encoding=(\S+) guest_frontbuffer_format=([^\r\n(]+)\((\d+)\)')
WHITE_FRAME = re.compile(r'FSI WHITE FRAME: transition=(\d+) frame=(\d+) swapchain_white=(\d+)/(\d+) guest_output=near_white white=(\d+)/(\d+) swap_texture=near_white white=(\d+)/(\d+)')
LADDER = re.compile(r'BRIGHTNESS LADDER:\s+stage=(swap_texture|guest_output) .*?white_rgb_ge240=(\d+)/(\d+).*?frame=(\d+)')
GAMMA_CONTRACT = re.compile(r'GAMMA CHANNEL CONTRACT: frame=(\d+) .*?full_table_channel_pairs_differ=(\d+)')

# Xenos VdSwap/front-buffer formats, not Vulkan VkFormat values.
FORMAT_ENCODING = {
    6: 'unorm_8_8_8_8', 7: 'unorm_10_10_10_2',
    50: 'unorm_8_8_8_8', 54: 'unorm_10_10_10_2',
    62: 'gamma_8_8_8_8', 26: 'unorm_16_16_16_16', 63: 'xenos_7e3',
}

# IEEE answers for each probe line (1 = true, 0 = false or zero). The legacy multiply and both NaN
# clamps are the exact patterns Xenia emits; Xenia's own source notes that Inf*0 = NaN "causes
# white screen in 4D5307E6".
IEEE = {'isnan(NaN)': 1.0, 'isinf(+inf)': 1.0, 'legacy_mul(0,inf)': 0.0, 'isnan(0*inf)': 1.0,
        'clamp(NaN,0,31.875)': 0.0, 'min(max(NaN,0),31.875)': 0.0, 'isnan(inf-inf)': 1.0,
        'exp2(-inf)': 0.0, 'log2(0)==-inf': 1.0, 'NaN!=NaN': 1.0, 'isinf(1/0)': 1.0}

# What the saved disassemblies show, stage by stage. Each row names the file it was read from.
CHAIN = (
    ('shader_template_0_1_0_1_2_2_0_0_0_0.slot2.ps', 'Material lighting (static SH)',
     'colour = (albedo x lighting) x extinction + inscatter, then x c0.x; oC0 = colour (LDR), '
     'oC1 = colour / c0.y (HDR); optional sqrt encodings under b142/b143'),
    ('sky_dome_simple.ps', 'Sky dome',
     'sun glow pow(cos, c1.w) x c2 plus interpolated sky colour x c0.x; same LDR/HDR pair as the materials'),
    ('shader_shared_vertex_shaders.slot1.vs', 'Atmosphere (vertex)',
     'exponential-height Rayleigh/Mie scattering: extinction = exp2(-(c236 x ODr + c235 x ODm)), '
     'inscatter = sun c234 x (Rayleigh c237 x (1+cos^2) + Mie c238 x phase) x (1 - extinction)'),
    ('exposure_downsample.ps', 'Exposure measurement',
     '32 linear taps of scene alpha (tf0.w) weighted by tf1.y, log2 average, blended with c2.x; '
     'no later shader in this disassembled chain samples its output; any feedback into c0 must be established outside these shader binaries'),
    ('downsize_2x_to_bloom.ps', 'HDR reconstruction + bright pass',
     'scene = max(LDR, HDR x c0.y) after optional squaring (b142/b143), then threshold c2'),
    ('final_composite.ps', 'Final composite',
     'x = scene x bloom.w + bloom.rgb; colour matrix c229-c231; luminance curve avg^(c232.x-1); '
     'clamp c3.x; cubic c3.yzw; output numeric values are visible here, but the actual EDRAM/front-buffer encoding depends on bound render-target and resolve state'),
    ('restore_ldr_hdr_depth.ps', 'EDRAM restore', 'LDR, HDR and depth restored as three colour targets'),
)


def decode_7e3(code):
    """Xenos 7e3: 3-bit exponent (bias 3), 7-bit mantissa, no sign; 0x180 is 1.0."""
    exponent, mantissa = code >> 7, code & 0x7F
    if exponent == 0:
        return mantissa / 128.0 * 0.25
    return 2.0 ** (exponent - 3) * (1.0 + mantissa / 128.0)


def parse_probe(text):
    mode = MODE.search(text)
    if not mode:
        raise InventoryError('Fast-math probe log has no mode line')
    return {'mode': int(mode[1]), 'results': {name: float(value) for name, value, _bits in RESULT.findall(text)}}


def front_buffer(text):
    """Return sampled RGB with observed format and pipeline stage, never guessed 7e3 values.

    BRIGHTNESS SAMPLED RGB is already an 8-bit normalized view of readback channels. It is not
    the packed source word and cannot be decoded as 7e3. For recognized UNORM formats, byte/255
    is reported as a normalized sample; exact 7e3 values require raw packed-channel statistics.
    """
    run_format = FRONT_BUFFER.search(text)
    format_code = int(run_format[3]) if run_format else None
    format_name = run_format[2].strip() if run_format else None
    described_swaps = int(run_format[1]) if run_format else None
    per_frame_encoding = {
        int(frame): {'encoding': encoding, 'format_name': name.strip(), 'format_code': int(code)}
        for frame, encoding, name, code in SOURCE_ENCODING.findall(text)
    }
    white_counts = {
        (int(frame), stage): {'pixels': int(count), 'total': int(total)}
        for stage, count, total, frame in LADDER.findall(text)
    }
    white_frames = {}
    for transition, frame, swap_count, swap_total, output_count, output_total, texture_count, texture_total in WHITE_FRAME.findall(text):
        white_frames[int(frame)] = {
            'transition': int(transition),
            'swapchain': {'white_pixels': int(swap_count), 'total_pixels': int(swap_total)},
            'guest_output': {'white_pixels': int(output_count), 'total_pixels': int(output_total)},
            'swap_texture': {'white_pixels': int(texture_count), 'total_pixels': int(texture_total)},
        }
    gamma_contracts = {int(frame): int(differ) for frame, differ in GAMMA_CONTRACT.findall(text)}

    samples = {}
    for frame, stage, r, g, b, mr, mg, mb in SAMPLED.findall(text):
        row = samples.setdefault(int(frame), {})
        row[stage] = {'mean_rgb_8bit': [int(r), int(g), int(b)],
                      'max_rgb_8bit': [int(mr), int(mg), int(mb)]}
    rows = []
    for frame, stages in sorted(samples.items()):
        source = stages.get('swap_texture')
        if source is None:
            continue
        encoding = per_frame_encoding.get(frame)
        if encoding is not None:
            encoding_source = 'frame_source_encoding_record'
        elif format_code is not None:
            encoding = {'encoding': FORMAT_ENCODING.get(format_code, 'unknown'),
                        'format_name': format_name, 'format_code': format_code}
            encoding_source = 'run_front_buffer_descriptor'
        else:
            encoding_source = 'unknown'
        means = source['mean_rgb_8bit']
        output = stages.get('guest_output')
        output_means = output['mean_rgb_8bit'] if output else None
        rows.append({
            'frame': frame,
            'encoding': encoding['encoding'] if encoding else 'unknown',
            'encoding_source': encoding_source,
            'guest_frontbuffer_format': encoding.get('format_name') if encoding else None,
            'guest_frontbuffer_format_code': encoding.get('format_code') if encoding else None,
            'run_frontbuffer_descriptor': {'format': format_name, 'format_code': format_code,
                                           'swaps_described': described_swaps} if run_format else None,
            'pre_gamma_mean_rgb_8bit': means,
            'pre_gamma_max_rgb_8bit': source['max_rgb_8bit'],
            'pre_gamma_mean_unorm': [round(v / 255, 4) for v in means]
                if encoding and encoding['encoding'].startswith('unorm_') else None,
            'post_gamma_mean_rgb_8bit': output_means,
            'post_gamma_max_rgb_8bit': output['max_rgb_8bit'] if output else None,
            'pre_gamma_red_over_green': round(means[0] / means[1], 3) if means[1] else None,
            'post_gamma_red_over_green': (round(output_means[0] / output_means[1], 3)
                                          if output_means and output_means[1] else None),
            'pre_gamma_white_ge240': white_counts.get((frame, 'swap_texture')),
            'post_gamma_white_ge240': white_counts.get((frame, 'guest_output')),
            'white_transition': white_frames.get(frame),
            'gamma_channel_pairs_differ': gamma_contracts.get(frame),
            'seven_e3_decode': None,
        })
    return rows


def front_buffer_format(text):
    """Run-level VdSwap descriptor, distinct from its host Vulkan image format."""
    match = FRONT_BUFFER.search(text)
    if not match:
        return {'name': None, 'code': None, 'encoding': 'unknown', 'swaps_described': None}
    code = int(match[3])
    return {'name': match[2].strip(), 'code': code,
            'encoding': FORMAT_ENCODING.get(code, 'unknown'), 'swaps_described': int(match[1])}


def record_chain(snapshot, probe_logs, disasm_dir, run_log, sources, notes):
    probes = [parse_probe(Path(p).resolve(strict=True).read_text(errors='replace')) for p in probe_logs]
    by_mode = {p['mode']: p['results'] for p in probes}
    if set(by_mode) != {0, 1} or any(set(r) != set(IEEE) for r in by_mode.values()):
        raise InventoryError('Need one complete probe log for each fast-math mode (0 and 1)')
    production = by_mode[0]
    disasm = {}
    for path in sorted(Path(disasm_dir).resolve(strict=True).glob('*.txt')):
        disasm[path.name] = str(path)
    for stem, _stage, _text in CHAIN:
        if not any(name.startswith(stem) for name in disasm):
            raise InventoryError(f'Missing saved disassembly for {stem}')
    run_text = Path(run_log).resolve(strict=True).read_text(errors='replace')
    files = [*probe_logs, *disasm.values(), run_log, *sources]
    snapshot['hdr_chain'] = {
        'schema': SCHEMA,
        'fast_math': {
            'production_matches_ieee': all(production[k] == v for k, v in IEEE.items()),
            'setting_effective': any(by_mode[0][k] != by_mode[1][k] for k in IEEE),
            'results': by_mode,
        },
        'chain': [{'file': next(n for n in disasm if n.startswith(stem)), 'stage': stage, 'reads': text}
                  for stem, stage, text in CHAIN],
        'front_buffer': front_buffer(run_text),
        'run_frontbuffer_format': front_buffer_format(run_text),
        'notes': notes,
        'hashes': {str(Path(p).resolve(strict=True)): hash_file(Path(p).resolve(strict=True)) for p in files},
    }
    return verify_chain(snapshot)


def verify_chain(snapshot):
    record = snapshot.get('hdr_chain')
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


def chain_view(snapshot):
    record = snapshot.get('hdr_chain')
    if not record:
        return ''
    esc = lambda value: html.escape(str(value))
    status = verify_chain(snapshot)
    if status['stale']:
        return ("<section id='hdr-chain'><h2>Halo 3 HDR chain</h2><p class='note'>Claims withdrawn: "
                f"{esc('; '.join(status['stale']))} changed after the record was made.</p></section>")
    fast = record['fast_math']
    probe_rows = ''.join(
        f"<tr><td>{esc(name)}</td><td>{fast['results'][0][name]:g}</td><td>{fast['results'][1][name]:g}</td><td>{expected:g}</td></tr>"
        for name, expected in IEEE.items())
    chain_rows = ''.join(f"<tr><td>{esc(c['stage'])}</td><td>{esc(c['reads'])}</td><td><code>{esc(c['file'])}</code></td></tr>"
                         for c in record['chain'])
    def channels(values):
        return '—' if values is None else '/'.join(map(str, values))

    def white_count(value):
        if value is None:
            return '—'
        return f"{value['pixels']:,}/{value['total']:,}"

    buffer_rows = ''.join(
        f"<tr><td>{f['frame']}</td><td>{esc(f['encoding'])}<br><small>{esc(f['encoding_source'])}</small></td>"
        f"<td>{channels(f['pre_gamma_mean_rgb_8bit'])}</td><td>{channels(f['post_gamma_mean_rgb_8bit'])}</td>"
        f"<td>{esc(f['pre_gamma_red_over_green'])} → {esc(f['post_gamma_red_over_green'])}</td>"
        f"<td>{white_count(f['pre_gamma_white_ge240'])} / {white_count(f['post_gamma_white_ge240'])}</td>"
        f"<td>{'yes' if f['gamma_channel_pairs_differ'] == 0 else 'no' if f['gamma_channel_pairs_differ'] is not None else 'unknown'}</td></tr>"
        for f in record['front_buffer'])
    verdict = ('Production mode (0) keeps every IEEE answer and differs from mode 1, so the setting reaches Metal'
               if fast['production_matches_ieee'] and fast['setting_effective'] else
               'Production mode does not keep IEEE semantics or the setting has no effect: investigate')
    return f"""<section id="hdr-chain"><h2>Halo 3 HDR chain and pre-gamma evidence (round 40)</h2>
<p>{esc(record.get('notes', ''))}</p>
<h3>What Halo's own shaders do</h3>
<div class="scroll"><table><thead><tr><th>Stage</th><th>Reads (from the ISO microcode disassembly)</th><th>Evidence</th></tr></thead><tbody>{chain_rows}</tbody></table></div>
<p class="note">The disassembly identifies shader inputs, but not the values bound in this run. The exposure shader's output is not sampled by a later GPU pass, but this log contains neither the CPU readback nor per-draw constant buffers needed to prove that exposure, atmosphere, or the colour matrix caused the picture.</p>
<h3>Metal special values under Rosette's MoltenVK setting</h3>
<p>{esc(verdict)}.</p>
<div class="scroll"><table><thead><tr><th>Expression</th><th>Fast math 0 (Rosette)</th><th>Fast math 1</th><th>IEEE</th></tr></thead><tbody>{probe_rows}</tbody></table></div>
<h3>Observed source encoding and sampled RGB</h3>
<p>The VdSwap descriptor reports <code>{esc(record.get('run_frontbuffer_format', {}).get('name', 'unknown'))}</code> (code {esc(record.get('run_frontbuffer_format', {}).get('code', 'unknown'))}), encoding <code>{esc(record.get('run_frontbuffer_format', {}).get('encoding', 'unknown'))}</code>. Sampled RGB is an 8-bit normalized view, not the packed source word; it is never decoded as 7e3. The run explicitly records format 54 as UNORM at the white transitions.</p>
<div class="scroll"><table><thead><tr><th>Frame</th><th>Source encoding</th><th>Pre-gamma mean RGB (8-bit)</th><th>Post-gamma mean RGB (8-bit)</th><th>R/G source → output</th><th>Pre/post-gamma near-white pixels (≥240)</th><th>Equal RGB gamma tables?</th></tr></thead><tbody>{buffer_rows}</tbody></table></div>
<p class="note">Frame 896 has 716,800/737,280 near-white swap-texture pixels before gamma and 716,800/737,280 after it; sampled means are 248/248/248 → 247/248/248. At frames 1024 and 1152 the red bias is already present before gamma (195/112/120 and 189/88/89). Equal gamma-channel tables mean the same nonlinear table was installed; they do not preserve RGB ratios. At frame 1152 the sampled R/G ratio changes from 2.148 to 5.871. This localizes the measured symptoms to the source image before gamma, but not to the pass, shader, constant, or resource that first produced them. The run had no GFXReconstruct capture, and no rendering fix is claimed.</p>
<p><strong>Next decisive evidence:</strong> capture one white transition and one red frame with GFXReconstruct, then dump descriptors/resources around the first draw sequence that writes the bad pixels. The four recent accepted draw candidates in this log are temporal neighbors only; there are no per-draw constants or upstream render-target samples to attribute the fault.</p></section>"""
