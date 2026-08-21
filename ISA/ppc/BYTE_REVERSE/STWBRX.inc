// BYTE_REVERSE/STWBRX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stwbrx"
mnemonic = "stwbrx"
category = "memory_byte_reversed"
operation = "MEM32[(rA|0) + (rB)] = rS stored byte-reversed (little-endian)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00052c"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00052c", form = "stwbrx [RS], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + (rB)
MEM(EA, 4) <- (rS)[32:63]
"""

handler = "ppc_stwbrx"
jit_lowering = "arm64_ppc_stwbrx"

