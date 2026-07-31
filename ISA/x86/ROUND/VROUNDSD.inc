// ROUND/VROUNDSD.inc
// Source contract: VROUNDSD — simd_round.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROUND/VROUNDSD.inc"
x86_handler = "x86_vroundsd"
neon_lowering = "arm64_vroundsd"
lowering_kind = "arm64_documented_contract"

name = "VROUNDSD"
aliases = []
category = "simd_round"
feature = "avx"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F3A 0B /r ib", form = "VROUNDSD xmm1, xmm2, xmm3/m64, imm8", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}
simd_fp_exceptions = []

semantic_general = """
Round Scalar Double-Precision Floating-Point Values.
"""

handler = "x86_vroundsd"
jit_lowering = "arm64_vroundsd"
fallback = "zig_vroundsd"

neon_register_model = """
VROUNDSD is a simd_round instruction.
"""

neon_flag_model = """
VROUNDSD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VROUNDSD stub (simd_round)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

