// PTEST.inc
// TEST PTEST — Logical Compare of Packed Integers (bitwise AND, set ZF/CF)

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PTEST: bitwise AND of DEST with SRC, discard result, set ZF/CF.
Category: bit_test.
"""

name = "PTEST"
category = "bit_test"
feature = "SSE4_1"
element_type = "i128"
legacy_width = 128

encodings = [
  { opcode = "66 0F 38 17 /r", form = "PTEST xmm1, xmm2/m128", op_en = "RM", feature = "SSE4_1", mode = "V/V", handler = "x86_ptest_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F38.W0 17 /r", form = "VPTEST xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vptest_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F38.W0 17 /r", form = "VPTEST ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vptest_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "RM", tuple = "N/A", operand1 = "ModRM:reg (r,w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RVM", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
TEMP = DEST AND SRC;
ZF = (TEMP == 0) ? 1 : 0;
CF = (TEMP == MSB_ALL_ONES_IN_ALL_LANES) ? 1 : 0;
OF = 0;
AF = 0;
PF = 0;
SF = 0;
DEST unchanged;
"""

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

handler = "x86_ptest"
jit_lowering = "arm64_neon_cmeq_and"
