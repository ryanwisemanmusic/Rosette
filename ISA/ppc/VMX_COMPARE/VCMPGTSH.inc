// VMX_COMPARE/VCMPGTSH.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VC", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vcmpgtsh"
mnemonic = "vcmpgtsh"
category = "vector_compare"
operation = "vD[i] = all-ones when vA[i] > vB[i] (signed)"

form = "VC"
primary_opcode = 4
opcode_pattern = "0x10000346"
opcode_mask = "0xfc0003ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000346", form = "vcmpgtsh[Rc] [VD], [VA], [VB]", op_en = "VC" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["CR6 (when Rc=1)"]
special_registers = ["VSCR"]

semantic = """
vD[i] = all-ones when vA[i] > vB[i] (signed)
"""

handler = "ppc_vcmpgtsh"
jit_lowering = "arm64_ppc_vcmpgtsh"

