// VMX_ARITH/VMAXSW.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vmaxsw"
mnemonic = "vmaxsw"
category = "vector_arithmetic"
operation = "vD[i] = lanewise maximum of vA[i] and vB[i], signed 32-bit lanes, modulo"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000182"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000182", form = "vmaxsw [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = lanewise maximum of vA[i] and vB[i], signed 32-bit lanes, modulo
"""

handler = "ppc_vmaxsw"
jit_lowering = "arm64_ppc_vmaxsw"

