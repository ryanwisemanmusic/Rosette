// VMX128/VSLDOI128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_5", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "SHB" },
]

source_isa = "ppc"
name = "vsldoi128"
mnemonic = "vsldoi128"
category = "vector_vmx128"
operation = "vsldoi128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_5"
primary_opcode = 4
opcode_pattern = "0x10000010"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000010", form = "vsldoi128 [VD], [VA], [VB], [SHB]", op_en = "VX128_5" }
]

reads = ["VR[VA]", "VR[VB]", "SHB"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vsldoi128 decodes a VMX128 (VX128_5) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vsldoi128"
jit_lowering = "arm64_ppc_vsldoi128_helper"

