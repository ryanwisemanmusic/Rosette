// VMX_COMPARE/VCMPEQUB.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VC", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vcmpequb"
mnemonic = "vcmpequb"
category = "vector_compare"
operation = "vD[i] = all-ones when vA[i] == vB[i] (unsigned)"

form = "VC"
primary_opcode = 4
opcode_pattern = "0x10000006"
opcode_mask = "0xfc0003ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000006", form = "vcmpequb[Rc] [VD], [VA], [VB]", op_en = "VC" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["CR6 (when Rc=1)"]
special_registers = ["VSCR"]

semantic = """
vD[i] = all-ones when vA[i] == vB[i] (unsigned)
"""

handler = "ppc_vcmpequb"
jit_lowering = "arm64_ppc_vcmpequb"

