// VMX_CONVERT/VRFIZ.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vrfiz"
mnemonic = "vrfiz"
category = "vector_convert"
operation = "vD[i] = trunc(vB[i])"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000024a"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000024a", form = "vrfiz [VD], [VB]", op_en = "VX" }
]

reads = ["VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = trunc(vB[i])
"""

handler = "ppc_vrfiz"
jit_lowering = "arm64_ppc_vrfiz"

