// PARTIAL/FPTAN.inc
// ARM64/NEON translation mirror.
// Source contract: FPTAN — Partial Tangent.

semantic = """
IF ST(0) < 2^63 THEN
    C2 := 0;
    ST(0) := fptan(ST(0));
    TOP := TOP - 1;
    ST(0) := 1.0;
ELSE
    C2 := 1;
FI;
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "PARTIAL/FPTAN.inc"

name = "FPTAN"
aliases = []
category = "floating_point_transcendental"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D9 F2", form = "FPTAN", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if SNaN or unsupported format",
  "#D if denormal source",
  "#U if result too small",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
ST(0) := tan(ST(0)); Push 1.0 onto stack;
"""
