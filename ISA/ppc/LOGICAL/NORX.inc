// LOGICAL/NORX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "norx"
mnemonic = "nor"
category = "integer_logical"
operation = "rA = ~(rS | rB)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0000f8"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0000f8", form = "nor[Rc] [RA], [RS], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RB]"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
rA <- ~((rS) | (rB))
"""

handler = "ppc_norx"
jit_lowering = "arm64_ppc_norx"

