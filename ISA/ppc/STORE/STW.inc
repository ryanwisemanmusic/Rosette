// STORE/STW.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RS]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stw"
mnemonic = "stw"
category = "memory_store"
operation = "MEM32[(rA|0) + EXTS(d)] = rS stored big-endian"

form = "D"
primary_opcode = 36
opcode_pattern = "0x90000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x90000000", form = "stw [RS], [d]([RA0])", op_en = "D" }
]

reads = ["GPR[RS]", "d", "GPR[RA]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + EXTS(d)
MEM(EA, 4) <- (rS)[32:63]
"""

handler = "ppc_stw"
jit_lowering = "arm64_ppc_stw"

