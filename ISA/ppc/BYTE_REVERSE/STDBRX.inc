// BYTE_REVERSE/STDBRX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stdbrx"
mnemonic = "stdbrx"
category = "memory_byte_reversed"
operation = "MEM64[(rA|0) + (rB)] = rS stored byte-reversed (little-endian)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000528"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000528", form = "stdbrx [RS], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
MEM(EA, 8) <- (rS)[0:63]
"""

handler = "ppc_stdbrx"
jit_lowering = "arm64_ppc_stdbrx"

