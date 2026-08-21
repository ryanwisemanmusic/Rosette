// VMX_PERMUTE/VSEL.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VC]" },
]

source_isa = "ppc"
name = "vsel"
mnemonic = "vsel"
category = "vector_permute"
operation = "vD[i] = vC[i] ? vB[i] : vA[i] (bitwise)"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x1000002a"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000002a", form = "vsel [VD], [VA], [VB], [VC]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "VR[VC]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = vC[i] ? vB[i] : vA[i] (bitwise)
"""

handler = "ppc_vsel"
jit_lowering = "arm64_ppc_vsel"

