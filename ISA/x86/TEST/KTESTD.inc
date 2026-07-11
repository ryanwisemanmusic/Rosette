// KTESTD.inc
// TEST KTESTD — AND of two 32-bit mask registers, set ZF/CF according to result

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KTESTD: bitwise AND of k1 and k2 (both 32-bit mask registers), discard result, set ZF/CF.
Category: mask_test.
"""

name = "KTESTD"
category = "mask_test"
feature = "AVX512BW"
element_type = "u32"

encodings = [
  { opcode = "VEX.L0.66.0F.W1 99 /r", form = "KTESTD k1, k2", op_en = "RR", feature = "AVX512BW", mode = "V/V", handler = "x86_ktestd" }
]

operand_encodings = [
  { op_en = "RR", tuple = "N/A", operand1 = "ModRM:reg (r)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
TEMP = k1 AND k2;
ZF = (TEMP == 0) ? 1 : 0;
CF = (TEMP == 0xFFFFFFFF) ? 1 : 0;
OF = 0;
AF = 0;
PF = 0;
SF = 0;
k1, k2 unchanged;
"""

other_exceptions = ["#UD if CR4.OSFXSR = 0", "#UD if LOCK prefix used", "#UD if VEX.W = 0"]

handler = "x86_ktestd"
jit_lowering = "arm64_neon_and_test"
