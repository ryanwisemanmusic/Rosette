// LOAD_INDEXED/LWAUX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lwaux"
mnemonic = "lwaux"
category = "memory_load"
operation = "rD = EXTS(MEM32[(rA) + (rB)]) loaded big-endian"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0002ea"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0002ea", form = "lwaux [RD], [RA], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["GPR[RD]", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + (rB)
rD <- EXTS(MEM(EA, 4))
rA <- EA
"""

handler = "ppc_lwaux"
jit_lowering = "arm64_ppc_lwaux"

