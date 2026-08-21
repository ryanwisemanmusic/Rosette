// VMX_PACK/VPKUWUS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vpkuwus"
mnemonic = "vpkuwus"
category = "vector_pack"
operation = "vD packs vA and vB down one lane width, saturating"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x100000ce"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x100000ce", form = "vpkuwus [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["VSCR.SAT"]
special_registers = ["VSCR"]

semantic = """
vD packs vA and vB down one lane width, saturating
"""

handler = "ppc_vpkuwus"
jit_lowering = "arm64_ppc_vpkuwus"

