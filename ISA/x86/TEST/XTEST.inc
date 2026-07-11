// XTEST.inc
// TEST XTEST — Test If Executing Inside Transactional Region

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
XTEST: sets ZF to 1 if executing inside a transactional region (RTM or HLE), else 0.
Category: transactional_test.
"""

name = "XTEST"
category = "transactional_test"
feature = "HLE or RTM"

encodings = [
  { opcode = "NP 0F 01 D6", form = "XTEST", op_en = "ZO", feature = "HLE or RTM", mode = "V/V", handler = "x86_xtest" }
]

operand_encodings = [
  { op_en = "ZO", tuple = "N/A", operand1 = "N/A", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
IF (RTM_OR_HLE_REGION_ACTIVE)
  ZF = 0;
ELSE
  ZF = 1;
CF = 0;
OF = 0;
AF = 0;
PF = 0;
SF = 0;
"""

other_exceptions = ["#UD if LOCK prefix used", "#UD if executed inside an enclave"]

handler = "x86_xtest"
jit_lowering = "arm64_neon_mrs_el0"
