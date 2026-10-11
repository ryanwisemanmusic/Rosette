#!/usr/bin/env python3
"""Generate Rosette's PowerPC ISA tables and their ARM64/NEON lowering mirrors.

Reads tools/ppc_isa_spec.txt (one row per Xenon PowerPC instruction) and writes,
in the exact schema the x86 tables already use:

    ISA/ppc/<GROUP>/<MNEMONIC>.inc            PPC source contract
    ISA/ppc/Zig/<GROUP>/<MNEMONIC>.zig        embed bridge
    ISA/ppc/Zig/root.zig                      registry + ABI validation
    ISA/NEON/PPC/<GROUP>/<MNEMONIC>.inc       ARM64/NEON lowering mirror
    ISA/NEON/PPC/Zig/<GROUP>/<MNEMONIC>.zig   embed bridge
    ISA/NEON/PPC/Zig/root.zig                 mirror registry + mirror validation

The PPC mirrors live under ISA/NEON/PPC/ so the ARM64 folder keeps x86-sourced
lowerings and PPC-sourced lowerings distinguishable, and so the existing
x86-count == NEON-count invariant stays exactly as it was.

Usage:  python3 tools/gen_ppc_isa.py
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "tools", "ppc_isa_spec.txt")
PPC_DIR = os.path.join(ROOT, "ISA", "ppc")
NEON_DIR = os.path.join(ROOT, "ISA", "NEON", "PPC")

# --------------------------------------------------------------------------
# Spec loading
# --------------------------------------------------------------------------


class Insn:
    __slots__ = ("pattern", "mnem", "form", "group", "kind", "fmt")

    def __init__(self, pattern, mnem, form, group, kind, fmt):
        self.pattern = pattern
        self.mnem = mnem
        self.form = form
        self.group = group
        self.kind = kind
        self.fmt = fmt

    @property
    def primary(self):
        return (int(self.pattern, 16) >> 26) & 0x3F

    @property
    def has_rc(self):
        return "[Rc]" in self.fmt

    @property
    def has_oe(self):
        return "[OE]" in self.fmt

    @property
    def has_lk(self):
        return "[LK]" in self.fmt

    @property
    def base_mnem(self):
        """Assembler mnemonic without the optional-suffix markers."""
        head = self.fmt.split(" ", 1)[0] if self.fmt else self.mnem
        head = re.sub(r"\[[A-Za-z0-9_]+\]", "", head)
        return head or self.mnem

    @property
    def operands(self):
        rhs = self.fmt.split(" ", 1)
        if len(rhs) < 2:
            return []
        return [f for f in re.findall(r"\[([A-Za-z0-9_]+)\]", rhs[1])]


def load_spec():
    out = []
    with open(SPEC, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) != 6:
                raise SystemExit(f"malformed spec row: {line}")
            out.append(Insn(*parts))
    return out


# --------------------------------------------------------------------------
# Group classification -> folder name (mirrors the x86 uppercase family dirs)
# --------------------------------------------------------------------------

EXPLICIT_GROUP = {
    "addcx": "ADD", "addex": "ADD", "addi": "ADD", "addic": "ADD",
    "addicx": "ADD", "addis": "ADD", "addmex": "ADD", "addx": "ADD",
    "addzex": "ADD",
    "subfcx": "SUB", "subfex": "SUB", "subfic": "SUB", "subfmex": "SUB",
    "subfx": "SUB", "subfzex": "SUB", "negx": "SUB",
    "mulhdux": "MUL", "mulhdx": "MUL", "mulhwux": "MUL", "mulhwx": "MUL",
    "mulldx": "MUL", "mulli": "MUL", "mullwx": "MUL",
    "divdux": "DIV", "divdx": "DIV", "divwux": "DIV", "divwx": "DIV",
    "andcx": "LOGICAL", "andisx": "LOGICAL", "andix": "LOGICAL",
    "andx": "LOGICAL", "eqvx": "LOGICAL", "nandx": "LOGICAL",
    "norx": "LOGICAL", "orcx": "LOGICAL", "ori": "LOGICAL",
    "oris": "LOGICAL", "orx": "LOGICAL", "xori": "LOGICAL",
    "xoris": "LOGICAL", "xorx": "LOGICAL",
    "cntlzdx": "COUNT", "cntlzwx": "COUNT", "popcntb": "COUNT",
    "extsbx": "EXTEND", "extshx": "EXTEND", "extswx": "EXTEND",
    "sldx": "SHIFT", "slwx": "SHIFT", "sradix": "SHIFT", "sradx": "SHIFT",
    "srawix": "SHIFT", "srawx": "SHIFT", "srdx": "SHIFT", "srwx": "SHIFT",
    "rldclx": "ROTATE", "rldcrx": "ROTATE", "rldicx": "ROTATE",
    "rldiclx": "ROTATE", "rldicrx": "ROTATE", "rldimix": "ROTATE",
    "rlwimix": "ROTATE", "rlwinmx": "ROTATE", "rlwnmx": "ROTATE",
    "cmp": "CMP", "cmpi": "CMP", "cmpl": "CMP", "cmpli": "CMP",
    "bcctrx": "BRANCH", "bclrx": "BRANCH", "bcx": "BRANCH", "bx": "BRANCH",
    "sc": "SYSTEM", "rfid": "SYSTEM", "mfmsr": "SYSTEM", "mtmsr": "SYSTEM",
    "mtmsrd": "SYSTEM", "mfsr": "SYSTEM", "mfsrin": "SYSTEM",
    "mtsr": "SYSTEM", "mtsrin": "SYSTEM", "slbia": "SYSTEM",
    "slbie": "SYSTEM", "tlbia": "SYSTEM", "tlbie": "SYSTEM",
    "tlbiel": "SYSTEM", "tlbsync": "SYSTEM", "eciwx": "SYSTEM",
    "ecowx": "SYSTEM",
    "mfspr": "SPR", "mftb": "SPR", "mtspr": "SPR",
    "mcrf": "CONDITION_REGISTER", "mcrxr": "CONDITION_REGISTER",
    "mfcr": "CONDITION_REGISTER", "mtcrf": "CONDITION_REGISTER",
    "crand": "CONDITION_REGISTER", "crandc": "CONDITION_REGISTER",
    "creqv": "CONDITION_REGISTER", "crnand": "CONDITION_REGISTER",
    "crnor": "CONDITION_REGISTER", "cror": "CONDITION_REGISTER",
    "crorc": "CONDITION_REGISTER", "crxor": "CONDITION_REGISTER",
    "td": "TRAP", "tdi": "TRAP", "tw": "TRAP", "twi": "TRAP",
    "eieio": "SYNC", "isync": "SYNC", "sync": "SYNC",
    "dcbf": "CACHE", "dcbi": "CACHE", "dcbst": "CACHE", "dcbt": "CACHE",
    "dcbtst": "CACHE", "dcbz": "CACHE", "dcbz128": "CACHE", "icbi": "CACHE",
    "ldarx": "ATOMIC", "lwarx": "ATOMIC", "stdcx": "ATOMIC",
    "stwcx": "ATOMIC",
    "ldbrx": "BYTE_REVERSE", "lhbrx": "BYTE_REVERSE",
    "lwbrx": "BYTE_REVERSE", "stdbrx": "BYTE_REVERSE",
    "sthbrx": "BYTE_REVERSE", "stwbrx": "BYTE_REVERSE",
    "lmw": "LOAD_MULTIPLE", "lswi": "LOAD_MULTIPLE", "lswx": "LOAD_MULTIPLE",
    "stmw": "STORE_MULTIPLE", "stswi": "STORE_MULTIPLE",
    "stswx": "STORE_MULTIPLE",
    "mcrfs": "FP_STATUS", "mffsx": "FP_STATUS", "mtfsb0x": "FP_STATUS",
    "mtfsb1x": "FP_STATUS", "mtfsfix": "FP_STATUS", "mtfsfx": "FP_STATUS",
    "fcmpo": "FP_COMPARE", "fcmpu": "FP_COMPARE",
    "fabsx": "FP_MOVE", "fmrx": "FP_MOVE", "fnabsx": "FP_MOVE",
    "fnegx": "FP_MOVE", "fselx": "FP_MOVE",
    "mfvscr": "VMX_STATUS", "mtvscr": "VMX_STATUS",
}

FP_CONVERT = {
    "fcfidx", "fctidx", "fctidzx", "fctiwx", "fctiwzx", "frspx",
}
FP_MULADD = {
    "fmaddsx", "fmaddx", "fmsubsx", "fmsubx", "fnmaddsx", "fnmaddx",
    "fnmsubsx", "fnmsubx",
}


def classify(insn: Insn) -> str:
    m = insn.mnem
    if m in EXPLICIT_GROUP:
        return EXPLICIT_GROUP[m]
    if m in FP_CONVERT:
        return "FP_CONVERT"
    if m in FP_MULADD:
        return "FP_MULTIPLY_ADD"
    if m.endswith("128"):
        return "VMX128"
    if m.startswith("v"):
        return vector_group(m)
    if m.startswith("lf"):
        return "FP_LOAD"
    if m.startswith("stf"):
        return "FP_STORE"
    if m.startswith("f"):
        return "FP_ARITH"
    if m.startswith("lv"):
        return "VMX_LOAD"
    if m.startswith("stv"):
        return "VMX_STORE"
    if m.startswith("st"):
        return "STORE_INDEXED" if insn.form == "X" else "STORE"
    if m.startswith("l"):
        return "LOAD_INDEXED" if insn.form == "X" else "LOAD"
    return "SYSTEM"


def vector_group(m: str) -> str:
    if m.startswith("vcmp"):
        return "VMX_COMPARE"
    if m.startswith("vpk") or m.startswith("vupk"):
        return "VMX_PACK"
    if m.startswith("vspltis") or m.startswith("vsplt"):
        return "VMX_SPLAT"
    if m.startswith("vperm") or m.startswith("vsel") or m.startswith("vsldoi") \
            or m.startswith("vmrg"):
        return "VMX_PERMUTE"
    if m.startswith("vand") or m in ("vor", "vnor", "vxor"):
        return "VMX_LOGICAL"
    if m.startswith("vrl") or m.startswith("vsl") or m.startswith("vsr"):
        return "VMX_SHIFT"
    if m.startswith("vct") or m.startswith("vcf") or m.startswith("vrfi"):
        return "VMX_CONVERT"
    if m in ("vrefp", "vrsqrtefp", "vexptefp", "vlogefp"):
        return "VMX_ESTIMATE"
    if m.startswith("vmsum") or m.startswith("vsum") or m.startswith("vmhadd") \
            or m.startswith("vmhradd") or m.startswith("vmladd") \
            or m.startswith("vmaddfp") or m.startswith("vnmsubfp"):
        return "VMX_MULTIPLY_ADD"
    return "VMX_ARITH"


# --------------------------------------------------------------------------
# Field / operand documentation
# --------------------------------------------------------------------------

FIELD_DOC = {
    "RD": ("GPR[RD]", "destination general-purpose register"),
    "RS": ("GPR[RS]", "source general-purpose register"),
    "RA": ("GPR[RA]", "first general-purpose source"),
    "RA0": ("GPR[RA] or 0", "first source; literal 0 when RA==0"),
    "RB": ("GPR[RB]", "second general-purpose source"),
    "SIMM": ("SIMM", "16-bit signed immediate"),
    "UIMM": ("UIMM", "16-bit unsigned immediate"),
    "DS": ("d", "signed displacement"),
    "SH": ("SH", "shift amount"),
    "MB": ("MB", "mask begin bit"),
    "ME": ("ME", "mask end bit"),
    "NB": ("NB", "byte count"),
    "BO": ("BO", "branch options"),
    "BI": ("BI", "condition-register bit index"),
    "BD": ("BD", "signed branch displacement"),
    "LI": ("LI", "signed branch displacement"),
    "AA": ("AA", "absolute-address flag"),
    "LK": ("LK", "link flag (writes LR)"),
    "OE": ("OE", "overflow-enable flag (writes XER.OV/SO)"),
    "Rc": ("Rc", "record flag (writes CR0 / CR1)"),
    "crfD": ("CR[crfD]", "destination condition-register field"),
    "crfS": ("CR[crfS]", "source condition-register field"),
    "crbD": ("CR[crbD]", "destination condition-register bit"),
    "crbA": ("CR[crbA]", "first condition-register bit source"),
    "crbB": ("CR[crbB]", "second condition-register bit source"),
    "CRM": ("CRM", "condition-register field mask"),
    "L": ("L", "operand-width select (0=32-bit, 1=64-bit)"),
    "TO": ("TO", "trap condition mask"),
    "SPR": ("SPR", "special-purpose register number"),
    "FM": ("FM", "FPSCR field mask"),
    "IMM": ("IMM", "immediate"),
    "FD": ("FPR[FD]", "destination floating-point register"),
    "FS": ("FPR[FS]", "source floating-point register"),
    "FA": ("FPR[FA]", "first floating-point source"),
    "FB": ("FPR[FB]", "second floating-point source"),
    "FC": ("FPR[FC]", "third floating-point source"),
    "FPSCRD": ("FPSCR[FPSCRD]", "destination FPSCR bit"),
    "CRFD": ("CR[CRFD]", "destination condition-register field"),
    "CRFS": ("CR[CRFS]", "source condition-register field"),
    "CRBD": ("CR[CRBD]", "destination condition-register bit"),
    "CRBA": ("CR[CRBA]", "first condition-register bit source"),
    "CRBB": ("CR[CRBB]", "second condition-register bit source"),
    "d": ("d", "signed displacement"),
    "ds": ("ds", "signed displacement, low two bits implied zero"),
    "ADDR": ("LI", "signed branch displacement"),
    "TBR": ("TBR", "time-base register number"),
    "LEV": ("LEV", "system-call level"),
    "type": ("type", "VMX128 pack/unpack type selector"),
    "pack": ("pack", "VMX128 pack selector"),
    "shift": ("shift", "VMX128 shift amount"),
    "z": ("z", "VMX128 lane selector"),
    "VD": ("VR[VD]", "destination vector register"),
    "VS": ("VR[VS]", "source vector register"),
    "VA": ("VR[VA]", "first vector source"),
    "VB": ("VR[VB]", "second vector source"),
    "VC": ("VR[VC]", "third vector source"),
    "SHB": ("SHB", "byte shift amount"),
    "VD128": ("VR128[VD128]", "destination VMX128 vector register"),
    "VS128": ("VR128[VS128]", "source VMX128 vector register"),
    "VA128": ("VR128[VA128]", "first VMX128 vector source"),
    "VB128": ("VR128[VB128]", "second VMX128 vector source"),
    "VC128": ("VR128[VC128]", "third VMX128 vector source"),
}


def operand_rows(insn: Insn):
    ops = insn.operands
    cells = []
    for i in range(4):
        if i < len(ops):
            name = ops[i]
            doc = FIELD_DOC.get(name, (name, "instruction field"))[0]
            cells.append(doc)
        else:
            cells.append("N/A")
    return cells


# --------------------------------------------------------------------------
# Semantics + ARM64 lowering
# --------------------------------------------------------------------------

# (operation, semantic, arm64 assembly, lowering kind)
SCALAR = {
    "addx": ("rD = rA + rB",
             "rD <- (rA) + (rB)",
             "add xD, xA, xB", "arm64_scalar"),
    "addcx": ("rD = rA + rB, XER.CA = carry",
              "rD <- (rA) + (rB)\nXER.CA <- carry_out(rA + rB)",
              "adds xD, xA, xB\ncset xCA, cs", "arm64_scalar"),
    "addex": ("rD = rA + rB + XER.CA",
              "rD <- (rA) + (rB) + XER.CA\nXER.CA <- carry_out",
              "cmp xzr, xCA, lsl #63\nadcs xD, xA, xB\ncset xCA, cs",
              "arm64_scalar"),
    "addi": ("rD = (rA|0) + SIMM",
             "rD <- (rA|0) + EXTS(SIMM)",
             "add xD, xA, #SIMM", "arm64_scalar"),
    "addic": ("rD = (rA) + SIMM, XER.CA = carry",
              "rD <- (rA) + EXTS(SIMM)\nXER.CA <- carry_out",
              "adds xD, xA, #SIMM\ncset xCA, cs", "arm64_scalar"),
    "addicx": ("rD = (rA) + SIMM, XER.CA = carry, CR0 updated",
               "rD <- (rA) + EXTS(SIMM)\nXER.CA <- carry_out\nCR0 <- cmp(rD, 0)",
               "adds xD, xA, #SIMM\ncset xCA, cs\nbl rosette_ppc_update_cr0",
               "arm64_scalar"),
    "addis": ("rD = (rA|0) + (SIMM << 16)",
              "rD <- (rA|0) + (EXTS(SIMM) || 0x0000)",
              "add xD, xA, #SIMM, lsl #16", "arm64_scalar"),
    "addmex": ("rD = rA + XER.CA - 1",
               "rD <- (rA) + XER.CA + 0xFFFFFFFFFFFFFFFF\nXER.CA <- carry_out",
               "cmp xzr, xCA, lsl #63\nadcs xD, xA, xM1\ncset xCA, cs",
               "arm64_scalar"),
    "addzex": ("rD = rA + XER.CA",
               "rD <- (rA) + XER.CA\nXER.CA <- carry_out",
               "cmp xzr, xCA, lsl #63\nadcs xD, xA, xzr\ncset xCA, cs",
               "arm64_scalar"),
    "subfx": ("rD = rB - rA",
              "rD <- ~(rA) + (rB) + 1",
              "sub xD, xB, xA", "arm64_scalar"),
    "subfcx": ("rD = rB - rA, XER.CA = carry",
               "rD <- ~(rA) + (rB) + 1\nXER.CA <- carry_out",
               "subs xD, xB, xA\ncset xCA, cs", "arm64_scalar"),
    "subfex": ("rD = ~rA + rB + XER.CA",
               "rD <- ~(rA) + (rB) + XER.CA\nXER.CA <- carry_out",
               "cmp xzr, xCA, lsl #63\nsbcs xD, xB, xA\ncset xCA, cs",
               "arm64_scalar"),
    "subfic": ("rD = SIMM - rA, XER.CA = carry",
               "rD <- ~(rA) + EXTS(SIMM) + 1\nXER.CA <- carry_out",
               "mov xT, #SIMM\nsubs xD, xT, xA\ncset xCA, cs", "arm64_scalar"),
    "subfmex": ("rD = ~rA + XER.CA - 1",
                "rD <- ~(rA) + XER.CA + 0xFFFFFFFFFFFFFFFF\nXER.CA <- carry_out",
                "cmp xzr, xCA, lsl #63\nsbcs xD, xM1, xA\ncset xCA, cs",
                "arm64_scalar"),
    "subfzex": ("rD = ~rA + XER.CA",
                "rD <- ~(rA) + XER.CA\nXER.CA <- carry_out",
                "cmp xzr, xCA, lsl #63\nsbcs xD, xzr, xA\ncset xCA, cs",
                "arm64_scalar"),
    "negx": ("rD = -rA",
             "rD <- ~(rA) + 1",
             "neg xD, xA", "arm64_scalar"),
    "mullwx": ("rD = (rA[32:63] * rB[32:63]) sign-extended",
               "rD <- EXTS((rA)[32:63] * (rB)[32:63])",
               "smull xD, wA, wB", "arm64_scalar"),
    "mulldx": ("rD = low 64 bits of rA * rB",
               "rD <- ((rA) * (rB))[64:127]",
               "mul xD, xA, xB", "arm64_scalar"),
    "mulhwx": ("rD = high 32 bits of signed rA * rB",
               "rD[32:63] <- ((rA)[32:63] *si (rB)[32:63])[0:31]",
               "smull xT, wA, wB\nasr xD, xT, #32", "arm64_scalar"),
    "mulhwux": ("rD = high 32 bits of unsigned rA * rB",
                "rD[32:63] <- ((rA)[32:63] *ui (rB)[32:63])[0:31]",
                "umull xT, wA, wB\nlsr xD, xT, #32", "arm64_scalar"),
    "mulhdx": ("rD = high 64 bits of signed rA * rB",
               "rD <- ((rA) *si (rB))[0:63]",
               "smulh xD, xA, xB", "arm64_scalar"),
    "mulhdux": ("rD = high 64 bits of unsigned rA * rB",
                "rD <- ((rA) *ui (rB))[0:63]",
                "umulh xD, xA, xB", "arm64_scalar"),
    "mulli": ("rD = rA * SIMM",
              "rD <- ((rA) * EXTS(SIMM))[64:127]",
              "mov xT, #SIMM\nmul xD, xA, xT", "arm64_scalar"),
    "divwx": ("rD = rA / rB (32-bit signed)",
              "rD[32:63] <- (rA)[32:63] /si (rB)[32:63]\n"
              "undefined when rB == 0 or (rA == 0x80000000 and rB == -1)",
              "sdiv wD, wA, wB", "arm64_scalar"),
    "divwux": ("rD = rA / rB (32-bit unsigned)",
               "rD[32:63] <- (rA)[32:63] /ui (rB)[32:63]\n"
               "undefined when rB == 0",
               "udiv wD, wA, wB", "arm64_scalar"),
    "divdx": ("rD = rA / rB (64-bit signed)",
              "rD <- (rA) /si (rB)\n"
              "undefined when rB == 0 or (rA == INT64_MIN and rB == -1)",
              "sdiv xD, xA, xB", "arm64_scalar"),
    "divdux": ("rD = rA / rB (64-bit unsigned)",
               "rD <- (rA) /ui (rB)\nundefined when rB == 0",
               "udiv xD, xA, xB", "arm64_scalar"),
    "andx": ("rA = rS & rB", "rA <- (rS) & (rB)",
             "and xA, xS, xB", "arm64_scalar"),
    "andcx": ("rA = rS & ~rB", "rA <- (rS) & ~(rB)",
              "bic xA, xS, xB", "arm64_scalar"),
    "andix": ("rA = rS & UIMM, CR0 updated",
              "rA <- (rS) & (0x0000 || UIMM)\nCR0 <- cmp(rA, 0)",
              "and xA, xS, #UIMM\nbl rosette_ppc_update_cr0", "arm64_scalar"),
    "andisx": ("rA = rS & (UIMM << 16), CR0 updated",
               "rA <- (rS) & (UIMM || 0x0000)\nCR0 <- cmp(rA, 0)",
               "and xA, xS, #UIMM_HI\nbl rosette_ppc_update_cr0",
               "arm64_scalar"),
    "orx": ("rA = rS | rB", "rA <- (rS) | (rB)",
            "orr xA, xS, xB", "arm64_scalar"),
    "orcx": ("rA = rS | ~rB", "rA <- (rS) | ~(rB)",
             "orn xA, xS, xB", "arm64_scalar"),
    "ori": ("rA = rS | UIMM", "rA <- (rS) | (0x0000 || UIMM)",
            "orr xA, xS, #UIMM", "arm64_scalar"),
    "oris": ("rA = rS | (UIMM << 16)", "rA <- (rS) | (UIMM || 0x0000)",
             "orr xA, xS, #UIMM_HI", "arm64_scalar"),
    "xorx": ("rA = rS ^ rB", "rA <- (rS) ^ (rB)",
             "eor xA, xS, xB", "arm64_scalar"),
    "xori": ("rA = rS ^ UIMM", "rA <- (rS) ^ (0x0000 || UIMM)",
             "eor xA, xS, #UIMM", "arm64_scalar"),
    "xoris": ("rA = rS ^ (UIMM << 16)", "rA <- (rS) ^ (UIMM || 0x0000)",
              "eor xA, xS, #UIMM_HI", "arm64_scalar"),
    "nandx": ("rA = ~(rS & rB)", "rA <- ~((rS) & (rB))",
              "and xT, xS, xB\nmvn xA, xT", "arm64_scalar"),
    "norx": ("rA = ~(rS | rB)", "rA <- ~((rS) | (rB))",
             "orr xT, xS, xB\nmvn xA, xT", "arm64_scalar"),
    "eqvx": ("rA = ~(rS ^ rB)", "rA <- ~((rS) ^ (rB))",
             "eon xA, xS, xB", "arm64_scalar"),
    "extsbx": ("rA = sign_extend8(rS)", "rA <- EXTS((rS)[56:63])",
               "sxtb xA, wS", "arm64_scalar"),
    "extshx": ("rA = sign_extend16(rS)", "rA <- EXTS((rS)[48:63])",
               "sxth xA, wS", "arm64_scalar"),
    "extswx": ("rA = sign_extend32(rS)", "rA <- EXTS((rS)[32:63])",
               "sxtw xA, wS", "arm64_scalar"),
    "cntlzwx": ("rA = count_leading_zeros32(rS)",
                "rA <- number of leading zero bits in (rS)[32:63], 0..32",
                "clz wA, wS", "arm64_scalar"),
    "cntlzdx": ("rA = count_leading_zeros64(rS)",
                "rA <- number of leading zero bits in (rS), 0..64",
                "clz xA, xS", "arm64_scalar"),
    "slwx": ("rA = rS << (rB & 63), 32-bit with >=32 clearing",
             "n <- (rB)[58:63]\nrA <- if n < 32 then EXTZ((rS)[32:63] << n) else 0",
             "and wT, wB, #63\nlsl xA, xS, xT\nand xA, xA, #0xffffffff",
             "arm64_scalar"),
    "srwx": ("rA = rS >> (rB & 63), 32-bit logical with >=32 clearing",
             "n <- (rB)[58:63]\nrA <- if n < 32 then EXTZ((rS)[32:63] >>ui n) else 0",
             "and wT, wB, #63\nlsr xA, xS, xT", "arm64_scalar"),
    "srawx": ("rA = arithmetic shift right 32-bit, XER.CA from lost ones",
              "n <- (rB)[58:63]\nrA <- EXTS((rS)[32:63] >>si min(n, 31))\n"
              "XER.CA <- (rS < 0) and any 1 bits shifted out",
              "and wT, wB, #63\nasr wA, wS, wT\nsxtw xA, wA", "arm64_scalar"),
    "srawix": ("rA = arithmetic shift right 32-bit by SH, XER.CA set",
               "rA <- EXTS((rS)[32:63] >>si SH)\n"
               "XER.CA <- (rS < 0) and any 1 bits shifted out",
               "asr wA, wS, #SH\nsxtw xA, wA", "arm64_scalar"),
    "sldx": ("rA = rS << (rB & 127), >=64 clears",
             "n <- (rB)[57:63]\nrA <- if n < 64 then (rS) << n else 0",
             "lsl xA, xS, xT", "arm64_scalar"),
    "srdx": ("rA = rS >> (rB & 127) logical, >=64 clears",
             "n <- (rB)[57:63]\nrA <- if n < 64 then (rS) >>ui n else 0",
             "lsr xA, xS, xT", "arm64_scalar"),
    "sradx": ("rA = rS >> (rB & 127) arithmetic, XER.CA set",
              "n <- (rB)[57:63]\nrA <- (rS) >>si min(n, 63)\n"
              "XER.CA <- (rS < 0) and any 1 bits shifted out",
              "asr xA, xS, xT", "arm64_scalar"),
    "sradix": ("rA = rS >> SH arithmetic, XER.CA set",
               "rA <- (rS) >>si SH\nXER.CA <- (rS < 0) and any 1 bits shifted out",
               "asr xA, xS, #SH", "arm64_scalar"),
    "rlwinmx": ("rA = ROTL32(rS, SH) & MASK(MB, ME)",
                "n <- SH\nr <- ROTL32((rS)[32:63], n)\nm <- MASK(MB+32, ME+32)\n"
                "rA <- r & m",
                "ror wT, wS, #(32-SH)\nand xA, xT, #MASK", "arm64_scalar"),
    "rlwnmx": ("rA = ROTL32(rS, rB) & MASK(MB, ME)",
               "n <- (rB)[59:63]\nr <- ROTL32((rS)[32:63], n)\n"
               "m <- MASK(MB+32, ME+32)\nrA <- r & m",
               "neg wT, wB\nror wT, wS, wT\nand xA, xT, #MASK", "arm64_scalar"),
    "rlwimix": ("rA = (ROTL32(rS, SH) & M) | (rA & ~M)",
                "r <- ROTL32((rS)[32:63], SH)\nm <- MASK(MB+32, ME+32)\n"
                "rA <- (r & m) | ((rA) & ~m)",
                "ror wT, wS, #(32-SH)\nbfi xA, xT, #POS, #WIDTH", "arm64_scalar"),
    "rldiclx": ("rA = ROTL64(rS, SH) & MASK(MB, 63)",
                "r <- ROTL64((rS), SH)\nm <- MASK(MB, 63)\nrA <- r & m",
                "ror xT, xS, #(64-SH)\nand xA, xT, #MASK", "arm64_scalar"),
    "rldicrx": ("rA = ROTL64(rS, SH) & MASK(0, ME)",
                "r <- ROTL64((rS), SH)\nm <- MASK(0, ME)\nrA <- r & m",
                "ror xT, xS, #(64-SH)\nand xA, xT, #MASK", "arm64_scalar"),
    "rldicx": ("rA = ROTL64(rS, SH) & MASK(MB, 63-SH)",
               "r <- ROTL64((rS), SH)\nm <- MASK(MB, 63-SH)\nrA <- r & m",
               "ror xT, xS, #(64-SH)\nand xA, xT, #MASK", "arm64_scalar"),
    "rldimix": ("rA = (ROTL64(rS, SH) & M) | (rA & ~M)",
                "r <- ROTL64((rS), SH)\nm <- MASK(MB, 63-SH)\n"
                "rA <- (r & m) | ((rA) & ~m)",
                "ror xT, xS, #(64-SH)\nbfi xA, xT, #POS, #WIDTH", "arm64_scalar"),
    "rldclx": ("rA = ROTL64(rS, rB) & MASK(MB, 63)",
               "n <- (rB)[58:63]\nr <- ROTL64((rS), n)\nm <- MASK(MB, 63)\n"
               "rA <- r & m",
               "neg xT, xB\nror xT, xS, xT\nand xA, xT, #MASK", "arm64_scalar"),
    "rldcrx": ("rA = ROTL64(rS, rB) & MASK(0, ME)",
               "n <- (rB)[58:63]\nr <- ROTL64((rS), n)\nm <- MASK(0, ME)\n"
               "rA <- r & m",
               "neg xT, xB\nror xT, xS, xT\nand xA, xT, #MASK", "arm64_scalar"),
    "cmp": ("CR[crfD] = signed compare(rA, rB)",
            "a <- if L then (rA) else EXTS((rA)[32:63])\n"
            "b <- if L then (rB) else EXTS((rB)[32:63])\n"
            "CR[crfD] <- {a<b, a>b, a=b, XER.SO}",
            "cmp xA, xB\nbl rosette_ppc_pack_cr_signed", "arm64_scalar"),
    "cmpi": ("CR[crfD] = signed compare(rA, SIMM)",
             "a <- if L then (rA) else EXTS((rA)[32:63])\n"
             "CR[crfD] <- {a<SIMM, a>SIMM, a=SIMM, XER.SO}",
             "cmp xA, #SIMM\nbl rosette_ppc_pack_cr_signed", "arm64_scalar"),
    "cmpl": ("CR[crfD] = unsigned compare(rA, rB)",
             "a <- if L then (rA) else EXTZ((rA)[32:63])\n"
             "b <- if L then (rB) else EXTZ((rB)[32:63])\n"
             "CR[crfD] <- {a<ui b, a>ui b, a=b, XER.SO}",
             "cmp xA, xB\nbl rosette_ppc_pack_cr_unsigned", "arm64_scalar"),
    "cmpli": ("CR[crfD] = unsigned compare(rA, UIMM)",
              "a <- if L then (rA) else EXTZ((rA)[32:63])\n"
              "CR[crfD] <- {a<ui UIMM, a>ui UIMM, a=UIMM, XER.SO}",
              "cmp xA, #UIMM\nbl rosette_ppc_pack_cr_unsigned", "arm64_scalar"),
    "bx": ("branch to LI, optionally absolute and linking",
           "if AA then NIA <- EXTS(LI || 0b00)\n"
           "else NIA <- CIA + EXTS(LI || 0b00)\nif LK then LR <- CIA + 4",
           "b #target", "arm64_scalar"),
    "bcx": ("conditionally branch to BD using BO/BI and CTR",
            "if not BO[2] then CTR <- CTR - 1\n"
            "ctr_ok <- BO[2] | ((CTR != 0) ^ BO[3])\n"
            "cond_ok <- BO[0] | (CR[BI] == BO[1])\n"
            "if ctr_ok & cond_ok then NIA <- target\nif LK then LR <- CIA + 4",
            "sub xCTR, xCTR, #1\ncbz xCTR, .Lfall\nb.cond #target",
            "arm64_scalar"),
    "bclrx": ("conditionally branch to LR",
              "ctr_ok & cond_ok as in bc; NIA <- LR[0:61] || 0b00\n"
              "if LK then LR <- CIA + 4",
              "br xLR", "arm64_scalar"),
    "bcctrx": ("conditionally branch to CTR",
               "cond_ok as in bc (CTR decrement is invalid here)\n"
               "NIA <- CTR[0:61] || 0b00\nif LK then LR <- CIA + 4",
               "br xCTR", "arm64_scalar"),
    "sc": ("system call — traps into the Xbox 360 kernel",
           "raise system-call interrupt; Rosette routes it to the kernel shim table",
           "bl rosette_ppc_system_call", "system_dispatch"),
    "mfspr": ("rD = SPR[n]",
              "n <- SPR[5:9] || SPR[0:4]\nrD <- SPR(n)",
              "bl rosette_ppc_read_spr", "system_dispatch"),
    "mtspr": ("SPR[n] = rS",
              "n <- SPR[5:9] || SPR[0:4]\nSPR(n) <- (rS)",
              "bl rosette_ppc_write_spr", "system_dispatch"),
    "mftb": ("rD = time base",
             "rD <- TB or TBU depending on the encoded TBR",
             "mrs xD, cntvct_el0", "arm64_scalar"),
    "mfcr": ("rD = CR", "rD <- 0x00000000 || CR",
             "bl rosette_ppc_read_cr", "system_dispatch"),
    "mtcrf": ("CR fields selected by CRM = rS",
              "mask <- expand(CRM)\nCR <- ((rS)[32:63] & mask) | (CR & ~mask)",
              "bl rosette_ppc_write_cr_masked", "system_dispatch"),
    "mcrf": ("CR[crfD] = CR[crfS]", "CR[crfD] <- CR[crfS]",
             "bl rosette_ppc_move_cr_field", "system_dispatch"),
    "mcrxr": ("CR[crfD] = XER[0:3], then clear them",
              "CR[crfD] <- XER[0:3]\nXER[0:3] <- 0b0000",
              "bl rosette_ppc_move_xer_to_cr", "system_dispatch"),
    "isync": ("instruction synchronize",
              "refetch: discard prefetched instructions and any speculative state",
              "isb", "arm64_scalar"),
    "sync": ("memory barrier", "all prior storage accesses complete before any later one",
             "dmb ish", "arm64_scalar"),
    "eieio": ("enforce in-order execution of I/O",
              "orders storage accesses to caching-inhibited memory",
              "dmb oshst", "arm64_scalar"),
    "mffsx": ("frD = FPSCR", "frD[32:63] <- FPSCR",
              "mrs xT, fpsr\nfmov dD, xT", "neon_scalar"),
    "mtfsfx": ("FPSCR fields selected by FM = frB",
               "mask <- expand(FM)\nFPSCR <- ((frB)[32:63] & mask) | (FPSCR & ~mask)",
               "fmov xT, dB\nmsr fpcr, xT", "neon_scalar"),
    "fmrx": ("frD = frB", "frD <- (frB)", "fmov dD, dB", "neon_scalar"),
    "fnegx": ("frD = -frB", "frD <- (frB) with sign bit inverted",
              "fneg dD, dB", "neon_scalar"),
    "fabsx": ("frD = |frB|", "frD <- (frB) with sign bit cleared",
              "fabs dD, dB", "neon_scalar"),
    "fnabsx": ("frD = -|frB|", "frD <- (frB) with sign bit set",
               "fabs dT, dB\nfneg dD, dT", "neon_scalar"),
    "fselx": ("frD = frA >= 0 ? frC : frB",
              "frD <- if (frA) >= 0.0 then (frC) else (frB)",
              "fcmp dA, #0.0\nfcsel dD, dC, dB, ge", "neon_scalar"),
    "fcmpu": ("CR[crfD] = unordered compare(frA, frB)",
              "CR[crfD] <- {a<b, a>b, a=b, unordered}\nFPSCR.FPCC updated; "
              "signals VXSNAN on a signalling NaN",
              "fcmp dA, dB\nbl rosette_ppc_pack_fp_cr", "neon_scalar"),
    "fcmpo": ("CR[crfD] = ordered compare(frA, frB)",
              "CR[crfD] <- {a<b, a>b, a=b, unordered}\nFPSCR.FPCC updated; "
              "signals VXSNAN/VXVC as ordered comparison requires",
              "fcmpe dA, dB\nbl rosette_ppc_pack_fp_cr", "neon_scalar"),
    "twi": ("trap if the signed compare of rA and SIMM matches TO",
            "if any TO condition holds for ((rA), EXTS(SIMM)) then raise trap",
            "cmp xA, #SIMM\nb.cond .Lno_trap\nbl rosette_ppc_trap\n.Lno_trap:", "system_dispatch"),
    "tw": ("trap if the 32-bit compare of rA and rB matches TO",
           "if any TO condition holds for ((rA)[32:63], (rB)[32:63]) then raise trap",
           "cmp wA, wB\nb.cond .Lno_trap\nbl rosette_ppc_trap\n.Lno_trap:", "system_dispatch"),
    "tdi": ("trap if the 64-bit compare of rA and SIMM matches TO",
            "if any TO condition holds for ((rA), EXTS(SIMM)) then raise trap",
            "cmp xA, #SIMM\nb.cond .Lno_trap\nbl rosette_ppc_trap\n.Lno_trap:", "system_dispatch"),
    "td": ("trap if the 64-bit compare of rA and rB matches TO",
           "if any TO condition holds for ((rA), (rB)) then raise trap",
           "cmp xA, xB\nb.cond .Lno_trap\nbl rosette_ppc_trap\n.Lno_trap:", "system_dispatch"),
}

CR_LOGICAL = {
    "crand": ("&", "and xT, xA, xB"),
    "crandc": ("& ~", "bic xT, xA, xB"),
    "cror": ("|", "orr xT, xA, xB"),
    "crorc": ("| ~", "orn xT, xA, xB"),
    "crxor": ("^", "eor xT, xA, xB"),
    "crnand": ("nand", "and xT, xA, xB\nmvn xT, xT"),
    "crnor": ("nor", "orr xT, xA, xB\nmvn xT, xT"),
    "creqv": ("xnor", "eon xT, xA, xB"),
}

# Scalar load/store: mnemonic -> (width, signed, update, indexed, reversed, gpr)
LOADSTORE = {
    "lbz": (8, False, False, False, False), "lbzu": (8, False, True, False, False),
    "lbzx": (8, False, False, True, False), "lbzux": (8, False, True, True, False),
    "lhz": (16, False, False, False, False), "lhzu": (16, False, True, False, False),
    "lhzx": (16, False, False, True, False), "lhzux": (16, False, True, True, False),
    "lha": (16, True, False, False, False), "lhau": (16, True, True, False, False),
    "lhax": (16, True, False, True, False), "lhaux": (16, True, True, True, False),
    "lwz": (32, False, False, False, False), "lwzu": (32, False, True, False, False),
    "lwzx": (32, False, False, True, False), "lwzux": (32, False, True, True, False),
    "lwa": (32, True, False, False, False),
    "lwax": (32, True, False, True, False), "lwaux": (32, True, True, True, False),
    "ld": (64, False, False, False, False), "ldu": (64, False, True, False, False),
    "ldx": (64, False, False, True, False), "ldux": (64, False, True, True, False),
    "lhbrx": (16, False, False, True, True), "lwbrx": (32, False, False, True, True),
    "ldbrx": (64, False, False, True, True),
}
STORES = {
    "stb": (8, False, False, False), "stbu": (8, True, False, False),
    "stbx": (8, False, True, False), "stbux": (8, True, True, False),
    "sth": (16, False, False, False), "sthu": (16, True, False, False),
    "sthx": (16, False, True, False), "sthux": (16, True, True, False),
    "stw": (32, False, False, False), "stwu": (32, True, False, False),
    "stwx": (32, False, True, False), "stwux": (32, True, True, False),
    "std": (64, False, False, False), "stdu": (64, True, False, False),
    "stdx": (64, False, True, False), "stdux": (64, True, True, False),
    "sthbrx": (16, False, True, True), "stwbrx": (32, False, True, True),
    "stdbrx": (64, False, True, True),
}
ARM_LOAD = {8: "ldrb wD, [xEA]", 16: "ldrh wD, [xEA]",
            32: "ldr wD, [xEA]", 64: "ldr xD, [xEA]"}
ARM_LOAD_S = {16: "ldrsh xD, [xEA]", 32: "ldrsw xD, [xEA]"}
ARM_STORE = {8: "strb wS, [xEA]", 16: "strh wS, [xEA]",
             32: "str wS, [xEA]", 64: "str xS, [xEA]"}
REV = {16: "rev16 wD, wD", 32: "rev wD, wD", 64: "rev xD, xD"}

FP_LOADSTORE = {
    "lfs": ("load", 32, False), "lfsu": ("load", 32, True),
    "lfsx": ("load", 32, False), "lfsux": ("load", 32, True),
    "lfd": ("load", 64, False), "lfdu": ("load", 64, True),
    "lfdx": ("load", 64, False), "lfdux": ("load", 64, True),
    "stfs": ("store", 32, False), "stfsu": ("store", 32, True),
    "stfsx": ("store", 32, False), "stfsux": ("store", 32, True),
    "stfd": ("store", 64, False), "stfdu": ("store", 64, True),
    "stfdx": ("store", 64, False), "stfdux": ("store", 64, True),
    "stfiwx": ("store", 32, False),
}

FP_ARITH = {
    "faddx": ("+", "fadd dD, dA, dB", 64), "faddsx": ("+", "fadd sD, sA, sB", 32),
    "fsubx": ("-", "fsub dD, dA, dB", 64), "fsubsx": ("-", "fsub sD, sA, sB", 32),
    "fmulx": ("*", "fmul dD, dA, dC", 64), "fmulsx": ("*", "fmul sD, sA, sC", 32),
    "fdivx": ("/", "fdiv dD, dA, dB", 64), "fdivsx": ("/", "fdiv sD, sA, sB", 32),
    "fsqrtx": ("sqrt", "fsqrt dD, dB", 64), "fsqrtsx": ("sqrt", "fsqrt sD, sB", 32),
    "fresx": ("1/x estimate", "frecpe sD, sB", 32),
    "frsqrtex": ("1/sqrt(x) estimate", "frsqrte dD, dB", 64),
    "frsqrtesx": ("1/sqrt(x) estimate", "frsqrte sD, sB", 32),
}
FP_MADD = {
    "fmaddx": ("(frA * frC) + frB", "fmadd dD, dA, dC, dB", 64),
    "fmaddsx": ("(frA * frC) + frB", "fmadd sD, sA, sC, sB", 32),
    "fmsubx": ("(frA * frC) - frB", "fnmsub dD, dA, dC, dB", 64),
    "fmsubsx": ("(frA * frC) - frB", "fnmsub sD, sA, sC, sB", 32),
    "fnmaddx": ("-((frA * frC) + frB)", "fmadd dT, dA, dC, dB\nfneg dD, dT", 64),
    "fnmaddsx": ("-((frA * frC) + frB)", "fmadd sT, sA, sC, sB\nfneg sD, sT", 32),
    "fnmsubx": ("-((frA * frC) - frB)", "fmsub dT, dA, dC, dB\nfneg dD, dT", 64),
    "fnmsubsx": ("-((frA * frC) - frB)", "fmsub sT, sA, sC, sB\nfneg sD, sT", 32),
}
FP_CVT = {
    "frspx": ("round to single precision", "fcvt sT, dB\nfcvt dD, sT"),
    "fctiwx": ("convert to 32-bit integer using FPSCR.RN", "fcvtns wT, dB"),
    "fctiwzx": ("convert to 32-bit integer, round toward zero", "fcvtzs wT, dB"),
    "fctidx": ("convert to 64-bit integer using FPSCR.RN", "fcvtns xT, dB"),
    "fctidzx": ("convert to 64-bit integer, round toward zero", "fcvtzs xT, dB"),
    "fcfidx": ("convert 64-bit integer to double", "scvtf dD, xT"),
}

# AltiVec base operations: base -> (english, neon template, is_float)
VEC_BASE = {
    "add": ("lanewise add", "add vD.{T}, vA.{T}, vB.{T}", False),
    "sub": ("lanewise subtract", "sub vD.{T}, vA.{T}, vB.{T}", False),
    "addc": ("lanewise add producing the carry-out", "uqadd vT.{T}, vA.{T}, vB.{T}\ncmhi vD.{T}, vA.{T}, vT.{T}", False),
    "subc": ("lanewise subtract producing the borrow-out", "cmhs vD.{T}, vA.{T}, vB.{T}", False),
    "avg": ("lanewise rounding average", "urhadd vD.{T}, vA.{T}, vB.{T}", False),
    "max": ("lanewise maximum", "umax vD.{T}, vA.{T}, vB.{T}", False),
    "min": ("lanewise minimum", "umin vD.{T}, vA.{T}, vB.{T}", False),
    "mule": ("multiply even lanes to double width", "umull vD.{W}, vA.{T}, vB.{T}", False),
    "mulo": ("multiply odd lanes to double width", "umull2 vD.{W}, vA.{T}, vB.{T}", False),
    "rl": ("lanewise rotate left", "ushl vT.{T}, vA.{T}, vB.{T}\norr vD.16b, vT.16b, vT.16b", False),
    "sl": ("lanewise shift left", "ushl vD.{T}, vA.{T}, vB.{T}", False),
    "sr": ("lanewise logical shift right", "neg vT.{T}, vB.{T}\nushl vD.{T}, vA.{T}, vT.{T}", False),
    "sra": ("lanewise arithmetic shift right", "neg vT.{T}, vB.{T}\nsshl vD.{T}, vA.{T}, vT.{T}", False),
}

VEC_EXPLICIT = {
    "vaddfp": ("vD[i] = vA[i] + vB[i] (single precision)",
               "fadd vD.4s, vA.4s, vB.4s"),
    "vsubfp": ("vD[i] = vA[i] - vB[i] (single precision)",
               "fsub vD.4s, vA.4s, vB.4s"),
    "vmaxfp": ("vD[i] = max(vA[i], vB[i]) (single precision)",
               "fmax vD.4s, vA.4s, vB.4s"),
    "vminfp": ("vD[i] = min(vA[i], vB[i]) (single precision)",
               "fmin vD.4s, vA.4s, vB.4s"),
    "vmaddfp": ("vD[i] = (vA[i] * vC[i]) + vB[i] (single precision)",
                "fmla vD.4s, vA.4s, vC.4s"),
    "vnmsubfp": ("vD[i] = -((vA[i] * vC[i]) - vB[i]) (single precision)",
                 "fmls vD.4s, vA.4s, vC.4s\nfneg vD.4s, vD.4s"),
    "vrefp": ("vD[i] = 1/vB[i] estimate", "frecpe vD.4s, vB.4s"),
    "vrsqrtefp": ("vD[i] = 1/sqrt(vB[i]) estimate", "frsqrte vD.4s, vB.4s"),
    "vexptefp": ("vD[i] = 2**vB[i] estimate", "bl rosette_ppc_vexptefp"),
    "vlogefp": ("vD[i] = log2(vB[i]) estimate", "bl rosette_ppc_vlogefp"),
    "vrfim": ("vD[i] = floor(vB[i])", "frintm vD.4s, vB.4s"),
    "vrfin": ("vD[i] = round-to-nearest(vB[i])", "frintn vD.4s, vB.4s"),
    "vrfip": ("vD[i] = ceil(vB[i])", "frintp vD.4s, vB.4s"),
    "vrfiz": ("vD[i] = trunc(vB[i])", "frintz vD.4s, vB.4s"),
    "vctsxs": ("vD[i] = saturating signed int(vB[i] * 2**UIMM)",
               "fcvtzs vD.4s, vB.4s, #UIMM"),
    "vctuxs": ("vD[i] = saturating unsigned int(vB[i] * 2**UIMM)",
               "fcvtzu vD.4s, vB.4s, #UIMM"),
    "vcfsx": ("vD[i] = float(signed vB[i]) / 2**UIMM",
              "scvtf vD.4s, vB.4s, #UIMM"),
    "vcfux": ("vD[i] = float(unsigned vB[i]) / 2**UIMM",
              "ucvtf vD.4s, vB.4s, #UIMM"),
    "vand": ("vD = vA & vB", "and vD.16b, vA.16b, vB.16b"),
    "vandc": ("vD = vA & ~vB", "bic vD.16b, vA.16b, vB.16b"),
    "vor": ("vD = vA | vB", "orr vD.16b, vA.16b, vB.16b"),
    "vnor": ("vD = ~(vA | vB)", "orr vT.16b, vA.16b, vB.16b\nmvn vD.16b, vT.16b"),
    "vxor": ("vD = vA ^ vB", "eor vD.16b, vA.16b, vB.16b"),
    "vsel": ("vD[i] = vC[i] ? vB[i] : vA[i] (bitwise)",
             "mov vD.16b, vC.16b\nbsl vD.16b, vB.16b, vA.16b"),
    "vperm": ("vD[i] = concat(vA, vB)[vC[i] & 31]",
              "tbl vD.16b, {vA.16b, vB.16b}, vC.16b"),
    "vsldoi": ("vD = ((vA || vB) << (SHB * 8))[0:127]",
               "ext vD.16b, vA.16b, vB.16b, #SHB"),
    "vsl": ("vD = vA << (vB[15] & 7) as a 128-bit bit shift",
            "bl rosette_ppc_vsl"),
    "vsr": ("vD = vA >> (vB[15] & 7) as a 128-bit bit shift",
            "bl rosette_ppc_vsr"),
    "vslo": ("vD = vA << ((vB[15] >> 3) * 8) as a 128-bit byte shift",
             "ext vD.16b, vA.16b, vZ.16b, #SHB"),
    "vsro": ("vD = vA >> ((vB[15] >> 3) * 8) as a 128-bit byte shift",
             "ext vD.16b, vZ.16b, vA.16b, #SHB"),
    "mfvscr": ("vD[112:127] = VSCR", "bl rosette_ppc_read_vscr"),
    "mtvscr": ("VSCR = vB[112:127]", "bl rosette_ppc_write_vscr"),
    "vupkhpx": ("unpack the high four 1-5-5-5 pixels into words",
                "bl rosette_ppc_vupkhpx"),
    "vupklpx": ("unpack the low four 1-5-5-5 pixels into words",
                "bl rosette_ppc_vupklpx"),
    "vpkpx": ("pack eight words into 1-5-5-5 pixels", "bl rosette_ppc_vpkpx"),
}

LANE = {"b": ("16b", "8h", 8), "h": ("8h", "4s", 16), "w": ("4s", "2d", 32)}


def vector_semantics(mnem: str):
    """Return (operation, semantic, arm64 assembly, kind) for an AltiVec op."""
    if mnem in VEC_EXPLICIT:
        op, asm = VEC_EXPLICIT[mnem]
        kind = "fallback" if asm.startswith("bl ") else "neon_vector"
        return op, op, asm, kind

    m = re.match(r"^vcmp(equ|gtu|gts|eqfp|gefp|gtfp|bfp)([bhw]?)$", mnem)
    if m:
        rel, width = m.group(1), m.group(2)
        if rel.endswith("fp"):
            neon = {"eqfp": "fcmeq", "gefp": "fcmge", "gtfp": "fcmgt"}.get(rel)
            if neon is None:  # vcmpbfp
                return ("vD[i] = in-bounds flags for vA[i] against +/-vB[i]",
                        "vD[i][0] <- vA[i] >  vB[i]\nvD[i][1] <- vA[i] < -vB[i]",
                        "bl rosette_ppc_vcmpbfp", "fallback")
            op = f"vD[i] = all-ones when vA[i] {rel[:-2]} vB[i] (single precision)"
            return op, op, f"{neon} vD.4s, vA.4s, vB.4s", "neon_vector"
        t = LANE[width][0]
        neon = {"equ": "cmeq", "gtu": "cmhi", "gts": "cmgt"}[rel]
        signed = "signed" if rel == "gts" else "unsigned"
        relation = "==" if rel == "equ" else ">"
        op = f"vD[i] = all-ones when vA[i] {relation} vB[i] ({signed})"
        return op, op, f"{neon} vD.{t}, vA.{t}, vB.{t}", "neon_vector"

    m = re.match(r"^vmrg([hl])([bhw])$", mnem)
    if m:
        half, width = m.group(1), m.group(2)
        t = LANE[width][0]
        neon = "zip1" if half == "h" else "zip2"
        op = ("vD interleaves the %s halves of vA and vB" %
              ("high" if half == "h" else "low"))
        return op, op, f"{neon} vD.{t}, vA.{t}, vB.{t}", "neon_vector"

    m = re.match(r"^vsplt([bhw])$", mnem)
    if m:
        t = LANE[m.group(1)][0]
        op = "vD[i] = vB[UIMM] broadcast to every lane"
        return op, op, f"dup vD.{t}, vB.{t}[UIMM]", "neon_vector"

    m = re.match(r"^vspltis([bhw])$", mnem)
    if m:
        t = LANE[m.group(1)][0]
        op = "vD[i] = sign-extended SIMM broadcast to every lane"
        return op, op, f"movi vD.{t}, #SIMM", "neon_vector"

    m = re.match(r"^vpk([us])([hw])([us])([ms])$", mnem)
    if m:
        src_sign, src_w, dst_sign, mode = m.groups()
        src_t, _, _ = LANE[src_w]
        dst_t = LANE["b" if src_w == "h" else "h"][0]
        if mode == "m":
            op = "vD packs vA and vB down one lane width, truncating"
            asm = f"xtn vD.{dst_t}, vA.{src_t}\nxtn2 vD.16b, vB.{src_t}"
        else:
            sat = ("sqxtn" if src_sign == "s" and dst_sign == "s" else
                   "sqxtun" if src_sign == "s" else "uqxtn")
            op = "vD packs vA and vB down one lane width, saturating"
            asm = f"{sat} vD.{dst_t}, vA.{src_t}\n{sat}2 vD.16b, vB.{src_t}"
        return op, op, asm, "neon_vector"

    m = re.match(r"^vupk([hl])s([bh])$", mnem)
    if m:
        half, width = m.group(1), m.group(2)
        src_t, dst_t, _ = LANE[width]
        neon = "sshll" if half == "h" else "sshll2"
        op = ("vD sign-extends the %s half of vB to the next lane width" %
              ("high" if half == "h" else "low"))
        return op, op, f"{neon} vD.{dst_t}, vB.{src_t}, #0", "neon_vector"

    m = re.match(r"^vm(h|hr)addshs$", mnem)
    if m:
        op = ("vD[i] = saturate(((vA[i] * vB[i]) >> 15%s) + vC[i]) on halfwords" %
              (" rounded" if m.group(1) == "hr" else ""))
        return op, op, "sqdmulh vT.8h, vA.8h, vB.8h\nsqadd vD.8h, vT.8h, vC.8h", "neon_vector"

    if mnem == "vmladduhm":
        op = "vD[i] = (vA[i] * vB[i]) + vC[i] on halfwords, modulo"
        return op, op, "mul vT.8h, vA.8h, vB.8h\nadd vD.8h, vT.8h, vC.8h", "neon_vector"

    m = re.match(r"^vmsum([us])([bhw])([ms])[ms]?$", mnem)
    if m:
        op = "vD[i] = vC[i] + sum of the lane products inside each word"
        return op, op, "bl rosette_ppc_vmsum", "fallback"

    m = re.match(r"^vsum(4?|2)s?([bhw]?)s$", mnem)
    if m:
        op = "vD accumulates lane sums of vA into the words of vC"
        return op, op, "bl rosette_ppc_vsum", "fallback"

    m = re.match(r"^v(add|sub|avg|max|min|mule|mulo|rl|sl|sr|sra|addc|subc)"
                 r"([us])([bhw])([ms]?)$", mnem)
    if m:
        base, sign, width, mode = m.groups()
        english, tmpl, _ = VEC_BASE[base]
        src_t, wide_t, bits = LANE[width]
        asm = tmpl.replace("{T}", src_t).replace("{W}", wide_t)
        if sign == "s":
            asm = (asm.replace("umax", "smax").replace("umin", "smin")
                      .replace("umull", "smull").replace("urhadd", "srhadd")
                      .replace("uqadd", "sqadd").replace("ushl", "sshl")
                      .replace("cmhi", "cmgt").replace("cmhs", "cmge"))
        if mode == "s":
            asm = (asm.replace("add v", "uqadd v" if sign == "u" else "sqadd v")
                      .replace("sub v", "uqsub v" if sign == "u" else "sqsub v"))
        signword = "signed" if sign == "s" else "unsigned"
        modeword = "saturating" if mode == "s" else "modulo"
        op = f"vD[i] = {english} of vA[i] and vB[i], {signword} {bits}-bit lanes, {modeword}"
        return op, op, asm, "neon_vector"

    op = f"{mnem}: AltiVec operation executed by the Rosette PPC vector unit"
    return op, op, f"bl rosette_ppc_{mnem}", "fallback"


def describe(insn: Insn, group: str):
    """Return (operation, semantic, arm64_assembly, lowering_kind)."""
    m = insn.mnem

    if m in SCALAR:
        op, sem, asm, kind = SCALAR[m]
        return op, sem, asm, kind

    if m in CR_LOGICAL:
        sym, asm = CR_LOGICAL[m]
        op = f"CR[crbD] = CR[crbA] {sym} CR[crbB]"
        sem = f"CR[crbD] <- CR[crbA] {sym} CR[crbB]"
        return op, sem, asm, "arm64_scalar"

    if m in LOADSTORE:
        width, signed, update, indexed, reversed_ = LOADSTORE[m]
        ea = "(rA|0) + (rB)" if indexed else "(rA|0) + EXTS(d)"
        if update:
            ea = "(rA) + " + ("(rB)" if indexed else "EXTS(d)")
        ext = "EXTS" if signed else "EXTZ"
        order = "byte-reversed (little-endian)" if reversed_ else "big-endian"
        op = f"rD = {ext}(MEM{width}[{ea}]) loaded {order}"
        sem = f"EA <- {ea}\nrD <- {ext}(MEM(EA, {width // 8}))"
        if update:
            sem += "\nrA <- EA"
        asm = (ARM_LOAD_S[width] if (signed and width in ARM_LOAD_S)
               else ARM_LOAD[width])
        # Guest memory holds PowerPC big-endian bytes. A normal load needs a
        # REV on the little-endian host; a *brx load already wants the
        # little-endian reading, so it must not be reversed twice.
        if not reversed_ and width in REV:
            asm += "\n" + REV[width]
        if update:
            asm += "\nmov xA, xEA"
        return op, sem, asm, "arm64_scalar"

    if m in STORES:
        width, update, indexed, reversed_ = STORES[m]
        ea = ("(rA) + " if update else "(rA|0) + ") + \
             ("(rB)" if indexed else "EXTS(d)")
        order = "byte-reversed (little-endian)" if reversed_ else "big-endian"
        op = f"MEM{width}[{ea}] = rS stored {order}"
        sem = f"EA <- {ea}\nMEM(EA, {width // 8}) <- (rS)[{64 - width}:63]"
        if update:
            sem += "\nrA <- EA"
        asm = ((REV[width] + "\n") if (width in REV and not reversed_) else "") + \
            ARM_STORE[width]
        if update:
            asm += "\nmov xA, xEA"
        return op, sem, asm, "arm64_scalar"

    if m in ("lwarx", "ldarx"):
        width = 32 if m == "lwarx" else 64
        op = f"rD = MEM{width}[(rA|0) + rB] and set the reservation"
        sem = (f"EA <- (rA|0) + (rB)\nRESERVE <- 1\nRESERVE_ADDR <- EA\n"
               f"rD <- EXTZ(MEM(EA, {width // 8}))")
        asm = ("ldaxr wD, [xEA]" if width == 32 else "ldaxr xD, [xEA]")
        return op, sem, asm + "\n" + REV[width], "arm64_scalar"

    if m in ("stwcx", "stdcx"):
        width = 32 if m == "stwcx" else 64
        op = f"conditionally store rS to MEM{width}[(rA|0) + rB]"
        sem = (f"EA <- (rA|0) + (rB)\n"
               f"if RESERVE and RESERVE_ADDR = EA then\n"
               f"  MEM(EA, {width // 8}) <- (rS)\n  CR0 <- 0b001 || XER.SO\n"
               f"else\n  CR0 <- 0b000 || XER.SO\nRESERVE <- 0")
        asm = (REV[width] + "\n" +
               ("stlxr wT, wS, [xEA]" if width == 32 else "stlxr wT, xS, [xEA]") +
               "\nbl rosette_ppc_store_conditional_cr0")
        return op, sem, asm, "arm64_scalar"

    if m in FP_LOADSTORE:
        direction, width, update = FP_LOADSTORE[m]
        if m == "stfiwx":
            op = "MEM32[(rA|0) + rB] = the low 32 bits of frS"
            sem = "EA <- (rA|0) + (rB)\nMEM(EA, 4) <- (frS)[32:63]"
            return op, sem, "fmov xT, dS\nrev wT, wT\nstr wT, [xEA]", "neon_scalar"
        if direction == "load":
            conv = ("single-precision value converted to double"
                    if width == 32 else "double-precision value")
            op = f"frD = MEM{width}[EA] as a {conv}"
            sem = (f"EA <- {'(rA) + ' if update else '(rA|0) + '}displacement\n"
                   f"frD <- {'DOUBLE(' if width == 32 else ''}"
                   f"MEM(EA, {width // 8}){')' if width == 32 else ''}")
            asm = ("ldr wT, [xEA]\nrev wT, wT\nfmov sD, wT\nfcvt dD, sD"
                   if width == 32 else "ldr xT, [xEA]\nrev xT, xT\nfmov dD, xT")
        else:
            conv = ("frS rounded to single precision" if width == 32 else "frS")
            op = f"MEM{width}[EA] = {conv}"
            sem = (f"EA <- {'(rA) + ' if update else '(rA|0) + '}displacement\n"
                   f"MEM(EA, {width // 8}) <- "
                   f"{'SINGLE((frS))' if width == 32 else '(frS)'}")
            asm = ("fcvt sT, dS\nfmov wT, sT\nrev wT, wT\nstr wT, [xEA]"
                   if width == 32 else "fmov xT, dS\nrev xT, xT\nstr xT, [xEA]")
        if update:
            sem += "\nrA <- EA"
            asm += "\nmov xA, xEA"
        return op, sem, asm, "neon_scalar"

    if m in FP_ARITH:
        sym, asm, width = FP_ARITH[m]
        prec = "single" if width == 32 else "double"
        if sym in ("sqrt", "1/x estimate", "1/sqrt(x) estimate"):
            op = f"frD = {sym}(frB) in {prec} precision"
            sem = f"frD <- {sym}((frB)) rounded per FPSCR.RN"
        else:
            src = "frC" if sym == "*" else "frB"
            op = f"frD = frA {sym} {src} in {prec} precision"
            sem = f"frD <- (frA) {sym} ({src}) rounded per FPSCR.RN"
        return op, sem, asm, "neon_scalar"

    if m in FP_MADD:
        expr, asm, width = FP_MADD[m]
        prec = "single" if width == 32 else "double"
        op = f"frD = {expr} in {prec} precision"
        sem = (f"frD <- {expr} computed with one rounding "
               f"(fused multiply-add) per FPSCR.RN")
        return op, sem, asm, "neon_scalar"

    if m in FP_CVT:
        english, asm = FP_CVT[m]
        op = f"frD = {english}"
        sem = (f"frD <- {english} of (frB)\n"
               "FPSCR.FPRF/FR/FI and the VXCVI/XX exceptions are updated")
        return op, sem, asm, "neon_scalar"

    if m in ("mtfsb0x", "mtfsb1x"):
        value = "0" if m == "mtfsb0x" else "1"
        op = f"FPSCR[crbD] = {value}"
        sem = f"FPSCR[crbD] <- {value}"
        return op, sem, "bl rosette_ppc_write_fpscr_bit", "system_dispatch"

    if m == "mtfsfix":
        op = "FPSCR[crfD] = IMM"
        return op, "FPSCR field crfD <- IMM", \
            "bl rosette_ppc_write_fpscr_field", "system_dispatch"

    if m == "mcrfs":
        op = "CR[crfD] = FPSCR[crfS], then clear the sticky bits copied"
        return op, "CR[crfD] <- FPSCR[crfS]\nexception bits copied out are cleared", \
            "bl rosette_ppc_move_fpscr_to_cr", "system_dispatch"

    if group in ("LOAD_MULTIPLE", "STORE_MULTIPLE"):
        loading = group == "LOAD_MULTIPLE"
        word = "loads" if loading else "stores"
        op = f"{word} a consecutive register run starting at r{'D' if loading else 'S'}"
        sem = ("EA <- (rA|0) + displacement\n"
               f"for r in r{'D' if loading else 'S'}..r31: "
               f"{'r <- MEM(EA, 4)' if loading else 'MEM(EA, 4) <- r[32:63]'}"
               "; EA <- EA + 4")
        asm = ("bl rosette_ppc_load_multiple" if loading
               else "bl rosette_ppc_store_multiple")
        return op, sem, asm, "fallback"

    if group == "CACHE":
        english = {
            "dcbf": "flush the data cache block", "dcbi": "invalidate the data cache block",
            "dcbst": "store the data cache block", "dcbt": "touch (prefetch) the data cache block",
            "dcbtst": "touch for store the data cache block",
            "dcbz": "zero the 32-byte data cache block",
            "dcbz128": "zero the 128-byte data cache block",
            "icbi": "invalidate the instruction cache block",
        }[m]
        op = f"{english} at (rA|0) + (rB)"
        sem = f"EA <- (rA|0) + (rB)\n{english} containing EA"
        asm = {"dcbf": "dc civac, xEA", "dcbi": "dc ivac, xEA",
               "dcbst": "dc cvac, xEA", "dcbt": "prfm pldl1keep, [xEA]",
               "dcbtst": "prfm pstl1keep, [xEA]",
               "dcbz": "dc zva, xEA", "dcbz128": "dc zva, xEA",
               "icbi": "ic ivau, xEA"}[m]
        return op, sem, asm, "arm64_scalar"

    if group in ("VMX_LOAD", "VMX_STORE"):
        if m in ("lvsl", "lvsr"):
            side = "left" if m == "lvsl" else "right"
            op = f"vD = the shift-{side} permute control vector for EA"
            sem = (f"EA <- (rA|0) + (rB)\nsh <- EA[60:63]\n"
                   f"vD <- the 16 byte indices that align a {side} shift by sh")
            return op, sem, "bl rosette_ppc_lvs", "fallback"
        elem = re.search(r"lv(e[bhw])x|stv(e[bhw])x", m)
        if elem:
            width = (elem.group(1) or elem.group(2))[1]
            bits = {"b": 8, "h": 16, "w": 32}[width]
            loading = m.startswith("lv")
            op = (f"vD[lane] = MEM{bits}[EA]" if loading
                  else f"MEM{bits}[EA] = vS[lane]")
            sem = (f"EA <- ((rA|0) + (rB)) & ~{bits // 8 - 1}\n"
                   f"lane <- EA[60:63] / {bits // 8}\n" +
                   (f"vD[lane] <- MEM(EA, {bits // 8})" if loading
                    else f"MEM(EA, {bits // 8}) <- vS[lane]"))
            asm = (f"ld1 {{vD.{width}}}[lane], [xEA]" if loading
                   else f"st1 {{vS.{width}}}[lane], [xEA]")
            return op, sem, asm, "neon_vector"
        loading = m.startswith("lv")
        op = ("vD = MEM128[EA & ~15]" if loading else "MEM128[EA & ~15] = vS")
        sem = ("EA <- ((rA|0) + (rB)) & ~15\n" +
               ("vD <- MEM(EA, 16)" if loading else "MEM(EA, 16) <- (vS)") +
               "\nthe word lanes are byte-reversed on a little-endian host")
        asm = (("ldr qD, [xEA]\nrev32 vD.16b, vD.16b" if loading
                else "rev32 vT.16b, vS.16b\nstr qT, [xEA]"))
        return op, sem, asm, "neon_vector"

    if group == "VMX128":
        op = (f"{m}: Xbox 360 VMX128 vector operation on the 128-entry "
              f"vector register file")
        sem = (f"{m} decodes a VMX128 ({insn.form}) encoding whose register "
               "fields are split across the instruction word; the operation "
               "is the VMX128 form of the corresponding AltiVec instruction.")
        return op, sem, f"bl rosette_ppc_{m}", "fallback"

    if m.startswith("v") or m in ("mfvscr", "mtvscr"):
        return vector_semantics(m)

    if group == "SYSTEM":
        op = f"{m}: supervisor / machine-state operation"
        sem = (f"{m} manipulates supervisor state (MSR, segment registers, or "
               "the TLB). Rosette models it against the Xbox 360 kernel view of "
               "machine state rather than real hardware.")
        return op, sem, f"bl rosette_ppc_{m}", "system_dispatch"

    op = f"{m}: PowerPC {insn.form}-form instruction"
    sem = f"{m} is executed by the Rosette PPC interpreter."
    return op, sem, f"bl rosette_ppc_{m}", "fallback"


# --------------------------------------------------------------------------
# Register / flag contract
# --------------------------------------------------------------------------

READ_HINT = {
    "RA": "GPR[RA]", "RA0": "GPR[RA]", "RB": "GPR[RB]", "RS": "GPR[RS]",
    "FA": "FPR[FA]", "FB": "FPR[FB]", "FC": "FPR[FC]", "FS": "FPR[FS]",
    "VA": "VR[VA]", "VB": "VR[VB]", "VC": "VR[VC]", "VS": "VR[VS]",
    "VA128": "VR128[VA128]", "VB128": "VR128[VB128]",
    "VC128": "VR128[VC128]", "VS128": "VR128[VS128]",
    "CRBA": "CR[CRBA]", "CRBB": "CR[CRBB]", "CRFS": "CR[CRFS]",
    "SIMM": "SIMM", "UIMM": "UIMM", "d": "d", "ds": "ds", "DS": "d",
    "SH": "SH", "NB": "NB", "BO": "BO", "BI": "CR[BI]", "BD": "BD",
    "ADDR": "LI", "SPR": "SPR", "TBR": "TBR", "LEV": "LEV",
    "CRM": "CRM", "FM": "FM", "IMM": "IMM", "TO": "TO", "L": "L",
    "MB": "MB", "ME": "ME", "SHB": "SHB", "type": "type", "pack": "pack",
    "shift": "shift", "z": "z",
}
WRITE_HINT = {
    "RD": "GPR[RD]", "RA": "GPR[RA]", "FD": "FPR[FD]",
    "VD": "VR[VD]", "VD128": "VR128[VD128]",
    "CRBD": "CR[CRBD]", "CRFD": "CR[CRFD]", "FPSCRD": "FPSCR[FPSCRD]",
}


def contract(insn: Insn, group: str):
    ops = insn.operands
    reads, writes, flags = [], [], []

    # In every PowerPC form the architected destination is the first operand;
    # rA in an X-form logical/rotate is a destination, rA in an XO-form add is
    # a source, and only operand position tells them apart.
    if ops and ops[0] in WRITE_HINT:
        writes.append(WRITE_HINT[ops[0]])
    for name in ops:
        hint = READ_HINT.get(name)
        if hint and hint not in reads and hint not in writes:
            reads.append(hint)

    touches_memory = group in (
        "LOAD", "LOAD_INDEXED", "LOAD_MULTIPLE", "FP_LOAD", "VMX_LOAD",
        "STORE", "STORE_INDEXED", "STORE_MULTIPLE", "FP_STORE", "VMX_STORE",
        "BYTE_REVERSE", "ATOMIC",
    )
    if touches_memory:
        if insn.mnem.startswith("st"):
            writes.append("MEM")
        elif "MEM" not in reads:
            reads.append("MEM")
    # Update forms write the effective address back into rA.
    updates = (insn.mnem in LOADSTORE and LOADSTORE[insn.mnem][2]) or \
              (insn.mnem in STORES and STORES[insn.mnem][1]) or \
              (insn.mnem in FP_LOADSTORE and FP_LOADSTORE[insn.mnem][2])
    if updates and "GPR[RA]" not in writes:
        writes.append("GPR[RA]")

    if insn.has_rc:
        if insn.form in ("VC", "VX128_R"):
            flags.append("CR6 (when Rc=1)")
        elif group.startswith("FP"):
            flags.append("CR1 (when Rc=1)")
        else:
            flags.append("CR0 (when Rc=1)")
    if insn.has_oe:
        flags.append("XER.OV/XER.SO (when OE=1)")
    if insn.mnem in ("addcx", "addex", "addicx", "addic", "addmex", "addzex",
                     "subfcx", "subfex", "subfic", "subfmex", "subfzex",
                     "srawx", "srawix", "sradx", "sradix"):
        flags.append("XER.CA")
    if insn.mnem in ("stwcx", "stdcx"):
        flags.append("CR0")
    if group in ("CMP",):
        flags.append("CR[crfD]")
    if group in ("FP_COMPARE",):
        flags += ["CR[crfD]", "FPSCR.FPCC", "FPSCR.VXSNAN"]
    if group in ("FP_ARITH", "FP_MULTIPLY_ADD", "FP_CONVERT"):
        flags.append("FPSCR.FPRF/FX/OX/UX/XX/VX")
    if group.startswith("VMX") and insn.mnem.endswith(("s", "xs")):
        flags.append("VSCR.SAT")
    if insn.mnem in ("bcx", "bclrx", "bcctrx"):
        flags.append("CTR (when BO decrements)")
    if not flags:
        flags.append("none")

    if not reads:
        reads.append("none")
    if not writes:
        writes.append("none")
    return reads, writes, flags


def special_regs(insn: Insn, group: str):
    regs = []
    if insn.has_lk:
        regs.append("LR (when LK=1)")
    if insn.mnem in ("bclrx",):
        regs.append("LR (source)")
    if insn.mnem in ("bcctrx",):
        regs.append("CTR (source)")
    if insn.mnem in ("bcx", "bclrx"):
        regs.append("CTR (decrement)")
    if insn.mnem in ("mfspr", "mtspr"):
        regs.append("SPR (LR, CTR, XER, and the Xenon-specific SPRs)")
    if insn.mnem == "mftb":
        regs.append("TB / TBU")
    if group.startswith("FP"):
        regs.append("FPSCR")
    if group.startswith("VMX"):
        regs.append("VSCR")
    if insn.mnem in ("lwarx", "ldarx", "stwcx", "stdcx"):
        regs.append("reservation (address + valid bit)")
    return regs or ["none"]


# --------------------------------------------------------------------------
# Emission
# --------------------------------------------------------------------------


CATEGORY = {
    "ADD": "integer_arithmetic", "SUB": "integer_arithmetic",
    "MUL": "integer_arithmetic", "DIV": "integer_arithmetic",
    "LOGICAL": "integer_logical", "SHIFT": "integer_shift",
    "ROTATE": "integer_rotate", "CMP": "integer_compare",
    "EXTEND": "integer_extend", "COUNT": "integer_count",
    "LOAD": "memory_load", "LOAD_INDEXED": "memory_load",
    "LOAD_MULTIPLE": "memory_load", "STORE": "memory_store",
    "STORE_INDEXED": "memory_store", "STORE_MULTIPLE": "memory_store",
    "BYTE_REVERSE": "memory_byte_reversed", "ATOMIC": "memory_atomic",
    "CACHE": "cache_management", "SYNC": "memory_ordering",
    "BRANCH": "control_flow", "CONDITION_REGISTER": "condition_register",
    "TRAP": "control_trap", "SYSTEM": "system_supervisor",
    "SPR": "special_purpose_register",
    "FP_ARITH": "floating_point_arithmetic",
    "FP_MULTIPLY_ADD": "floating_point_fused_multiply_add",
    "FP_CONVERT": "floating_point_convert",
    "FP_COMPARE": "floating_point_compare",
    "FP_MOVE": "floating_point_move",
    "FP_STATUS": "floating_point_status",
    "FP_LOAD": "floating_point_load", "FP_STORE": "floating_point_store",
    "VMX_LOAD": "vector_load", "VMX_STORE": "vector_store",
    "VMX_ARITH": "vector_arithmetic", "VMX_LOGICAL": "vector_logical",
    "VMX_COMPARE": "vector_compare", "VMX_PERMUTE": "vector_permute",
    "VMX_PACK": "vector_pack", "VMX_SHIFT": "vector_shift",
    "VMX_SPLAT": "vector_splat", "VMX_CONVERT": "vector_convert",
    "VMX_ESTIMATE": "vector_estimate",
    "VMX_MULTIPLY_ADD": "vector_multiply_add",
    "VMX_STATUS": "vector_status", "VMX128": "vector_vmx128",
}


def q(items):
    return "[" + ", ".join('"%s"' % i for i in items) + "]"


def lowering_tag(insn: Insn, kind: str) -> str:
    return f"arm64_ppc_{insn.mnem}" + ("_helper" if kind == "fallback" else "")


def encoding_rows(insn: Insn):
    rows = []
    pattern = int(insn.pattern, 16)
    rows.append({
        "opcode": f"{pattern:#010x}",
        "form": insn.fmt,
        "op_en": insn.form,
    })
    return rows


def render_source_inc(insn: Insn, group: str):
    operation, semantic, _asm, kind = describe(insn, group)
    reads, writes, flags = contract(insn, group)
    cells = operand_rows(insn)
    pattern = int(insn.pattern, 16)
    mask = form_mask(insn)
    name = insn.mnem
    lines = []
    a = lines.append
    a(f"// {group}/{name.upper()}.inc")
    a("")
    a("// Canonical table metadata for registry-wide .inc validation.")
    a("operand_encoding = [")
    a('  { op_en = "%s", operand_1 = "%s", operand_2 = "%s", operand_3 = "%s", operand_4 = "%s" },'
      % (insn.form, cells[0], cells[1], cells[2], cells[3]))
    a("]")
    a("")
    a('source_isa = "ppc"')
    a('name = "%s"' % name)
    a('mnemonic = "%s"' % insn.base_mnem)
    a('category = "%s"' % CATEGORY.get(group, group.lower()))
    a('operation = "%s"' % operation.replace('"', "'"))
    a("")
    a('form = "%s"' % insn.form)
    a("primary_opcode = %d" % insn.primary)
    a('opcode_pattern = "%#010x"' % pattern)
    a('opcode_mask = "%#010x"' % mask)
    a('instruction_length = 4')
    a('byte_order = "big_endian"')
    a("")
    a("encodings = [")
    for row in encoding_rows(insn):
        a('  { opcode = "%s", form = "%s", op_en = "%s" }'
          % (row["opcode"], row["form"], row["op_en"]))
    a("]")
    a("")
    a("reads = %s" % q(reads))
    a("writes = %s" % q(writes))
    a("flags_written = %s" % q(flags))
    a("special_registers = %s" % q(special_regs(insn, group)))
    a("")
    a("semantic = \"\"\"")
    for line in semantic.split("\n"):
        a(line)
    a("\"\"\"")
    a("")
    a('handler = "ppc_%s"' % name)
    a('jit_lowering = "%s"' % lowering_tag(insn, kind))
    a("")
    return "\n".join(lines) + "\n"


def render_mirror_inc(insn: Insn, group: str, source_body: str):
    operation, semantic, asm, kind = describe(insn, group)
    name = insn.mnem
    rel = f"{group}/{name.upper()}.inc"
    lines = []
    a = lines.append
    a(f"// {rel}")
    a(f"// ARM64/NEON translation mirror generated from ISA/ppc/{rel}.")
    a("// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.")
    a("")
    body = source_body.split("\n")
    # Drop the source header comment line, keep everything else verbatim.
    body = body[1:]
    header_extra = [
        'source_isa = "ppc"',
        'target_isa = "arm64_neon"',
        'ppc_table = "%s"' % rel,
        'ppc_handler = "ppc_%s"' % name,
        'neon_lowering = "%s"' % lowering_tag(insn, kind),
        'lowering_kind = "%s"' % kind,
        "",
    ]
    # The preserved body already carries `source_isa`; drop the duplicate.
    body = [ln for ln in body if ln != 'source_isa = "ppc"']
    lines.extend(header_extra)
    lines.extend(body)
    a("neon_register_model = \"\"\"")
    a("PowerPC architected state lives in the Rosette PPC register file: GPR0-31 and")
    a("LR/CTR/XER as 64-bit slots, FPR0-31 as IEEE doubles, VR0-127 as 128-bit lanes,")
    a("and CR as eight 4-bit fields. The lowering loads the operands it needs into")
    a("ARM64 temporaries, computes, and writes the architected slot back explicitly.")
    a("\"\"\"")
    a("")
    a("neon_flag_model = \"\"\"")
    a("ARM64 NZCV is repacked into the PowerPC condition contract named by")
    a("flags_written above: CR field bits are ordered LT, GT, EQ, SO, with SO copied")
    a("from XER; XER.CA and XER.OV are produced from the ARM64 carry/overflow flags.")
    a("\"\"\"")
    a("")
    a("neon_assembly = \"\"\"")
    for line in asm.split("\n"):
        a(line)
    a("\"\"\"")
    a("")
    a("neon_notes = [")
    a('  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",')
    a('  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",')
    a('  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."')
    a("]")
    a("")
    a('abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]')
    a("")
    return "\n".join(lines) + "\n"


def form_mask(insn: Insn) -> int:
    """Bits that are fixed by the encoding (opcode + extended opcode)."""
    primary = 0xFC000000
    form = insn.form
    if form in ("D", "B", "I", "SC", "M"):
        base = primary
    elif form == "DS":
        base = primary | 0x3
    elif form in ("X", "XL", "XFX", "XFL", "DCBZ"):
        base = primary | 0x7FE
    elif form == "XO":
        base = primary | 0x3FE
    elif form == "XS":
        base = primary | 0x7FC
    elif form == "A":
        base = primary | 0x3E
    elif form in ("MD",):
        base = primary | 0x1C
    elif form in ("MDS",):
        base = primary | 0x1E
    elif form == "VA":
        base = primary | 0x3F
    elif form == "VC":
        base = primary | 0x3FF
    elif form == "VX":
        base = primary | 0x7FF
    elif form.startswith("VX128"):
        base = primary | 0x7F3
    else:
        base = primary
    return base & 0xFFFFFFFF


def zig_bridge(group: str, name: str, depth_prefix: str, rel_dir: str):
    return (
        'pub const family = "%s";\n'
        'pub const path = "%s/%s.inc";\n'
        'pub const source = @embedFile("%s%s/%s.inc");\n'
        % (group, group, name.upper(), depth_prefix, group, name.upper())
    )


def ident(group: str, name: str) -> str:
    return re.sub(r"[^a-z0-9]", "_", (group + "_" + name).lower())


PPC_ROOT_TEMPLATE = '''const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");

// Generated by tools/gen_ppc_isa.py from tools/ppc_isa_spec.txt. Do not edit by hand.

{imports}

pub const TableMetadata = struct {{
    name: []const u8,
    mnemonic: []const u8,
    category: []const u8,
    form: []const u8,
    handler: []const u8,
    jit_lowering: []const u8,
    encoding_count: usize,
    source_path: []const u8,
    primary_opcode: u8,
    has_semantic: bool,
    has_registers: bool,
    has_condition_model: bool,
}};

pub const InstructionTable = struct {{
    family: []const u8,
    path: []const u8,
    source: []const u8,

    pub fn metadata(self: InstructionTable) TableMetadata {{
        return .{{
            .name = stringAssignment(self.source, "name") orelse mnemonicFromPath(self.path),
            .mnemonic = stringAssignment(self.source, "mnemonic") orelse mnemonicFromPath(self.path),
            .category = stringAssignment(self.source, "category") orelse "documented_contract",
            .form = stringAssignment(self.source, "form") orelse "unknown",
            .handler = anyStringAssignment(self.source, &[_][]const u8{{ "handler", "ppc_handler" }}) orelse "ppc_documented_contract_handler",
            .jit_lowering = anyStringAssignment(self.source, &[_][]const u8{{ "jit_lowering", "neon_lowering", "arm64_lowering" }}) orelse "arm64_documented_contract_fallback",
            .encoding_count = countEncodingRows(self.source),
            .source_path = self.path,
            .primary_opcode = numberAssignment(self.source, "primary_opcode") orelse 0xFF,
            .has_semantic = hasAnyAssignment(self.source, &[_][]const u8{{ "semantic", "operation" }}),
            .has_registers = hasAnyAssignment(self.source, &[_][]const u8{{ "reads", "writes" }}),
            .has_condition_model = hasAnyAssignment(self.source, &[_][]const u8{{ "flags_written", "special_registers" }}),
        }};
    }}

    pub fn validate(self: InstructionTable) void {{
        const meta = self.metadata();
        runtime_abi.isa.validatePpcTable(.{{
            .name = meta.name,
            .mnemonic = meta.mnemonic,
            .category = meta.category,
            .form = meta.form,
            .handler = meta.handler,
            .jit_lowering = meta.jit_lowering,
            .source_path = meta.source_path,
            .encoding_count = meta.encoding_count,
            .primary_opcode = meta.primary_opcode,
            .has_semantic = meta.has_semantic,
            .has_registers = meta.has_registers,
            .has_condition_model = meta.has_condition_model,
        }});
    }}
}};

pub const tables = blk: {{
    @setEvalBranchQuota({quota});
    break :blk [_]InstructionTable{{
{entries}
    }};
}};

pub fn tableCount() usize {{
    return tables.len;
}}

pub fn findByName(name: []const u8) ?InstructionTable {{
    for (tables) |table| {{
        if (std.mem.eql(u8, table.metadata().name, name)) return table;
    }}
    return null;
}}

pub fn findByPath(path: []const u8) ?InstructionTable {{
    for (tables) |table| {{
        if (std.mem.eql(u8, table.path, path)) return table;
    }}
    return null;
}}

pub fn validateAll() void {{
    for (tables) |table| table.validate();
}}

fn entry(family: []const u8, path: []const u8, source: []const u8) InstructionTable {{
    return .{{ .family = family, .path = path, .source = source }};
}}

{helpers}

test "PPC ISA tables expose required metadata" {{
    try std.testing.expectEqual(@as(usize, {count}), tableCount());
    runtime_abi.isa.init();
    defer runtime_abi.isa.deinit();
    validateAll();
    const add = (findByName("addx") orelse return error.MissingAdd).metadata();
    try std.testing.expectEqualStrings("ppc_addx", add.handler);
    try std.testing.expectEqualStrings("add", add.mnemonic);
    try std.testing.expectEqual(@as(u8, 31), add.primary_opcode);
    try std.testing.expect(add.encoding_count >= 1);
}}

test "every PPC table names a real primary opcode and a handler" {{
    for (tables) |table| {{
        const meta = table.metadata();
        try std.testing.expect(meta.primary_opcode <= 63);
        try std.testing.expect(meta.handler.len > 0);
        try std.testing.expect(meta.encoding_count >= 1);
        try std.testing.expect(meta.has_semantic);
    }}
}}
'''

NEON_ROOT_TEMPLATE = '''const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const ppc = @import("../../../ppc/Zig/root.zig");

// Generated by tools/gen_ppc_isa.py from tools/ppc_isa_spec.txt. Do not edit by hand.

{imports}

pub const LoweringKind = enum {{
    arm64_scalar,
    neon_vector,
    neon_scalar,
    system_dispatch,
    fallback,
}};

pub const MirrorTable = struct {{
    path: []const u8,
    source: []const u8,

    pub fn name(self: MirrorTable) []const u8 {{
        return stringAssignment(self.source, "name") orelse mnemonicFromPath(self.path);
    }}

    pub fn ppcTablePath(self: MirrorTable) []const u8 {{
        return stringAssignment(self.source, "ppc_table") orelse self.path;
    }}

    pub fn neonLowering(self: MirrorTable) []const u8 {{
        return anyStringAssignment(self.source, &[_][]const u8{{ "neon_lowering", "jit_lowering", "arm64_lowering" }}) orelse "arm64_documented_contract_fallback";
    }}

    pub fn loweringKind(self: MirrorTable) LoweringKind {{
        const raw = stringAssignment(self.source, "lowering_kind") orelse "fallback";
        if (std.mem.eql(u8, raw, "arm64_scalar")) return .arm64_scalar;
        if (std.mem.eql(u8, raw, "neon_vector")) return .neon_vector;
        if (std.mem.eql(u8, raw, "neon_scalar")) return .neon_scalar;
        if (std.mem.eql(u8, raw, "system_dispatch")) return .system_dispatch;
        return .fallback;
    }}

    pub fn encodingCount(self: MirrorTable) usize {{
        return countEncodingRows(self.source);
    }}

    pub fn hasSemantic(self: MirrorTable) bool {{
        return hasAnyAssignment(self.source, &[_][]const u8{{ "semantic", "operation" }});
    }}

    pub fn hasRegisters(self: MirrorTable) bool {{
        return hasAnyAssignment(self.source, &[_][]const u8{{ "reads", "writes" }});
    }}

    pub fn hasConditionModel(self: MirrorTable) bool {{
        return hasAnyAssignment(self.source, &[_][]const u8{{ "flags_written", "special_registers" }});
    }}

    pub fn hasNeonRegisterModel(self: MirrorTable) bool {{
        return hasAssignment(self.source, "neon_register_model");
    }}

    pub fn hasNeonFlagModel(self: MirrorTable) bool {{
        return hasAssignment(self.source, "neon_flag_model");
    }}

    pub fn hasNeonAssembly(self: MirrorTable) bool {{
        return hasAssignment(self.source, "neon_assembly");
    }}

    pub fn assembly(self: MirrorTable) []const u8 {{
        return blockAssignment(self.source, "neon_assembly") orelse "";
    }}
}};

pub const LoweringPlan = struct {{
    ppc_name: []const u8,
    ppc_lowering: []const u8,
    kind: LoweringKind,
    assembly: []const u8,
    can_lower: bool,
}};

pub const mirror_tables = blk: {{
    @setEvalBranchQuota({quota});
    break :blk [_]MirrorTable{{
{entries}
    }};
}};

pub fn tableCount() usize {{
    return mirror_tables.len;
}}

pub fn findMirror(path: []const u8) ?MirrorTable {{
    for (mirror_tables) |table| {{
        if (std.mem.eql(u8, table.path, path)) return table;
    }}
    return null;
}}

pub fn planFor(table: ppc.InstructionTable) LoweringPlan {{
    const meta = table.metadata();
    const mirror_table = findMirror(table.path) orelse return .{{
        .ppc_name = meta.name,
        .ppc_lowering = meta.jit_lowering,
        .kind = .fallback,
        .assembly = "",
        .can_lower = false,
    }};
    const kind = mirror_table.loweringKind();
    // A system_dispatch lowering is architecturally a call into the Rosette
    // runtime (sc, mtspr, mfcr), not a direct instruction lowering, so it is
    // validated as a helper body rather than as inline ARM64 like .fallback is.
    return .{{
        .ppc_name = meta.name,
        .ppc_lowering = meta.jit_lowering,
        .kind = kind,
        .assembly = mirror_table.assembly(),
        .can_lower = kind != .fallback and kind != .system_dispatch,
    }};
}}

pub fn validateAll() void {{
    runtime_abi.isa.validatePpcMirrorTableCounts(ppc.tableCount(), tableCount());
    for (ppc.tables) |table| validateTable(table);
}}

pub fn validateTable(table: ppc.InstructionTable) void {{
    const meta = table.metadata();
    const mirror_table = findMirror(table.path) orelse {{
        runtime_abi.isa.validateMissingPpcNeonMirror(table.path);
        return;
    }};
    runtime_abi.isa.validatePpcNeonMirror(.{{
        .ppc_path = table.path,
        .neon_path = mirror_table.path,
        .declared_ppc_table = mirror_table.ppcTablePath(),
        .ppc_name = meta.name,
        .neon_name = mirror_table.name(),
        .ppc_lowering = meta.jit_lowering,
        .neon_lowering = mirror_table.neonLowering(),
        .ppc_encoding_count = meta.encoding_count,
        .neon_encoding_count = mirror_table.encodingCount(),
        .ppc_has_semantic = meta.has_semantic,
        .neon_has_semantic = mirror_table.hasSemantic(),
        .ppc_has_registers = meta.has_registers,
        .neon_has_registers = mirror_table.hasRegisters(),
        .ppc_has_condition_model = meta.has_condition_model,
        .neon_has_condition_model = mirror_table.hasConditionModel(),
        .neon_has_register_model = mirror_table.hasNeonRegisterModel(),
        .neon_has_flag_model = mirror_table.hasNeonFlagModel(),
        .neon_has_assembly = mirror_table.hasNeonAssembly(),
    }});

    const plan = planFor(table);
    runtime_abi.isa.validatePpcNeonLowering(.{{
        .name = plan.ppc_name,
        .jit_lowering = plan.ppc_lowering,
        .kind = @tagName(plan.kind),
        .assembly = plan.assembly,
        .can_lower = plan.can_lower,
    }});
}}

fn mirror(family: []const u8, path: []const u8, source: []const u8) MirrorTable {{
    _ = family;
    return .{{ .path = path, .source = source }};
}}

{helpers}

test "NEON mirrors every PPC instruction table" {{
    try std.testing.expectEqual(ppc.tableCount(), tableCount());
    runtime_abi.isa.init();
    defer runtime_abi.isa.deinit();
    validateAll();
    const add = ppc.findByName("addx") orelse return error.MissingAdd;
    const plan = planFor(add);
    try std.testing.expectEqual(LoweringKind.arm64_scalar, plan.kind);
    try std.testing.expect(std.mem.indexOf(u8, plan.assembly, "add") != null);
}}

test "every PPC mirror carries an ARM64 lowering body" {{
    for (mirror_tables) |table| {{
        try std.testing.expect(table.hasNeonRegisterModel());
        try std.testing.expect(table.hasNeonFlagModel());
        try std.testing.expect(table.hasNeonAssembly());
        try std.testing.expect(table.assembly().len > 0);
    }}
}}
'''

HELPERS = r'''
fn stripLineComment(line: []const u8) []const u8 {
    if (std.mem.indexOf(u8, line, "//")) |idx| return line[0..idx];
    return line;
}

fn assignmentName(line: []const u8) ?[]const u8 {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    const name = std.mem.trim(u8, line[0..eq], " \t");
    if (name.len == 0) return null;
    for (name) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or ch == '_';
        if (!ok) return null;
    }
    return name;
}

fn stringAssignment(source: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        const name = assignmentName(line) orelse continue;
        if (!std.mem.eql(u8, name, key)) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (value.len < 2 or value[0] != '"') continue;
        const end = std.mem.indexOfScalar(u8, value[1..], '"') orelse continue;
        return value[1 .. 1 + end];
    }
    return null;
}

fn anyStringAssignment(source: []const u8, keys: []const []const u8) ?[]const u8 {
    for (keys) |key| if (stringAssignment(source, key)) |value| return value;
    return null;
}

fn numberAssignment(source: []const u8, key: []const u8) ?u8 {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        const name = assignmentName(line) orelse continue;
        if (!std.mem.eql(u8, name, key)) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        return std.fmt.parseInt(u8, value, 10) catch null;
    }
    return null;
}

fn hasAssignment(source: []const u8, key: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        const name = assignmentName(line) orelse continue;
        if (std.mem.eql(u8, name, key)) return true;
    }
    return false;
}

fn hasAnyAssignment(source: []const u8, keys: []const []const u8) bool {
    for (keys) |key| if (hasAssignment(source, key)) return true;
    return false;
}

fn blockAssignment(source: []const u8, key: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, source, key) orelse return null;
    const open_rel = std.mem.indexOf(u8, source[start..], "\"\"\"") orelse return null;
    const body_start = start + open_rel + 3;
    const close_rel = std.mem.indexOf(u8, source[body_start..], "\"\"\"") orelse return null;
    return std.mem.trim(u8, source[body_start .. body_start + close_rel], " \t\r\n");
}

fn countEncodingRows(source: []const u8) usize {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var in_block = false;
    var count: usize = 0;
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        if (!in_block) {
            const name = assignmentName(line) orelse continue;
            if (!std.mem.eql(u8, name, "encodings")) continue;
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const rhs = std.mem.trim(u8, line[eq + 1 ..], " \t");
            if (rhs.len == 0 or rhs[0] != '[') continue;
            in_block = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "{")) {
            count += 1;
            continue;
        }
        if (line.len >= 1 and line[0] == ']') break;
    }
    return count;
}

fn mnemonicFromPath(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse 0;
    const start = if (path[slash] == '/') slash + 1 else slash;
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse path.len;
    return path[start..dot];
}
'''


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def main():
    spec = load_spec()
    spec.sort(key=lambda i: (classify(i), i.mnem))

    ppc_imports, ppc_entries = [], []
    neon_imports, neon_entries = [], []
    groups = {}

    for insn in spec:
        group = classify(insn)
        groups.setdefault(group, []).append(insn.mnem)
        name = insn.mnem
        leaf = name.upper()
        var = ident(group, name)

        source_body = render_source_inc(insn, group)
        write(os.path.join(PPC_DIR, group, leaf + ".inc"), source_body)
        write(os.path.join(PPC_DIR, "Zig", group, leaf + ".zig"),
              zig_bridge(group, name, "../../", group))
        ppc_imports.append('const %s = @import("%s/%s.zig");' % (var, group, leaf))
        ppc_entries.append("        entry(%s.family, %s.path, %s.source),"
                           % (var, var, var))

        mirror_body = render_mirror_inc(insn, group, source_body)
        write(os.path.join(NEON_DIR, group, leaf + ".inc"), mirror_body)
        write(os.path.join(NEON_DIR, "Zig", group, leaf + ".zig"),
              zig_bridge(group, name, "../../", group))
        neon_imports.append('const %s = @import("%s/%s.zig");' % (var, group, leaf))
        neon_entries.append("        mirror(%s.family, %s.path, %s.source),"
                            % (var, var, var))

    quota = max(20000, len(spec) * 60)
    write(os.path.join(PPC_DIR, "Zig", "root.zig"),
          PPC_ROOT_TEMPLATE.format(imports="\n".join(ppc_imports),
                                   entries="\n".join(ppc_entries),
                                   helpers=HELPERS.strip(),
                                   quota=quota,
                                   count=len(spec)))
    write(os.path.join(NEON_DIR, "Zig", "root.zig"),
          NEON_ROOT_TEMPLATE.format(imports="\n".join(neon_imports),
                                    entries="\n".join(neon_entries),
                                    helpers=HELPERS.strip(),
                                    quota=quota))

    print("instructions: %d" % len(spec))
    for group in sorted(groups):
        print("  %-22s %3d" % (group, len(groups[group])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
