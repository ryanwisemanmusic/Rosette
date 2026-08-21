// BRANCH/BCLRX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XL", operand_1 = "BO", operand_2 = "BI", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "bclrx"
mnemonic = "bclr"
category = "control_flow"
operation = "conditionally branch to LR"

form = "XL"
primary_opcode = 19
opcode_pattern = "0x4c000020"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x4c000020", form = "bclr[LK] [BO], [BI]", op_en = "XL" }
]

reads = ["BO", "CR[BI]"]
writes = ["none"]
flags_written = ["CTR (when BO decrements)"]
special_registers = ["LR (when LK=1)", "LR (source)", "CTR (decrement)"]

semantic = """
ctr_ok & cond_ok as in bc; NIA <- LR[0:61] || 0b00
if LK then LR <- CIA + 4
"""

handler = "ppc_bclrx"
jit_lowering = "arm64_ppc_bclrx"

