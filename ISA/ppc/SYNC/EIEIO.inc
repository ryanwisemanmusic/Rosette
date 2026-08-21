// SYNC/EIEIO.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "N/A", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "eieio"
mnemonic = "eieio"
category = "memory_ordering"
operation = "enforce in-order execution of I/O"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0006ac"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0006ac", form = "eieio", op_en = "X" }
]

reads = ["none"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
orders storage accesses to caching-inhibited memory
"""

handler = "ppc_eieio"
jit_lowering = "arm64_ppc_eieio"

