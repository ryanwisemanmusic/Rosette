// VMX_PERMUTE/VSLDOI.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "SHB" },
]

source_isa = "ppc"
name = "vsldoi"
mnemonic = "vsldoi"
category = "vector_permute"
operation = "vD = ((vA || vB) << (SHB * 8))[0:127]"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x1000002c"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000002c", form = "vsldoi [VD], [VA], [VB], [SHB]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "SHB"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD = ((vA || vB) << (SHB * 8))[0:127]
"""

handler = "ppc_vsldoi"
jit_lowering = "arm64_ppc_vsldoi"

