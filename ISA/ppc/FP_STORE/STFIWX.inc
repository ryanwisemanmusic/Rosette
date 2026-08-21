// FP_STORE/STFIWX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPR[FS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stfiwx"
mnemonic = "stfiwx"
category = "floating_point_store"
operation = "MEM32[(rA|0) + rB] = the low 32 bits of frS"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0007ae"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0007ae", form = "stfiwx [FS], [RA0], [RB]", op_en = "X" }
]

reads = ["FPR[FS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA|0) + (rB)
MEM(EA, 4) <- (frS)[32:63]
"""

handler = "ppc_stfiwx"
jit_lowering = "arm64_ppc_stfiwx"

