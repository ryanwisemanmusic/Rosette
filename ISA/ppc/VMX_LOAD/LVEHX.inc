// VMX_LOAD/LVEHX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "VR[VD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lvehx"
mnemonic = "lvehx"
category = "vector_load"
operation = "vD[lane] = MEM16[EA]"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00004e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00004e", form = "lvehx [VD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
EA <- ((rA|0) + (rB)) & ~1
lane <- EA[60:63] / 2
vD[lane] <- MEM(EA, 2)
"""

handler = "ppc_lvehx"
jit_lowering = "arm64_ppc_lvehx"

