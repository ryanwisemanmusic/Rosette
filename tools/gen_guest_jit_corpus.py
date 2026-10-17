#!/usr/bin/env python3
"""Every instruction form Xenia's x64 JIT can emit, as bytes, for Rosette's tests.

Why this exists
---------------
The 2026-09-14 run ended at 0xa0535c03, inside code Xenia's JIT had just
generated for the title: the decoder had no entry for the form. Nothing could
have found that ahead of a run, because generated code has no file to read.
But the *vocabulary* of generated code is fixed: it is every Xbyak method
Xenia's x64 backend calls. This tool reads that vocabulary out of Xenia's
sources, assembles each mnemonic in every operand form the assembler accepts,
and writes the result where the ELF processor's test embeds it:

    lib/processor/ELF_processor/guest_jit_corpus.txt   (hex|mnemonic|source)

The test there decodes and executes every line. A form Xenia can emit that
Rosette cannot run now fails the build instead of a run.

Only extensions Rosette's `xenia` CPUID profile advertises are written: Xenia
gates AVX2, AVX-512, FMA, BMI, XOP and GFNI on CPUID, so forms needing them
are never emitted here. Advertising one of those later means extending the
filter below, and the test then holds Rosette to it.

Usage: tools/gen_guest_jit_corpus.py --xenia-root /path/to/xenia
Needs clang (x86_64 assembler) and llvm-objdump.
"""
import argparse
import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "lib/processor/ELF_processor/guest_jit_corpus.txt")

SKIP = {"backend", "db", "dd", "dw", "emit_instr", "epilog_label", "inverse_instr",
        "stack_size", "call", "jmp", "lock"}
JCC = {"ja", "jae", "jb", "jbe", "jc", "je", "jg", "jge", "jl", "jle", "jnc", "jne", "jnz", "jo", "jz", "jrcxz"}
RENAME = {"and_": "and", "or_": "or", "xor_": "xor", "not_": "not", "cdq": "cltd", "cqo": "cqto"}
# Extensions Xenia gates on CPUID and Rosette's `xenia` profile does not
# advertise (src/x64-ASM/capabilities.zig).
GATED = set("""vpbroadcastb vpbroadcastd vpbroadcastw vpblendd vextracti128 vpsllvd vpsravd vpsrlvd
vmovdqa32 vmovdqu8 vpblendmd vpblendmq vpcmpub vpcmpud vpcmpuw vpmovd2m vpmovm2b vpmovm2d vpmovm2w
vprolvd vpternlogd vptestmq vptestnmd vpxord vrangeps vrsqrt14ss vcvttps2udq vpermb vpermi2b vpermi2w
vfmadd213ps vfmadd213sd vfmsub213ps vfmsub213sd andn mulx sarx shlx shrx
vpcmov vpcomb vpcomd vpcomw vprotb vprotd vprotw vpshab vpshad vpshaw vpshlb vpshld vpshlw
gf2p8affineqb vgf2p8affineqb vgf2p8mulb""".split())

