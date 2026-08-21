// FP_CONVERT/FCTIDZX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPR[FD]", operand_2 = "FPR[FB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fctidzx"
mnemonic = "fctidz"
category = "floating_point_convert"
operation = "frD = convert to 64-bit integer, round toward zero"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc00065e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00065e", form = "fctidz[Rc] [FD], [FB]", op_en = "X" }
]

reads = ["FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- convert to 64-bit integer, round toward zero of (frB)
FPSCR.FPRF/FR/FI and the VXCVI/XX exceptions are updated
"""

handler = "ppc_fctidzx"
jit_lowering = "arm64_ppc_fctidzx"

