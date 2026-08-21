// STORE_MULTIPLE/STSWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stswx"
mnemonic = "stswx"
category = "memory_store"
operation = "stores a consecutive register run starting at rS"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00052a"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00052a", form = "stswx [RS], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + displacement
for r in rS..r31: MEM(EA, 4) <- r[32:63]; EA <- EA + 4
"""

handler = "ppc_stswx"
jit_lowering = "arm64_ppc_stswx_helper"

