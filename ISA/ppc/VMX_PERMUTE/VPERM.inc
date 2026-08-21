// VMX_PERMUTE/VPERM.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VC]" },
]

source_isa = "ppc"
name = "vperm"
mnemonic = "vperm"
category = "vector_permute"
operation = "vD[i] = concat(vA, vB)[vC[i] & 31]"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x1000002b"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000002b", form = "vperm [VD], [VA], [VB], [VC]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "VR[VC]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = concat(vA, vB)[vC[i] & 31]
"""

handler = "ppc_vperm"
jit_lowering = "arm64_ppc_vperm"

