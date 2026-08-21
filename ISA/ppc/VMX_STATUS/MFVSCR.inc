// VMX_STATUS/MFVSCR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mfvscr"
mnemonic = "mfvscr"
category = "vector_status"
operation = "vD[112:127] = VSCR"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000604"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000604", form = "mfvscr [VD]", op_en = "VX" }
]

reads = ["none"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[112:127] = VSCR
"""

handler = "ppc_mfvscr"
jit_lowering = "arm64_ppc_mfvscr_helper"

