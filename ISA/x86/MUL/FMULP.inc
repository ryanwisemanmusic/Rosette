// FMULP.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ST(i) (r, w)", operand_2 = "ST(0) (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "ZO", operand_1 = "ST(1) (r, w)", operand_2 = "ST(0) (r)", operand_3 = "N/A", operand_4 = "N/A" },
]

name = "FMULP"
category = "gpr_x87_alu"
feature = "x87 FPU"
element_type = "f32"

encodings = [
  { opcode = "DE C8+i", form = "FMULP ST(i), ST(0)", op_en = "A", feature = "x87 FPU" },
  { opcode = "DE C9", form = "FMULP", op_en = "ZO", feature = "x87 FPU" },
]

lanes = {}

mxcsr_used = false

flags_written = ["C1"]

semantic = """
DEST := DEST * ST(0);
PopRegisterStack;
"""

handler = "x86_fmulp"
jit_lowering = "arm64_neon_fmul_scalar"
fallback = "zig_x87_fallback"
