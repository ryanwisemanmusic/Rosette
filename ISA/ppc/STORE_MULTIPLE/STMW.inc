// STORE_MULTIPLE/STMW.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RS]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stmw"
mnemonic = "stmw"
category = "memory_store"
operation = "stores a consecutive register run starting at rS"

form = "D"
primary_opcode = 47
opcode_pattern = "0xbc000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xbc000000", form = "stmw [RS], [DS]([RA0])", op_en = "D" }
]

reads = ["GPR[RS]", "d", "GPR[RA]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + displacement
for r in rS..r31: MEM(EA, 4) <- r[32:63]; EA <- EA + 4
"""

handler = "ppc_stmw"
jit_lowering = "arm64_ppc_stmw_helper"

