// LOAD/LDU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DS", operand_1 = "GPR[RD]", operand_2 = "ds", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "ldu"
mnemonic = "ldu"
category = "memory_load"
operation = "rD = EXTZ(MEM64[(rA) + EXTS(d)]) loaded big-endian"

form = "DS"
primary_opcode = 58
opcode_pattern = "0xe8000001"
opcode_mask = "0xfc000003"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xe8000001", form = "ldu [RD], [ds]([RA])", op_en = "DS" }
]

reads = ["ds", "GPR[RA]", "MEM"]
writes = ["GPR[RD]", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + EXTS(d)
rD <- EXTZ(MEM(EA, 8))
rA <- EA
"""

handler = "ppc_ldu"
jit_lowering = "arm64_ppc_ldu"

