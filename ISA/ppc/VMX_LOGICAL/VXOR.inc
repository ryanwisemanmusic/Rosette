// VMX_LOGICAL/VXOR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vxor"
mnemonic = "vxor"
category = "vector_logical"
operation = "vD = vA ^ vB"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x100004c4"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x100004c4", form = "vxor [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD = vA ^ vB
"""

handler = "ppc_vxor"
jit_lowering = "arm64_ppc_vxor"

