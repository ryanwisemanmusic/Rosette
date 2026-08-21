// TRAP/TD.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "TO", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "td"
mnemonic = "td"
category = "control_trap"
operation = "trap if the 64-bit compare of rA and rB matches TO"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000088"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000088", form = "td [TO], [RA], [RB]", op_en = "X" }
]

reads = ["TO", "GPR[RA]", "GPR[RB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
if any TO condition holds for ((rA), (rB)) then raise trap
"""

handler = "ppc_td"
jit_lowering = "arm64_ppc_td"

