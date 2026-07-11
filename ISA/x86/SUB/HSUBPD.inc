// HSUBPD.inc
// Horizontal subtract packed double precision floating-point values.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
HSUBPD: horizontal subtract of adjacent double-precision pairs within each source.
Category: simd_float_horizontal_subtract.
"""

name = "HSUBPD"
category = "simd_float_horizontal_subtract"
feature = "SSE3"
element_type = "f64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
mxcsr_used = true

encodings = [
  { opcode = "66 0F 7D /r", form = "HSUBPD xmm1, xmm2/m128", op_en = "RM", feature = "SSE3", mode = "V/V", handler = "x86_hsubpd_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG 7D /r", form = "VHSUBPD xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubpd_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG 7D /r", form = "VHSUBPD ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubpd_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "RM", tuple = "N/A", operand1 = "ModRM:reg (r,w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RVM", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST[63:0] = DEST[127:64] - DEST[63:0];
DEST[127:64] = SRC[127:64] - SRC[63:0];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[63:0] = SRC1[127:64] - SRC1[63:0];
DEST[127:64] = SRC2[127:64] - SRC2[63:0];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST[63:0] = SRC1[127:64] - SRC1[63:0];
DEST[127:64] = SRC2[127:64] - SRC2[63:0];
DEST[191:128] = SRC1[255:192] - SRC1[191:128];
DEST[255:192] = SRC2[255:192] - SRC2[191:128];
DEST[MAXVL-1:256] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions"]

handler = "x86_hsubpd"
jit_lowering = "arm64_neon_hsub_pd"
