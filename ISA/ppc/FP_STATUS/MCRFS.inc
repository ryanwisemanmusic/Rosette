// FP_STATUS/MCRFS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "CR[CRFD]", operand_2 = "CR[CRFS]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mcrfs"
mnemonic = "mcrfs"
category = "floating_point_status"
operation = "CR[crfD] = FPSCR[crfS], then clear the sticky bits copied"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc000080"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc000080", form = "mcrfs [CRFD], [CRFS]", op_en = "X" }
]

reads = ["CR[CRFS]"]
writes = ["CR[CRFD]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
CR[crfD] <- FPSCR[crfS]
exception bits copied out are cleared
"""

handler = "ppc_mcrfs"
jit_lowering = "arm64_ppc_mcrfs"

