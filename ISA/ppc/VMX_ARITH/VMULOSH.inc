// VMX_ARITH/VMULOSH.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vmulosh"
mnemonic = "vmulosh"
category = "vector_arithmetic"
operation = "vD[i] = multiply odd lanes to double width of vA[i] and vB[i], signed 16-bit lanes, modulo"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000148"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000148", form = "vmulosh [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = multiply odd lanes to double width of vA[i] and vB[i], signed 16-bit lanes, modulo
"""

handler = "ppc_vmulosh"
jit_lowering = "arm64_ppc_vmulosh"

