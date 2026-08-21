// VMX128/STVEWX128.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_1", operand_1 = "VR[VS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stvewx128"
mnemonic = "stvewx128"
category = "vector_vmx128"
operation = "stvewx128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_1"
primary_opcode = 4
opcode_pattern = "0x10000183"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000183", form = "stvewx128 [VS], [RA0], [RB]", op_en = "VX128_1" }
]

reads = ["VR[VS]", "GPR[RA]", "GPR[RB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
stvewx128 decodes a VMX128 (VX128_1) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_stvewx128"
jit_lowering = "arm64_ppc_stvewx128_helper"

