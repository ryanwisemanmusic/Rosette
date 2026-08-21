// SYNC/SYNC.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "N/A", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sync"
mnemonic = "sync"
category = "memory_ordering"
operation = "memory barrier"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0004ac"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0004ac", form = "sync", op_en = "X" }
]

reads = ["none"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
all prior storage accesses complete before any later one
"""

handler = "ppc_sync"
jit_lowering = "arm64_ppc_sync"

