// TRAP/TW.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "TO", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "tw"
mnemonic = "tw"
category = "control_trap"
operation = "trap if the 32-bit compare of rA and rB matches TO"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000008"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000008", form = "tw [TO], [RA], [RB]", op_en = "X" }
]

reads = ["TO", "GPR[RA]", "GPR[RB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
if any TO condition holds for ((rA)[32:63], (rB)[32:63]) then raise trap
"""

handler = "ppc_tw"
jit_lowering = "arm64_ppc_tw"

