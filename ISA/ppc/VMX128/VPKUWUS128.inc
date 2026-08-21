// VMX128/VPKUWUS128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vpkuwus128"
mnemonic = "vpkuwus128"
category = "vector_vmx128"
operation = "vpkuwus128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128"
primary_opcode = 5
opcode_pattern = "0x140003c0"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x140003c0", form = "vpkuwus128 [VD], [VA], [VB]", op_en = "VX128" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vpkuwus128 decodes a VMX128 (VX128) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vpkuwus128"
jit_lowering = "arm64_ppc_vpkuwus128_helper"

