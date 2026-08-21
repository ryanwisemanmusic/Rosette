// MUL/MULHWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XO", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mulhwx"
mnemonic = "mulhw"
category = "integer_arithmetic"
operation = "rD = high 32 bits of signed rA * rB"

form = "XO"
primary_opcode = 31
opcode_pattern = "0x7c000096"
opcode_mask = "0xfc0003fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000096", form = "mulhw[Rc] [RD], [RA], [RB]", op_en = "XO" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["GPR[RD]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
rD[32:63] <- ((rA)[32:63] *si (rB)[32:63])[0:31]
"""

handler = "ppc_mulhwx"
jit_lowering = "arm64_ppc_mulhwx"

