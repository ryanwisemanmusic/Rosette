// VMX_MULTIPLY_ADD/VMHRADDSHS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "VR[VC]" },
]

source_isa = "ppc"
name = "vmhraddshs"
mnemonic = "vmhraddshs"
category = "vector_multiply_add"
operation = "vD[i] = saturate(((vA[i] * vB[i]) >> 15 rounded) + vC[i]) on halfwords"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x10000021"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000021", form = "vmhraddshs [VD], [VA], [VB], [VC]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "VR[VC]"]
writes = ["VR[VD]"]
flags_written = ["VSCR.SAT"]
special_registers = ["VSCR"]

semantic = """
vD[i] = saturate(((vA[i] * vB[i]) >> 15 rounded) + vC[i]) on halfwords
"""

handler = "ppc_vmhraddshs"
jit_lowering = "arm64_ppc_vmhraddshs"

