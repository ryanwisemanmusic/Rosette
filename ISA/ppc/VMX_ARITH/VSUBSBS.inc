// VMX_ARITH/VSUBSBS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vsubsbs"
mnemonic = "vsubsbs"
category = "vector_arithmetic"
operation = "vD[i] = lanewise subtract of vA[i] and vB[i], signed 8-bit lanes, saturating"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000700"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000700", form = "vsubsbs [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["VSCR.SAT"]
special_registers = ["VSCR"]

semantic = """
vD[i] = lanewise subtract of vA[i] and vB[i], signed 8-bit lanes, saturating
"""

handler = "ppc_vsubsbs"
jit_lowering = "arm64_ppc_vsubsbs"

