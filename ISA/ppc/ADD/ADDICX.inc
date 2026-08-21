// ADD/ADDICX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "SIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "addicx"
mnemonic = "addic."
category = "integer_arithmetic"
operation = "rD = (rA) + SIMM, XER.CA = carry, CR0 updated"

form = "D"
primary_opcode = 13
opcode_pattern = "0x34000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x34000000", form = "addic. [RD], [RA], [SIMM]", op_en = "D" }
]

reads = ["GPR[RA]", "SIMM"]
writes = ["GPR[RD]"]
flags_written = ["XER.CA"]
special_registers = ["none"]

semantic = """
rD <- (rA) + EXTS(SIMM)
XER.CA <- carry_out
CR0 <- cmp(rD, 0)
"""

handler = "ppc_addicx"
jit_lowering = "arm64_ppc_addicx"

