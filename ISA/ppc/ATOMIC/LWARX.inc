// ATOMIC/LWARX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lwarx"
mnemonic = "lwarx"
category = "memory_atomic"
operation = "rD = MEM32[(rA|0) + rB] and set the reservation"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000028"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000028", form = "lwarx [RD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["reservation (address + valid bit)"]

semantic = """
EA <- (rA|0) + (rB)
RESERVE <- 1
RESERVE_ADDR <- EA
rD <- EXTZ(MEM(EA, 4))
"""

handler = "ppc_lwarx"
jit_lowering = "arm64_ppc_lwarx"

