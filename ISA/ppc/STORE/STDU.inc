// STORE/STDU.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DS", operand_1 = "GPR[RS]", operand_2 = "ds", operand_3 = "GPR[RA]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stdu"
mnemonic = "stdu"
category = "memory_store"
operation = "MEM64[(rA) + EXTS(d)] = rS stored big-endian"

form = "DS"
primary_opcode = 62
opcode_pattern = "0xf8000001"
opcode_mask = "0xfc000003"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xf8000001", form = "stdu [RS], [ds]([RA])", op_en = "DS" }
]

reads = ["GPR[RS]", "ds", "GPR[RA]"]
writes = ["MEM", "GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA) + EXTS(d)
MEM(EA, 8) <- (rS)[0:63]
rA <- EA
"""

handler = "ppc_stdu"
jit_lowering = "arm64_ppc_stdu"

