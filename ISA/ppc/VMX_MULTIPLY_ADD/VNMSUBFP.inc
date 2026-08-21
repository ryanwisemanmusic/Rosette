// VMX_MULTIPLY_ADD/VNMSUBFP.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VC]", operand_4 = "VR[VB]" },
]

source_isa = "ppc"
name = "vnmsubfp"
mnemonic = "vnmsubfp"
category = "vector_multiply_add"
operation = "vD[i] = -((vA[i] * vC[i]) - vB[i]) (single precision)"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x1000002f"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000002f", form = "vnmsubfp [VD], [VA], [VC], [VB]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VC]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = -((vA[i] * vC[i]) - vB[i]) (single precision)
"""

handler = "ppc_vnmsubfp"
jit_lowering = "arm64_ppc_vnmsubfp"

