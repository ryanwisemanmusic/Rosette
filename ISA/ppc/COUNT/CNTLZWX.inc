// COUNT/CNTLZWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "cntlzwx"
mnemonic = "cntlzw"
category = "integer_count"
operation = "rA = count_leading_zeros32(rS)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000034"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000034", form = "cntlzw[Rc] [RA], [RS]", op_en = "X" }
]

reads = ["GPR[RS]"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
rA <- number of leading zero bits in (rS)[32:63], 0..32
"""

handler = "ppc_cntlzwx"
jit_lowering = "arm64_ppc_cntlzwx"

