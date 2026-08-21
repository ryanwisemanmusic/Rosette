// VMX128/VEXPTEFP128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_3", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vexptefp128"
mnemonic = "vexptefp128"
category = "vector_vmx128"
operation = "vexptefp128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_3"
primary_opcode = 6
opcode_pattern = "0x180006b0"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x180006b0", form = "vexptefp128 [VD], [VB]", op_en = "VX128_3" }
]

reads = ["VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vexptefp128 decodes a VMX128 (VX128_3) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vexptefp128"
jit_lowering = "arm64_ppc_vexptefp128_helper"

