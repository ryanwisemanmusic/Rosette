// VPERMB.inc
// Permute byte elements in a vector using a byte-index vector.

operand_encoding = [
  { op_en = "A", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPERMB: permute byte elements in a vector using a byte-index control vector.
Category: simd_integer_permute_var.
"""

name = "VPERMB"
category = "simd_integer_permute_var"
feature = "AVX512_VBMI"
element_type = "i8"
legacy_width = 128
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64
mxcsr_used = false

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 8D /r", form = "VPERMB xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512VL AVX512_VBMI", mode = "V/V", tuple = "Full Mem", handler = "x86_vpermb_xmm_xmm_xmmm128" },
  { opcode = "EVEX.256.66.0F38.W0 8D /r", form = "VPERMB ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512VL AVX512_VBMI", mode = "V/V", tuple = "Full Mem", handler = "x86_vpermb_ymm_ymm_ymmm256" },
  { opcode = "EVEX.512.66.0F38.W0 8D /r", form = "VPERMB zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512_VBMI", mode = "V/V", tuple = "Full Mem", handler = "x86_vpermb_zmm_zmm_zmmm512" },
]

operand_encodings = [
  { op_en = "A", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
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
for each i in 0..VL/8-1:
    DEST.i8[i] = SRC2.i8[SRC1.i8[i] mod (VL/8)];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["EVEX Type E4NF class exceptions"]

handler = "x86_vpermb"
jit_lowering = "arm64_neon_tbl"