M = "8(%r12,%r13,2)"
LM = "(%rax)"
GPR = [
    "{m}", "{m} %r10", "{m} %r10d", "{m} %r10w", "{m} %r10b", "{m} %rax", "{m} %eax", "{m} %ax", "{m} %al",
    "{m}q " + M, "{m}l " + M, "{m}w " + M, "{m}b " + M,
    "{m} %r9, %r10", "{m} %r9d, %r10d", "{m} %r9w, %r10w", "{m} %r9b, %r10b",
    "{m} %rcx, %rax", "{m} %ecx, %eax", "{m} %cx, %ax", "{m} %cl, %al",
    "{m} " + M + ", %r10", "{m} " + M + ", %r10d", "{m} " + M + ", %r10w", "{m} " + M + ", %r10b",
    "{m} %r10, " + M, "{m} %r10d, " + M, "{m} %r10w, " + M, "{m} %r10b, " + M,
    "{m} $5, %r10", "{m} $0x12345, %r10", "{m} $5, %r10d", "{m} $0x12345, %r10d", "{m} $5, %r10w",
    "{m} $0x1234, %r10w", "{m} $5, %r10b", "{m} $5, %al", "{m} $0x12345, %eax",
    "{m}q $5, " + M, "{m}l $0x12345, " + M, "{m}w $5, " + M, "{m}b $5, " + M,
    "{m} %cl, %r10", "{m} %cl, %r10d", "{m} %cl, %r10w", "{m} %cl, %r10b",
    "{m} $3, %r9, %r10", "{m} $3, %r9d, %r10d", "{m} $0x1234, " + M + ", %r10",
    "{m} %r9, %r11, %r10", "{m} %r9d, %r11d, %r10d", "{m} %r9, " + M + ", %r10", "{m} " + M + ", %r9, %r10",
]
VEC = [
    "{m} %xmm11, %xmm9, %xmm10", "{m} %xmm3, %xmm2, %xmm1", "{m} " + M + ", %xmm9, %xmm10", "{m} " + LM + ", %xmm2, %xmm1",
    "{m} %ymm11, %ymm9, %ymm10", "{m} %ymm3, %ymm2, %ymm1", "{m} " + M + ", %ymm9, %ymm10",
    "{m} %xmm9, %xmm10", "{m} %xmm2, %xmm1", "{m} " + M + ", %xmm10", "{m} " + LM + ", %xmm1",
    "{m} %xmm10, " + M, "{m} %xmm1, " + LM, "{m} %ymm9, %ymm10", "{m} %ymm2, %ymm1",
    "{m} " + M + ", %ymm10", "{m} %ymm10, " + M, "{m} %xmm9, %ymm10", "{m} %xmm2, %ymm1",
    "{m} $3, %xmm11, %xmm9, %xmm10", "{m} $3, %xmm3, %xmm2, %xmm1", "{m} $3, " + M + ", %xmm9, %xmm10",
    "{m} $3, %xmm9, %xmm10", "{m} $3, %xmm2, %xmm1", "{m} $3, " + M + ", %xmm10",
    "{m} $3, %ymm11, %ymm9, %ymm10", "{m} $3, %ymm9, %ymm10",
    "{m} $1, %ymm9, %xmm10", "{m} $1, %ymm9, " + M, "{m} $1, %xmm11, %ymm9, %ymm10", "{m} $1, " + M + ", %ymm9, %ymm10",
    "{m} %r10, %xmm9", "{m} %xmm9, %r10", "{m} %r10d, %xmm9", "{m} %xmm9, %r10d", "{m} %rax, %xmm1", "{m} %xmm1, %rax",
    "{m} %eax, %xmm1", "{m} %xmm1, %eax",
    "{m} " + M + ", %xmm9", "{m} %xmm9, " + M,
    "{m} $1, %r10, %xmm9, %xmm10", "{m} $1, %r10d, %xmm9, %xmm10", "{m} $1, %eax, %xmm2, %xmm1", "{m} $1, %rax, %xmm2, %xmm1",
    "{m} $1, " + M + ", %xmm9, %xmm10",
    "{m} $1, %xmm9, %r10", "{m} $1, %xmm9, %r10d", "{m} $1, %xmm1, %eax", "{m} $1, %xmm1, %rax", "{m} $1, %xmm9, " + M,
    "{m}q %r10, %xmm9, %xmm10", "{m}l %r10d, %xmm9, %xmm10", "{m}q " + M + ", %xmm9, %xmm10", "{m}l " + M + ", %xmm9, %xmm10",
    "{m}q %rax, %xmm2, %xmm1", "{m}l %eax, %xmm2, %xmm1",
    "{m} " + M + ", %r10", "{m} " + M + ", %r10d",
    "{m} %xmm12, %xmm11, %xmm9, %xmm10", "{m} %xmm4, %xmm3, %xmm2, %xmm1", "{m} %xmm12, " + M + ", %xmm9, %xmm10",
    "{m} %ymm12, %ymm11, %ymm9, %ymm10",
    "{m} " + M, "{m}l " + M,
]
SPECIAL = {
    "movzx": ["movzbl %r9b, %r10d", "movzwl %r9w, %r10d", "movzbq %r9b, %r10", "movzwq %r9w, %r10",
              "movzbl " + M + ", %r10d", "movzwl " + M + ", %r10d", "movzbl %al, %eax", "movzwl %ax, %eax"],
    "movsx": ["movsbl %r9b, %r10d", "movswl %r9w, %r10d", "movsbq %r9b, %r10", "movswq %r9w, %r10",
              "movsbq " + M + ", %r10", "movswq " + M + ", %r10", "movsbw %r9b, %r10w"],
    "movsxd": ["movslq %r9d, %r10", "movslq " + M + ", %r10", "movslq %eax, %rax"],
    "bswap": ["bswap %r10", "bswap %r10d", "bswap %eax", "bswap %rax"],
    "movq": ["movq %r10, %xmm9", "movq %xmm9, %r10", "movq %xmm9, %xmm10", "movq " + M + ", %xmm9", "movq %xmm9, " + M],
    "mov": ["movabsq $0x123456789abc, %r10", "movabsq $0x123456789abc, %rax"],
    "vpextrb": ["vpextrb $1, %xmm9, %r10d", "vpextrb $1, %xmm9, " + M],
    "vpextrw": ["vpextrw $1, %xmm9, %r10d", "vpextrw $1, %xmm9, " + M],
    "vpinsrb": ["vpinsrb $1, %r10d, %xmm9, %xmm10", "vpinsrb $1, " + M + ", %xmm9, %xmm10"],
    "vpinsrw": ["vpinsrw $1, %r10d, %xmm9, %xmm10", "vpinsrw $1, " + M + ", %xmm9, %xmm10"],
    "vldmxcsr": ["vldmxcsr " + M],
    "clflush": ["clflush " + M],
    "prefetchw": ["prefetchw " + M],
    "prefetcht0": ["prefetcht0 " + M],
}


