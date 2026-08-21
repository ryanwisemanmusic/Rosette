// STORE/STWU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RS]", operand_2 = "d", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stwu"
mnemonic = "stwu"
category = "memory_store"
operation = "MEM32[(rA) + EXTS(d)] = rS stored big-endian"

form = "D"
primary_opcode = 37
opcode_pattern = "0x94000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x94000000", form = "stwu [RS], [d]([RA])", op_en = "D" }
]

reads = ["GPR[RS]", "d", "GPR[RA]"]
writes = ["MEM", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + EXTS(d)
MEM(EA, 4) <- (rS)[32:63]
rA <- EA
"""

handler = "ppc_stwu"
jit_lowering = "arm64_ppc_stwu"

