// VPERMPD.inc
// Permute double-precision floating-point elements across the full vector.

operand_encoding = [
  { op_en = "A", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPERMPD: permute double-precision floating-point elements across the full vector using either an immediate or a vector index.
Category: simd_float_permute_full.
"""

name = "VPERMPD"
category = "simd_float_permute_full"
feature = "AVX2"
element_type = "f64"
legacy_width = 256
lanes_128 = 0
lanes_256 = 4
lanes_512 = 8
mxcsr_used = false

encodings = [
  { opcode = "VEX.256.66.0F3A.W1 01 /r ib", form = "VPERMPD ymm1, ymm2, ymm3/m256, imm8", op_en = "A", feature = "AVX2", mode = "V/V", handler = "x86_vpermpd_ymm_ymm_ymmm256_imm8" },
  { opcode = "EVEX.256.66.0F3A.W1 01 /r ib", form = "VPERMPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "B", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermpd_evex256_imm" },
  { opcode = "EVEX.512.66.0F3A.W1 01 /r ib", form = "VPERMPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst{er}, imm8", op_en = "B", feature = "AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermpd_evex512_imm" },
  { opcode = "EVEX.256.66.0F38.W1 16 /r", form = "VPERMPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermpd_evex256_var" },
  { opcode = "EVEX.512.66.0F38.W1 16 /r", form = "VPERMPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst{er}", op_en = "C", feature = "AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermpd_evex512_var" },
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "B", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
N/A
"""

semantic_vex_128 = """
N/A
"""

semantic_vex_256 = """
DEST.f64[i] = SRC2.f64[imm8[2*i+1:2*i]];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f64 lane selected by k1 or no writemask:
    DEST.f64[i] = SRC2.f64[imm8[2*i+1:2*i]];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["VEX Type 4 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_vpermpd"
jit_lowering = "arm64_neon_tbl"
