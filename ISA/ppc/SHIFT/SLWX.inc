// SHIFT/SLWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "slwx"
mnemonic = "slw"
category = "integer_shift"
operation = "rA = rS << (rB & 63), 32-bit with >=32 clearing"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000030"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000030", form = "slw[Rc] [RA], [RS], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RB]"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
n <- (rB)[58:63]
rA <- if n < 32 then EXTZ((rS)[32:63] << n) else 0
"""

handler = "ppc_slwx"
jit_lowering = "arm64_ppc_slwx"

