// COMPUTE/FYL2X.inc
// ARM64/NEON translation mirror generated from ISA/x86/COMPUTE/FYL2X.inc.
// Source contract: FYL2X — Compute y * log2(x).

semantic = """
FYL2X: preserve the operation and form-specific semantic blocks.
Category: x87_fpu.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/FYL2X.inc"
x86_handler = "x86_fyl2x"
neon_lowering = "arm64_fyl2x"
lowering_kind = "arm64_fpu"

name = "FYL2X"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "D9 F1", form = "FYL2X", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
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
ST(1) := ST(1) * log2(ST(0));
Pop stack;
Result is in ST(0) after pop.
"""

handler = "x86_fyl2x"
jit_lowering = "arm64_fyl2x"
fallback = "zig_fyl2x"

neon_register_model = """
x87 FP stack mapped to ARM64 register file via soft-float emulation.
FYL2X requires transcendental log2 and multiply in software.
"""

neon_flag_model = """
C1 set to 0 if stack underflow occurred. C0, C2, C3 undefined.
"""

neon_assembly = """
// NEON lowering: soft-float y * log2(x) computation (no direct ARM64 instruction).
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "No direct ARM64/NEON hardware instruction; uses software emulation via polynomial approximation."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
