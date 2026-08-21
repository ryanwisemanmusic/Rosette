// VMX_COMPARE/VCMPEQFP.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VC", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vcmpeqfp"
mnemonic = "vcmpeqfp"
category = "vector_compare"
operation = "vD[i] = all-ones when vA[i] eq vB[i] (single precision)"

form = "VC"
primary_opcode = 4
opcode_pattern = "0x100000c6"
opcode_mask = "0xfc0003ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x100000c6", form = "vcmpeqfp[Rc] [VD], [VA], [VB]", op_en = "VC" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["CR6 (when Rc=1)"]
special_registers = ["VSCR"]

semantic = """
vD[i] = all-ones when vA[i] eq vB[i] (single precision)
"""

handler = "ppc_vcmpeqfp"
jit_lowering = "arm64_ppc_vcmpeqfp"

