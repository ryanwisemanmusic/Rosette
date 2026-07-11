// HSUBPS.inc
// Horizontal subtract packed single precision floating-point values.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
HSUBPS: horizontal subtract of adjacent single-precision pairs within each source.
Category: simd_float_horizontal_subtract.
"""

name = "HSUBPS"
category = "simd_float_horizontal_subtract"
feature = "SSE3"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
mxcsr_used = true

encodings = [
  { opcode = "F2 0F 7D /r", form = "HSUBPS xmm1, xmm2/m128", op_en = "RM", feature = "SSE3", mode = "V/V", handler = "x86_hsubps_xmm_xmmm128" },
  { opcode = "VEX.128.F2.0F.WIG 7D /r", form = "VHSUBPS xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubps_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.F2.0F.WIG 7D /r", form = "VHSUBPS ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubps_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "RM", tuple = "N/A", operand1 = "ModRM:reg (r,w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RVM", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST[31:0] = DEST[63:32] - DEST[31:0];
DEST[63:32] = DEST[127:96] - DEST[95:64];
DEST[95:64] = SRC[63:32] - SRC[31:0];
DEST[127:96] = SRC[127:96] - SRC[95:64];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[31:0] = SRC1[63:32] - SRC1[31:0];
DEST[63:32] = SRC1[127:96] - SRC1[95:64];
DEST[95:64] = SRC2[63:32] - SRC2[31:0];
DEST[127:96] = SRC2[127:96] - SRC2[95:64];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST[31:0] = SRC1[63:32] - SRC1[31:0];
DEST[63:32] = SRC1[127:96] - SRC1[95:64];
DEST[95:64] = SRC2[63:32] - SRC2[31:0];
DEST[127:96] = SRC2[127:96] - SRC2[95:64];
DEST[159:128] = SRC1[191:160] - SRC1[159:128];
DEST[191:160] = SRC1[255:224] - SRC1[223:192];
DEST[223:192] = SRC2[63:32] - SRC2[31:0];
DEST[255:224] = SRC2[127:96] - SRC2[95:64];
DEST[MAXVL-1:256] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions"]

handler = "x86_hsubps"
jit_lowering = "arm64_neon_hsub_ps"
