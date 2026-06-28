// COMPUTE/F2XM1.inc
// ARM64/NEON translation mirror generated from ISA/x86/COMPUTE/F2XM1.inc.
// Source contract: F2XM1 — Compute 2^x - 1.

semantic = """
F2XM1: preserve the operation and form-specific semantic blocks.
Category: x87_fpu.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/F2XM1.inc"
x86_handler = "x86_f2xm1"
neon_lowering = "arm64_f2xm1"
lowering_kind = "arm64_fpu"

name = "F2XM1"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "D9 F0", form = "F2XM1", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#NM if CR0.EM or CR0.TS",
  "#IA if stack underflow",
  "#UD if LOCK prefix"
]

semantic_general = """
ST(0) := 2^ST(0) - 1;
Result value range is -1.0 to +1.0.
"""

handler = "x86_f2xm1"
jit_lowering = "arm64_f2xm1"
fallback = "zig_f2xm1"

neon_register_model = """
x87 FP stack mapped to ARM64 register file via soft-float emulation.
F2XM1 requires transcendental 2^x-1 approximation in software.
"""

neon_flag_model = """
C1 set to 0 if stack underflow occurred. C0, C2, C3 undefined.
"""

neon_assembly = """
// NEON lowering: soft-float polynomial approximation of 2^x - 1 (no direct ARM64 instruction).
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "No direct ARM64/NEON hardware instruction; uses software emulation via polynomial approximation."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
