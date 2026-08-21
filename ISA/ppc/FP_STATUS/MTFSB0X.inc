// FP_STATUS/MTFSB0X.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPSCR[FPSCRD]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mtfsb0x"
mnemonic = "mtfsb0"
category = "floating_point_status"
operation = "FPSCR[crbD] = 0"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc00008c"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00008c", form = "mtfsb0[Rc] [FPSCRD]", op_en = "X" }
]

reads = ["none"]
writes = ["FPSCR[FPSCRD]"]
flags_written = ["CR1 (when Rc=1)"]
special_registers = ["FPSCR"]

semantic = """
FPSCR[crbD] <- 0
"""

handler = "ppc_mtfsb0x"
jit_lowering = "arm64_ppc_mtfsb0x"

