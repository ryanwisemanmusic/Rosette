// LOAD/LWZU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "d", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lwzu"
mnemonic = "lwzu"
category = "memory_load"
operation = "rD = EXTZ(MEM32[(rA) + EXTS(d)]) loaded big-endian"

form = "D"
primary_opcode = 33
opcode_pattern = "0x84000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x84000000", form = "lwzu [RD], [d]([RA])", op_en = "D" }
]

reads = ["d", "GPR[RA]", "MEM"]
writes = ["GPR[RD]", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + EXTS(d)
rD <- EXTZ(MEM(EA, 4))
rA <- EA
"""

handler = "ppc_lwzu"
jit_lowering = "arm64_ppc_lwzu"

