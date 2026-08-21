// FP_STORE/STFD.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "FPR[FS]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stfd"
mnemonic = "stfd"
category = "floating_point_store"
operation = "MEM64[EA] = frS"

form = "D"
primary_opcode = 54
opcode_pattern = "0xd8000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xd8000000", form = "stfd [FS], [d]([RA0])", op_en = "D" }
]

reads = ["FPR[FS]", "d", "GPR[RA]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA|0) + displacement
MEM(EA, 8) <- (frS)
"""

handler = "ppc_stfd"
jit_lowering = "arm64_ppc_stfd"

