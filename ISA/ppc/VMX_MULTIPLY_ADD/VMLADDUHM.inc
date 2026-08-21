// VMX_MULTIPLY_ADD/VMLADDUHM.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VC]" },
]

source_isa = "ppc"
name = "vmladduhm"
mnemonic = "vmladduhm"
category = "vector_multiply_add"
operation = "vD[i] = (vA[i] * vB[i]) + vC[i] on halfwords, modulo"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x10000022"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000022", form = "vmladduhm [VD], [VA], [VB], [VC]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "VR[VC]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = (vA[i] * vB[i]) + vC[i] on halfwords, modulo
"""

handler = "ppc_vmladduhm"
jit_lowering = "arm64_ppc_vmladduhm"

