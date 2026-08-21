// LOAD_INDEXED/LWAX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lwax"
mnemonic = "lwax"
category = "memory_load"
operation = "rD = EXTS(MEM32[(rA|0) + (rB)]) loaded big-endian"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0002aa"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0002aa", form = "lwax [RD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
rD <- EXTS(MEM(EA, 4))
"""

handler = "ppc_lwax"
jit_lowering = "arm64_ppc_lwax"

