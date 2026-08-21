// VMX_LOAD/LVEBX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "VR[VD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lvebx"
mnemonic = "lvebx"
category = "vector_load"
operation = "vD[lane] = MEM8[EA]"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00000e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00000e", form = "lvebx [VD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
EA <- ((rA|0) + (rB)) & ~0
lane <- EA[60:63] / 1
vD[lane] <- MEM(EA, 1)
"""

handler = "ppc_lvebx"
jit_lowering = "arm64_ppc_lvebx"

