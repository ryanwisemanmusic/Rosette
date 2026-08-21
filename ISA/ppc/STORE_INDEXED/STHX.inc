// STORE_INDEXED/STHX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sthx"
mnemonic = "sthx"
category = "memory_store"
operation = "MEM16[(rA|0) + (rB)] = rS stored big-endian"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00032e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00032e", form = "sthx [RS], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
MEM(EA, 2) <- (rS)[48:63]
"""

handler = "ppc_sthx"
jit_lowering = "arm64_ppc_sthx"

