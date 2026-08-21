// CONDITION_REGISTER/MTCRF.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XFX", operand_1 = "CRM", operand_2 = "GPR[RS]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mtcrf"
mnemonic = "mtcrf"
category = "condition_register"
operation = "CR fields selected by CRM = rS"

form = "XFX"
primary_opcode = 31
opcode_pattern = "0x7c000120"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000120", form = "mtcrf [CRM], [RS]", op_en = "XFX" }
]

reads = ["CRM", "GPR[RS]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
mask <- expand(CRM)
CR <- ((rS)[32:63] & mask) | (CR & ~mask)
"""

handler = "ppc_mtcrf"
jit_lowering = "arm64_ppc_mtcrf"

