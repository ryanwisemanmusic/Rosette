// COUNT/CNTLZDX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "cntlzdx"
mnemonic = "cntlzd"
category = "integer_count"
operation = "rA = count_leading_zeros64(rS)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000074"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000074", form = "cntlzd [RA], [RS]", op_en = "X" }
]

reads = ["GPR[RS]"]
writes = ["GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
rA <- number of leading zero bits in (rS), 0..64
"""

handler = "ppc_cntlzdx"
jit_lowering = "arm64_ppc_cntlzdx"

