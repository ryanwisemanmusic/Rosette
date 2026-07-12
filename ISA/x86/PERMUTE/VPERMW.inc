// VPERMW.inc
// Permute word elements in a vector using a word-index control vector.

operand_encoding = [
  { op_en = "C", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPERMW: permute word elements using a word-index control vector.
Category: simd_integer_permute_var.
"""

name = "VPERMW"
category = "simd_integer_permute_var"
feature = "AVX512BW"
element_type = "i16"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = false

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 8D /r", form = "VPERMW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VL AVX512BW", mode = "V/V", tuple = "Full Mem", handler = "x86_vpermw_xmm_xmm_xmmm128" },
  { opcode = "EVEX.256.66.0F38.W1 8D /r", form = "VPERMW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VL AVX512BW", mode = "V/V", tuple = "Full Mem", handler = "x86_vpermw_ymm_ymm_ymmm256" },
  { opcode = "EVEX.512.66.0F38.W1 8D /r", form = "VPERMW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", mode = "V/V", tuple = "Full Mem", handler = "x86_vpermw_zmm_zmm_zmmm512" },
]

operand_encodings = [
  { op_en = "C", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
N/A
"""

semantic_vex_128 = """
N/A
"""

semantic_vex_256 = """
N/A
"""

semantic_evex = """
for each i in 0..VL/16-1:
    DEST.i16[i] = SRC2.i16[SRC1.i16[i] mod (VL/16)];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["EVEX Type E4NF class exceptions"]

handler = "x86_vpermw"
jit_lowering = "arm64_neon_tbl"
