// LOAD_INDEXED/LHZUX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lhzux"
mnemonic = "lhzux"
category = "memory_load"
operation = "rD = EXTZ(MEM16[(rA) + (rB)]) loaded big-endian"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00026e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00026e", form = "lhzux [RD], [RA], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["GPR[RD]", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + (rB)
rD <- EXTZ(MEM(EA, 2))
rA <- EA
"""

handler = "ppc_lhzux"
jit_lowering = "arm64_ppc_lhzux"

