// LOAD/LBZ.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lbz"
mnemonic = "lbz"
category = "memory_load"
operation = "rD = EXTZ(MEM8[(rA|0) + EXTS(d)]) loaded big-endian"

form = "D"
primary_opcode = 34
opcode_pattern = "0x88000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x88000000", form = "lbz [RD], [d]([RA0])", op_en = "D" }
]

reads = ["d", "GPR[RA]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + EXTS(d)
rD <- EXTZ(MEM(EA, 1))
"""

handler = "ppc_lbz"
jit_lowering = "arm64_ppc_lbz"

