// SPR/MFSPR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XFX", operand_1 = "GPR[RD]", operand_2 = "SPR", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mfspr"
mnemonic = "mfspr"
category = "special_purpose_register"
operation = "rD = SPR[n]"

form = "XFX"
primary_opcode = 31
opcode_pattern = "0x7c0002a6"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0002a6", form = "mfspr [RD], [SPR]", op_en = "XFX" }
]

reads = ["SPR"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["SPR (LR, CTR, XER, and the Xenon-specific SPRs)"]

semantic = """
n <- SPR[5:9] || SPR[0:4]
rD <- SPR(n)
"""

handler = "ppc_mfspr"
jit_lowering = "arm64_ppc_mfspr"

