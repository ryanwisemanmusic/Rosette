// ADD/ADDI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "GPR[RA] or 0", operand_3 = "SIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "addi"
mnemonic = "addi"
category = "integer_arithmetic"
operation = "rD = (rA|0) + SIMM"

form = "D"
primary_opcode = 14
opcode_pattern = "0x38000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x38000000", form = "addi [RD], [RA0], [SIMM]", op_en = "D" }
]

reads = ["GPR[RA]", "SIMM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
rD <- (rA|0) + EXTS(SIMM)
"""

handler = "ppc_addi"
jit_lowering = "arm64_ppc_addi"

