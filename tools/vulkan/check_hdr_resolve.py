#!/usr/bin/env python3
"""Finite EDRAM -> resolve decode/bias parity, no game execution or ISO writes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]

def decode(h):
    e, m = divmod(h & 32767, 1024)
    value = m * 2**-24 if not e else (1 + m / 1024) * 2**(e - 15)
    return -value if h & 32768 else value

def fixtures():
    yield 'all_encodings', [(h, 0) for h in range(65536)]
    extended = [sign | h for sign in (0, 32768) for h in range(0x7c00, 0x8000)]
    yield 'extended_negative_bias', [(h, bias) for h in extended for bias in range(-32, 0)]
    yield 'extended_positive_bias', [(h, bias) for h in extended for bias in range(32)]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--sdk', type=Path, default=Path.home()/'VulkanSDK/vulkan/macOS')
    p.add_argument('--xenia-build', type=Path, help='legacy capsule layout containing source/ and bundle/')
    p.add_argument('--xenia-source', type=Path, default=Path(os.environ['XENIA_ROOT']) if os.environ.get('XENIA_ROOT') else None,
                   help='Xenia source checkout (or set XENIA_ROOT)')
    p.add_argument('--xenia-bundle', type=Path, default=ROOT/'build/xenia-windows-clean/bundle',
                   help='directory containing the offline xenia_canary.exe identity')
    p.add_argument('--snapshot', type=Path, required=True,
                   help='explicit shader snapshot JSON; old snapshots are not kept in .rosette')
    a = p.parse_args(); out = a.out.resolve()
    if a.xenia_build:
        xenia_source = a.xenia_build/'source'
        xenia_bundle = a.xenia_build/'bundle'
    else:
        xenia_source = a.xenia_source
        xenia_bundle = a.xenia_bundle
    if xenia_source is None:
        p.error('pass --xenia-source or set XENIA_ROOT')
    if out.exists(): p.error('Use a fresh evidence directory')
    out.mkdir(parents=True)
    m = {'schema': 'rosette-hdr-resolve-v1', 'status': 'incomplete', 'commands': [], 'kernels': [], 'checks': [],
         'scope': 'Exact shipped resolve identities/compilation plus bounded synthetic primitive execution; actual Halo EDRAM values and orb attribution unknown.'}
    sources = [Path(__file__).resolve(), ROOT/'tools/vulkan/prepare_hdr_resolve.zig', ROOT/'lib/gpu/vulkan/hdr_resolve.zig',
               ROOT/'lib/gpu/vulkan/robust_access.zig', ROOT/'tools/vulkan/hdr_resolve.comp', ROOT/'tools/vulkan/hdr_contract_probe.mm',
               ROOT/'lib/metal/shaders/hdr_resolve.metal']
    tool_paths = []
    def run(cmd, name, timeout=90):
        cmd = list(map(str, cmd)); log = out/(name+'.log'); started = time.monotonic()
        with log.open('wb') as stream:
            r = subprocess.run(cmd, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        m['commands'].append({'command': cmd, 'returncode': r.returncode, 'log': str(log), 'sha256': sha(log), 'seconds': time.monotonic()-started})
        if r.returncode: raise RuntimeError(log.read_text()[-4000:])
        return log
    try:
        # Withdraw the live claim when its hook or the read-only writer/resolve
        # references change, even if the standalone decoder stays identical.
        sources += [x.resolve(strict=True) for x in (
            ROOT/'lib/linker/dyld/dynamic_library_forwarder.zig', ROOT/'lib/gpu/vulkan/root.zig',
            xenia_source/'src/xenia/gpu/spirv_shader_translator_rb.cc',
            xenia_source/'src/xenia/gpu/shaders/resolve.xesli')]
        metal = Path(subprocess.check_output(['xcrun', '--find', 'metal'], text=True).strip())
        metallib = Path(subprocess.check_output(['xcrun', '--find', 'metallib'], text=True).strip())
        clang = Path(subprocess.check_output(['xcrun', '--find', 'clang++'], text=True).strip())
        sysroot = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        validator = a.sdk/'bin/spirv-val'; converter = a.sdk/'bin/MoltenVKShaderConverter'
        glslang = a.sdk/'bin/glslangValidator'; driver = a.sdk/'lib/libMoltenVK.dylib'
        tool_paths = [metal, metallib, clang, validator, converter, glslang, driver, Path(shutil.which('zig'))]
        helper = out/'rewrite'
        run(['zig', 'build-exe', '-O', 'ReleaseFast', '-lc', '--dep', 'hdr', '--dep', 'robust',
             '-Mroot='+str(sources[1]), '-Mhdr='+str(sources[2]), '-Mrobust='+str(sources[3]), '-femit-bin='+str(helper)], 'helper-build')
        probe = out/'probe'
        probe_args = [clang, '-std=c++17', '-arch', 'arm64', '-isysroot', sysroot, '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror', '-I', ROOT/'pkg/vendor/sources/vulkan-headers/1.4.313/include', sources[5]]
        run([*probe_args, '-M', '-MT', 'HDR_DEPS'], 'probe-dependencies')
        import shlex
        sources += [Path(x).resolve() for x in shlex.split((out/'probe-dependencies.log').read_text().replace('\\\n', ' ')) if x != 'HDR_DEPS:' and Path(x).is_file()]
        run([*probe_args, '-framework', 'Metal', '-framework', 'Foundation', '-o', probe], 'probe-build')
        run([glslang, '-V', '--target-env', 'vulkan1.2', ROOT/'tools/vulkan/hdr_resolve.comp', '-o', out/'original.spv'], 'fixture-build')
        run([helper, out/'original.spv', out/'corrected.spv', 'probe'], 'fixture-rewrite')
        for variant in ('original', 'corrected'):
            run([validator, '--target-env', 'vulkan1.2', out/(variant+'.spv')], variant+'-validate')
            run([converter, '-si', out/(variant+'.spv'), '-mo', out/(variant+'.metal'), '-mv', '2.3', '-mp', 'macos', '-q'], variant+'-msl')
            run([metal, '-std=macos-metal2.3', '-fno-fast-math', '-c', out/(variant+'.metal'), '-o', out/(variant+'.air')], variant+'-air')
        native_fixture = out/'native.metal'
        native_fixture.write_text('#define rosette_hdr_resolve rosette_hdr_float16\n'+(ROOT/'lib/metal/shaders/hdr_resolve.metal').read_text())
        run([metal, '-std=macos-metal2.3', '-fno-fast-math', '-c', native_fixture, '-o', out/'native.air'], 'native-air')
        run([metallib, out/'native.air', '-o', out/'native.metallib'], 'native-metallib')
        for group, rows in fixtures():
            records = []; expected = []
            for h, bias in rows:
                other = h ^ 0x8000
                records.append((h | other << 16, bits(2**bias), 0, 0))
                x, y = decode(h), decode(other)
                expected.append((bits(x), bits(y), bits(x*2**bias), bits(y*2**bias)))
            inp = out/(group+'.input.bin'); inp.write_bytes(b''.join(struct.pack('<4I', *r) for r in records))
            (out/(group+'.expected.bin')).write_bytes(b''.join(struct.pack('<4I', *r) for r in expected))
            for variant in ('original', 'corrected'):
                prefix = out/(group+'.'+variant)
                run([probe, driver, out/(variant+'.spv'), out/'native.metallib', inp, prefix], group+'-'+variant+'-gpu', 60)
                for route in ('vulkan', 'metal'):
                    actual = list(struct.iter_unpack('<4I', Path(str(prefix)+'.'+route+'.bin').read_bytes()))
                    if len(actual) != len(expected): raise RuntimeError('Truncated GPU output')
                    bad = sum(x != y for x, y in zip(actual, expected))
                    normal_bad = sum(x != y for x, y, (h, _) in zip(actual, expected, rows) if (h & 0x7c00) != 0x7c00)
                    examples = [{'row': i, 'actual': x, 'expected': y} for i, (x, y) in enumerate(zip(actual, expected)) if x != y][:4]
                    want = (2048 if group == 'all_encodings' else len(rows)) if variant == 'original' and route == 'vulkan' else 0
                    if bad != want or normal_bad: raise RuntimeError(f'{group}/{variant}/{route}: bad={bad}, expected={want}, normal_bad={normal_bad}')
                    m['checks'].append({'group': group, 'variant': variant, 'route': route, 'rows': len(rows), 'mismatch_rows': bad,
                                        'nonextended_mismatch_rows': normal_bad, 'expected_mismatch_rows': want, 'status': 'pass', 'examples': examples})
        # Exact shipped kernels, read only. Only compile them; no game dispatch.
        snapshot = json.loads(a.snapshot.read_text()); sources.append(a.snapshot)
        observed = {x['sha256'] for x in snapshot['shader_archive']['modules'] if x['role'] == 'guest'}
        pe = xenia_bundle/'xenia_canary.exe'; exe = pe.read_bytes(); sources.append(pe)
        for header in sorted((xenia_source/'src/xenia/gpu/shaders/bytecode/vulkan_spirv').glob('resolve_full*cs.h')):
            words = [int(x, 16) for x in re.findall(r'0x([\da-fA-F]{8})', header.read_text())]
            data = struct.pack('<'+'I'*len(words), *words); sources.append(header)
            offset = exe.find(data)
            if offset < 0: raise RuntimeError('Resolve bytes absent from shipped PE')
            name = header.stem; src = out/(name+'.original.spv'); dst = out/(name+'.corrected.spv'); src.write_bytes(data)
            log = run([helper, src, dst, 'live'], name+'-rewrite')
            match = re.search(r'HDR_RESOLVE name=(\S+) unpacks=(\d+)', log.read_text())
            if not match or int(match[2]) == 0: raise RuntimeError('Exact resolve identity refused')
            run([validator, '--target-env', 'vulkan1.2', dst], name+'-validate')
            run([converter, '-si', dst, '-mo', out/(name+'.metal'), '-mv', '2.3', '-mp', 'macos', '-q'], name+'-msl')
            run([metal, '-std=macos-metal2.3', '-fno-fast-math', '-c', out/(name+'.metal'), '-o', out/(name+'.air')], name+'-air')
            m['kernels'].append({'name': match[1], 'sha256': sha(src), 'pe_offset': offset, 'observed': sha(src) in observed,
                                 'unpacks': int(match[2]), 'status': 'pass'})
        m['status'] = 'pass'
    except Exception as error:
        m.update(status='fail', error=str(error))
    m['source_hashes'] = {str(x.resolve()): sha(x) for x in sources if x.is_file()}
    m['tool_hashes'] = {str(x.resolve()): sha(x) for x in tool_paths if x.is_file()}
    m['artifact_hashes'] = {str(x): sha(x) for x in out.rglob('*') if x.is_file()}
    (out/'manifest.json').write_text(json.dumps(m, indent=2)+'\n')
    print(json.dumps({k: m.get(k) for k in ('status', 'error')}) + f" checks={len(m['checks'])} kernels={len(m['kernels'])}")
    return 0 if m['status'] == 'pass' else 1

if __name__ == '__main__': raise SystemExit(main())
