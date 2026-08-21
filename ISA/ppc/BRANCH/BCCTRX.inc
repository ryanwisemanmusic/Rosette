// BRANCH/BCCTRX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XL", operand_1 = "BO", operand_2 = "BI", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "bcctrx"
mnemonic = "bcctr"
category = "control_flow"
operation = "conditionally branch to CTR"

form = "XL"
primary_opcode = 19
opcode_pattern = "0x4c000420"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x4c000420", form = "bcctr[LK] [BO], [BI]", op_en = "XL" }
]

reads = ["BO", "CR[BI]"]
writes = ["none"]
flags_written = ["CTR (when BO decrements)"]
special_registers = ["LR (when LK=1)", "CTR (source)"]

semantic = """
cond_ok as in bc (CTR decrement is invalid here)
NIA <- CTR[0:61] || 0b00
if LK then LR <- CIA + 4
"""

handler = "ppc_bcctrx"
jit_lowering = "arm64_ppc_bcctrx"

