// ADD/FADDP.inc
// ARM64/NEON mirror generated from ISA/x86/ADD/FADDP.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/FADDP.inc"
x86_handler = "x86_faddp"
neon_lowering = "arm64_faddp"
lowering_kind = "arm64_documented_contract"

// ADD/FADDP.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/FADDP.inc.
// Source contract: FADDP — Add and Pop (x87 FPU).

semantic = """
DEST := DEST + SRC;
PopRegisterStack;
"""

name = "FADDP"
category = "floating_point_add"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "DE C0+i", form = "FADDP ST(i), ST(0)", op_en = "RR", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DE C1", form = "FADDP", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
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
PopRegisterStack;
"""
