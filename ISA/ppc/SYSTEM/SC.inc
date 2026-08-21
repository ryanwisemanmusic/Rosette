// SYSTEM/SC.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "SC", operand_1 = "LEV", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sc"
mnemonic = "sc"
category = "system_supervisor"
operation = "system call — traps into the Xbox 360 kernel"

form = "SC"
primary_opcode = 17
opcode_pattern = "0x44000002"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x44000002", form = "sc [LEV]", op_en = "SC" }
]

reads = ["LEV"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
raise system-call interrupt; Rosette routes it to the kernel shim table
"""

handler = "ppc_sc"
jit_lowering = "arm64_ppc_sc"

