// SYNC/ISYNC.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XL", operand_1 = "N/A", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "isync"
mnemonic = "isync"
category = "memory_ordering"
operation = "instruction synchronize"

form = "XL"
primary_opcode = 19
opcode_pattern = "0x4c00012c"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x4c00012c", form = "isync", op_en = "XL" }
]

reads = ["none"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
refetch: discard prefetched instructions and any speculative state
"""

handler = "ppc_isync"
jit_lowering = "arm64_ppc_isync"

