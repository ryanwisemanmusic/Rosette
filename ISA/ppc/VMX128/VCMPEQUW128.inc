// VMX128/VCMPEQUW128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_R", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vcmpequw128"
mnemonic = "vcmpequw128"
category = "vector_vmx128"
operation = "vcmpequw128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_R"
primary_opcode = 6
opcode_pattern = "0x18000200"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x18000200", form = "vcmpequw128[Rc] [VD], [VA], [VB]", op_en = "VX128_R" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["CR6 (when Rc=1)"]
special_registers = ["VSCR"]

semantic = """
vcmpequw128 decodes a VMX128 (VX128_R) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vcmpequw128"
jit_lowering = "arm64_ppc_vcmpequw128_helper"

