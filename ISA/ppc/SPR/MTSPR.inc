// SPR/MTSPR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XFX", operand_1 = "SPR", operand_2 = "GPR[RS]", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mtspr"
mnemonic = "mtspr"
category = "special_purpose_register"
operation = "SPR[n] = rS"

form = "XFX"
primary_opcode = 31
opcode_pattern = "0x7c0003a6"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0003a6", form = "mtspr [SPR], [RS]", op_en = "XFX" }
]

reads = ["SPR", "GPR[RS]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["SPR (LR, CTR, XER, and the Xenon-specific SPRs)"]

semantic = """
n <- SPR[5:9] || SPR[0:4]
SPR(n) <- (rS)
"""

handler = "ppc_mtspr"
jit_lowering = "arm64_ppc_mtspr"

