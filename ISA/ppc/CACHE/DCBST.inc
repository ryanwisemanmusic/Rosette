// CACHE/DCBST.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA] or 0", operand_2 = "GPR[RB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "dcbst"
mnemonic = "dcbst"
category = "cache_management"
operation = "store the data cache block at (rA|0) + (rB)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00006c"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00006c", form = "dcbst [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
store the data cache block containing EA
"""

handler = "ppc_dcbst"
jit_lowering = "arm64_ppc_dcbst"

