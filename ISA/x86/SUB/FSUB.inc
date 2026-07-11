// FSUB.inc
// Subtract (x87 FPU).

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
FSUB: subtract x87 floating-point values.
Category: x87_fpu_subtract.
"""

name = "FSUB"
category = "x87_fpu_subtract"
feature = "x87"
element_type = "f80"

encodings = [
  { opcode = "D8 /4", form = "FSUB m32fp", op_en = "M", feature = "x87", handler = "x86_fsub_m32fp" },
  { opcode = "DC /4", form = "FSUB m64fp", op_en = "M", feature = "x87", handler = "x86_fsub_m64fp" },
  { opcode = "D8 E0+i", form = "FSUB ST(0), ST(i)", op_en = "RR", feature = "x87", handler = "x86_fsub_st0_sti" },
  { opcode = "DC E8+i", form = "FSUB ST(i), ST(0)", op_en = "RR", feature = "x87", handler = "x86_fsub_sti_st0" }
]

operand_encodings = [
  { op_en = "M", tuple = "N/A", operand1 = "ModRM:r/m (r)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RR", tuple = "N/A", operand1 = "ST(i) (r,w)", operand2 = "ST(0) (r)", operand3 = "N/A", operand4 = "N/A" }
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

handler = "x86_fsub"
jit_lowering = "arm64_neon_fsub_scalar"
