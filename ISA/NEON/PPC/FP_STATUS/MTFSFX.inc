// FP_STATUS/MTFSFX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/FP_STATUS/MTFSFX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "FP_STATUS/MTFSFX.inc"
ppc_handler = "ppc_mtfsfx"
neon_lowering = "arm64_ppc_mtfsfx"
lowering_kind = "neon_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XFL", operand_1 = "FM", operand_2 = "FPR[FB]", operand_3 = "N/A", operand_4 = "N/A" },
]

name = "mtfsfx"
mnemonic = "mtfsf"
category = "floating_point_status"
operation = "FPSCR fields selected by FM = frB"

form = "XFL"
primary_opcode = 63
opcode_pattern = "0xfc00058e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc00058e", form = "mtfsf[Rc] [FM], [FB]", op_en = "XFL" }
]

reads = ["FM", "FPR[FB]"]
writes = ["none"]
flags_written = ["CR1 (when Rc=1)"]
special_registers = ["FPSCR"]

semantic = """
mask <- expand(FM)
FPSCR <- ((frB)[32:63] & mask) | (FPSCR & ~mask)
"""

handler = "ppc_mtfsfx"
jit_lowering = "arm64_ppc_mtfsfx"


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
fmov xT, dB
msr fpcr, xT
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

