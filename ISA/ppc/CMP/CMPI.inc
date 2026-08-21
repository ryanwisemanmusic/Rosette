// CMP/CMPI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "CR[CRFD]", operand_2 = "L", operand_3 = "GPR[RA]", operand_4 = "SIMM" },
]

source_isa = "ppc"
name = "cmpi"
mnemonic = "cmpi"
category = "integer_compare"
operation = "CR[crfD] = signed compare(rA, SIMM)"

form = "D"
primary_opcode = 11
opcode_pattern = "0x2c000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x2c000000", form = "cmpi [CRFD], [L], [RA], [SIMM]", op_en = "D" }
]

reads = ["L", "GPR[RA]", "SIMM"]
writes = ["CR[CRFD]"]
flags_written = ["CR[crfD]"]
special_registers = ["none"]

semantic = """
a <- if L then (rA) else EXTS((rA)[32:63])
CR[crfD] <- {a<SIMM, a>SIMM, a=SIMM, XER.SO}
"""

handler = "ppc_cmpi"
jit_lowering = "arm64_ppc_cmpi"

