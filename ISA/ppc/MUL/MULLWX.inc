// MUL/MULLWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XO", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mullwx"
mnemonic = "mullw"
category = "integer_arithmetic"
operation = "rD = (rA[32:63] * rB[32:63]) sign-extended"

form = "XO"
primary_opcode = 31
opcode_pattern = "0x7c0001d6"
opcode_mask = "0xfc0003fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0001d6", form = "mullw[OE][Rc] [RD], [RA], [RB]", op_en = "XO" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["GPR[RD]"]
flags_written = ["CR0 (when Rc=1)", "XER.OV/XER.SO (when OE=1)"]
special_registers = ["none"]

semantic = """
rD <- EXTS((rA)[32:63] * (rB)[32:63])
"""

handler = "ppc_mullwx"
jit_lowering = "arm64_ppc_mullwx"

