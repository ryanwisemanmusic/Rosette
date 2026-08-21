// FP_STORE/STFDUX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPR[FS]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stfdux"
mnemonic = "stfdux"
category = "floating_point_store"
operation = "MEM64[EA] = frS"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0005ee"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0005ee", form = "stfdux [FS], [RA], [RB]", op_en = "X" }
]

reads = ["FPR[FS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA) + displacement
MEM(EA, 8) <- (frS)
rA <- EA
"""

handler = "ppc_stfdux"
jit_lowering = "arm64_ppc_stfdux"

