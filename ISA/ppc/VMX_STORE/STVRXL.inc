// VMX_STORE/STVRXL.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "VR[VS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stvrxl"
mnemonic = "stvrxl"
category = "vector_store"
operation = "MEM128[EA & ~15] = vS"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00074e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00074e", form = "stvrxl [VS], [RA0], [RB]", op_en = "X" }
]

reads = ["VR[VS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
EA <- ((rA|0) + (rB)) & ~15
MEM(EA, 16) <- (vS)
the word lanes are byte-reversed on a little-endian host
"""

handler = "ppc_stvrxl"
jit_lowering = "arm64_ppc_stvrxl"

