// SERIALIZE/SERIALIZE.inc
// Source contract: SERIALIZE — serialization.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SERIALIZE/SERIALIZE.inc"
x86_handler = "x86_serialize"
neon_lowering = "arm64_serialize"
lowering_kind = "arm64_documented_contract"

name = "SERIALIZE"
aliases = []
category = "serialization"
feature = "serialize"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "NP 0F 01 E8", form = "SERIALIZE ", op_en = "ZO", feature = "serialize", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Serialize instruction execution — drain all buffered writes.
"""

handler = "x86_serialize"
jit_lowering = "arm64_serialize"
fallback = "zig_serialize"

neon_register_model = """
SERIALIZE is a system-level instruction.
"""

neon_flag_model = """
SERIALIZE does not modify flags.
"""

neon_assembly = """
// NEON lowering: SERIALIZE stub (serialization)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
