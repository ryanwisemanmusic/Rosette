// FSUBP.inc
// Subtract and pop (x87 FPU).

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
FSUBP: subtract x87 floating-point values and pop register stack.
Category: x87_fpu_subtract_pop.
"""

name = "FSUBP"
category = "x87_fpu_subtract_pop"
feature = "x87"
element_type = "f80"

encodings = [
  { opcode = "DE E8+i", form = "FSUBP ST(i), ST(0)", op_en = "RR", feature = "x87", handler = "x86_fsubp_sti_st0" },
  { opcode = "DE E9", form = "FSUBP", op_en = "ZO", feature = "x87", handler = "x86_fsubp" }
]

operand_encodings = [
  { op_en = "RR", tuple = "N/A", operand1 = "ST(i) (r,w)", operand2 = "ST(0) (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "ZO", tuple = "N/A", operand1 = "N/A", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if SNaN or unlike-sign infinities",
  "#D if denormal source",
  "#U if result too small",
  "#O if result too large",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

handler = "x86_fsubp"
jit_lowering = "arm64_neon_fsub_scalar"
