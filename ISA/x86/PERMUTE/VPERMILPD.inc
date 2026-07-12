// VPERMILPD.inc
// Permute in-lane double-precision floating-point values.

operand_encoding = [
  { op_en = "A", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
  { op_en = "D", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPERMILPD: permute in-lane double-precision floating-point values using either a vector index or an immediate.
Category: simd_float_permute_inlane.
"""

name = "VPERMILPD"
category = "simd_float_permute_inlane"
feature = "AVX"
element_type = "f64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = false

encodings = [
  { opcode = "VEX.128.66.0F38.W0 0D /r", form = "VPERMILPD xmm1, xmm2, xmm3/m128", op_en = "A", feature = "AVX", mode = "V/V", handler = "x86_vpermilpd_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F38.W0 0D /r", form = "VPERMILPD ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX", mode = "V/V", handler = "x86_vpermilpd_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F38.W1 0D /r", form = "VPERMILPD xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermilpd_evex128" },
  { opcode = "EVEX.256.66.0F38.W1 0D /r", form = "VPERMILPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermilpd_evex256" },
  { opcode = "EVEX.512.66.0F38.W1 0D /r", form = "VPERMILPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst{er}", op_en = "C", feature = "AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermilpd_evex512" },
  { opcode = "VEX.128.66.0F3A.W0 05 /r ib", form = "VPERMILPD xmm1, xmm2, xmm3/m128, imm8", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpermilpd_xmm_xmm_xmmm128_imm8" },
  { opcode = "VEX.256.66.0F3A.W0 05 /r ib", form = "VPERMILPD ymm1, ymm2, ymm3/m256, imm8", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpermilpd_ymm_ymm_ymmm256_imm8" },
  { opcode = "EVEX.128.66.0F3A.W1 05 /r ib", form = "VPERMILPD xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "D", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermilpd_evex128_imm" },
  { opcode = "EVEX.256.66.0F3A.W1 05 /r ib", form = "VPERMILPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "D", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermilpd_evex256_imm" },
  { opcode = "EVEX.512.66.0F3A.W1 05 /r ib", form = "VPERMILPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst{er}, imm8", op_en = "D", feature = "AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermilpd_evex512_imm" },
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "D", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

semantic_legacy = """
N/A
"""

semantic_vex_128 = """
for each i in 0..1:
    DEST.f64[i] = SRC2.f64[SRC1.f64[i] mod 2];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for each i in 0..3:
    DEST.f64[i] = SRC2.f64[SRC1.f64[i] mod 2];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f64 lane selected by k1 or no writemask:
    DEST.f64[i] = SRC2.f64[SRC1.f64[i] mod 2];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_vpermilpd"
jit_lowering = "arm64_neon_tbl"
