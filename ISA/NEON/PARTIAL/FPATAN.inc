// PARTIAL/FPATAN.inc
// ARM64/NEON translation mirror.
// Source contract: FPATAN — Partial Arctangent.

semantic = """
ST(1) := arctan(ST(1) / ST(0));
PopRegisterStack;
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "PARTIAL/FPATAN.inc"
x86_handler = "x86_fpatan"
neon_lowering = "arm64_fpatan"
lowering_kind = "arm64_scalar"

name = "FPATAN"
aliases = []
category = "floating_point_transcendental"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D9 F3", form = "FPATAN", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow/overflow",
  "#IA if SNaN or unsupported format",
  "#D if denormal source",
  "#U if result too small",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
ST(1) := arctan(ST(1) / ST(0));
PopRegisterStack;
"""

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. FPATAN is a scalar x87 transcendental operation.
"""

neon_flag_model = """
ARM64 does not directly update x87 C flags. C1 tracking may require separate flag management.
"""

neon_assembly = """
// NEON lowering: software-emulated x87 transcendental via ARM64 FPU or runtime helper.
"""
