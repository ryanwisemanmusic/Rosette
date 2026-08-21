// LOAD_MULTIPLE/LSWI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "NB", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lswi"
mnemonic = "lswi"
category = "memory_load"
operation = "loads a consecutive register run starting at rD"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0004aa"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0004aa", form = "lswi [RD], [RA0], [NB]", op_en = "X" }
]

reads = ["GPR[RA]", "NB", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + displacement
for r in rD..r31: r <- MEM(EA, 4); EA <- EA + 4
"""

handler = "ppc_lswi"
jit_lowering = "arm64_ppc_lswi_helper"

