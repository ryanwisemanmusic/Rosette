// FP_CONVERT/FRSPX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPR[FD]", operand_2 = "FPR[FB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "frspx"
mnemonic = "frsp"
category = "floating_point_convert"
operation = "frD = round to single precision"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc000018"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc000018", form = "frsp[Rc] [FD], [FB]", op_en = "X" }
]

reads = ["FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- round to single precision of (frB)
FPSCR.FPRF/FR/FI and the VXCVI/XX exceptions are updated
"""

handler = "ppc_frspx"
jit_lowering = "arm64_ppc_frspx"

