// STORE_INDEXED/STDUX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stdux"
mnemonic = "stdux"
category = "memory_store"
operation = "MEM64[(rA) + (rB)] = rS stored big-endian"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00016a"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00016a", form = "stdux [RS], [RA], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + (rB)
MEM(EA, 8) <- (rS)[0:63]
rA <- EA
"""

handler = "ppc_stdux"
jit_lowering = "arm64_ppc_stdux"

