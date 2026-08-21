// VMX_LOAD/LVLXL.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "VR[VD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lvlxl"
mnemonic = "lvlxl"
category = "vector_load"
operation = "vD = MEM128[EA & ~15]"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00060e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00060e", form = "lvlxl [VD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
EA <- ((rA|0) + (rB)) & ~15
vD <- MEM(EA, 16)
the word lanes are byte-reversed on a little-endian host
"""

handler = "ppc_lvlxl"
jit_lowering = "arm64_ppc_lvlxl"

