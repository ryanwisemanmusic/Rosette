// VMX_MULTIPLY_ADD/VMSUMMBM.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VC]" },
]

source_isa = "ppc"
name = "vmsummbm"
mnemonic = "vmsummbm"
category = "vector_multiply_add"
operation = "vmsummbm: AltiVec operation executed by the Rosette PPC vector unit"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x10000025"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000025", form = "vmsummbm [VD], [VA], [VB], [VC]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "VR[VC]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vmsummbm: AltiVec operation executed by the Rosette PPC vector unit
"""

handler = "ppc_vmsummbm"
jit_lowering = "arm64_ppc_vmsummbm_helper"

