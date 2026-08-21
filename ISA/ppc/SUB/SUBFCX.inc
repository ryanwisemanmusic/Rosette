// SUB/SUBFCX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XO", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "subfcx"
mnemonic = "subfc"
category = "integer_arithmetic"
operation = "rD = rB - rA, XER.CA = carry"

form = "XO"
primary_opcode = 31
opcode_pattern = "0x7c000010"
opcode_mask = "0xfc0003fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000010", form = "subfc[OE][Rc] [RD], [RA], [RB]", op_en = "XO" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["GPR[RD]"]
flags_written = ["CR0 (when Rc=1)", "XER.OV/XER.SO (when OE=1)", "XER.CA"]
special_registers = ["none"]

semantic = """
rD <- ~(rA) + (rB) + 1
XER.CA <- carry_out
"""

handler = "ppc_subfcx"
jit_lowering = "arm64_ppc_subfcx"

