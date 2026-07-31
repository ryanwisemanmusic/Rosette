// ACCUMULATE/CRC32.inc
// ARM64/NEON mirror generated from ISA/x86/ACCUMULATE/CRC32.inc.
// Source contract: CRC32 — crc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ACCUMULATE/CRC32.inc"
x86_handler = "x86_crc32"
neon_lowering = "arm64_crc32"
lowering_kind = "arm64_documented_contract"

name = "CRC32"
aliases = []
category = "crc"
feature = "sse4_2"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "F2 0F 38 F0 /r", form = "CRC32 r32, r/m8", op_en = "RM", feature = "sse4_2", vector_length = 0, encoding = "legacy" }
  { opcode = "F2 0F 38 F1 /r", form = "CRC32 r32, r/m16", op_en = "RM", feature = "sse4_2", vector_length = 0, encoding = "legacy" }
  { opcode = "F2 0F 38 F1 /r", form = "CRC32 r32, r/m32", op_en = "RM", feature = "sse4_2", vector_length = 0, encoding = "legacy" }
  { opcode = "F2 REX.W 0F 38 F0 /r", form = "CRC32 r64, r/m8", op_en = "RM", feature = "sse4_2", vector_length = 0, encoding = "legacy" }
  { opcode = "F2 REX.W 0F 38 F1 /r", form = "CRC32 r64, r/m64", op_en = "RM", feature = "sse4_2", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Accumulate CRC32 Value.
"""

handler = "x86_crc32"
jit_lowering = "arm64_crc32"
fallback = "zig_crc32"

neon_register_model = """
CRC32 is a crc instruction.
"""

neon_flag_model = """
CRC32 does not modify flags.
"""

neon_assembly = """
// NEON lowering: CRC32 stub (crc)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

