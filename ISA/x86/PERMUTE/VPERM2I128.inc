// VPERM2I128.inc
// Permute 128-bit integer lanes from two 256-bit operands using an 8-bit immediate.

operand_encoding = [
  { op_en = "RVMI", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "see preserved_source_contract" },
]
semantic = """
VPERM2I128: permute 128-bit integer lanes from two 256-bit operands using an 8-bit immediate.
Category: simd_integer_permute_128bit_lane.
"""

name = "VPERM2I128"
category = "simd_integer_permute_128bit_lane"
feature = "AVX2"
element_type = "i32"
legacy_width = 256
lanes_128 = 4
lanes_256 = 4
lanes_512 = 0
mxcsr_used = false

encodings = [
  { opcode = "VEX.256.66.0F3A.W0 46 /r ib", form = "VPERM2I128 ymm1, ymm2, ymm3/m256, imm8", op_en = "RVMI", feature = "AVX2", mode = "V/V", handler = "x86_vperm2i128_ymm_ymm_ymmm256_imm8" },
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
DEST.i32[0..3] = (imm8[0] == 0) ? SRC1.i32[0..3] : SRC1.i32[4..7];
DEST.i32[4..7] = (imm8[1] == 0) ? SRC2.i32[0..3] : SRC2.i32[4..7];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
N/A
"""

simd_fp_exceptions = []
other_exceptions = ["VEX Type 4 class exceptions"]

handler = "x86_vperm2i128"
jit_lowering = "arm64_neon_tbl"
