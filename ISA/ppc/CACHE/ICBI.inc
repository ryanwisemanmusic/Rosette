// CACHE/ICBI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "icbi"
mnemonic = "icbi"
category = "cache_management"
operation = "invalidate the instruction cache block at (rA|0) + (rB)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0007ac"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0007ac", form = "icbi [RA], [RB]", op_en = "X" }
]

reads = ["GPR[RB]"]
writes = ["GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
invalidate the instruction cache block containing EA
"""

handler = "ppc_icbi"
jit_lowering = "arm64_ppc_icbi"

