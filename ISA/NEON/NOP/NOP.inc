// NOP/NOP.inc
// ARM64/NEON mirror generated from ISA/x86/NOP/NOP.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "NOP/NOP.inc"
x86_handler = "x86_nop"
neon_lowering = "arm64_nop"
lowering_kind = "arm64_documented_contract"

name = "NOP"
aliases = []
category = "data_transfer"
feature = "x86_gpr"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 90", form = "NOP", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "NP 0F 1F /0", form = "NOP r/m16", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "NP 0F 1F /0", form = "NOP r/m32", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
  M = ["ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
One-byte or multi-byte no-operation instruction.
"""

handler = "x86_nop"
jit_lowering = "arm64_nop"
fallback = "zig_nop"

neon_register_model = """
NOP is a data_transfer no-op. No registers modified.
"""

neon_flag_model = """
No x86 flags modified by NOP.
"""

neon_assembly = """
// NEON lowering: ARM64 NOP instruction
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
