// VMX_MULTIPLY_ADD/VMSUMUHS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VC]" },
]

source_isa = "ppc"
name = "vmsumuhs"
mnemonic = "vmsumuhs"
category = "vector_multiply_add"
operation = "vD[i] = vC[i] + sum of the lane products inside each word"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x10000027"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000027", form = "vmsumuhs [VD], [VA], [VB], [VC]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "VR[VC]"]
writes = ["VR[VD]"]
flags_written = ["VSCR.SAT"]
special_registers = ["VSCR"]

semantic = """
vD[i] = vC[i] + sum of the lane products inside each word
"""

handler = "ppc_vmsumuhs"
jit_lowering = "arm64_ppc_vmsumuhs_helper"

