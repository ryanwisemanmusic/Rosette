// VMX_STORE/STVEWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "VR[VS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stvewx"
mnemonic = "stvewx"
category = "vector_store"
operation = "MEM32[EA] = vS[lane]"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00018e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00018e", form = "stvewx [VS], [RA0], [RB]", op_en = "X" }
]

reads = ["VR[VS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
EA <- ((rA|0) + (rB)) & ~3
lane <- EA[60:63] / 4
MEM(EA, 4) <- vS[lane]
"""

handler = "ppc_stvewx"
jit_lowering = "arm64_ppc_stvewx"

