// ENCODE/ENCODEKEY128.inc
// ARM64/NEON mirror generated from ISA/x86/ENCODE/ENCODEKEY128.inc.
// Source contract: ENCODEKEY128 — aes_kle.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ENCODE/ENCODEKEY128.inc"
x86_handler = "x86_encodekey128"
neon_lowering = "arm64_encodekey128"
lowering_kind = "arm64_documented_contract"

name = "ENCODEKEY128"
aliases = []
category = "aes_kle"
feature = "aes_kle"
element_type = "i8"
element_size = 8

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Encode 128-bit AES key.
"""

handler = "x86_encodekey128"
jit_lowering = "arm64_encodekey128"
fallback = "zig_encodekey128"

neon_register_model = """
ENCODEKEY128 is a aes_kle instruction.
"""

neon_flag_model = """
ENCODEKEY128 does not modify flags.
"""

neon_assembly = """
// NEON lowering: ENCODEKEY128 stub (aes_kle)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

