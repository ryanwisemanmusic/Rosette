// BYTE_REVERSE/LHBRX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lhbrx"
mnemonic = "lhbrx"
category = "memory_byte_reversed"
operation = "rD = EXTZ(MEM16[(rA|0) + (rB)]) loaded byte-reversed (little-endian)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00062c"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00062c", form = "lhbrx [RD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
rD <- EXTZ(MEM(EA, 2))
"""

handler = "ppc_lhbrx"
jit_lowering = "arm64_ppc_lhbrx"

