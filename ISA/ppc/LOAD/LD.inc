// LOAD/LD.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DS", operand_1 = "GPR[RD]", operand_2 = "ds", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "ld"
mnemonic = "ld"
category = "memory_load"
operation = "rD = EXTZ(MEM64[(rA|0) + EXTS(d)]) loaded big-endian"

form = "DS"
primary_opcode = 58
opcode_pattern = "0xe8000000"
opcode_mask = "0xfc000003"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xe8000000", form = "ld [RD], [ds]([RA0])", op_en = "DS" }
]

reads = ["ds", "GPR[RA]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + EXTS(d)
rD <- EXTZ(MEM(EA, 8))
"""

handler = "ppc_ld"
jit_lowering = "arm64_ppc_ld"

