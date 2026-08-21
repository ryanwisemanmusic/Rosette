// FP_LOAD/LFD.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "FPR[FD]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lfd"
mnemonic = "lfd"
category = "floating_point_load"
operation = "frD = MEM64[EA] as a double-precision value"

form = "D"
primary_opcode = 50
opcode_pattern = "0xc8000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xc8000000", form = "lfd [FD], [d]([RA0])", op_en = "D" }
]

reads = ["d", "GPR[RA]", "MEM"]
writes = ["FPR[FD]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA|0) + displacement
frD <- MEM(EA, 8)
"""

handler = "ppc_lfd"
jit_lowering = "arm64_ppc_lfd"

