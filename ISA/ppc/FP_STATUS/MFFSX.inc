// FP_STATUS/MFFSX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mffsx"
mnemonic = "mffs"
category = "floating_point_status"
operation = "frD = FPSCR"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc00048e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00048e", form = "mffs[Rc] [RD]", op_en = "X" }
]

reads = ["none"]
writes = ["GPR[RD]"]
flags_written = ["CR1 (when Rc=1)"]
special_registers = ["FPSCR"]

semantic = """
frD[32:63] <- FPSCR
"""

handler = "ppc_mffsx"
jit_lowering = "arm64_ppc_mffsx"

