// VPERMPS.inc
// Permute single-precision floating-point elements across the full vector.

operand_encoding = [
  { op_en = "A", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPERMPS: permute single-precision floating-point elements across the full vector using a vector index.
Category: simd_float_permute_full.
"""

name = "VPERMPS"
category = "simd_float_permute_full"
feature = "AVX2"
element_type = "f32"
legacy_width = 256
lanes_128 = 0
lanes_256 = 8
lanes_512 = 16
mxcsr_used = false

encodings = [
  { opcode = "VEX.256.66.0F38.W0 16 /r", form = "VPERMPS ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX2", mode = "V/V", handler = "x86_vpermps_ymm_ymm_ymmm256" },
  { opcode = "EVEX.256.66.0F38.W0 16 /r", form = "VPERMPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermps_evex256" },
  { opcode = "EVEX.512.66.0F38.W0 16 /r", form = "VPERMPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst{er}", op_en = "B", feature = "AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermps_evex512" },
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "B", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
N/A
"""

semantic_vex_128 = """
N/A
"""

semantic_vex_256 = """
DEST.f32[i] = SRC2.f32[SRC1.f32[i]];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f32 lane selected by k1 or no writemask:
    DEST.f32[i] = SRC2.f32[SRC1.f32[i] mod (VL/32)];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_vpermps"
jit_lowering = "arm64_neon_tbl"
