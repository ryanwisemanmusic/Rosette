// VMX_SPLAT/VSPLTW.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "UIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vspltw"
mnemonic = "vspltw"
category = "vector_splat"
operation = "vD[i] = vB[UIMM] broadcast to every lane"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000028c"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000028c", form = "vspltw [VD], [VB], [UIMM]", op_en = "VX" }
]

reads = ["VR[VB]", "UIMM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = vB[UIMM] broadcast to every lane
"""

handler = "ppc_vspltw"
jit_lowering = "arm64_ppc_vspltw"

