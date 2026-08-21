// FP_MOVE/FNEGX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPR[FD]", operand_2 = "FPR[FB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fnegx"
mnemonic = "fneg"
category = "floating_point_move"
operation = "frD = -frB"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc000050"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc000050", form = "fneg[Rc] [FD], [FB]", op_en = "X" }
]

reads = ["FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)"]
special_registers = ["FPSCR"]

semantic = """
frD <- (frB) with sign bit inverted
"""

handler = "ppc_fnegx"
jit_lowering = "arm64_ppc_fnegx"

