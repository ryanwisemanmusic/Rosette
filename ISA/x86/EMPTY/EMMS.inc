// EMPTY/EMMS.inc
// Source contract: EMMS — mmx.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EMPTY/EMMS.inc"
x86_handler = "x86_emms"
neon_lowering = "arm64_emms"
lowering_kind = "arm64_documented_contract"

name = "EMMS"
aliases = []
category = "mmx"
feature = "MMX"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 77", form = "EMMS", op_en = "ZO", feature = "MMX", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Set the x87 FPU tag word to empty, clearing MMX state.
"""

handler = "x86_emms"
jit_lowering = "arm64_emms"
fallback = "zig_emms"

neon_register_model = """
EMMS is a mmx instruction.
"""

neon_flag_model = """
No x86 flags modified by EMMS.
"""

neon_assembly = """
// NEON lowering: no-op (ARM64 has no x87 FPU tag word)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
