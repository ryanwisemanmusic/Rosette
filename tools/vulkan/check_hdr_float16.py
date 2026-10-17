#!/usr/bin/env python3
"""Bounded synthetic HDR16 semantics; read-only Xenia functions, no game dispatch."""
import argparse
import bisect
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import shlex
import struct
import subprocess
import time

ROOT=Path(__file__).resolve().parents[2]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def bits(value):
    return struct.unpack('<I',struct.pack('<f',value))[0]

def value(code):
    sign=-1 if code&32768 else 1
    e,m=divmod(code&32767,1024)
    return sign*(m*2**-24 if not e else (1+m/1024)*2**(e-15))

VALUES=[value(i) for i in range(32768)]

def pack(raw):
    f=struct.unpack('<f',struct.pack('<I',raw))[0]
    if math.isnan(f): return 0
    sign=32768 if raw>>31 else 0
    magnitude=abs(f)
    i=bisect.bisect_left(VALUES,magnitude)
    if i==0:return sign
    if i==len(VALUES):return sign|32767
    lo,hi=VALUES[i-1],VALUES[i]
    # Numeric nearest-value oracle, independent of GPU integer encoding.
    chosen=i-1 if magnitude-lo<hi-magnitude or magnitude-lo==hi-magnitude and (i-1)%2==0 else i
    return sign|chosen

def fixture():
    records=[];expected=[];groups=[]
    def add(name,items):
        start=len(records)
        for code,x,y in items:
            records.append((code,x,y,0))
            expected.append((bits(value(code&65535)),bits(value(code>>16)),pack(x)|(pack(y)<<16),code))
        groups.append({'name':name,'start':start,'rows':len(records)-start})
    add('all_65536_encodings',((i|((65535-i)<<16),bits(value(i)),bits(value(65535-i))) for i in range(65536)))
    add('all_32767_positive_and_negative_midpoint_ties',((i|((i^32768)<<16),bits((VALUES[i]+VALUES[i+1])/2),bits(-(VALUES[i]+VALUES[i+1])/2)) for i in range(32767)))
    # Float32 neighbors around subnormal midpoint ties and the two overflow edges.
    indices=list(range(1024))+[0x7bfe,0x7bff,0x7c00,0x7ffe]
    add('midpoint_float32_neighbors',((i|((i^32768)<<16),bits((VALUES[i]+VALUES[i+1])/2)+d,(bits((VALUES[i]+VALUES[i+1])/2)+d)|0x80000000) for i in indices for d in (-1,0,1)))
    special=[0,0x80000000,0x7f800000,0xff800000,0x7fc00000,0xffc00000,0x7fa00001,0xffa00001,1,0x80000001,0x47ffe000,0xc7ffe000,0x47ffffff,0xc7ffffff]
    add('nonfinite_signed_zero_and_saturation',((0x7fff8000,x,y) for x in special for y in special))
    return records,expected,groups

