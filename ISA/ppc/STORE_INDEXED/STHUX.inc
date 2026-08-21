// STORE_INDEXED/STHUX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sthux"
mnemonic = "sthux"
category = "memory_store"
operation = "MEM16[(rA) + (rB)] = rS stored big-endian"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00036e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00036e", form = "sthux [RS], [RA], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + (rB)
MEM(EA, 2) <- (rS)[48:63]
rA <- EA
"""

handler = "ppc_sthux"
jit_lowering = "arm64_ppc_sthux"

