#!/usr/bin/env python3
"""Build Rosette's native Metal library and verify bounded synthetic contracts.

No ISO/game shader dispatch. No Vulkan/MoltenVK source modifications. CPU
oracles below use numeric palettes/nearest-value search rather than MSL bits.
"""
import argparse
import bisect
import ctypes as C
import hashlib
import json
from pathlib import Path
import platform
import random
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, log, timeout=90):
    start = time.monotonic()
    with log.open("wb") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    record = {"command": command, "returncode": result.returncode, "seconds": time.monotonic()-start,
              "log": str(log), "log_sha256": digest(log)}
    if result.returncode:
        raise RuntimeError(f"Build failed: {log}\n{log.read_text()[-4000:]}")
    return record


def value7e3(code):
    exponent, mantissa = divmod(code, 128)
    return mantissa / 512 if exponent == 0 else (1 + mantissa/128) * 2**(exponent-3)


VALUES = [value7e3(i) for i in range(1024)]


class NativeFailure(RuntimeError):
    def __init__(self, message, device, checks):
        super().__init__(message)
        self.device, self.checks = device, checks


def nearest7e3(value):
    high = bisect.bisect_left(VALUES, value)
    if high == 0: return 0
    if high == len(VALUES): return 1023
    low = high-1
    dl, dh = value-VALUES[low], VALUES[high]-value
    return low if dl < dh or dl == dh and low % 2 == 0 else high


def endian_word(word, mode):
    b = word.to_bytes(4, "little")
    orders = ((0,1,2,3), (1,0,3,2), (3,2,1,0), (2,3,0,1))
    return int.from_bytes(bytes(b[i] for i in orders[mode]), "little")


