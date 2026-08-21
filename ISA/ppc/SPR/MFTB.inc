// SPR/MFTB.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XFX", operand_1 = "GPR[RD]", operand_2 = "TBR", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mftb"
mnemonic = "mftb"
category = "special_purpose_register"
operation = "rD = time base"

form = "XFX"
primary_opcode = 31
opcode_pattern = "0x7c0002e6"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0002e6", form = "mftb [RD], [TBR]", op_en = "XFX" }
]

reads = ["TBR"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["TB / TBU"]

semantic = """
rD <- TB or TBU depending on the encoded TBR
"""

handler = "ppc_mftb"
jit_lowering = "arm64_ppc_mftb"

