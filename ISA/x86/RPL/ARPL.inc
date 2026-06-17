// RPL/ARPL.inc
// Source contract: ARPL — protection.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RPL/ARPL.inc"
x86_handler = "x86_arpl"
neon_lowering = "arm64_arpl"
lowering_kind = "arm64_documented_contract"

name = "ARPL"
aliases = []
category = "protection"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "63 /r", form = "ARPL r/m16, r16", op_en = "MR", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  MR = []
}

flags_affected = ['ZF']

simd_fp_exceptions = []

semantic_general = """
Adjust RPL field of segment selector.
"""

handler = "x86_arpl"
jit_lowering = "arm64_arpl"
fallback = "zig_arpl"

neon_register_model = """
ARPL is a system-level instruction.
"""

neon_flag_model = """
ARPL affects: ZF.
"""

neon_assembly = """
// NEON lowering: ARPL stub (protection)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
