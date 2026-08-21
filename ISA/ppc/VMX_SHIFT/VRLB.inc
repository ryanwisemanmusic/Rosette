// VMX_SHIFT/VRLB.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vrlb"
mnemonic = "vrlb"
category = "vector_shift"
operation = "vrlb: AltiVec operation executed by the Rosette PPC vector unit"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000004"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000004", form = "vrlb [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vrlb: AltiVec operation executed by the Rosette PPC vector unit
"""

handler = "ppc_vrlb"
jit_lowering = "arm64_ppc_vrlb_helper"

