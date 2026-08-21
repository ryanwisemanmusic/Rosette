// MUL/MULLI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "SIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mulli"
mnemonic = "mulli"
category = "integer_arithmetic"
operation = "rD = rA * SIMM"

form = "D"
primary_opcode = 7
opcode_pattern = "0x1c000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1c000000", form = "mulli [RD], [RA], [SIMM]", op_en = "D" }
]

reads = ["GPR[RA]", "SIMM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
rD <- ((rA) * EXTS(SIMM))[64:127]
"""

handler = "ppc_mulli"
jit_lowering = "arm64_ppc_mulli"

