// FP_ARITH/FRESX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fresx"
mnemonic = "fres"
category = "floating_point_arithmetic"
operation = "frD = 1/x estimate(frB) in single precision"

form = "A"
primary_opcode = 59
opcode_pattern = "0xec000030"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xec000030", form = "fres[Rc] [FD], [FB]", op_en = "A" }
]

reads = ["FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- 1/x estimate((frB)) rounded per FPSCR.RN
"""

handler = "ppc_fresx"
jit_lowering = "arm64_ppc_fresx"

