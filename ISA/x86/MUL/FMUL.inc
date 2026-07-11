// FMUL.inc

operand_encoding = [
  { op_en = "M", operand_1 = "ModRM:r/m (r)", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "A", operand_1 = "ST(0) (r, w)", operand_2 = "ST(i) (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ST(i) (r, w)", operand_2 = "ST(0) (r)", operand_3 = "N/A", operand_4 = "N/A" },
]

name = "FMUL"
category = "gpr_x87_alu"
feature = "x87 FPU"
element_type = "f32"

encodings = [
  { opcode = "D8 /1", form = "FMUL m32fp", op_en = "M", feature = "x87 FPU" },
  { opcode = "DC /1", form = "FMUL m64fp", op_en = "M", feature = "x87 FPU" },
  { opcode = "D8 C8+i", form = "FMUL ST(0), ST(i)", op_en = "A", feature = "x87 FPU" },
  { opcode = "DC C8+i", form = "FMUL ST(i), ST(0)", op_en = "B", feature = "x87 FPU" },
]

lanes = {}

mxcsr_used = false

flags_written = ["C1"]

semantic = """
DEST := DEST * SRC;
"""

handler = "x86_fmul"
jit_lowering = "arm64_neon_fmul_scalar"
fallback = "zig_x87_fallback"
