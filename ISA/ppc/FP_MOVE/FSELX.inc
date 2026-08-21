// FP_MOVE/FSELX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FC]", operand_4 = "FPR[FB]" },
]

source_isa = "ppc"
name = "fselx"
mnemonic = "fsel"
category = "floating_point_move"
operation = "frD = frA >= 0 ? frC : frB"

form = "A"
primary_opcode = 63
opcode_pattern = "0xfc00002e"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00002e", form = "fsel[Rc] [FD], [FA], [FC], [FB]", op_en = "A" }
]

reads = ["FPR[FA]", "FPR[FC]", "FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)"]
special_registers = ["FPSCR"]

semantic = """
frD <- if (frA) >= 0.0 then (frC) else (frB)
"""

handler = "ppc_fselx"
jit_lowering = "arm64_ppc_fselx"

