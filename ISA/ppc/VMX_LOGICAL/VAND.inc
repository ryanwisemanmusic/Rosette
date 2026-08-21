// VMX_LOGICAL/VAND.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vand"
mnemonic = "vand"
category = "vector_logical"
operation = "vD = vA & vB"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000404"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000404", form = "vand [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD = vA & vB
"""

handler = "ppc_vand"
jit_lowering = "arm64_ppc_vand"

