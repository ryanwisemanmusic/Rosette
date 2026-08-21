// FP_MULTIPLY_ADD/FNMADDSX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FC]", operand_4 = "FPR[FB]" },
]

source_isa = "ppc"
name = "fnmaddsx"
mnemonic = "fnmadds"
category = "floating_point_fused_multiply_add"
operation = "frD = -((frA * frC) + frB) in single precision"

form = "A"
primary_opcode = 59
opcode_pattern = "0xec00003e"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xec00003e", form = "fnmadds[Rc] [FD], [FA], [FC], [FB]", op_en = "A" }
]

reads = ["FPR[FA]", "FPR[FC]", "FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- -((frA * frC) + frB) computed with one rounding (fused multiply-add) per FPSCR.RN
"""

handler = "ppc_fnmaddsx"
jit_lowering = "arm64_ppc_fnmaddsx"

