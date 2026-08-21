// VMX_ARITH/VMINFP.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vminfp"
mnemonic = "vminfp"
category = "vector_arithmetic"
operation = "vD[i] = min(vA[i], vB[i]) (single precision)"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000044a"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000044a", form = "vminfp [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = min(vA[i], vB[i]) (single precision)
"""

handler = "ppc_vminfp"
jit_lowering = "arm64_ppc_vminfp"

