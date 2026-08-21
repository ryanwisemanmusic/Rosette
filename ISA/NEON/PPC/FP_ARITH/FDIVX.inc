// FP_ARITH/FDIVX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/FP_ARITH/FDIVX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "FP_ARITH/FDIVX.inc"
ppc_handler = "ppc_fdivx"
neon_lowering = "arm64_ppc_fdivx"
lowering_kind = "neon_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "A", operand_1 = "FPR[FD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FB]", operand_4 = "N/A" },
]

name = "fdivx"
mnemonic = "fdiv"
category = "floating_point_arithmetic"
operation = "frD = frA / frB in double precision"

form = "A"
primary_opcode = 63
opcode_pattern = "0xfc000024"
opcode_mask = "0xfc00003e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc000024", form = "fdiv[Rc] [FD], [FA], [FB]", op_en = "A" }
]

reads = ["FPR[FA]", "FPR[FB]"]
writes = ["FPR[FD]"]
flags_written = ["CR1 (when Rc=1)", "FPSCR.FPRF/FX/OX/UX/XX/VX"]
special_registers = ["FPSCR"]

semantic = """
frD <- (frA) / (frB) rounded per FPSCR.RN
"""

handler = "ppc_fdivx"
jit_lowering = "arm64_ppc_fdivx"


neon_register_model = """
PowerPC architected state lives in the Rosette PPC register file: GPR0-31 and
LR/CTR/XER as 64-bit slots, FPR0-31 as IEEE doubles, VR0-127 as 128-bit lanes,
and CR as eight 4-bit fields. The lowering loads the operands it needs into
ARM64 temporaries, computes, and writes the architected slot back explicitly.
"""

neon_flag_model = """
ARM64 NZCV is repacked into the PowerPC condition contract named by
flags_written above: CR field bits are ordered LT, GT, EQ, SO, with SO copied
from XER; XER.CA and XER.OV are produced from the ARM64 carry/overflow flags.
"""

neon_assembly = """
fdiv dD, dA, dB
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

