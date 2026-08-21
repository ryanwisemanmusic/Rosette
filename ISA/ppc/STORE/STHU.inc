// STORE/STHU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RS]", operand_2 = "d", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sthu"
mnemonic = "sthu"
category = "memory_store"
operation = "MEM16[(rA) + EXTS(d)] = rS stored big-endian"

form = "D"
primary_opcode = 45
opcode_pattern = "0xb4000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xb4000000", form = "sthu [RS], [d]([RA])", op_en = "D" }
]

reads = ["GPR[RS]", "d", "GPR[RA]"]
writes = ["MEM", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + EXTS(d)
MEM(EA, 2) <- (rS)[48:63]
rA <- EA
"""

handler = "ppc_sthu"
jit_lowering = "arm64_ppc_sthu"