def extract_functions(source):
    text=source.read_text()
    start=text.index('spv::Id SpirvShaderTranslator::PackFloat16x2ExtendedRange(')
    split=text.index('spv::Id SpirvShaderTranslator::UnpackFloat16x2ExtendedRange(',start)
    end=text.index('std::array<spv::Id, 2> SpirvShaderTranslator::FSI_ClampAndPackColor(',split)
    return text[:text.index('#include')]+text[start:end]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',required=True,type=Path)
    xenia_env=os.environ.get('ROSETTE_XENIA_ROOT') or os.environ.get('XENIA_ROOT')
    sdk_env=os.environ.get('VULKAN_SDK') or os.environ.get('VK_SDK_PATH')
    spirv_val=shutil.which('spirv-val')
    discovered_sdk=Path(sdk_env).expanduser() if sdk_env else (Path(spirv_val).resolve().parent.parent if spirv_val else None)
    parser.add_argument('--xenia',type=Path,default=Path(xenia_env).expanduser() if xenia_env else None)
    parser.add_argument('--sdk',type=Path,default=discovered_sdk)
    args=parser.parse_args();out=args.out.resolve()
    if args.xenia is None: parser.error('pass --xenia or set ROSETTE_XENIA_ROOT/XENIA_ROOT')
    if args.sdk is None: parser.error('pass --sdk or set VULKAN_SDK/VK_SDK_PATH (or put spirv-val on PATH)')
    if out.exists():parser.error('Use a fresh evidence directory')
    out.mkdir(parents=True);commands=[]
    manifest={'schema':'rosette-hdr-float16-v1','status':'incomplete','commands':commands,
              'scope':'Synthetic HDR16 conversion only. No Halo shader/resource execution, bloom attribution, ISO rendering coverage or FPS proof.'}
    source=args.xenia/'src/xenia/gpu/spirv_shader_translator_rb.cc'
    sources=[Path(__file__).resolve(),ROOT/'tools/vulkan/hdr_float16_generate.cc',ROOT/'tools/vulkan/hdr_contract_probe.mm',ROOT/'lib/metal/shaders/hdr_float16.metal',source]
    tools=[]
    def run(command,name,timeout=90):
        command=list(map(str,command));log=out/(name+'.log');start=time.monotonic()
        with log.open('wb') as stream:
            result=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
        commands.append({'command':command,'returncode':result.returncode,'seconds':time.monotonic()-start,'log':str(log),'sha256':sha(log)})
        if result.returncode:raise RuntimeError(log.read_text()[-4000:])
    try:
        records,expected,groups=fixture();manifest['groups']=groups;manifest['rows']=len(records)
        # An ordinary IEEE-half interpretation must fail exactly the extended
        # exponent-31 values. This CPU negative control distinguishes the
        # oracle from testing ordinary half on both sides by mistake.
        ieee_mismatches=sum(bits(struct.unpack('<e',struct.pack('<H',h))[0]) != bits(value(h)) for h in range(65536))
        manifest['ordinary_ieee_half_decode_mismatches']=ieee_mismatches
        if ieee_mismatches != 2048:raise RuntimeError('HDR oracle negative control failed')
        for name,data in [('input',records),('expected',expected)]:
            (out/(name+'.bin')).write_bytes(b''.join(struct.pack('<4I',*r) for r in data))
        (out/'hdr_production.inc').write_text(extract_functions(source))
        compiler_command=shlex.split(os.environ.get('CXX',''))
        if not compiler_command:
            clangxx=shutil.which('clang++')
            if not clangxx and shutil.which('xcrun'):
                clangxx=subprocess.check_output(['xcrun','--find','clang++'],text=True).strip()
            if not clangxx: raise RuntimeError('clang++ not found; install Xcode command-line tools or set CXX')
            compiler_command=[clangxx]
        sysroot=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
        base=args.xenia;builder=base/'third_party/glslang/SPIRV'
        dependencies=[base/'src/xenia/gpu/spirv_builder.cc']+[builder/n for n in ('SpvBuilder.cpp','SpvPostProcess.cpp','Logger.cpp','InReadableOrder.cpp')]+[ROOT/'tools/graphics_support/native/support.cc']
        sources+=dependencies
        generator=out/'generate'
        compile_args=[*compiler_command,'-std=c++20','-arch',platform.machine(),'-isysroot',sysroot,'-O2','-DFMT_HEADER_ONLY','-I',out,'-I',base/'src','-I',base,'-I',base/'third_party/glslang',ROOT/'tools/vulkan/hdr_float16_generate.cc',*dependencies]
        run([*compile_args,'-M','-MT','HDR_DEPS'],'generator-dependencies',180)
        dependency_tokens=shlex.split((out/'generator-dependencies.log').read_text().replace('\\\n',' '))
        sources += [Path(p).resolve() for p in dependency_tokens if p != 'HDR_DEPS:' and Path(p).is_file()]
        run([*compile_args,'-o',generator], 'generator-build',180)
        inp=out/'original';inp.mkdir();rewritten=out/'rewritten';rewritten.mkdir()
        run([generator,inp/'hdr.spv',str(len(records))],'generate')
        helper=out/'prepare'
        rewrite_sources=[ROOT/'tools/vulkan/prepare_fsi_shaders.zig',ROOT/'lib/gpu/vulkan/rect_list_expand.zig',ROOT/'lib/gpu/vulkan/robust_access.zig',ROOT/'lib/gpu/vulkan/fsi/pixel_frequency.zig'];sources+=rewrite_sources
        run(['zig','build-exe','-O','ReleaseFast','-lc','--dep','rect','--dep','robust','--dep','sampling','-Mroot='+str(rewrite_sources[0]),'-Mrect='+str(rewrite_sources[1]),'-Mrobust='+str(rewrite_sources[2]),'-Msampling='+str(rewrite_sources[3]),'-femit-bin='+str(helper)],'helper-build')
        run([helper,inp,rewritten],'rewrite')
        metal=Path(subprocess.check_output(['xcrun','--find','metal'],text=True).strip());metallib=Path(subprocess.check_output(['xcrun','--find','metallib'],text=True).strip());clang=Path(subprocess.check_output(['xcrun','--find','clang++'],text=True).strip())
        for name,spv in [('original',inp/'hdr.spv'),('rewritten',rewritten/'hdr.spv')]:
            run([args.sdk/'bin/spirv-val','--target-env','vulkan1.2',spv],name+'-validate')
            run([args.sdk/'bin/MoltenVKShaderConverter','-si',spv,'-mo',out/(name+'.metal'),'-mv','2.3','-mp','macos','-q'],name+'-msl')
            run([metal,'-std=macos-metal2.3','-fno-fast-math','-c',out/(name+'.metal'),'-o',out/(name+'.air')],name+'-air')
        run([metal,'-std=macos-metal2.3','-fno-fast-math','-c',ROOT/'lib/metal/shaders/hdr_float16.metal','-o',out/'native.air'],'native-air')
        run([metallib,out/'native.air','-o',out/'native.metallib'],'native-metallib')
        probe=out/'probe'
        probe_args=[clang,'-std=c++17','-arch','arm64','-isysroot',sysroot,'-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-I',ROOT/'pkg/vendor/sources/vulkan-headers/1.4.313/include',ROOT/'tools/vulkan/hdr_contract_probe.mm']
        run([*probe_args,'-M','-MT','HDR_DEPS'],'probe-dependencies')
        dependency_tokens=shlex.split((out/'probe-dependencies.log').read_text().replace('\\\n',' '))
        sources += [Path(p).resolve() for p in dependency_tokens if p != 'HDR_DEPS:' and Path(p).is_file()]
        run([*probe_args,'-framework','Metal','-framework','Foundation','-o',probe],'probe-build')
        driver=args.sdk/'lib/libMoltenVK.dylib'
        # Both bounded original and robust-rewritten synthetic functions have
        # statically checked extents. No hostile indices or game code.
        for variant,spv in [('original',inp/'hdr.spv'),('rewritten',rewritten/'hdr.spv')]:
            run([probe,driver,spv,out/'native.metallib',out/'input.bin',out/variant],variant+'-gpu',60)
        checks=[]
        for variant in ('original','rewritten'):
            for path in ('vulkan','metal'):
                data=(out/(variant+'.'+path+'.bin')).read_bytes()
                if len(data)!=len(expected)*16:raise RuntimeError('Truncated GPU output')
                actual=list(struct.iter_unpack('<4I',data))
                for g in groups:
                    start,end=g['start'],g['start']+g['rows'];bad=[0,0,0,0];examples=[]
                    for i in range(start,end):
                        for column in range(4):
                            if actual[i][column]!=expected[i][column]:
                                bad[column]+=1
                                if len(examples)<4:examples.append({'row':i,'column':column,'actual':actual[i][column],'expected':expected[i][column]})
                    checks.append({'variant':variant,'path':path,'group':g['name'],'rows':g['rows'],'bad_decode_x':bad[0],'bad_decode_y':bad[1],'bad_pack':bad[2],'bad_roundtrip':bad[3],'status':'fail' if any(bad) else 'pass','examples':examples})
        manifest['checks']=checks;manifest['status']='pass' if all(c['status']=='pass' for c in checks) else 'fail'
        manifest['passed']=sum(c['status']=='pass' for c in checks)
        manifest['device_logs']={v:(out/(v+'-gpu.log')).read_text() for v in ('original','rewritten')}
        tools=[compiler,metal,metallib,clang,driver,args.sdk/'bin/spirv-val',args.sdk/'bin/MoltenVKShaderConverter',Path(shutil.which('zig'))]
    except Exception as error:manifest.update(status='fail',error=str(error))
    manifest['source_hashes']={str(p.resolve()):sha(p) for p in sources if p.is_file()}
    manifest['tool_hashes']={str(p.resolve()):sha(p) for p in tools if p.is_file()}
    manifest['artifact_hashes']={str(p):sha(p) for p in out.rglob('*') if p.is_file()}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:manifest.get(k) for k in ('status','rows','passed','error')}))
    return 0 if manifest['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())
