// VMX128/LVXL128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_1", operand_1 = "VR[VD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "lvxl128"
mnemonic = "lvxl128"
category = "vector_vmx128"
operation = "lvxl128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_1"
primary_opcode = 4
opcode_pattern = "0x100002c3"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x100002c3", form = "lvxl128 [VD], [RA0], [RB]", op_en = "VX128_1" }
]

reads = ["GPR[RA]", "GPR[RB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
lvxl128 decodes a VMX128 (VX128_1) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_lvxl128"
jit_lowering = "arm64_ppc_lvxl128_helper"

