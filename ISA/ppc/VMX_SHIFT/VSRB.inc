// VMX_SHIFT/VSRB.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vsrb"
mnemonic = "vsrb"
category = "vector_shift"
operation = "vsrb: AltiVec operation executed by the Rosette PPC vector unit"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000204"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000204", form = "vsrb [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vsrb: AltiVec operation executed by the Rosette PPC vector unit
"""

handler = "ppc_vsrb"
jit_lowering = "arm64_ppc_vsrb_helper"

