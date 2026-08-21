// VMX128/VMADDFP128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VD]" },
]

source_isa = "ppc"
name = "vmaddfp128"
mnemonic = "vmaddfp128"
category = "vector_vmx128"
operation = "vmaddfp128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128"
primary_opcode = 5
opcode_pattern = "0x140000d0"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x140000d0", form = "vmaddfp128 [VD], [VA], [VB], [VD]", op_en = "VX128" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vmaddfp128 decodes a VMX128 (VX128) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vmaddfp128"
jit_lowering = "arm64_ppc_vmaddfp128_helper"

