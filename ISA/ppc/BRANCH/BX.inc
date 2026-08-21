// BRANCH/BX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "I", operand_1 = "LI", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "bx"
mnemonic = "b"
category = "control_flow"
operation = "branch to LI, optionally absolute and linking"

form = "I"
primary_opcode = 18
opcode_pattern = "0x48000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x48000000", form = "b[LK][AA] [ADDR]", op_en = "I" }
]

reads = ["LI"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["LR (when LK=1)"]

semantic = """
if AA then NIA <- EXTS(LI || 0b00)
else NIA <- CIA + EXTS(LI || 0b00)
if LK then LR <- CIA + 4
"""

handler = "ppc_bx"
jit_lowering = "arm64_ppc_bx"

