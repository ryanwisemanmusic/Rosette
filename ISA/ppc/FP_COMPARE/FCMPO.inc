// FP_COMPARE/FCMPO.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "CR[CRFD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fcmpo"
mnemonic = "fcmpo"
category = "floating_point_compare"
operation = "CR[crfD] = ordered compare(frA, frB)"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc000040"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc000040", form = "fcmpo [CRFD], [FA], [FB]", op_en = "X" }
]

reads = ["FPR[FA]", "FPR[FB]"]
writes = ["CR[CRFD]"]
flags_written = ["CR[crfD]", "FPSCR.FPCC", "FPSCR.VXSNAN"]
special_registers = ["FPSCR"]

semantic = """
CR[crfD] <- {a<b, a>b, a=b, unordered}
FPSCR.FPCC updated; signals VXSNAN/VXVC as ordered comparison requires
"""

handler = "ppc_fcmpo"
jit_lowering = "arm64_ppc_fcmpo"

