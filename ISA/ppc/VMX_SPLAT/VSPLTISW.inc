// VMX_SPLAT/VSPLTISW.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX", operand_1 = "VR[VD]", operand_2 = "SIMM", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "vspltisw"
mnemonic = "vspltisw"
category = "vector_splat"
operation = "vD[i] = sign-extended SIMM broadcast to every lane"

form = "VX"
primary_opcode = 4
opcode_pattern = "0x1000038c"
opcode_mask = "0xfc0007ff"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000038c", form = "vspltisw [VD], [SIMM]", op_en = "VX" }
]

reads = ["SIMM"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD[i] = sign-extended SIMM broadcast to every lane
"""

handler = "ppc_vspltisw"
jit_lowering = "arm64_ppc_vspltisw"

