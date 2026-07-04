// DIV/FIDIV.inc
// ARM64/NEON mirror generated from ISA/x86/DIV/FIDIV.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DIV/FIDIV.inc"
x86_handler = "x86_fidiv"
neon_lowering = "arm64_fidiv"
lowering_kind = "arm64_documented_contract"

// DIV/FIDIV.inc
// ARM64/NEON translation mirror generated from ISA/x86/DIV/FIDIV.inc.
// Source contract: FIDIV — Divide Integer to FPU.

semantic = """
DEST := DEST / ConvertToDoubleExtendedPrecisionFP(SRC)
"""

name = "FIDIV"
category = "floating_point_div"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "DA /6", form = "FIDIV m32int", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DE /6", form = "FIDIV m16int", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if SNaN or unlike-sign infinities or zero-divide",
  "#D if denormal source",
  "#U if result too small",
  "#O if result too large",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
DEST := DEST / ConvertToDoubleExtendedPrecisionFP(SRC);
"""
