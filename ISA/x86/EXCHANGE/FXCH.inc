// EXCHANGE/FXCH.inc
// Source contract: FXCH — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXCHANGE/FXCH.inc"
x86_handler = "x86_fxch"
neon_lowering = "arm64_fxch"
lowering_kind = "arm64_documented_contract"

name = "FXCH"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f32_f64_f80"
element_size = 80

encodings = [
  { opcode = "D9 C8+i", form = "FXCH ST(i)", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" },
  { opcode = "D9 C9", form = "FXCH", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["C1"]
simd_fp_exceptions = []

semantic_general = """
Exchange the contents of ST(0) and ST(i).
"""

handler = "x86_fxch"
jit_lowering = "arm64_fxch"
fallback = "zig_fxch"

neon_register_model = """
x86 GPR/x87 FPU mapped to ARM64 equivalents. FXCH is a x87_fpu instruction.
"""

neon_flag_model = """
FXCH writes C1.
"""

neon_assembly = """
// NEON lowering: x87 FPU register exchange stub (not supported on ARM64)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