def mnemonics(xenia_root: str) -> list[str]:
    names: set[str] = set()
    backend = os.path.join(xenia_root, "src/xenia/cpu/backend/x64")
    for path in glob.glob(os.path.join(backend, "*.cc")) + glob.glob(os.path.join(backend, "*.h")):
        with open(path, encoding="utf-8", errors="replace") as source:
            names.update(re.findall(r"\be\.([a-z][a-z0-9_]*)\(", source.read()))
    return sorted(names)


def assemble(lines, workdir: str, tag: str):
    src = os.path.join(workdir, f"corpus_{tag}.s")
    obj = os.path.join(workdir, f"corpus_{tag}.o")
    with open(src, "w") as out:
        out.write(".text\n")
        for index, (_, line) in lines:
            out.write(f"x{index}:\n{line}\n")
    proc = subprocess.run(["clang", "-target", "x86_64-apple-macos", "-c", src, "-o", obj],
                          capture_output=True, text=True)
    return obj, proc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xenia-root", default=os.environ.get("XENIA_ROOT", ""))
    parser.add_argument("--objdump", default="llvm-objdump")
    args = parser.parse_args()
    if not args.xenia_root:
        print("gen_xenia_jit_corpus: pass --xenia-root or set XENIA_ROOT", file=sys.stderr)
        return 2

    lines = []
    for raw in mnemonics(args.xenia_root):
        if raw in SKIP or raw in GATED:
            continue
        mnemonic = RENAME.get(raw, raw)
        if raw in JCC:
            lines.append((raw, f"{mnemonic} .+0x40"))
            if raw != "jrcxz":
                lines.append((raw, f"{mnemonic} .+0x4000"))
            continue
        for template in SPECIAL.get(raw, []):
            lines.append((raw, template))
        base = GPR if not mnemonic.startswith("v") else []
        vector = VEC if (mnemonic.startswith("v") or mnemonic in ("pxor", "movq")) else []
        for template in base + vector:
            lines.append((raw, template.format(m=mnemonic)))

    indexed = list(enumerate(lines))
    rejected: set[int] = set()
    with tempfile.TemporaryDirectory() as workdir:
        good = list(indexed)
        for attempt in range(16):
            obj, proc = assemble(good, workdir, str(attempt))
            if proc.returncode == 0:
                break
            removed = 0
            for match in re.finditer(r":(\d+):\d+: error", proc.stderr):
                line_no = int(match.group(1))
                if line_no < 2:
                    continue
                position = (line_no - 3) // 2 if line_no % 2 == 1 else (line_no - 2) // 2
                if position < len(good):
                    rejected.add(good[position][0])
                    removed += 1
            if removed == 0:
                print(proc.stderr[:4000], file=sys.stderr)
                return 1
            good = [(i, e) for i, e in indexed if i not in rejected]
        else:
            print("gen_xenia_jit_corpus: the assembler never accepted the remaining lines", file=sys.stderr)
            return 1
        dump = subprocess.run([args.objdump, "-d", obj], capture_output=True, text=True, check=True).stdout

    by_label: dict[int, list[str]] = {}
    current = None
    for row in dump.splitlines():
        header = re.match(r"^[0-9a-f]+ <x(\d+)>:", row)
        if header:
            current = int(header.group(1))
            by_label[current] = []
            continue
        code = re.match(r"^\s*[0-9a-f]+:\s+((?:[0-9a-f]{2}(?:[ \t]|$))+)", row)
        if code and current is not None:
            by_label[current].append(" ".join(code.group(1).split()))

    source = dict(indexed)
    seen: set[str] = set()
    out_lines = []
    for index, rows in sorted(by_label.items()):
        hexbytes = " ".join(rows)
        mnemonic, line = source[index]
        first = hexbytes.split()[0] if hexbytes else ""
        # EVEX (62) and XOP (8F) encodings, and 256-bit integer forms, need
        # extensions the profile does not advertise.
        if not hexbytes or hexbytes in seen or first in ("62", "8f"):
            continue
        if mnemonic.startswith("vp") and "%ymm" in line:
            continue
        seen.add(hexbytes)
        out_lines.append(f"{hexbytes}|{mnemonic}|{line}\n")
    with open(OUT, "w") as out:
        out.writelines(out_lines)
    print(f"gen_xenia_jit_corpus: {len(out_lines)} encodings from {len({l.split('|')[1] for l in out_lines})} mnemonics -> {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
