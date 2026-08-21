// MUL/MULHDX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XO", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mulhdx"
mnemonic = "mulhd"
category = "integer_arithmetic"
operation = "rD = high 64 bits of signed rA * rB"

form = "XO"
primary_opcode = 31
opcode_pattern = "0x7c000092"
opcode_mask = "0xfc0003fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000092", form = "mulhd[Rc] [RD], [RA], [RB]", op_en = "XO" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["GPR[RD]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
rD <- ((rA) *si (rB))[0:63]
"""

handler = "ppc_mulhdx"
jit_lowering = "arm64_ppc_mulhdx"

