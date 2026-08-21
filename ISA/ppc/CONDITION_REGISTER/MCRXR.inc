// CONDITION_REGISTER/MCRXR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "CR[CRFD]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mcrxr"
mnemonic = "mcrxr"
category = "condition_register"
operation = "CR[crfD] = XER[0:3], then clear them"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000400"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000400", form = "mcrxr [CRFD]", op_en = "X" }
]

reads = ["none"]
writes = ["CR[CRFD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
CR[crfD] <- XER[0:3]
XER[0:3] <- 0b0000
"""

handler = "ppc_mcrxr"
jit_lowering = "arm64_ppc_mcrxr"

