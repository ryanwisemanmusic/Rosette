// GALOIS/GF2P8MULB.inc
// ARM64/NEON mirror generated from ISA/x86/GALOIS/GF2P8MULB.inc.
// Source contract: GF2P8MULB — gfni.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GALOIS/GF2P8MULB.inc"
x86_handler = "x86_gf2p8mulb"
neon_lowering = "arm64_gf2p8mulb"
lowering_kind = "arm64_documented_contract"

name = "GF2P8MULB"
aliases = []
category = "gfni"
feature = "gfni"
element_type = "i8"
element_size = 8

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Galois Field Multiply Bytes.
"""

handler = "x86_gf2p8mulb"
jit_lowering = "arm64_gf2p8mulb"
fallback = "zig_gf2p8mulb"

neon_register_model = """
GF2P8MULB is a gfni instruction.
"""

neon_flag_model = """
GF2P8MULB does not modify flags.
"""

neon_assembly = """
// NEON lowering: GF2P8MULB stub (gfni)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

