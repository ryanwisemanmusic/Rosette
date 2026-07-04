// FULL_PERMUTE/VPERMT2D.inc
// ARM64/NEON mirror generated from ISA/x86/FULL_PERMUTE/VPERMT2D.inc.
// Source contract: VPERMT2D — Full Permute of Dwords From Two Tables Overwriting One Table.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FULL_PERMUTE/VPERMT2D.inc"
x86_handler = "x86_vpermt2d"
neon_lowering = "arm64_vpermt2d"
lowering_kind = "arm64_documented_contract"

name = "VPERMT2D"
aliases = []
category = "simd_permute"
feature = "AVX512F_AVX512VL"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 7E /r", form = "VPERMT2D xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.256.66.0F38.W0 7E /r", form = "VPERMT2D ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.512.66.0F38.W0 7E /r", form = "VPERMT2D zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m32bcst" }
]

operand_encoding = { B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"] }

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-50, Type E4NF Class Exception Conditions."
]

semantic_general = """
VPERMT2D permutes dwords from two tables using index in SRC1, overwriting one table.
"""

handler = "x86_vpermt2d"
jit_lowering = "arm64_vpermt2d"
fallback = "zig_vpermt2d"

neon_register_model = "VPERMT2D is an AVX512F/VL SIMD permute instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPERMT2D stub"

neon_notes = [
  "VPERMT2D permutes dwords from two tables; ARM64: TBL/TBX.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
