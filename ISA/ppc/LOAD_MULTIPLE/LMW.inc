// LOAD_MULTIPLE/LMW.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lmw"
mnemonic = "lmw"
category = "memory_load"
operation = "loads a consecutive register run starting at rD"

form = "D"
primary_opcode = 46
opcode_pattern = "0xb8000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xb8000000", form = "lmw [RD], [DS]([RA0])", op_en = "D" }
]

reads = ["d", "GPR[RA]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + displacement
for r in rD..r31: r <- MEM(EA, 4); EA <- EA + 4
"""

handler = "ppc_lmw"
jit_lowering = "arm64_ppc_lmw_helper"

