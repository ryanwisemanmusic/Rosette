// VMX_SPLAT/VSPLTISH.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "SIMM", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vspltish"
mnemonic = "vspltish"
category = "vector_splat"
operation = "vD[i] = sign-extended SIMM broadcast to every lane"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000034c"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000034c", form = "vspltish [VD], [SIMM]", op_en = "VX" }
]

reads = ["SIMM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = sign-extended SIMM broadcast to every lane
"""

handler = "ppc_vspltish"
jit_lowering = "arm64_ppc_vspltish"

