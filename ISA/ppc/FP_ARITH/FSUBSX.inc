// FP_ARITH/FSUBSX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fsubsx"
mnemonic = "fsubs"
category = "floating_point_arithmetic"
operation = "frD = frA - frB in single precision"

form = "A"
primary_opcode = 59
opcode_pattern = "0xec000028"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xec000028", form = "fsubs[Rc] [FD], [FA], [FB]", op_en = "A" }
]

reads = ["FPR[FA]", "FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- (frA) - (frB) rounded per FPSCR.RN
"""

handler = "ppc_fsubsx"
jit_lowering = "arm64_ppc_fsubsx"

