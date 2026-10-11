#!/bin/bash
# Regenerates lib/processor/ELF_processor/xenia_jit_sse_oracle.{txt,bin}: the
# native SSE results `zig build sse-oracle-check` compares Rosette with.
#
# The VEX.128 register forms of Xenia's JIT corpus and of xenia_canary.exe's
# own code become equivalent legacy SSE snippets (gen_sse_oracle.py), which
# run under Apple Rosetta 2. Rosetta 2 implements SSE through SSE4.2 but no
# VEX encodings, hence the translation. The Rosette shell shim reroutes
# x86-64 Mach-Os to Rosette itself, so the run uses a clean environment.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
data="$root/lib/processor/ELF_processor"
llvm_mc="${LLVM_MC:-$(command -v llvm-mc || echo /opt/homebrew/opt/llvm@19/bin/llvm-mc)}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 - "$data" "$llvm_mc" "$work" <<'PY'
import subprocess, sys
data, llvm_mc, work = sys.argv[1:4]
jit = open(data + '/xenia_jit_corpus.txt').read()
known = set(line.split('|')[0] for line in jit.splitlines())
forms = []
for line in open(data + '/xenia_image_corpus.txt'):
    parts = line.split('|')
    if len(parts) < 2: continue
    hexs, shape = parts[0], parts[1]
    raw = bytes(int(x, 16) for x in hexs.split())
    if raw[0] not in (0xC4, 0xC5) or 'm[' in shape or 'ymm' in shape or hexs in known: continue
    forms.append(hexs)
forms = sorted(set(forms))
source = '\n'.join('0x' + ' 0x'.join(h.split()) for h in forms) + '\n'
text = subprocess.run([llvm_mc, '--disassemble', '-triple=x86_64'], input=source, capture_output=True, text=True, check=True).stdout
insns = [x.strip() for x in text.splitlines() if x.strip() and not x.strip().startswith('.')]
assert len(insns) == len(forms)
with open(work + '/corpus.txt', 'w') as out:
    out.write(jit if jit.endswith('\n') else jit + '\n')
    for hexs, insn in zip(forms, insns):
        insn = ' '.join(insn.split('#')[0].split())
        mnemonic = insn.split(' ')[0]
        if mnemonic.startswith('v') and '%xmm' in insn:
            out.write('%s|%s|%s\n' % (hexs, mnemonic, insn))
PY

python3 "$here/gen_sse_oracle.py" "$work/corpus.txt" "$work"
cp "$here/driver.c" "$work/driver.c"
clang -arch x86_64 -c "$work/oracle.s" -o "$work/oracle.o"
clang -arch x86_64 -O1 -ffp-contract=off -msse4.2 -mno-avx "$work/driver.c" "$work/oracle.o" -o "$work/oracle"
env -i PATH=/usr/bin:/bin HOME="$HOME" /usr/bin/arch -x86_64 "$work/oracle" "$work/results.bin"

python3 - "$work" "$data" <<'PY'
import sys
work, data = sys.argv[1:3]
forms = [line.rstrip('\n').split('|') for line in open(work + '/forms.txt')]
raw = open(work + '/results.bin', 'rb').read()
inputs = 8
assert len(raw) == len(forms) * inputs * 392
packed = bytearray()
for index, form in enumerate(forms):
    kind = form[3]
    for k in range(inputs):
        record = raw[(index * inputs + k) * 392:(index * inputs + k + 1) * 392]
        if kind.startswith('xmm:'):
            scratch = int(kind.split(':')[2]); result = record[scratch * 16:scratch * 16 + 16]
        elif kind.startswith('gpr:'):
            number = int(kind.split(':')[1]); result = record[256 + number * 8:256 + number * 8 + 8] + bytes(8)
        else:
            result = bytes(16)
        packed += result + record[384:392]
open(data + '/xenia_jit_sse_oracle.bin', 'wb').write(packed)
open(data + '/xenia_jit_sse_oracle.txt', 'w').write(''.join('|'.join(form) + '\n' for form in forms))
print('%d forms, %d bytes' % (len(forms), len(packed)))
PY
