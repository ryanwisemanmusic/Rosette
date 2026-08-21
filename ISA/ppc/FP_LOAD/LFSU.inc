// FP_LOAD/LFSU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "FPR[FD]", operand_2 = "d", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lfsu"
mnemonic = "lfsu"
category = "floating_point_load"
operation = "frD = MEM32[EA] as a single-precision value converted to double"

form = "D"
primary_opcode = 49
opcode_pattern = "0xc4000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xc4000000", form = "lfsu [FD], [d]([RA])", op_en = "D" }
]

reads = ["d", "GPR[RA]", "MEM"]
writes = ["FPR[FD]", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA) + displacement
frD <- DOUBLE(MEM(EA, 4))
rA <- EA
"""

handler = "ppc_lfsu"
jit_lowering = "arm64_ppc_lfsu"

