#!/usr/bin/env python3
"""Verify the live texture contract with bounded synthetic data, never Xenia.

Four exact bundled loader identities; CPU oracle, production hardened loader,
native MSL, tiled addressing, descriptor ranges, guards and Vulkan ordering.
Failure is terminal; only short, bounded workloads are dispatched.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import shutil
import time
from check_support import ctx1_oracle, dxt_oracle, dxt_fixture, endian_word

ROOT=Path(__file__).resolve().parents[2]
NAMES=('ctx1','dxt1_rgba8','dxt3_rgba8','dxt5_rgba8')
KINDS=(0,1,3,5)
HASHES=('62d6655844c00aa27c41bb525e762bc875ab41e6040268f80a9b22831d0e34d1','bcdfce86372ebccd56fb9c1fd7e969ababa5298f0561d90101ffd91c9b4e0366','141670e9f738bb7cf528fdc8dbc577c5fe94c65f9f2d6bfcc0bf13cf7d2321d3','e078a76d45fd8bcced7de3e69ac9cac3ded81058f1783ec58cb09633b64805f9')
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def tiled(x,y,pitch,bpb):
    # Independently expressed integer address fields, checked against the
    # shipped loader as well as the native kernel across both tile boundaries.
    n=((y//32)*(pitch//32)+x//32)*64+((y//2)%8)*8+x%8
    n*=bpb
    return (y%2)*16+((x//8)%4 ^ ((y//8)%2)*2)*64+((y//16)%2)*2048+n%16+((n//16)%2)*32+((n//32)%8)*256+(n//256)*4096

def fixture(kind,bx,by,tile,mode,order,bounded=None,scale=0x90):
    bpp=2 if kind==0 else 4;bpb=8 if kind in (0,1) else 16
    gp=((bx+31)//32)*32;hp=((bx+3)//4)*16*bpp+16;height=by*4-1;go=32;ho=16
    blocks=dxt_fixture(kind,gp*by,order) if kind else [(0x317fb3e9 ^ ((i*257)&0x00ff00ff),0xe4e4e4e4 ^ (i*98731&0xffffffff)) for i in range(gp*by)]
    full=max(go+(tiled(x,y,gp,bpb) if tile else (y*gp+x)*bpb)+bpb for y in range(by) for x in range(gp))
    src=bytearray(full+64)
    for y in range(by):
        for x in range(gp):
            a=go+(tiled(x,y,gp,bpb) if tile else (y*gp+x)*bpb)
            struct.pack_into('<'+'I'*(bpb//4),src,a,*(endian_word(w,mode) for w in blocks[y*gp+x]))
    sr=len(src);dr=ho+hp*height+128
    if bounded=='source':sr=go+bpb-1
    if bounded=='dest':dr=ho+hp+7
    if bounded=='overflow':go=0xfffffffc;ho=0xfffffffc
    expected=bytearray([0xa7])*(16+hp*height+128);mask=bytearray(len(expected));width=bx*4
    decoded_blocks=[]
    for y in range(by):
        for x in range(gp):
            a=go+(tiled(x,y,gp,bpb) if tile else (y*gp+x)*bpb)
            decoded_blocks.append(blocks[y*gp+x] if a+bpb<=sr else (0,)*(bpb//4))
    pixels=ctx1_oracle(decoded_blocks,width,height,gp) if not kind else dxt_oracle(decoded_blocks,width,height,gp,kind)
    for y in range(height):
        for x in range(width):
            off=ho+y*hp+x*bpp
            if off+bpp<=dr:
                expected[off:off+bpp]=pixels[(y*width+x)*bpp:(y*width+x+1)*bpp];mask[off:off+bpp]=bytes([1])*bpp
    flags=scale|int(tile)|(mode<<2)
    if bounded in ('scaled','3d'):
        flags=(0xa0 if bounded=='scaled' else 0x92)|int(tile)|(mode<<2)
        expected[:]=bytes([0xa7])*len(expected);mask[:]=bytes(len(mask))
    push=(flags,go,gp,32,bx,by,1,ho,hp,height)
    header=(KINDS.index(kind),int(bounded is None),len(src),len(expected),sr,dr,*push)
    return struct.pack('<16I',*header)+src+expected+mask

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--sdk',type=Path,default=Path.home()/'VulkanSDK/vulkan/macOS')
    p.add_argument('--xenia-build',type=Path,default=ROOT/'.rosette/xenia-windows-clean')
    a=p.parse_args();out=a.out.resolve()
    if out.exists():p.error('Use a fresh evidence directory')
    out.mkdir(parents=True);original=out/'original';original.mkdir();hardened=out/'hardened';hardened.mkdir();cases=out/'cases';cases.mkdir()
    manifest={'schema':'rosette-live-metal-texture-v1','scope':'Synthetic live route contracts, not ISO payload or Halo rendering/FPS proof','status':'incomplete','commands':[],'checks':[]}
    def run(cmd,name,timeout=90):
        log=out/(name+'.log');start=time.monotonic()
        with log.open('wb') as stream:r=subprocess.run(list(map(str,cmd)),stdout=stream,stderr=subprocess.STDOUT,timeout=timeout,cwd=ROOT)
        manifest['commands'].append({'command':list(map(str,cmd)),'returncode':r.returncode,'seconds':time.monotonic()-start,'log':str(log),'sha256':sha(log)})
        if r.returncode:raise RuntimeError(log.read_text()[-4000:])
        return log
    try:
        pe=a.xenia_build/'bundle/xenia_canary.exe';exe=pe.read_bytes();manifest['xenia_pe']={'path':str(pe),'sha256':sha(pe)};identities=[]
        for name,expected in zip(NAMES,HASHES):
            header=a.xenia_build/'source/src/xenia/gpu/shaders/bytecode/vulkan_spirv'/('texture_load_'+name+'_cs.h')
            text=header.read_text();words=re.findall(r'0x([0-9a-fA-F]{8})',text)
            data=struct.pack('<'+'I'*len(words),*(int(w,16) for w in words));path=original/(name+'.original.spv');path.write_bytes(data)
            offset=exe.find(data)
            if sha(path)!=expected or offset<0:raise RuntimeError('Loader identity not present in PE: '+name)
            identities.append({'name':name,'sha256':expected,'header_sha256':sha(header),'pe_offset':offset})
        del exe;manifest['loader_identities']=identities
        src=ROOT/'lib/metal/textures';flat=out/'live.metal';flat.write_text((src/'block_formats.h').read_text()+'\n'+(src/'live_xenia.metal').read_text())
        metal=subprocess.check_output(['xcrun','--find','metal'],text=True).strip();mlib=subprocess.check_output(['xcrun','--find','metallib'],text=True).strip();clang=subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
        helper=out/'rewrite';run(['zig','build-exe','-O','ReleaseFast','-lc','--dep','rect','--dep','robust','-Mroot=tools/vulkan/prepare_rect_shaders.zig','-Mrect=lib/gpu/vulkan/rect_list_expand.zig','-Mrobust=lib/gpu/vulkan/robust_access.zig','-femit-bin='+str(helper)],'rewrite-build')
        run([helper,original,hardened],'rewrite')
        profile=out/'profile-probe'
        run(['zig','build-exe','-O','ReleaseFast','-lc','--dep','policy','-Mroot=tools/metal/probe_live_profile.zig','--dep','rosette_live_metal_source','-Mpolicy=lib/gpu/root.zig','-Mrosette_live_metal_source=lib/metal/textures/live_source.zig','-femit-bin='+str(profile)],'profile-build')
        run([profile,a.sdk/'lib/libMoltenVK.dylib',*[original/(n+'.original.spv') for n in NAMES]],'profile')
        for name in NAMES:run([a.sdk/'bin/spirv-val','--target-env','vulkan1.2',hardened/(name+'.original.spv')],name+'-validate')
        run([metal,'-std=macos-metal2.3','-fno-fast-math','-c',flat,'-o',out/'live.air'],'metal')
        run([mlib,out/'live.air','-o',out/'live.metallib'],'metallib')
        probe=out/'probe';run([clang,'-isysroot',subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip(),'-arch','arm64','-O2','-Wno-unused-function','-I',a.sdk/'include',ROOT/'tools/metal/probe_live_texture.c','-o',probe],'probe-build')
        paths=[]
        for kind in KINDS:
            for tile in (False,True):
                for mode in range(4):
                    for order in ('greater','less','equal'):
                        for bx,by in ((5,3),(36,35)):
                            label=f'{kind}-{int(tile)}-{mode}-{order}-{bx}x{by}';f=cases/(label+'.bin');f.write_bytes(fixture(kind,bx,by,tile,mode,order));paths.append(f)
            for bounded in ('source','dest','overflow'):
                f=cases/f'{kind}-bounds-{bounded}.bin';f.write_bytes(fixture(kind,5,3,True,2,'greater',bounded));paths.append(f)
            for tile in (False,True):
                f=cases/f'{kind}-legacy-{int(tile)}.bin';f.write_bytes(fixture(kind,5,3,tile,2,'greater',scale=0));paths.append(f)
            for bounded in ('scaled','3d'):
                f=cases/f'{kind}-refuse-{bounded}.bin';f.write_bytes(fixture(kind,5,3,True,2,'greater',bounded));paths.append(f)
        # Short bounded tests, no hostile reference accesses or game shaders.
        log=run([probe,a.sdk/'lib/libMoltenVK.dylib',flat,hardened,*paths],'gpu',timeout=180)
        lines=log.read_text().splitlines();passed=[line for line in lines if line.startswith('PASS ')]
        if len(passed)!=len(paths):raise RuntimeError('Missing GPU result')
        manifest['checks']=[{'name':line[5:],'status':'pass'} for line in passed]
        manifest['status']='pass'
        sources=[Path(__file__),ROOT/'tools/metal/check_support.py',ROOT/'tools/metal/probe_live_texture.c',ROOT/'tools/metal/probe_live_profile.zig',ROOT/'tools/vulkan/robust_access/probe.c',ROOT/'lib/gpu/metal/live_texture.zig',ROOT/'lib/linker/dyld/dynamic_library_forwarder.zig',ROOT/'lib/metal/textures/live_source.zig',src/'block_formats.h',src/'live_xenia.metal',ROOT/'lib/gpu/vulkan/rect_list_expand.zig',ROOT/'lib/gpu/vulkan/robust_access.zig',ROOT/'lib/gpu/vulkan/abi.zig',ROOT/'lib/gpu/vulkan/marshal.zig',ROOT/'build/build.zig',ROOT/'app/bundling/build.zig']
        sources.append(ROOT/'lib/gpu/vulkan/fsi/pixel_frequency.zig')
        manifest['source_hashes']={str(x):sha(x) for x in sources};manifest['tools']={str(x):sha(x) for x in (Path(metal),Path(mlib),Path(clang),a.sdk/'lib/libMoltenVK.dylib',a.sdk/'bin/spirv-val',Path(shutil.which('zig')))}
        manifest['artifact_hashes']={str(x):sha(x) for x in (flat,out/'live.air',out/'live.metallib',probe,profile,helper,*original.glob('*.spv'),*hardened.glob('*.spv'),*paths)}
    except Exception as e:manifest['status']='fail';manifest['error']=str(e)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps({'status':manifest['status'],'checks':len(manifest['checks']),'error':manifest.get('error'),'manifest':str(out/'manifest.json')},indent=2));return 0 if manifest['status']=='pass' else 1
if __name__=='__main__':raise SystemExit(main())
