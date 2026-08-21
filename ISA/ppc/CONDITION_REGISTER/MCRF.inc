// CONDITION_REGISTER/MCRF.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XL", operand_1 = "CR[CRFD]", operand_2 = "CR[CRFS]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mcrf"
mnemonic = "mcrf"
category = "condition_register"
operation = "CR[crfD] = CR[crfS]"

form = "XL"
primary_opcode = 19
opcode_pattern = "0x4c000000"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x4c000000", form = "mcrf [CRFD], [CRFS]", op_en = "XL" }
]

reads = ["CR[CRFS]"]
writes = ["CR[CRFD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
CR[crfD] <- CR[crfS]
"""

handler = "ppc_mcrf"
jit_lowering = "arm64_ppc_mcrf"

