// STORE/STH.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RS]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sth"
mnemonic = "sth"
category = "memory_store"
operation = "MEM16[(rA|0) + EXTS(d)] = rS stored big-endian"

form = "D"
primary_opcode = 44
opcode_pattern = "0xb0000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xb0000000", form = "sth [RS], [d]([RA0])", op_en = "D" }
]

reads = ["GPR[RS]", "d", "GPR[RA]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + EXTS(d)
MEM(EA, 2) <- (rS)[48:63]
"""

handler = "ppc_sth"
jit_lowering = "arm64_ppc_sth"

