// VMX_LOAD/LVSL.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "VR[VD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lvsl"
mnemonic = "lvsl"
category = "vector_load"
operation = "vD = the shift-left permute control vector for EA"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00000c"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00000c", form = "lvsl [VD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
EA <- (rA|0) + (rB)
sh <- EA[60:63]
vD <- the 16 byte indices that align a left shift by sh
"""

handler = "ppc_lvsl"
jit_lowering = "arm64_ppc_lvsl_helper"

