// FIMUL.inc

operand_encoding = [
  { op_en = "M", operand_1 = "ModRM:r/m (r)", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

name = "FIMUL"
category = "gpr_x87_alu"
feature = "x87 FPU"
element_type = "f32"

encodings = [
  { opcode = "DA /1", form = "FIMUL m32int", op_en = "M", feature = "x87 FPU" },
  { opcode = "DE /1", form = "FIMUL m16int", op_en = "M", feature = "x87 FPU" },
]

lanes = {}

mxcsr_used = false

flags_written = ["C1"]

semantic = """
DEST := DEST * ConvertToDoubleExtendedPrecisionFP(SRC);
"""

handler = "x86_fimul"
jit_lowering = "arm64_neon_fmul_scalar"
fallback = "zig_x87_fallback"
