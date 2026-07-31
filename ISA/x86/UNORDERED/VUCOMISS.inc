// UNORDERED/VUCOMISS.inc
// Source contract: VUCOMISS — simd_compare.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNORDERED/VUCOMISS.inc"
x86_handler = "x86_vucomiss"
neon_lowering = "arm64_vucomiss"
lowering_kind = "arm64_documented_contract"

name = "VUCOMISS"
aliases = []
category = "simd_compare"
feature = "avx"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "VEX.LIG.F3.0F 2E /r", form = "VUCOMISS xmm1, xmm2/m32", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['zf', 'pf', 'cf']
simd_fp_exceptions = []

semantic_general = """
Unordered Compare Scalar Single-Precision Floating-Point Values.
"""

handler = "x86_vucomiss"
jit_lowering = "arm64_vucomiss"
fallback = "zig_vucomiss"

neon_register_model = """
VUCOMISS is a simd_compare instruction.
"""

neon_flag_model = """
VUCOMISS does not modify flags.
"""

neon_assembly = """
// NEON lowering: VUCOMISS stub (simd_compare)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

