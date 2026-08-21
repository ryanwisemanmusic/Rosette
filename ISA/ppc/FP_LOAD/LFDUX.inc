// FP_LOAD/LFDUX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPR[FD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lfdux"
mnemonic = "lfdux"
category = "floating_point_load"
operation = "frD = MEM64[EA] as a double-precision value"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0004ee"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0004ee", form = "lfdux [FD], [RA], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["FPR[FD]", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA) + displacement
frD <- MEM(EA, 8)
rA <- EA
"""

handler = "ppc_lfdux"
jit_lowering = "arm64_ppc_lfdux"

