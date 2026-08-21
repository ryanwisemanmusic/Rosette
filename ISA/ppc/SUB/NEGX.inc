// SUB/NEGX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XO", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "negx"
mnemonic = "neg"
category = "integer_arithmetic"
operation = "rD = -rA"

form = "XO"
primary_opcode = 31
opcode_pattern = "0x7c0000d0"
opcode_mask = "0xfc0003fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0000d0", form = "neg[OE][Rc] [RD], [RA]", op_en = "XO" }
]

reads = ["GPR[RA]"]
writes = ["GPR[RD]"]
flags_written = ["CR0 (when Rc=1)", "XER.OV/XER.SO (when OE=1)"]
special_registers = ["none"]

semantic = """
rD <- ~(rA) + 1
"""

handler = "ppc_negx"
jit_lowering = "arm64_ppc_negx"

