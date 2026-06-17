// END/XEND.inc
// Source contract: XEND — transactional_memory.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "END/XEND.inc"
x86_handler = "x86_xend"
neon_lowering = "arm64_xend"
lowering_kind = "arm64_documented_contract"

name = "XEND"
aliases = []
category = "transactional_memory"
feature = "RTM"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 01 D5", form = "XEND", op_en = "A", feature = "RTM", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = []
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Marks the end of an RTM transactional code region.
"""

handler = "x86_xend"
jit_lowering = "arm64_xend"
fallback = "zig_xend"

neon_register_model = """
XEND is a transactional_memory instruction.
"""

neon_flag_model = """
No x86 flags modified by XEND.
"""

neon_assembly = """
// NEON lowering: RTM end stub (not supported on ARM64)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
