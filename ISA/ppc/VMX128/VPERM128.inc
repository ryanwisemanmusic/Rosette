// VMX128/VPERM128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_2", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VC]" },
]

source_isa = "ppc"
name = "vperm128"
mnemonic = "vperm128"
category = "vector_vmx128"
operation = "vperm128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_2"
primary_opcode = 5
opcode_pattern = "0x14000000"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x14000000", form = "vperm128 [VD], [VA], [VB], [VC]", op_en = "VX128_2" }
]

reads = ["VR[VA]", "VR[VB]", "VR[VC]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vperm128 decodes a VMX128 (VX128_2) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vperm128"
jit_lowering = "arm64_ppc_vperm128_helper"

