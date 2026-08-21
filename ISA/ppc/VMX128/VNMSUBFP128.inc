// VMX128/VNMSUBFP128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VD]", operand_4 = "VR[VB]" },
]

source_isa = "ppc"
name = "vnmsubfp128"
mnemonic = "vnmsubfp128"
category = "vector_vmx128"
operation = "vnmsubfp128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128"
primary_opcode = 5
opcode_pattern = "0x14000150"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x14000150", form = "vnmsubfp128 [VD], [VA], [VD], [VB]", op_en = "VX128" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vnmsubfp128 decodes a VMX128 (VX128) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vnmsubfp128"
jit_lowering = "arm64_ppc_vnmsubfp128_helper"

