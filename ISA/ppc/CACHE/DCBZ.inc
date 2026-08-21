// CACHE/DCBZ.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DCBZ", operand_1 = "GPR[RA] or 0", operand_2 = "GPR[RB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "dcbz"
mnemonic = "dcbz"
category = "cache_management"
operation = "zero the 32-byte data cache block at (rA|0) + (rB)"

form = "DCBZ"
primary_opcode = 31
opcode_pattern = "0x7c0007ec"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0007ec", form = "dcbz [RA0], [RB]", op_en = "DCBZ" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
zero the 32-byte data cache block containing EA
"""

handler = "ppc_dcbz"
jit_lowering = "arm64_ppc_dcbz"

