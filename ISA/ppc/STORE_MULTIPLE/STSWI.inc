// STORE_MULTIPLE/STSWI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA] or 0", operand_3 = "NB", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stswi"
mnemonic = "stswi"
category = "memory_store"
operation = "stores a consecutive register run starting at rS"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0005aa"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0005aa", form = "stswi [RS], [RA0], [NB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "NB"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + displacement
for r in rS..r31: MEM(EA, 4) <- r[32:63]; EA <- EA + 4
"""

handler = "ppc_stswi"
jit_lowering = "arm64_ppc_stswi_helper"

