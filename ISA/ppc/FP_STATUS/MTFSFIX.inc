// FP_STATUS/MTFSFIX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "CR[CRFD]", operand_2 = "IMM", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mtfsfix"
mnemonic = "mtfsfi"
category = "floating_point_status"
operation = "FPSCR[crfD] = IMM"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc00010c"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00010c", form = "mtfsfi[Rc] [CRFD], [IMM]", op_en = "X" }
]

reads = ["IMM"]
writes = ["CR[CRFD]"]
flags_written = ["CR1 (when Rc=1)"]
special_registers = ["FPSCR"]

semantic = """
FPSCR field crfD <- IMM
"""

handler = "ppc_mtfsfix"
jit_lowering = "arm64_ppc_mtfsfix"

