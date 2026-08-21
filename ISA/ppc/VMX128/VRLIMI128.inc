// VMX128/VRLIMI128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_4", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "IMM", operand_4 = "z" },
]

source_isa = "ppc"
name = "vrlimi128"
mnemonic = "vrlimi128"
category = "vector_vmx128"
operation = "vrlimi128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_4"
primary_opcode = 6
opcode_pattern = "0x18000710"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x18000710", form = "vrlimi128 [VD], [VB], [IMM], [z]", op_en = "VX128_4" }
]

reads = ["VR[VB]", "IMM", "z"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vrlimi128 decodes a VMX128 (VX128_4) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vrlimi128"
jit_lowering = "arm64_ppc_vrlimi128_helper"

