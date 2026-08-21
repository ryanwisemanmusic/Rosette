// VMX_SHIFT/VSR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vsr"
mnemonic = "vsr"
category = "vector_shift"
operation = "vD = vA >> (vB[15] & 7) as a 128-bit bit shift"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x100002c4"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x100002c4", form = "vsr [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD = vA >> (vB[15] & 7) as a 128-bit bit shift
"""

handler = "ppc_vsr"
jit_lowering = "arm64_ppc_vsr_helper"

