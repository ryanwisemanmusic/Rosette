// VMX128/VSPLTISW128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_3", operand_1 = "VR[VD]", operand_2 = "SIMM", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vspltisw128"
mnemonic = "vspltisw128"
category = "vector_vmx128"
operation = "vspltisw128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_3"
primary_opcode = 6
opcode_pattern = "0x18000770"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x18000770", form = "vspltisw128 [VD], [SIMM]", op_en = "VX128_3" }
]

reads = ["SIMM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vspltisw128 decodes a VMX128 (VX128_3) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vspltisw128"
jit_lowering = "arm64_ppc_vspltisw128_helper"

