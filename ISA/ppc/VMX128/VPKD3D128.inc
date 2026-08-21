// VMX128/VPKD3D128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_4", operand_1 = "VR128[VD128]", operand_2 = "VR128[VB128]", operand_3 = "type", operand_4 = "pack" },
]

source_isa = "ppc"
name = "vpkd3d128"
mnemonic = "vpkd3d128"
category = "vector_vmx128"
operation = "vpkd3d128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_4"
primary_opcode = 6
opcode_pattern = "0x18000610"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x18000610", form = "vpkd3d128 [VD128], [VB128], [type], [pack], [shift]", op_en = "VX128_4" }
]

reads = ["VR128[VB128]", "type", "pack", "shift"]
writes = ["VR128[VD128]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vpkd3d128 decodes a VMX128 (VX128_4) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vpkd3d128"
jit_lowering = "arm64_ppc_vpkd3d128_helper"

