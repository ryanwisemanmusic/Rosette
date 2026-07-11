// FTST.inc
// TEST FTST — x87 FPU Test for Stack Top (compare ST(0) against 0.0)

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
FTST: compare ST(0) against +0.0 and set FPU status flags C3, C2, C0.
Category: x87_fpu_test.
"""

name = "FTST"
category = "x87_fpu_test"
feature = "x87"
element_type = "f80"

encodings = [
  { opcode = "D9 E4", form = "FTST", op_en = "ZO", feature = "x87", mode = "V/V", handler = "x86_ftst" }
]

operand_encodings = [
  { op_en = "ZO", tuple = "N/A", operand1 = "N/A", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
C3 = 1 if ST(0) == 0.0, else 0;
C2 = 1 if ST(0) is denormal or zero, else 0;
C1 = 0;
C0 = 1 if ST(0) < 0.0, else 0;
ST(0) unchanged;
"""

other_exceptions = ["#IS if FPU stack underflow (C1 = 1, exception pending)", "#D x87 FPU stack underflow"]

handler = "x86_ftst"
jit_lowering = "arm64_neon_fcmp_sd"
