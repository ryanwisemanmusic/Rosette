// PARTIAL/FPREM.inc
// ARM64/NEON translation mirror.
// Source contract: FPREM — Partial Remainder.

semantic = """
Q := Integer(TruncateTowardZero(ST(0) / ST(1)));
ST(0) := ST(0) - (ST(1) * Q);
C2 := 0;
C0, C3, C1 := LeastSignificantBits(Q);
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "PARTIAL/FPREM.inc"
x86_handler = "x86_fprem"
neon_lowering = "arm64_fprem"
lowering_kind = "arm64_scalar"

name = "FPREM"
aliases = []
category = "floating_point_transcendental"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D9 F8", form = "FPREM", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
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
ST(0) := ST(0) - (Q * ST(1)) where Q = truncate_toward_zero(ST(0) / ST(1));
"""

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. FPREM is a scalar x87 remainder operation.
"""

neon_flag_model = """
ARM64 does not directly update x87 C flags. C0/C1/C2/C3 tracking is explicit in the software x87 state.
"""

neon_assembly = """
// NEON lowering: software-emulated x87 remainder via an ARM64 runtime helper.
"""
