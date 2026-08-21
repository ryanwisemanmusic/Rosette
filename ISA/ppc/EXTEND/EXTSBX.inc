// EXTEND/EXTSBX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "extsbx"
mnemonic = "extsb"
category = "integer_extend"
operation = "rA = sign_extend8(rS)"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000774"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000774", form = "extsb[Rc] [RA], [RS]", op_en = "X" }
]

reads = ["GPR[RS]"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
rA <- EXTS((rS)[56:63])
"""

handler = "ppc_extsbx"
jit_lowering = "arm64_ppc_extsbx"

