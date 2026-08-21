// VMX_MULTIPLY_ADD/VSUM2SWS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vsum2sws"
mnemonic = "vsum2sws"
category = "vector_multiply_add"
operation = "vD accumulates lane sums of vA into the words of vC"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000688"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000688", form = "vsum2sws [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["VSCR.SAT"]
special_registers = ["VSCR"]

semantic = """
vD accumulates lane sums of vA into the words of vC
"""

handler = "ppc_vsum2sws"
jit_lowering = "arm64_ppc_vsum2sws_helper"

