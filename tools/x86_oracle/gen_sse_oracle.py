#!/usr/bin/env python3
"""Builds a native SSE oracle for the VEX.128 register forms Xenia's JIT emits.

Each VEX form becomes an equivalent legacy SSE snippet (operating on a scratch
register where VEX has a separate first source). The snippets are assembled for
x86-64 and run under Apple Rosetta 2, which implements SSE through SSE4.2
natively, over inputs both sides derive from splitmix64. Usage:
  gen_oracle.py CORPUS OUTDIR
writes OUTDIR/oracle.s, OUTDIR/forms.txt and OUTDIR/forms.h.
"""
import os, re, sys

corpus, outdir = sys.argv[1], sys.argv[2]
GPR64 = ['rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi','r8','r9','r10','r11','r12','r13','r14','r15']
def gpr_number(name):
    n = name.lstrip('%')
    table = {}
    for i, r in enumerate(GPR64):
        table[r] = i
    for i, r in enumerate(['eax','ecx','edx','ebx','esp','ebp','esi','edi']): table[r] = i
    for i in range(8, 16):
        table['r%dd' % i] = i; table['r%dw' % i] = i; table['r%db' % i] = i
    for i, r in enumerate(['ax','cx','dx','bx','sp','bp','si','di']): table[r] = i
    for i, r in enumerate(['al','cl','dl','bl','spl','bpl','sil','dil']): table[r] = i
    return table.get(n)

def xmm_number(op):
    m = re.fullmatch(r'%xmm(\d+)', op)
    return int(m.group(1)) if m else None

def split_ops(text):
    ops, depth, cur = [], 0, ''
    for ch in text:
        if ch in '([': depth += 1
        if ch in ')]': depth -= 1
        if ch == ',' and depth == 0:
            ops.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip(): ops.append(cur.strip())
    return ops

IN_PLACE_SHIFTS = {'psllw','pslld','psllq','psrlw','psrld','psrlq','psraw','psrad','pslldq','psrldq'}
NO_LEGACY = {'vbroadcastss','vpermilps','vpermilpd','vperm2f128','vinsertf128','vextractf128','vtestps','vtestpd','vzeroupper','vmaskmovps'}
FLAG_ONLY = {'ptest','ucomiss','ucomisd','comiss','comisd'}

forms = []
for line in open(corpus):
    parts = line.rstrip('\n').split('|')
    if len(parts) < 3: continue
    hexs, mnem, text = parts[0], parts[1], parts[2]
    raw = bytes(int(x, 16) for x in hexs.split())
    if raw[0] not in (0xC4, 0xC5) or '(' in text or '%ymm' in text: continue
    if mnem in NO_LEGACY: continue
    sp = text.find(' ')
    if sp < 0: continue
    full_mnem = text[:sp]
    ops = split_ops(text[sp + 1:])
    imms = [o for o in ops if o.startswith('$')]
    regs = [o for o in ops if not o.startswith('$')]
    legacy = full_mnem[1:]
    lane = 'pd' if re.search(r'(pd|sd)$', legacy) and not legacy.startswith('p') else ('ps' if re.search(r'(ps|ss)$', legacy) and not legacy.startswith('p') else 'int')
    if legacy in ('cvtsd2si', 'cvttsd2si', 'cvtsd2ss', 'sqrtsd', 'roundsd', 'ucomisd', 'comisd', 'maxsd', 'minsd', 'divsd', 'mulsd', 'subsd', 'addsd', 'cvtsi2sd'): lane = 'pd'
    if legacy in ('cvtps2pd',): lane = 'ps'
    imm = (imms[0] + ', ') if imms else ''
    vex_xmm = [xmm_number(r) for r in regs]
    used = set(n for n in vex_xmm if n is not None)
    scratch = [n for n in range(1, 16) if n not in used]
    T, T2 = scratch[0], scratch[1]
    body = []
    result = None  # ('xmm', vex_dst, oracle_reg) | ('gpr', n) | ('flags',)
    if legacy in FLAG_ONLY:
        body.append('%s %s%s' % (legacy, imm, ', '.join(regs)))
        result = ('flags',)
    elif len(regs) == 4 and legacy in ('blendvps', 'pblendvb', 'blendvpd'):
        mask, src2, src1, dst = regs
        body.append('movaps %s, %%xmm%d' % (src2, T2) if xmm_number(src2) is not None else None)
        body.append('movaps %s, %%xmm%d' % (src1, T))
        body.append('movaps %s, %%xmm0' % mask)
        body.append('%s %%xmm0, %%xmm%d, %%xmm%d' % (legacy, T2, T))
        if 0 in (T, T2): continue
        result = ('xmm', xmm_number(dst), T)
    elif len(regs) == 3 and re.fullmatch(r'cmp(ge|gt)(ps|pd|ss|sd)', legacy):
        # VEX-only predicates: src1 >= src2 is src2 <= src1 (both false
        # when unordered), so the legacy form runs on a copy of src2.
        src2, src1, dst = regs
        swapped = legacy.replace('cmpge', 'cmple').replace('cmpgt', 'cmplt')
        body.append('movaps %s, %%xmm%d' % (src2, T))
        body.append('%s %s, %%xmm%d' % (swapped, src1, T))
        result = ('xmm', xmm_number(dst), T)
    elif len(regs) == 3 and legacy.startswith('cmp') and imms and int(imms[0][1:], 0) >= 8:
        continue
    elif len(regs) == 3:
        src2, src1, dst = regs
        if xmm_number(dst) is None or xmm_number(src1) is None: continue
        body.append('movaps %s, %%xmm%d' % (src1, T))
        body.append('%s %s%s, %%xmm%d' % (legacy, imm, src2, T))
        result = ('xmm', xmm_number(dst), T)
    elif len(regs) == 2:
        src, dst = regs
        if legacy in IN_PLACE_SHIFTS:
            body.append('movaps %s, %%xmm%d' % (src, T))
            body.append('%s %s%%xmm%d' % (legacy, imm, T))
            result = ('xmm', xmm_number(dst), T)
        elif xmm_number(dst) is not None:
            body.append('%s %s%s, %s' % (legacy, imm, src, dst))
            result = ('xmm', xmm_number(dst), xmm_number(dst))
        elif gpr_number(dst) is not None:
            body.append('%s %s%s, %s' % (legacy, imm, src, dst))
            result = ('gpr', gpr_number(dst))
        else:
            continue
    else:
        continue
    body = [b for b in body if b]
    if result is None: continue
    forms.append((hexs, text, legacy, lane, result, body))

