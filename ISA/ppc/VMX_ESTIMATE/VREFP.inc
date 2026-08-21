// VMX_ESTIMATE/VREFP.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vrefp"
mnemonic = "vrefp"
category = "vector_estimate"
operation = "vD[i] = 1/vB[i] estimate"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000010a"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000010a", form = "vrefp [VD], [VB]", op_en = "VX" }
]

reads = ["VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = 1/vB[i] estimate
"""

handler = "ppc_vrefp"
jit_lowering = "arm64_ppc_vrefp"

