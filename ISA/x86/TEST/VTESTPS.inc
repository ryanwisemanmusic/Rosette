// VTESTPS.inc
// TEST VTESTPS — Packed Single-Precision Bit Test (set ZF/CF)

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VTESTPS: bitwise AND of SRC1 with SRC2, discard result, set ZF/CF.
Category: bit_test.
"""

name = "VTESTPS"
category = "bit_test"
feature = "AVX"
element_type = "f32"

encodings = [
  { opcode = "VEX.128.66.0F38.W0 0E /r", form = "VTESTPS xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vtestps_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F38.W0 0E /r", form = "VTESTPS ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vtestps_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "RVM", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_vex_128 = """
TEMP = SRC1 AND SRC2;
ZF = (TEMP == 0) ? 1 : 0;
CF = (TEMP == MSB_ALL_ONES_IN_ALL_LANES) ? 1 : 0;
OF = 0;
AF = 0;
PF = 0;
SF = 0;
DEST (SRC1) unchanged;
"""

semantic_vex_256 = """
TEMP = SRC1 AND SRC2;
ZF = (TEMP == 0) ? 1 : 0;
CF = (TEMP == MSB_ALL_ONES_IN_ALL_LANES) ? 1 : 0;
OF = 0;
AF = 0;
PF = 0;
SF = 0;
DEST (SRC1) unchanged;
"""

other_exceptions = ["#UD if CR4.OSFXSR = 0", "#UD if LOCK prefix used", "#UD if VEX.L > 0 on 128-bit-only implementations"]

handler = "x86_vtestps"
jit_lowering = "arm64_neon_cmeq_and"
