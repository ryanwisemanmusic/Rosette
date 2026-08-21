// ADD/ADDIS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "SIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "addis"
mnemonic = "addis"
category = "integer_arithmetic"
operation = "rD = (rA|0) + (SIMM << 16)"

form = "D"
primary_opcode = 15
opcode_pattern = "0x3c000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x3c000000", form = "addis [RD], [RA0], [SIMM]", op_en = "D" }
]

reads = ["GPR[RA]", "SIMM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
rD <- (rA|0) + (EXTS(SIMM) || 0x0000)
"""

handler = "ppc_addis"
jit_lowering = "arm64_ppc_addis"

