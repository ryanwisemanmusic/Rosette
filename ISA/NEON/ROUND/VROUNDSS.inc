// ROUND/VROUNDSS.inc
// ARM64/NEON mirror generated from ISA/x86/ROUND/VROUNDSS.inc.
// Source contract: VROUNDSS — simd_round.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROUND/VROUNDSS.inc"
x86_handler = "x86_vroundss"
neon_lowering = "arm64_vroundss"
lowering_kind = "arm64_documented_contract"

name = "VROUNDSS"
aliases = []
category = "simd_round"
feature = "avx"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F3A 0A /r ib", form = "VROUNDSS xmm1, xmm2, xmm3/m32, imm8", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Round Scalar Single-Precision Floating-Point Values.
"""

handler = "x86_vroundss"
jit_lowering = "arm64_vroundss"
fallback = "zig_vroundss"

neon_register_model = """
VROUNDSS is a simd_round instruction.
"""

neon_flag_model = """
VROUNDSS does not modify flags.
"""

neon_assembly = """
// NEON lowering: VROUNDSS stub (simd_round)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

