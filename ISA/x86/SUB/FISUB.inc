// FISUB.inc
// Integer subtract (x87 FPU).

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
FISUB: subtract integer from x87 floating-point value (convert integer to extended precision).
Category: x87_fpu_integer_subtract.
"""

name = "FISUB"
category = "x87_fpu_integer_subtract"
feature = "x87"
element_type = "f80"

encodings = [
  { opcode = "DA /4", form = "FISUB m32int", op_en = "M", feature = "x87", handler = "x86_fisub_m32int" },
  { opcode = "DE /4", form = "FISUB m16int", op_en = "M", feature = "x87", handler = "x86_fisub_m16int" }
]

operand_encodings = [
  { op_en = "M", tuple = "N/A", operand1 = "ModRM:r/m (r)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
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

handler = "x86_fisub"
jit_lowering = "arm64_neon_fsub_scalar"
