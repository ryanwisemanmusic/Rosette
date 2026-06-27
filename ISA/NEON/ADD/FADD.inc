// ADD/FADD.inc
// ARM64/NEON mirror generated from ISA/x86/ADD/FADD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/FADD.inc"
x86_handler = "x86_fadd"
neon_lowering = "arm64_fadd"
lowering_kind = "arm64_documented_contract"

// ADD/FADD.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/FADD.inc.
// Source contract: FADD — Add (x87 FPU).

semantic = """
DEST := DEST + SRC
"""

name = "FADD"
aliases = ["FADDP"]
category = "floating_point_add"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D8 /0", form = "FADD m32fp", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DC /0", form = "FADD m64fp", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "D8 C0+i", form = "FADD ST(0), ST(i)", op_en = "RR", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DC C0+i", form = "FADD ST(i), ST(0)", op_en = "RR", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DE C0+i", form = "FADDP ST(i), ST(0)", op_en = "RR", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DE C1", form = "FADDP", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"],
  RR = ["ST(i) (r,w)", "ST(0) (r)"],
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if SNaN or unlike-sign infinities",
  "#D if denormal source",
  "#U if result too small",
  "#O if result too large",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
DEST := DEST + SRC;
If FADDP: PopRegisterStack;
"""
