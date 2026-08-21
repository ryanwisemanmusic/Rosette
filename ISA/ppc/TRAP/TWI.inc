// TRAP/TWI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "TO", operand_2 = "GPR[RA]", operand_3 = "SIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "twi"
mnemonic = "tw"
category = "control_trap"
operation = "trap if the signed compare of rA and SIMM matches TO"

form = "D"
primary_opcode = 3
opcode_pattern = "0x0c000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x0c000000", form = "tw [TO], [RA], [SIMM]", op_en = "D" }
]

reads = ["TO", "GPR[RA]", "SIMM"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
if any TO condition holds for ((rA), EXTS(SIMM)) then raise trap
"""

handler = "ppc_twi"
jit_lowering = "arm64_ppc_twi"

