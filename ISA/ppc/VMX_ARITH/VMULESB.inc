// VMX_ARITH/VMULESB.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vmulesb"
mnemonic = "vmulesb"
category = "vector_arithmetic"
operation = "vD[i] = multiply even lanes to double width of vA[i] and vB[i], signed 8-bit lanes, modulo"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000308"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000308", form = "vmulesb [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = multiply even lanes to double width of vA[i] and vB[i], signed 8-bit lanes, modulo
"""

handler = "ppc_vmulesb"
jit_lowering = "arm64_ppc_vmulesb"

