// STORE/STB.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RS]", operand_2 = "d", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stb"
mnemonic = "stb"
category = "memory_store"
operation = "MEM8[(rA|0) + EXTS(d)] = rS stored big-endian"

form = "D"
primary_opcode = 38
opcode_pattern = "0x98000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x98000000", form = "stb [RS], [d]([RA0])", op_en = "D" }
]

reads = ["GPR[RS]", "d", "GPR[RA]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + EXTS(d)
MEM(EA, 1) <- (rS)[56:63]
"""

handler = "ppc_stb"
jit_lowering = "arm64_ppc_stb"

