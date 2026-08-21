// FP_STATUS/MTFSFX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XFL", operand_1 = "FM", operand_2 = "FPR[FB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mtfsfx"
mnemonic = "mtfsf"
category = "floating_point_status"
operation = "FPSCR fields selected by FM = frB"

form = "XFL"
primary_opcode = 63
opcode_pattern = "0xfc00058e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00058e", form = "mtfsf[Rc] [FM], [FB]", op_en = "XFL" }
]

reads = ["FM", "FPR[FB]"]
writes = ["none"]
flags_written = ["CR1 (when Rc=1)"]
special_registers = ["FPSCR"]

semantic = """
mask <- expand(FM)
FPSCR <- ((frB)[32:63] & mask) | (FPSCR & ~mask)
"""

handler = "ppc_mtfsfx"
jit_lowering = "arm64_ppc_mtfsfx"

