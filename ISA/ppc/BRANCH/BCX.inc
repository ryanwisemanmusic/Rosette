// BRANCH/BCX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "B", operand_1 = "BO", operand_2 = "BI", operand_3 = "BD", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "bcx"
mnemonic = "bc"
category = "control_flow"
operation = "conditionally branch to BD using BO/BI and CTR"

form = "B"
primary_opcode = 16
opcode_pattern = "0x40000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x40000000", form = "bc[LK][AA] [BO], [BI], [BD]", op_en = "B" }
]

reads = ["BO", "CR[BI]", "BD"]
writes = ["none"]
flags_written = ["CTR (when BO decrements)"]
special_registers = ["LR (when LK=1)", "CTR (decrement)"]

semantic = """
if not BO[2] then CTR <- CTR - 1
ctr_ok <- BO[2] | ((CTR != 0) ^ BO[3])
cond_ok <- BO[0] | (CR[BI] == BO[1])
if ctr_ok & cond_ok then NIA <- target
if LK then LR <- CIA + 4
"""

handler = "ppc_bcx"
jit_lowering = "arm64_ppc_bcx"

