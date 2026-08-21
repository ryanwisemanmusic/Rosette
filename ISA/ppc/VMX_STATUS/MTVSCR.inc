// VMX_STATUS/MTVSCR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VB]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mtvscr"
mnemonic = "mtvscr"
category = "vector_status"
operation = "VSCR = vB[112:127]"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000644"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000644", form = "mtvscr [VB]", op_en = "VX" }
]

reads = ["VR[VB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
VSCR = vB[112:127]
"""

handler = "ppc_mtvscr"
jit_lowering = "arm64_ppc_mtvscr_helper"

