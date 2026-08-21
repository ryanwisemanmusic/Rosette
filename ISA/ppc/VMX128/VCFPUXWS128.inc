// VMX128/VCFPUXWS128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_3", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "UIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vcfpuxws128"
mnemonic = "vcfpuxws128"
category = "vector_vmx128"
operation = "vcfpuxws128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_3"
primary_opcode = 6
opcode_pattern = "0x18000270"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x18000270", form = "vcfpuxws128 [VD], [VB], [UIMM]", op_en = "VX128_3" }
]

reads = ["VR[VB]", "UIMM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vcfpuxws128 decodes a VMX128 (VX128_3) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vcfpuxws128"
jit_lowering = "arm64_ppc_vcfpuxws128_helper"