with open(os.path.join(outdir, 'oracle.s'), 'w') as f:
    f.write('.text\n')
    for i, (_, _, _, _, _, body) in enumerate(forms):
        f.write('.globl _form_%d\n_form_%d:\n' % (i, i))
        f.write('  push %rbx\n  push %rbp\n  push %r12\n  push %r13\n  push %r14\n  push %r15\n')
        f.write('  movq %rsi, _out_ptr(%rip)\n')
        for r in range(16):
            f.write('  movups %d(%%rdi), %%xmm%d\n' % (r * 16, r))
        for r, name in enumerate(GPR64):
            if name in ('rsp', 'rdi'): continue
            f.write('  movq %d(%%rdi), %%%s\n' % (256 + r * 8, name))
        f.write('  movq %d(%%rdi), %%rdi\n' % (256 + 7 * 8))
        for b in body:
            f.write('  %s\n' % b)
        f.write('  pushfq\n  movq %rax, _saved_rax(%rip)\n  movq _out_ptr(%rip), %rax\n')
        for r in range(16):
            f.write('  movups %%xmm%d, %d(%%rax)\n' % (r, r * 16))
        for r, name in enumerate(GPR64):
            if name in ('rax', 'rsp'): continue
            f.write('  movq %%%s, %d(%%rax)\n' % (name, 256 + r * 8))
        f.write('  movq _saved_rax(%rip), %rbx\n  movq %rbx, 256(%rax)\n')
        f.write('  popq %rbx\n  movq %rbx, 384(%rax)\n')
        f.write('  pop %r15\n  pop %r14\n  pop %r13\n  pop %r12\n  pop %rbp\n  pop %rbx\n  ret\n')
    f.write('.data\n.globl _out_ptr\n_out_ptr: .quad 0\n_saved_rax: .quad 0\n')

with open(os.path.join(outdir, 'forms.h'), 'w') as f:
    f.write('#define FORM_COUNT %d\n' % len(forms))
    for i in range(len(forms)): f.write('void form_%d(const void *in, void *out);\n' % i)
    f.write('static void (*const forms[])(const void *, void *) = {%s};\n' % ', '.join('form_%d' % i for i in range(len(forms))))
    f.write('static const int form_lane[] = {%s};\n' % ', '.join({'ps': '0', 'pd': '1', 'int': '2'}[x[3]] for x in forms))

with open(os.path.join(outdir, 'forms.txt'), 'w') as f:
    for hexs, text, legacy, lane, result, body in forms:
        if result[0] == 'xmm': rs = 'xmm:%d:%d' % (result[1], result[2])
        elif result[0] == 'gpr': rs = 'gpr:%d' % result[1]
        else: rs = 'flags'
        f.write('%s|%s|%s|%s|%s\n' % (hexs, text, lane, rs, '; '.join(body)))
print(len(forms), 'forms')
