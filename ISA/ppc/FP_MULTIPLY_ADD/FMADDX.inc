// FP_MULTIPLY_ADD/FMADDX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FC]", operand_4 = "FPR[FB]" },
]

source_isa = "ppc"
name = "fmaddx"
mnemonic = "fmadd"
category = "floating_point_fused_multiply_add"
operation = "frD = (frA * frC) + frB in double precision"

form = "A"
primary_opcode = 63
opcode_pattern = "0xfc00003a"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00003a", form = "fmadd[Rc] [FD], [FA], [FC], [FB]", op_en = "A" }
]

reads = ["FPR[FA]", "FPR[FC]", "FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- (frA * frC) + frB computed with one rounding (fused multiply-add) per FPSCR.RN
"""

handler = "ppc_fmaddx"
jit_lowering = "arm64_ppc_fmaddx"

