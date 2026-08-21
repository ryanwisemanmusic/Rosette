// LOAD_MULTIPLE/LSWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lswx"
mnemonic = "lswx"
category = "memory_load"
operation = "loads a consecutive register run starting at rD"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00042a"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00042a", form = "lswx [RD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + displacement
for r in rD..r31: r <- MEM(EA, 4); EA <- EA + 4
"""

handler = "ppc_lswx"
jit_lowering = "arm64_ppc_lswx_helper"

