// EXAMINE/FXAM.inc
// Source contract: FXAM — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXAMINE/FXAM.inc"
x86_handler = "x86_fxam"
neon_lowering = "arm64_fxam"
lowering_kind = "arm64_documented_contract"

name = "FXAM"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f32_f64_f80"
element_size = 80

encodings = [
  { opcode = "D9 E5", form = "FXAM", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["C0", "C1", "C2", "C3"]
simd_fp_exceptions = []

semantic_general = """
Examine the contents of ST(0) and set condition code flags.
"""

handler = "x86_fxam"
jit_lowering = "arm64_fxam"
fallback = "zig_fxam"

neon_register_model = """
FXAM is a x87_fpu instruction.
"""

neon_flag_model = """
FXAM writes C0, C1, C2, C3.
"""

neon_assembly = """
// NEON lowering: x87 FPU examine stub (FPU classification)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
