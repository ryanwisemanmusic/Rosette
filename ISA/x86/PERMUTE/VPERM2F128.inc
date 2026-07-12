// VPERM2F128.inc
// Permute 128-bit lanes of packed single-precision floating-point values.

operand_encoding = [
  { op_en = "RVMI", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "see preserved_source_contract" },
]
semantic = """
VPERM2F128: permute 128-bit lanes of packed f32 values from two 256-bit operands using an 8-bit immediate.
Category: simd_float_permute_128bit_lane.
"""

name = "VPERM2F128"
category = "simd_float_permute_128bit_lane"
feature = "AVX"
element_type = "f32"
legacy_width = 256
lanes_128 = 4
lanes_256 = 4
lanes_512 = 0
mxcsr_used = false

encodings = [
  { opcode = "VEX.256.66.0F3A.W0 06 /r ib", form = "VPERM2F128 ymm1, ymm2, ymm3/m256, imm8", op_en = "RVMI", feature = "AVX", mode = "V/V", handler = "x86_vperm2f128_ymm_ymm_ymmm256_imm8" },
]

operand_encodings = [
  { op_en = "RVMI", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

semantic_legacy = """
N/A
"""

semantic_vex_128 = """
N/A
"""

semantic_vex_256 = """
DEST.f32[0..3] = (imm8[0] == 0) ? SRC1.f32[0..3] : SRC1.f32[4..7];
DEST.f32[4..7] = (imm8[1] == 0) ? SRC2.f32[0..3] : SRC2.f32[4..7];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
N/A
"""

simd_fp_exceptions = ["invalid"]
other_exceptions = ["VEX Type 4 class exceptions"]

handler = "x86_vperm2f128"
jit_lowering = "arm64_neon_tbl"
