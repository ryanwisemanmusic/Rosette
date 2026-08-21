// FP_LOAD/LFDU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "FPR[FD]", operand_2 = "d", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lfdu"
mnemonic = "lfdu"
category = "floating_point_load"
operation = "frD = MEM64[EA] as a double-precision value"

form = "D"
primary_opcode = 51
opcode_pattern = "0xcc000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xcc000000", form = "lfdu [FD], [d]([RA])", op_en = "D" }
]

reads = ["d", "GPR[RA]", "MEM"]
writes = ["FPR[FD]", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA) + displacement
frD <- MEM(EA, 8)
rA <- EA
"""

handler = "ppc_lfdu"
jit_lowering = "arm64_ppc_lfdu"

