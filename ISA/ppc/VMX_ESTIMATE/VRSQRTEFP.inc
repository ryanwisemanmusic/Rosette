// VMX_ESTIMATE/VRSQRTEFP.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vrsqrtefp"
mnemonic = "vrsqrtefp"
category = "vector_estimate"
operation = "vD[i] = 1/sqrt(vB[i]) estimate"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000014a"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000014a", form = "vrsqrtefp [VD], [VB]", op_en = "VX" }
]

reads = ["VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = 1/sqrt(vB[i]) estimate
"""

handler = "ppc_vrsqrtefp"
jit_lowering = "arm64_ppc_vrsqrtefp"

