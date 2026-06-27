// ABSOLUTE/FABS.inc
// ARM64/NEON translation mirror.
// Source contract: FABS — Absolute Value.

semantic = """
ST(0) := |ST(0)|
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "ABSOLUTE/FABS.inc"

name = "FABS"
aliases = []
category = "floating_point_absolute"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D9 E1", form = "FABS", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
ST(0) := |ST(0)|;
"""
