// VMX_MULTIPLY_ADD/VSUM4UBS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vsum4ubs"
mnemonic = "vsum4ubs"
category = "vector_multiply_add"
operation = "vsum4ubs: AltiVec operation executed by the Rosette PPC vector unit"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x10000608"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000608", form = "vsum4ubs [VD], [VA], [VB]", op_en = "VX" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["VSCR.SAT"]
special_registers = ["VSCR"]

semantic = """
vsum4ubs: AltiVec operation executed by the Rosette PPC vector unit
"""

handler = "ppc_vsum4ubs"
jit_lowering = "arm64_ppc_vsum4ubs_helper"

