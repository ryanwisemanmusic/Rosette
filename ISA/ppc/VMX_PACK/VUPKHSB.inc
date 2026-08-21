// VMX_PACK/VUPKHSB.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vupkhsb"
mnemonic = "vupkhsb"
category = "vector_pack"
operation = "vD sign-extends the high half of vB to the next lane width"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000020e"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000020e", form = "vupkhsb [VD], [VB]", op_en = "VX" }
]

reads = ["VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD sign-extends the high half of vB to the next lane width
"""

handler = "ppc_vupkhsb"
jit_lowering = "arm64_ppc_vupkhsb"

