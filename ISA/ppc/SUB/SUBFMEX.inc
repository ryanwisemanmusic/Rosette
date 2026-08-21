// SUB/SUBFMEX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XO", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "subfmex"
mnemonic = "subfme"
category = "integer_arithmetic"
operation = "rD = ~rA + XER.CA - 1"

form = "XO"
primary_opcode = 31
opcode_pattern = "0x7c0001d0"
opcode_mask = "0xfc0003fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0001d0", form = "subfme[OE][Rc] [RD], [RA]", op_en = "XO" }
]

reads = ["GPR[RA]"]
writes = ["GPR[RD]"]
flags_written = ["CR0 (when Rc=1)", "XER.OV/XER.SO (when OE=1)", "XER.CA"]
special_registers = ["none"]

semantic = """
rD <- ~(rA) + XER.CA + 0xFFFFFFFFFFFFFFFF
XER.CA <- carry_out
"""

handler = "ppc_subfmex"
jit_lowering = "arm64_ppc_subfmex"