def ctx1_oracle(blocks, width, height, pitch):
    output = bytearray()
    for y in range(height):
        for x in range(width):
            endpoints, selectors = blocks[(y//4)*pitch+x//4]
            low, high = ((endpoints>>8)&255, endpoints&255), (endpoints>>24, (endpoints>>16)&255)
            palette = (low, high, tuple((2*a+b)//3 for a,b in zip(low,high)), tuple((a+2*b)//3 for a,b in zip(low,high)))
            output.extend(palette[(selectors >> (2*((y%4)*4+x%4))) & 3])
    return bytes(output)


def color565(value):
    # Expand the most significant bit pattern by repetition, independently
    # of the shader's shifts/masks, as required by Xenos's 565 conversion.
    components=((value>>11,5),((value>>5)&63,6),(value&31,5))
    return tuple(int((format(v,f"0{n}b")*2)[:8],2) for v,n in components)


def dxt_oracle(blocks, width, height, pitch, kind):
    pixels=bytearray()
    for y in range(height):
        for x in range(width):
            data=b"".join(w.to_bytes(4,"little") for w in blocks[(y//4)*pitch+x//4])
            color_offset=0 if kind==1 else 8
            c0,c1,selectors=struct.unpack_from("<HHI",data,color_offset)
            a,b=color565(c0),color565(c1)
            if kind==1 and c0<=c1:
                palette=(a,b,tuple((u+v)//2 for u,v in zip(a,b)),(0,0,0))
            else:
                palette=(a,b,tuple((2*u+v)//3 for u,v in zip(a,b)),tuple((u+2*v)//3 for u,v in zip(a,b)))
            i=(y%4)*4+x%4;s=(selectors//(4**i))%4
            alpha=0 if kind==1 and c0<=c1 and s==3 else 255
            if kind==3:alpha=((int.from_bytes(data[:8],"little")//(16**i))%16)*17
            if kind==5:
                a0,a1=data[0],data[1]
                if a0>a1:alphas=[a0,a1]+[((7-n)*a0+n*a1)//7 for n in range(1,7)]
                else:alphas=[a0,a1]+[((5-n)*a0+n*a1)//5 for n in range(1,5)]+[0,255]
                alpha=alphas[(int.from_bytes(data[2:8],"little")//(8**i))%8]
            pixels.extend((*palette[s],alpha))
    return bytes(pixels)


def dxt_fixture(kind, count, order):
    rng=random.Random(884+kind+count)
    blocks=[]
    for block in range(count):
        lo,hi=sorted((rng.randrange(65536),rng.randrange(65536)))
        c0,c1=(hi,lo) if order=="greater" else (lo,hi) if order=="less" else (lo,lo)
        colors=c0|(c1<<16);selectors=sum((i%4)*(4**i) for i in range(16))
        if kind==1:words=(colors,selectors)
        elif kind==3:
            alphas=sum(((i+block)%16)*(16**i) for i in range(16))
            words=(alphas&0xffffffff,alphas>>32,colors,selectors)
        else:
            a0,a1=(231,17) if order=="greater" else (17,231) if order=="less" else (103,103)
            packed=a0|(a1<<8)|(sum((i%8)*(8**i) for i in range(16))<<16)
            words=(packed&0xffffffff,packed>>32,colors,selectors)
        blocks.append(words)
    return blocks


def bc4_palette(a0, a1):
    """Eight 8-bit values of a DXT5A/DXN channel block, built by rational steps."""
    if a0 > a1:
        return [a0, a1] + [((7-n)*a0 + n*a1)//7 for n in range(1, 7)]
    return [a0, a1] + [((5-n)*a0 + n*a1)//5 for n in range(1, 5)] + [0, 255]


def bc4_texel(data, texel):
    selectors = int.from_bytes(data[2:8], "little")
    return bc4_palette(data[0], data[1])[(selectors // (8**texel)) % 8]


def bc45_oracle(blocks, width, height, pitch, kind):
    """kind 1 = DXT5A -> R8, 2 = DXN -> RG8 (first half R, second G), 3 = DXT3A -> R8."""
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            data = b"".join(w.to_bytes(4, "little") for w in blocks[(y//4)*pitch + x//4])
            texel = (y % 4)*4 + x % 4
            if kind == 1:
                pixels.append(bc4_texel(data[:8], texel))
            elif kind == 2:
                pixels.extend((bc4_texel(data[:8], texel), bc4_texel(data[8:16], texel)))
            else:
                pixels.append(((int.from_bytes(data[:8], "little") // (16**texel)) % 16) * 17)
    return bytes(pixels)


def bc4_block_words(a0, a1, rotate):
    codes = sum(((i + rotate) % 8) * (8**i) for i in range(16))
    packed = a0 | (a1 << 8) | (codes << 16)
    return (packed & 0xffffffff, packed >> 32)


def bc45_fixture(kind, count, order):
    rng = random.Random(1907 + kind + count)
    blocks = []
    for block in range(count):
        lo, hi = sorted((rng.randrange(256), rng.randrange(256)))
        pairs = [(hi, lo) if order == "greater" else (lo, hi) if order == "less" else (lo, lo) for _ in range(2)]
        if kind == 3:
            nibbles = sum(((i + block) % 16) * (16**i) for i in range(16))
            blocks.append((nibbles & 0xffffffff, nibbles >> 32))
        elif kind == 1:
            blocks.append(bc4_block_words(*pairs[0], block))
        else:
            blocks.append(bc4_block_words(*pairs[0], block) + bc4_block_words(pairs[1][1], pairs[1][0], block + 3))
    return blocks


def gpu_checks(library, metallib):
    api = C.CDLL(str(library))
    U, I, F = C.c_uint32, C.c_int32, C.c_float
    api.rosette_metal_open.argtypes = [C.c_char_p, C.c_void_p, C.c_size_t]; api.rosette_metal_open.restype = C.c_void_p
    api.rosette_metal_close.argtypes = [C.c_void_p]
    for name in ("device_name", "error"):
        method = getattr(api, "rosette_metal_"+name); method.argtypes = [C.c_void_p]; method.restype = C.c_char_p
    api.rosette_metal_color7e3.argtypes = [C.c_void_p,U,C.POINTER(U)]
    api.rosette_metal_uniform4.argtypes = [C.c_void_p,C.POINTER(F),U,C.POINTER(I),U,C.POINTER(F)]
    api.rosette_metal_ctx1.argtypes = [C.c_void_p,C.POINTER(U),U,U,U,U,U,C.POINTER(C.c_uint8)]
    api.rosette_metal_dxt.argtypes = [C.c_void_p,C.POINTER(U),U,U,U,U,U,U,C.POINTER(C.c_uint8)]
    api.rosette_metal_bc45.argtypes = [C.c_void_p,C.POINTER(U),U,U,U,U,U,U,C.POINTER(C.c_uint8)]
    api.rosette_metal_order_probe.argtypes = [C.c_void_p,U,U,C.POINTER(U)]
    error = C.create_string_buffer(4096)
    context = api.rosette_metal_open(str(metallib).encode(), error, len(error))
    if not context: raise RuntimeError(error.value.decode())
    records = []
    def case(name, oracle, function):
        start = time.monotonic()
        try:
            function()
            records.append({"name": name, "status": "pass", "oracle": oracle, "seconds": time.monotonic()-start})
        except Exception as exc:
            records.append({"name": name, "status": "fail", "oracle": oracle, "error": str(exc), "seconds": time.monotonic()-start})
            # Stop on any failure; no failed GPU work is retried.
            raise NativeFailure(str(exc), api.rosette_metal_device_name(context).decode(), records) from exc
    def completed(status):
        if status: raise RuntimeError(f"Native status {status}: {api.rosette_metal_error(context).decode()}")
    def require(condition, message):
        if not condition: raise AssertionError(message)
    try:
        device = api.rosette_metal_device_name(context).decode()
        for count in (1,63,127,129,1024):
            def color(count=count):
                out = (U*(count*4+16))(*([0xfeedbeef]*(count*4+16)))
                completed(api.rosette_metal_color7e3(context,count,out))
                for i in range(count):
                    expected = (struct.unpack("<I",struct.pack("<f",VALUES[i]))[0],i,nearest7e3((VALUES[i]+VALUES[min(i+1,1023)])/2),0)
                    require(tuple(out[i*4:i*4+4]) == expected, f"7e3 code {i}: {tuple(out[i*4:i*4+4])} != {expected}")
                require(list(out[count*4:]) == [0xfeedbeef]*16,"Host output guard changed")
            case(f"7e3 numeric decode/roundtrip/ties {count}","All codes by rational exponent/mantissa; nearest-value search with ties to even; internal/host guards",color)
        for rows in (0,1,3,256):
            def uniforms(rows=rows):
                rng = random.Random(419+rows)
                bits = [rng.getrandbits(32) for _ in range(rows*4)]
                if rows: bits[:4] = [0x80000000,0x7fc12345,0x7f800000,0xff800000]
                values = (U*max(1,rows*4))(*(bits or [0xabcdef01]))
                indices = [-2147483648,-1,0,1,rows-1,rows,2147483647]+list(range(rows))
                ids = (I*len(indices))(*indices); out = (U*(len(indices)*4+16))(*([0xfeedbeef]*(len(indices)*4+16)))
                completed(api.rosette_metal_uniform4(context,C.cast(values,C.POINTER(F)),rows,ids,len(indices),C.cast(out,C.POINTER(F))))
                expected = [v for i in indices for v in (bits[i*4:i*4+4] if 0<=i<rows else [0]*4)]
                require(list(out[:len(expected)]) == expected,"Uniform bit patterns or OOB zero results differ")
                require(list(out[len(expected):]) == [0xfeedbeef]*16,"Host output guard changed")
            case(f"Uniform bound/bit identity {rows} rows","Exact uint bit patterns including NaN/sign zero/infinities; OOB reads return zero; internal/host guards",uniforms)
        rng = random.Random(732)
        for width,height,pitch in ((4,4,1),(7,5,3),(1,1,1),(12,8,3),(15,13,5)):
            blocks = [(rng.getrandbits(32),sum((i%4)<<(i*2) for i in range(16))) for _ in range(pitch*((height+3)//4))]
            for mode in range(4):
                def texture(width=width,height=height,pitch=pitch,blocks=blocks,mode=mode):
                    words = [endian_word(word,mode) for pair in blocks for word in pair]
                    source = (U*len(words))(*words); out = (C.c_uint8*(width*height*2+16))(*([0xab]*(width*height*2+16)))
                    completed(api.rosette_metal_ctx1(context,source,len(blocks),width,height,pitch,mode,out))
                    require(bytes(out[:width*height*2]) == ctx1_oracle(blocks,width,height,pitch),"RG8 texture pixels differ from integer CTX1 palette")
                    require(bytes(out[width*height*2:]) == b"\xab"*16,"Host output guard changed")
                case(f"CTX1 RG8 {width}x{height} pitch{pitch} endian{mode}","Independent integer palette; asymmetric endpoints/all selectors/odd extents/padded block rows; real texture readback",texture)
        def dxt_readback(kind,width,height,pitch,blocks,mode):
            words=[endian_word(w,mode) for block in blocks for w in block]
            source=(U*len(words))(*words);size=width*height*4
            output=(C.c_uint8*(size+16))(*([0xab]*(size+16)))
            completed(api.rosette_metal_dxt(context,source,len(words),width,height,pitch,mode,kind,output))
            require(bytes(output[:size])==dxt_oracle(blocks,width,height,pitch,kind),"DXT RGBA pixels differ from independent byte/palette oracle")
            require(bytes(output[size:])==b"\xab"*16,"DXT host output guard changed")
        for kind in (1,3,5):
            for width,height,pitch in ((4,4,1),(7,5,3),(13,9,5)):
                for order in ("greater","less","equal"):
                    blocks=dxt_fixture(kind,pitch*((height+3)//4),order)
                    for mode in range(4):
                        case(f"DXT{kind} RGBA {width}x{height} pitch{pitch} endpoints:{order} endian{mode}",
                             "Integer byte/palette oracle; all colour selectors, DXT1 punchthrough/equal endpoints, DXT3 nibbles, DXT5 6/8-step alpha including word-boundary selectors; guards",
                             lambda kind=kind,w=width,h=height,p=pitch,b=blocks,m=mode:dxt_readback(kind,w,h,p,b,m))
            # Every isolated R5/G6/B5 component value, in both endpoint orders.
            colors=[i<<11 for i in range(32)]+[i<<5 for i in range(64)]+list(range(32))
            blocks=dxt_fixture(kind,len(colors)*2,"greater")
            for n,color in enumerate(colors):
                for reverse in (0,1):
                    offset=0 if kind==1 else 2
                    words=list(blocks[n*2+reverse]);words[offset]=color<<16 if reverse else color
                    blocks[n*2+reverse]=tuple(words)
            case(f"DXT{kind} every isolated 565 component value","Bit-string replication oracle for all R5/G6/B5 values, both endpoint orders, real RGBA8 texture readback",
                 lambda kind=kind,b=blocks:dxt_readback(kind,len(b)*4,4,len(b),b,0))
        def dxt_admission():
            source=(U*8)(*([0]*8));out=(C.c_uint8*64)(*([0xab]*64))
            parameters=((1,4,4,1,0,1),(3,4,4,1,0,5),(4,4,4,0,0,5),(4,4,4,1,4,5),(4,4,4,1,0,2),(4,0,4,1,0,5),(4,4097,4,1,0,5))
            results=[api.rosette_metal_dxt(context,source,*args,out) for args in parameters]
            require(results==[-1]*len(results),"Invalid DXT request admitted")
            require(bytes(out)==b"\xab"*64,"Rejected DXT request changed output")
        case("Host rejects seven invalid DXT requests","Short blocks, insufficient pitch, invalid format/endian/extent rejected before GPU encoding",dxt_admission)
        names = {1: ("DXT5A R8", 1), 2: ("DXN RG8", 2), 3: ("DXT3A R8", 1)}
        def bc45_readback(kind,width,height,pitch,blocks,mode):
            words=[endian_word(w,mode) for block in blocks for w in block]
            source=(U*len(words))(*words);size=width*height*names[kind][1]
            output=(C.c_uint8*(size+16))(*([0xab]*(size+16)))
            completed(api.rosette_metal_bc45(context,source,len(words),width,height,pitch,mode,kind,output))
            require(bytes(output[:size])==bc45_oracle(blocks,width,height,pitch,kind),"DXT5A/DXN/DXT3A pixels differ from independent integer palette oracle")
            require(bytes(output[size:])==b"\xab"*16,"DXT5A/DXN/DXT3A host output guard changed")
        for kind in (1,2,3):
            for width,height,pitch in ((4,4,1),(7,5,3),(13,9,5)):
                for order in (("greater","less","equal") if kind != 3 else ("nibbles",)):
                    blocks=bc45_fixture(kind,pitch*((height+3)//4),order)
                    for mode in range(4):
                        case(f"{names[kind][0]} {width}x{height} pitch{pitch} endpoints:{order} endian{mode}",
                             "Independent rational endpoint palette (8-step, 6-step plus constants 0/255, equal endpoints) or explicit nibble*17; cropped/padded rows, all four Xenos endian modes, real texture readback and guards",
                             lambda kind=kind,w=width,h=height,p=pitch,b=blocks,m=mode:bc45_readback(kind,w,h,p,b,m))
        # Every one of the 65,536 endpoint pairs, each with all eight selector
        # codes spread over the 4x4 block, as one 1024x1024 texture.
        exhaustive=[bc4_block_words(a0,a1,(a0*3+a1)%8) for a0 in range(256) for a1 in range(256)]
        case("DXT5A R8 every endpoint pair x all selector codes","65,536 endpoint pairs from the rational palette oracle in one real 1024x1024 R8 texture; both interpolation modes and constants",
             lambda:bc45_readback(1,1024,1024,256,exhaustive,0))
        paired=[a+b for a,b in zip(exhaustive,exhaustive[::-1])]
        case("DXN RG8 every endpoint pair on both channels","Two independent BC4 halves per block: pair a on R and its mirror pair on G; one real 1024x1024 RG8 texture",
             lambda:bc45_readback(2,1024,1024,256,paired,0))
        def bc45_admission():
            source=(U*8)(*([0]*8));out=(C.c_uint8*64)(*([0xab]*64))
            parameters=((1,4,4,1,0,0),(1,4,4,1,0,4),(4,4,4,0,0,1),(4,4,4,1,4,1),(4,0,4,1,0,1),(4,4097,4,1,0,1),(2,4,4,1,0,2),(3,4,4,1,0,5))
            results=[api.rosette_metal_bc45(context,source,*args,out) for args in parameters]
            require(results==[-1]*len(results),"Invalid DXT5A/DXN/DXT3A request admitted")
            require(bytes(out)==b"\xab"*64,"Rejected DXT5A/DXN/DXT3A request changed output")
        case("Host rejects eight invalid DXT5A/DXN/DXT3A requests","Short blocks, insufficient pitch, invalid format/endian/extent rejected before GPU encoding",bc45_admission)
        for samples in (1,4):
            for draws in (1,2,8,16):
                def ordered(samples=samples,draws=draws):
                    expected = 0
                    for i in range(1,draws+1): expected = expected*3+i
                    out = (U*(4*samples+16))(*([0xfeedbeef]*(4*samples+16)))
                    completed(api.rosette_metal_order_probe(context,samples,draws,out))
                    require(list(out[:4*samples]) == [expected]*(4*samples),f"Raster ordering/sample results {list(out[:4*samples])} != {expected}")
                    require(list(out[4*samples:]) == [0xfeedbeef]*16,"Host output guard changed")
                case(f"Raster order {samples}x {draws} overlapping draws","CPU serial noncommutative recurrence for every sample of 2x2 target; internal/host guards; no atomic substitute",ordered)
        def admission():
            out = (U*16)(*([0xfeedbeef]*16)); source=(U*2)(0,0); ids=(I*1)(0); pixels=(C.c_uint8*32)(*([0xab]*32))
            calls = [api.rosette_metal_color7e3(context,1025,out),api.rosette_metal_uniform4(context,None,1,ids,1,C.cast(out,C.POINTER(F))),
                     api.rosette_metal_uniform4(context,None,0,ids,0,C.cast(out,C.POINTER(F))),
                     api.rosette_metal_ctx1(context,source,1,8,4,2,0,pixels),api.rosette_metal_ctx1(context,source,1,4,4,0,0,pixels),
                     api.rosette_metal_ctx1(context,source,1,4,4,1,4,pixels),api.rosette_metal_ctx1(context,source,1,0,4,1,0,pixels),
                     api.rosette_metal_order_probe(context,2,1,out),api.rosette_metal_order_probe(context,1,17,out)]
            require(calls == [-1]*len(calls),"Invalid input was admitted")
            require(list(out)==[0xfeedbeef]*16 and bytes(pixels)==b"\xab"*32,"Rejected work modified outputs")
        case("Host rejects nine invalid ranges before encoding","No invalid GPU access dispatched; output sentinels unchanged",admission)
        return device,records
    finally:
        api.rosette_metal_close(context)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,required=True)
    args = parser.parse_args(); output = args.out.resolve()
    if output.exists(): parser.error("Use a new output directory; existing evidence is preserved")
    output.mkdir(parents=True)
    native = ROOT/"lib/metal"
    sources = sorted(p for p in native.rglob("*") if p.suffix in (".metal",".h",".mm"))
    manifest = {"schema":"rosette-native-metal-contracts-v1", "scope":"Synthetic native Metal component contracts only; no game shader dispatch, ISO payload decoding, full EDRAM emulation or live Vulkan integration.",
                "source_hashes":{str(p):digest(p) for p in sources},"host":platform.platform(),"build":[],"checks":[],
                "oracle_script":{"path":str(Path(__file__).resolve()),"sha256":digest(__file__)},"output":str(output)}
    try:
        tool = lambda name: subprocess.check_output(["/usr/bin/xcrun","--find",name],text=True).strip()
        metal,linker,clang = tool("metal"),tool("metallib"),tool("clang++")
        manifest["tools"]={p:digest(p) for p in (metal,linker,clang,"/usr/bin/xcrun")}
        manifest["sdk"]={key:subprocess.check_output(["/usr/bin/xcrun","--sdk","macosx",key],text=True).strip() for key in ("--show-sdk-path","--show-sdk-version","--show-sdk-build-version")}
        manifest["metal_language"]="macos-metal2.3"; manifest["fast_math"]=False
        airs=[]
        for source in (p for p in sources if p.suffix==".metal"):
            air=output/(source.stem+".air"); airs.append(air)
            manifest["build"].append(run([metal,"-std=macos-metal2.3","-fno-fast-math","-I",str(native/"shaders"),"-c",str(source),"-o",str(air)],output/(source.stem+".compile.log")))
        metallib=output/"rosette_support.metallib"; library=output/"librosette_metal_support.dylib"
        manifest["build"].append(run([linker,*map(str,airs),"-o",str(metallib)],output/"metallib.log"))
        manifest["build"].append(run([clang,"-isysroot",manifest["sdk"]["--show-sdk-path"],"-arch","arm64","-std=c++20","-fobjc-arc","-dynamiclib","-framework","Foundation","-framework","Metal",str(native/"support.mm"),"-o",str(library)],output/"host.compile.log"))
        manifest["artifact_hashes"]={str(p):digest(p) for p in (*airs,metallib,library)}
        manifest["device"],manifest["checks"]=gpu_checks(library,metallib)
        manifest["status"]="pass"
    except Exception as error:
        manifest["status"]="fail"; manifest["error"]=str(error)
        if isinstance(error,NativeFailure): manifest["device"],manifest["checks"]=error.device,error.checks
    (output/"manifest.json").write_text(json.dumps(manifest,indent=2))
    print(json.dumps({"status":manifest["status"],"checks":len(manifest["checks"]),"device":manifest.get("device"),"error":manifest.get("error"),"manifest":str(output/"manifest.json")},indent=2))
    return 0 if manifest["status"]=="pass" else 1


if __name__ == "__main__":
    # The user's default Homebrew Python is x86_64. The support ABI is native
    # ARM64; use Apple's universal Python explicitly rather than Rosetta.
    if platform.machine() != "arm64":
        raise SystemExit(subprocess.call(["/usr/bin/arch","-arm64","/usr/bin/python3",str(Path(__file__).resolve()),*sys.argv[1:]]))
    raise SystemExit(main())
