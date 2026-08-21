// FP_ARITH/FMULSX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FC]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "fmulsx"
mnemonic = "fmuls"
category = "floating_point_arithmetic"
operation = "frD = frA * frC in single precision"

form = "A"
primary_opcode = 59
opcode_pattern = "0xec000032"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xec000032", form = "fmuls[Rc] [FD], [FA], [FC]", op_en = "A" }
]

reads = ["FPR[FA]", "FPR[FC]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- (frA) * (frC) rounded per FPSCR.RN
"""

handler = "ppc_fmulsx"
jit_lowering = "arm64_ppc_fmulsx"

