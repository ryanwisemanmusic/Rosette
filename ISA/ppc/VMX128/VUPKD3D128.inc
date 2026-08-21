// VMX128/VUPKD3D128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_3", operand_1 = "VR128[VD128]", operand_2 = "VR128[VB128]", operand_3 = "type", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vupkd3d128"
mnemonic = "vupkd3d128"
category = "vector_vmx128"
operation = "vupkd3d128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_3"
primary_opcode = 6
opcode_pattern = "0x180007f0"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x180007f0", form = "vupkd3d128 [VD128], [VB128], [type]", op_en = "VX128_3" }
]

reads = ["VR128[VB128]", "type"]
writes = ["VR128[VD128]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vupkd3d128 decodes a VMX128 (VX128_3) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vupkd3d128"
jit_lowering = "arm64_ppc_vupkd3d128_helper"

