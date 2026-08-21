// FP_COMPARE/FCMPU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "CR[CRFD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fcmpu"
mnemonic = "fcmpu"
category = "floating_point_compare"
operation = "CR[crfD] = unordered compare(frA, frB)"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc000000"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc000000", form = "fcmpu [CRFD], [FA], [FB]", op_en = "X" }
]

reads = ["FPR[FA]", "FPR[FB]"]
writes = ["CR[CRFD]"]
flags_written = ["CR[crfD]", "FPSCR.FPCC", "FPSCR.VXSNAN"]
special_registers = ["FPSCR"]

semantic = """
CR[crfD] <- {a<b, a>b, a=b, unordered}
FPSCR.FPCC updated; signals VXSNAN on a signalling NaN
"""

handler = "ppc_fcmpu"
jit_lowering = "arm64_ppc_fcmpu"

