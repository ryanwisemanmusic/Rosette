// LOAD_INDEXED/LHAX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lhax"
mnemonic = "lhax"
category = "memory_load"
operation = "rD = EXTS(MEM16[(rA|0) + (rB)]) loaded big-endian"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0002ae"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0002ae", form = "lhax [RD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
rD <- EXTS(MEM(EA, 2))
"""

handler = "ppc_lhax"
jit_lowering = "arm64_ppc_lhax"

