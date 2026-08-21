// SHIFT/SRAWIX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "SH", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "srawix"
mnemonic = "srawi"
category = "integer_shift"
operation = "rA = arithmetic shift right 32-bit by SH, XER.CA set"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000670"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000670", form = "srawi[Rc] [RA], [RS], [SH]", op_en = "X" }
]

reads = ["GPR[RS]", "SH"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)", "XER.CA"]
special_registers = ["none"]

semantic = """
rA <- EXTS((rS)[32:63] >>si SH)
XER.CA <- (rS < 0) and any 1 bits shifted out
"""

handler = "ppc_srawix"
jit_lowering = "arm64_ppc_srawix"

