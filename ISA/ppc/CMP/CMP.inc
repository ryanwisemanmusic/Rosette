// CMP/CMP.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "CR[CRFD]", operand_2 = "L", operand_3 = "GPR[RA]", operand_4 = "GPR[RB]" },
]

source_isa = "ppc"
name = "cmp"
mnemonic = "cmp"
category = "integer_compare"
operation = "CR[crfD] = signed compare(rA, rB)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000000"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000000", form = "cmp [CRFD], [L], [RA], [RB]", op_en = "X" }
]

reads = ["L", "GPR[RA]", "GPR[RB]"]
writes = ["CR[CRFD]"]
flags_written = ["CR[crfD]"]
special_registers = ["none"]

semantic = """
a <- if L then (rA) else EXTS((rA)[32:63])
b <- if L then (rB) else EXTS((rB)[32:63])
CR[crfD] <- {a<b, a>b, a=b, XER.SO}
"""

handler = "ppc_cmp"
jit_lowering = "arm64_ppc_cmp"

