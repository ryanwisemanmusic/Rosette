// FP_LOAD/LFS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "FPR[FD]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lfs"
mnemonic = "lfs"
category = "floating_point_load"
operation = "frD = MEM32[EA] as a single-precision value converted to double"

form = "D"
primary_opcode = 48
opcode_pattern = "0xc0000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xc0000000", form = "lfs [FD], [d]([RA0])", op_en = "D" }
]

reads = ["d", "GPR[RA]", "MEM"]
writes = ["FPR[FD]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA|0) + displacement
frD <- DOUBLE(MEM(EA, 4))
"""

handler = "ppc_lfs"
jit_lowering = "arm64_ppc_lfs"

