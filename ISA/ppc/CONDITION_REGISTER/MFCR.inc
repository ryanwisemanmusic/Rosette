// CONDITION_REGISTER/MFCR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mfcr"
mnemonic = "mfcr"
category = "condition_register"
operation = "rD = CR"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000026"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000026", form = "mfcr [RD]", op_en = "X" }
]

reads = ["none"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
rD <- 0x00000000 || CR
"""

handler = "ppc_mfcr"
jit_lowering = "arm64_ppc_mfcr"

