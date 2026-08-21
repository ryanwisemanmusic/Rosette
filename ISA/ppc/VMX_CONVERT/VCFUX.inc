// VMX_CONVERT/VCFUX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VB]", operand_3 = "UIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vcfux"
mnemonic = "vcfux"
category = "vector_convert"
operation = "vD[i] = float(unsigned vB[i]) / 2**UIMM"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000030a"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000030a", form = "vcfux [VD], [VB], [UIMM]", op_en = "VX" }
]

reads = ["VR[VB]", "UIMM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = float(unsigned vB[i]) / 2**UIMM
"""

handler = "ppc_vcfux"
jit_lowering = "arm64_ppc_vcfux"

