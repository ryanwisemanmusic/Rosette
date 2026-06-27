// PARTIAL/FPATAN.inc
// ARM64/NEON translation mirror generated from ISA/x86/PARTIAL/FPATAN.inc.
// Source contract: FPATAN — Partial Arctangent.

semantic = """
ST(1) := arctan(ST(1) / ST(0));
PopRegisterStack;
"""

source_isa = "x86"
target_isa = "arm64_neon"
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

handler = "x86_fpatan"
jit_lowering = "arm64_fpatan"
fallback = "zig_fpatan"

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. FPATAN is a scalar x87 transcendental operation.
"""

neon_flag_model = """
ARM64 does not directly update x87 C flags. C1 tracking may require separate flag management.
"""

neon_assembly = """
// NEON lowering: software-emulated x87 transcendental via ARM64 FPU or runtime helper.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
