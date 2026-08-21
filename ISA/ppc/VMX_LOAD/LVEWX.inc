// VMX_LOAD/LVEWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "VR[VD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lvewx"
mnemonic = "lvewx"
category = "vector_load"
operation = "vD[lane] = MEM32[EA]"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00008e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00008e", form = "lvewx [VD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
EA <- ((rA|0) + (rB)) & ~3
lane <- EA[60:63] / 4
vD[lane] <- MEM(EA, 4)
"""

handler = "ppc_lvewx"
jit_lowering = "arm64_ppc_lvewx"

