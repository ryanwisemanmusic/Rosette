#!/usr/bin/env python3
"""Every distinct instruction form in xenia_canary.exe's own code.

The Xenia JIT corpus (gen_guest_jit_corpus.py) covers what Xenia's code
generator emits. It does not cover the executable itself, and the 2026-09-14
run died there: `vmovntps %ymm0, mem` in xe::memory::vastcpy_impl_avx, on the
GPU command thread, the first time a draw uploaded shared memory.

This linearly disassembles the PE's executable sections and keeps one exemplar
per (mnemonic, operand shape, encoding family). The shape keeps what changes
how Rosette decodes a form - register class, whether a register needs a REX or
VEX extension bit, memory base/index/RIP and displacement width, immediate
presence - and throws away the rest, so millions of instructions reduce to a
list a test can step through.

Output lines are `hex|mnemonic shape|family|occurrences|symbol+offset`; the
process.zig test "every instruction form in xenia_canary.exe decodes to a real
operation" reads them. Regenerate after a Xenia rebuild:

    tools/gen_guest_image_corpus.py --exe <xenia_canary.exe> \
        --output lib/processor/ELF_processor/guest_image_corpus.txt
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

# llvm-objdump separates the byte column from the mnemonic with a tab, not a
# space, when an instruction is long enough to fill the column; the last byte
# is then followed by the tab.
LINE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{2}(?: |\t|$))+)\s*(\S+)(?:\s+(.*))?$")
SYMBOL = re.compile(r"^([0-9a-f]+) <(.*)>:$")

REG64 = set("rax rbx rcx rdx rsi rdi rsp rbp r8 r9 r10 r11 r12 r13 r14 r15 rip".split())
REG32 = set("eax ebx ecx edx esi edi esp ebp r8d r9d r10d r11d r12d r13d r14d r15d eip".split())
REG16 = set("ax bx cx dx si di sp bp r8w r9w r10w r11w r12w r13w r14w r15w".split())
REG8 = set("al bl cl dl sil dil spl bpl ah bh ch dh r8b r9b r10b r11b r12b r13b r14b r15b".split())


def register_class(name):
    name = name.lower()
    m = re.match(r"^(x|y|z)mm(\d+)$", name)
    if m:
        return f"{m.group(1)}mm" + ("+" if int(m.group(2)) >= 8 else "")
    if re.match(r"^k\d$", name):
        return "k"
    if name.startswith("st"):
        return "st"
    if name in ("cs", "ds", "es", "fs", "gs", "ss"):
        return "seg"
    extended = bool(re.match(r"^r(8|9|1[0-5])", name))
    suffix = "+" if extended else ""
    if name in REG64:
        return "r64" + suffix
    if name in REG32:
        return "r32" + suffix
    if name in REG16:
        return "r16" + suffix
    if name in REG8:
        return "r8" + suffix
    if name.startswith(("cr", "dr")):
        return name[:2]
    return "reg"


def memory_shape(text):
    # disp(base,index,scale) with an optional segment prefix.
    segment = ""
    if re.match(r"^%[a-z]s:", text):
        segment = text[1:3] + ":"
        text = text[4:]
    m = re.match(r"^(-?(?:0x)?[0-9a-f]*)\((%?[a-z0-9]*)?(?:,(%?[a-z0-9]*))?(?:,(\d))?\)", text)
    if not m:
        return segment + "abs"
    disp, base, index, _scale = m.groups()
    parts = []
    if base:
        base = base.lstrip("%")
        parts.append("rip" if base == "rip" else "b" + ("+" if re.match(r"^r(8|9|1[0-5])", base) else ""))
    if index:
        index = index.lstrip("%")
        parts.append("i" + ("+" if re.match(r"^r(8|9|1[0-5])", index) else ""))
    if disp:
        value = int(disp, 16) if "0x" in disp else int(disp or "0")
        if base != "rip":
            parts.append("d8" if -128 <= value <= 127 else "d32")
    return segment + "m[" + ",".join(parts) + "]"


def operand_shape(operands):
    if not operands:
        return ""
    operands = operands.split("#")[0].strip()
    operands = re.sub(r"<[^>]*>", "", operands).strip()
    shapes = []
    depth = 0
    token = ""
    for char in operands:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        if char == "," and depth == 0:
            shapes.append(token.strip())
            token = ""
        else:
            token += char
    if token.strip():
        shapes.append(token.strip())
    out = []
    for operand in shapes:
        mask = ""
        m = re.search(r"\{%(k\d)\}", operand)
        if m:
            mask = "{k}"
            operand = operand.replace(m.group(0), "")
        operand = operand.strip()
        if operand.startswith("$"):
            out.append("imm")
        elif operand.startswith("*"):
            inner = operand[1:]
            out.append("*" + (register_class(inner[1:]) if inner.startswith("%") else memory_shape(inner)))
        elif operand.startswith("%") and "(" not in operand and ":" not in operand:
            out.append(register_class(operand[1:]) + mask)
        elif re.match(r"^(0x)?[0-9a-f]+$", operand):
            out.append("rel")
        else:
            out.append(memory_shape(operand) + mask)
    return ",".join(out)


def family(raw):
    index = 0
    legacy = []
    while index < len(raw) and raw[index] in (0x66, 0x67, 0xF2, 0xF3, 0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65, 0x9B):
        legacy.append(f"{raw[index]:02x}")
        index += 1
    rex_w = False
    if index < len(raw) and 0x40 <= raw[index] <= 0x4F:
        rex_w = bool(raw[index] & 8)
        index += 1
    if index < len(raw) and raw[index] == 0xC5 and index + 1 < len(raw):
        vex = raw[index + 1]
        return f"vex2.L{(vex >> 2) & 1}.p{vex & 3}"
    if index < len(raw) and raw[index] in (0xC4, 0x8F) and index + 2 < len(raw):
        b1, b2 = raw[index + 1], raw[index + 2]
        kind = "vex3" if raw[index] == 0xC4 else "xop"
        return f"{kind}.m{b1 & 0x1F}.W{(b2 >> 7) & 1}.L{(b2 >> 2) & 1}.p{b2 & 3}"
    if index < len(raw) and raw[index] == 0x62 and index + 3 < len(raw):
        p0, p1, p2 = raw[index + 1], raw[index + 2], raw[index + 3]
        return f"evex.m{p0 & 7}.W{(p1 >> 7) & 1}.L{(p2 >> 5) & 3}.p{p1 & 3}"
    return "legacy" + ("." + "".join(legacy) if legacy else "") + (".W" if rex_w else "")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True)
    parser.add_argument("--objdump", default=os.environ.get("LLVM_OBJDUMP") or shutil.which("llvm-objdump") or "llvm-objdump")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    process = subprocess.Popen(
        [args.objdump, "-d", args.exe],
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1 << 20,
    )
    seen = {}
    symbol = "?"
    symbol_start = 0
    total = 0
    for line in process.stdout:
        header = SYMBOL.match(line)
        if header:
            symbol_start = int(header.group(1), 16)
            symbol = header.group(2)
            continue
        m = LINE.match(line)
        if not m:
            continue
        address = int(m.group(1), 16)
        raw = bytes(int(b, 16) for b in m.group(2).split())
        mnemonic = m.group(3)
        if mnemonic in ("int3", "(bad)", "<unknown>", "nop") or mnemonic.startswith("("):
            continue
        total += 1
        key = (mnemonic, operand_shape(m.group(4) or ""), family(raw))
        if key in seen:
            seen[key][3] += 1
            continue
        where = f"{symbol[:90]}+0x{address - symbol_start:x}"
        seen[key] = [raw.hex(" "), where, address, 1]
    process.wait()
    with open(args.output, "w") as out:
        for (mnemonic, shape, fam), (hexbytes, where, _address, count) in sorted(seen.items(), key=lambda item: item[1][2]):
            out.write(f"{hexbytes}|{mnemonic} {shape}|{fam}|{count}|{where}\n")
    print(f"instructions={total} forms={len(seen)}", file=sys.stderr)


if __name__ == "__main__":
    main()
