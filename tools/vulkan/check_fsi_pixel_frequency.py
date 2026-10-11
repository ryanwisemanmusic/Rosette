#!/usr/bin/env python3
"""Bounded native FSI pixel-frequency contract; synthetic shaders only, never Xenia."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--sdk', type=Path, default=Path.home() / 'VulkanSDK/vulkan/macOS')
    args = parser.parse_args()
    out = args.out.resolve()
    if out.exists():
        parser.error('Use a fresh evidence directory')
    out.mkdir(parents=True)
    inp, normalized = out / 'input', out / 'normalized'
    inp.mkdir(); normalized.mkdir()
    manifest = {'schema': 'rosette-fsi-pixel-frequency-v1', 'status': 'incomplete',
                'scope': 'Synthetic pixel-center, depth, coverage, invocation-count and ordered-storage contracts on MoltenVK. No game shader execution or Halo rendering proof.',
                'commands': [], 'cases': []}

    def run(command, name, timeout=90):
        command = list(map(str, command))
        log = out / (name + '.log')
        start = time.monotonic()
        with log.open('wb') as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        manifest['commands'].append({'command': command, 'returncode': result.returncode,
                                     'seconds': time.monotonic() - start, 'log': str(log), 'sha256': sha(log)})
        if result.returncode:
            raise RuntimeError(log.read_text()[-4000:])
        return log

    try:
        sdk = args.sdk.resolve()
        metal = Path(subprocess.check_output(['xcrun', '--find', 'metal'], text=True).strip())
        mlib = Path(subprocess.check_output(['xcrun', '--find', 'metallib'], text=True).strip())
        clang = Path(subprocess.check_output(['xcrun', '--find', 'clang'], text=True).strip())
        sysroot = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        helper = out / 'prepare'
        run(['zig', 'build-exe', '-O', 'ReleaseFast', '-lc', '--dep', 'sampling',
             '-Mroot=tools/vulkan/prepare_pixel_shaders.zig', '-Msampling=lib/gpu/vulkan/fsi/pixel_frequency.zig', '-femit-bin=' + str(helper)], 'prepare-build')
        probe = out / 'probe'
        run([clang, '-isysroot', sysroot, '-arch', 'arm64', '-std=c11', '-Wall', '-Wextra', '-Werror',
             '-I', ROOT / 'pkg/vendor/sources/vulkan-headers/1.4.313/include',
             'tools/vulkan/fsi_pixel_frequency_probe.c', '-o', probe], 'probe-build')
        vertex, original = out / 'vertex.spv', inp / 'fragment.spv'
        run([sdk / 'bin/glslangValidator', '--target-env', 'vulkan1.2', 'tools/vulkan/fsi_pixel_frequency.vert', '-o', vertex], 'vertex')
        run([sdk / 'bin/glslangValidator', '--target-env', 'vulkan1.2', 'tools/vulkan/fsi_pixel_frequency.frag', '-o', original], 'fragment')
        data = original.read_bytes()
        words = list(struct.unpack('<%dI' % (len(data) // 4), data))
        cursor = 5
        while cursor < len(words):
            count, op = words[cursor] >> 16, words[cursor] & 65535
            if op == 17 and words[cursor + 1] == 35:
                raise RuntimeError('Fixture already declares sample frequency')
            cursor += count
        # The only baseline difference from GLSL is Xenia's redundant capability.
        words[5:5] = [0x00020011, 35]
        original.write_bytes(struct.pack('<%dI' % len(words), *words))
        run([helper, inp, normalized], 'normalize')
        for name, path in [('vertex', vertex), ('baseline', original), ('normalized', normalized / 'fragment.spv')]:
            run([sdk / 'bin/spirv-val', '--target-env', 'vulkan1.2', path], name + '-validate')
            msl, air, library = out / (name + '.metal'), out / (name + '.air'), out / (name + '.metallib')
            run([sdk / 'bin/MoltenVKShaderConverter', '-si', path, '-mo', msl, '-mv', '2.3', '-mp', 'macos', '-q'], name + '-convert')
            run([metal, '-std=macos-metal2.3', '-fno-fast-math', '-c', msl, '-o', air], name + '-air')
            run([mlib, air, '-o', library], name + '-metallib')
        if '[[sample_id]]' not in (out / 'baseline.metal').read_text() or '[[sample_id]]' not in (out / 'normalized.metal').read_text():
            raise RuntimeError('Converter frequency signature differs from the tested contract')
        log = run([probe, sdk / 'lib/libMoltenVK.dylib', vertex, original, normalized / 'fragment.spv'], 'gpu', 60)
        for line in log.read_text().splitlines():
            if line.startswith('CASE '):
                case = {k: int(v) for k, v in re.findall(r'(\w+)=(\d+)(?= |$)', line)}
                case['guards'] = 'intact' if 'guards=intact' in line else 'unknown'
                manifest['cases'].append(case)
            if line.startswith('driver='):
                manifest['device_profile'] = line
        cases = manifest['cases']
        fixed = [c for c in cases if c['normalized']]
        controls = [c for c in cases if not c['normalized']]
        negative = sum(c['xy_bad'] > 0 for c in controls)
        if len(fixed) != 24 or len(controls) != 24 or negative != 16 or any(
                c['xy_bad'] or c['z_bad'] or c['z_parity_bad'] or c['count_bad'] or c['invocation_bad'] or c['guards'] != 'intact' for c in fixed):
            raise RuntimeError('Missing or failed native result')
        if any(c['z_bad'] or c['count_bad'] or c['invocation_bad'] or c['guards'] != 'intact' for c in controls):
            raise RuntimeError('Baseline has a failure outside the frequency negative control')
        manifest.update(status='pass', normalized_passes=24, negative_controls_detected=negative,
                        depth_finding='Depth follows the pixel-center plane in both paths, within raster interpolation rounding; old/new depth bits are identical.',
                        invocation_finding='Sample-rate invocations retained; all sample writes remain exact. No invocation-count reduction or Halo FPS claim.')
    except Exception as error:
        manifest.update(status='fail', error=str(error))
    sources = [Path(__file__), ROOT / 'tools/vulkan/prepare_pixel_shaders.zig', ROOT / 'tools/vulkan/fsi_pixel_frequency_probe.c',
               ROOT / 'tools/vulkan/fsi_pixel_frequency.vert', ROOT / 'tools/vulkan/fsi_pixel_frequency.frag',
               ROOT / 'lib/gpu/vulkan/fsi/pixel_frequency.zig', ROOT / 'lib/linker/dyld/dynamic_library_forwarder.zig']
    manifest['source_hashes'] = {str(p): sha(p) for p in sources}
    manifest['artifact_hashes'] = {str(p): sha(p) for p in out.rglob('*') if p.is_file()}
    tools = [Path(shutil.which('zig')), args.sdk / 'lib/libMoltenVK.dylib', args.sdk / 'bin/glslangValidator',
             args.sdk / 'bin/spirv-val', args.sdk / 'bin/MoltenVKShaderConverter']
    if 'metal' in locals(): tools += [metal, mlib, clang]
    manifest['tool_hashes'] = {str(p.resolve()): sha(p) for p in tools}
    path = out / 'manifest.json'
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({k: manifest.get(k) for k in ('status', 'normalized_passes', 'negative_controls_detected', 'error')}))
    return 0 if manifest['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
