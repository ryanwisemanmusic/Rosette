// SHIFT/SRAWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "srawx"
mnemonic = "sraw"
category = "integer_shift"
operation = "rA = arithmetic shift right 32-bit, XER.CA from lost ones"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000630"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000630", form = "sraw[Rc] [RA], [RS], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RB]"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)", "XER.CA"]
special_registers = ["none"]

semantic = """
n <- (rB)[58:63]
rA <- EXTS((rS)[32:63] >>si min(n, 31))
XER.CA <- (rS < 0) and any 1 bits shifted out
"""

handler = "ppc_srawx"
jit_lowering = "arm64_ppc_srawx"

