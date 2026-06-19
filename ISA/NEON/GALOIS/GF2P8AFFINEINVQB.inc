// GALOIS/GF2P8AFFINEINVQB.inc
// ARM64/NEON mirror generated from ISA/x86/GALOIS/GF2P8AFFINEINVQB.inc.
// Source contract: GF2P8AFFINEINVQB — gfni.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GALOIS/GF2P8AFFINEINVQB.inc"
x86_handler = "x86_gf2p8affineinvqb"
neon_lowering = "arm64_gf2p8affineinvqb"
lowering_kind = "arm64_documented_contract"

name = "GF2P8AFFINEINVQB"
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
Galois Field Affine Transformation Inverse.
"""

handler = "x86_gf2p8affineinvqb"
jit_lowering = "arm64_gf2p8affineinvqb"
fallback = "zig_gf2p8affineinvqb"

neon_register_model = """
GF2P8AFFINEINVQB is a gfni instruction.
"""

neon_flag_model = """
GF2P8AFFINEINVQB does not modify flags.
"""

neon_assembly = """
// NEON lowering: GF2P8AFFINEINVQB stub (gfni)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

