// DIV/DIVDX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XO", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "divdx"
mnemonic = "divd"
category = "integer_arithmetic"
operation = "rD = rA / rB (64-bit signed)"

form = "XO"
primary_opcode = 31
opcode_pattern = "0x7c0003d2"
opcode_mask = "0xfc0003fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0003d2", form = "divd[OE][Rc] [RD], [RA], [RB]", op_en = "XO" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["GPR[RD]"]
flags_written = ["CR0 (when Rc=1)", "XER.OV/XER.SO (when OE=1)"]
special_registers = ["none"]

semantic = """
rD <- (rA) /si (rB)
undefined when rB == 0 or (rA == INT64_MIN and rB == -1)
"""

handler = "ppc_divdx"
jit_lowering = "arm64_ppc_divdx"

