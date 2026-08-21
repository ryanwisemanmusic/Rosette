// FP_ARITH/FSQRTX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fsqrtx"
mnemonic = "fsqrt"
category = "floating_point_arithmetic"
operation = "frD = sqrt(frB) in double precision"

form = "A"
primary_opcode = 63
opcode_pattern = "0xfc00002c"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00002c", form = "fsqrt[Rc] [FD], [FB]", op_en = "A" }
]

reads = ["FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- sqrt((frB)) rounded per FPSCR.RN
"""

handler = "ppc_fsqrtx"
jit_lowering = "arm64_ppc_fsqrtx"

