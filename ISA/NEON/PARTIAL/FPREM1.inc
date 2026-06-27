// PARTIAL/FPREM1.inc
// ARM64/NEON translation mirror.
// Source contract: FPREM1 — IEEE Partial Remainder.

semantic = """
Q := Integer(RoundTowardNearestInteger(ST(0) / ST(1)));
ST(0) := ST(0) - (ST(1) * Q);
C2 := 0;
C0, C3, C1 := LeastSignificantBits(Q);
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "PARTIAL/FPREM1.inc"

name = "FPREM1"
aliases = []
category = "floating_point_transcendental"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D9 F5", form = "FPREM1", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow/overflow",
  "#IA if modulus is 0 or dividend is inf",
  "#D if denormal source",
  "#U if result too small",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
ST(0) := ST(0) - (Q * ST(1)) where Q = round_nearest(ST(0) / ST(1));
"""
