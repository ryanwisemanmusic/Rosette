// VMX_COMPARE/VCMPBFP.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VC", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vcmpbfp"
mnemonic = "vcmpbfp"
category = "vector_compare"
operation = "vD[i] = in-bounds flags for vA[i] against +/-vB[i]"

form = "VC"
primary_opcode = 4
opcode_pattern = "0x100003c6"
opcode_mask = "0xfc0003ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x100003c6", form = "vcmpbfp[Rc] [VD], [VA], [VB]", op_en = "VC" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["CR6 (when Rc=1)"]
special_registers = ["VSCR"]

semantic = """
vD[i][0] <- vA[i] >  vB[i]
vD[i][1] <- vA[i] < -vB[i]
"""

handler = "ppc_vcmpbfp"
jit_lowering = "arm64_ppc_vcmpbfp_helper"

