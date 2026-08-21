// CMP/CMPLI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "CR[CRFD]", operand_2 = "L", operand_3 = "GPR[RA]", operand_4 = "UIMM" },
]

source_isa = "ppc"
name = "cmpli"
mnemonic = "cmpli"
category = "integer_compare"
operation = "CR[crfD] = unsigned compare(rA, UIMM)"

form = "D"
primary_opcode = 10
opcode_pattern = "0x28000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x28000000", form = "cmpli [CRFD], [L], [RA], [UIMM]", op_en = "D" }
]

reads = ["L", "GPR[RA]", "UIMM"]
writes = ["CR[CRFD]"]
flags_written = ["CR[crfD]"]
special_registers = ["none"]

semantic = """
a <- if L then (rA) else EXTZ((rA)[32:63])
CR[crfD] <- {a<ui UIMM, a>ui UIMM, a=UIMM, XER.SO}
"""

handler = "ppc_cmpli"
jit_lowering = "arm64_ppc_cmpli"

