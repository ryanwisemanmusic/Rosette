// VMX_PACK/VUPKHPX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vupkhpx"
mnemonic = "vupkhpx"
category = "vector_pack"
operation = "unpack the high four 1-5-5-5 pixels into words"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000034e"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000034e", form = "vupkhpx [VD], [VB]", op_en = "VX" }
]

reads = ["VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
unpack the high four 1-5-5-5 pixels into words
"""

handler = "ppc_vupkhpx"
jit_lowering = "arm64_ppc_vupkhpx_helper"

