// FP_STORE/STFS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "FPR[FS]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stfs"
mnemonic = "stfs"
category = "floating_point_store"
operation = "MEM32[EA] = frS rounded to single precision"

form = "D"
primary_opcode = 52
opcode_pattern = "0xd0000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xd0000000", form = "stfs [FS], [d]([RA0])", op_en = "D" }
]

reads = ["FPR[FS]", "d", "GPR[RA]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA|0) + displacement
MEM(EA, 4) <- SINGLE((frS))
"""

handler = "ppc_stfs"
jit_lowering = "arm64_ppc_stfs"

