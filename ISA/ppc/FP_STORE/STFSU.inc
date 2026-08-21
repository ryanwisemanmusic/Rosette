// FP_STORE/STFSU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "FPR[FS]", operand_2 = "d", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stfsu"
mnemonic = "stfsu"
category = "floating_point_store"
operation = "MEM32[EA] = frS rounded to single precision"

form = "D"
primary_opcode = 53
opcode_pattern = "0xd4000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xd4000000", form = "stfsu [FS], [d]([RA])", op_en = "D" }
]

reads = ["FPR[FS]", "d", "GPR[RA]"]
writes = ["MEM", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA) + displacement
MEM(EA, 4) <- SINGLE((frS))
rA <- EA
"""

handler = "ppc_stfsu"
jit_lowering = "arm64_ppc_stfsu"

